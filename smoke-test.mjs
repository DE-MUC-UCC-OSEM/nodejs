// Smoke test for the size-trimmed node build used by osem.
// Run with: node --openssl-legacy-provider smoke-test.mjs
//
// Part 1 checks the features osem depends on.
// Part 2 checks that the features removed by configure are really gone.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import dns from 'node:dns';
import http from 'node:http';
import http2 from 'node:http2';
import tls from 'node:tls';
import zlib from 'node:zlib';
import { Worker } from 'node:worker_threads';

let failures = 0;

async function check(name, fn) {
  try {
    await fn();
    console.log(`ok   ${name}`);
  } catch (err) {
    failures++;
    console.error(`FAIL ${name}\n     ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Part 1: features osem needs
// ---------------------------------------------------------------------------

// i18next and luxon: German locale data must be present (small-icu en,de)
await check('Intl: German date formatting', () => {
  const thursday = new Date(Date.UTC(2026, 10, 12, 12));
  const fmt = new Intl.DateTimeFormat('de-DE', { weekday: 'long', timeZone: 'UTC' });
  assert.equal(fmt.format(thursday), 'Donnerstag');
});

await check('Intl: German number formatting', () => {
  const fmt = new Intl.NumberFormat('de-DE');
  assert.match(fmt.resolvedOptions().locale, /^de/);
  assert.equal(fmt.format(1234.5), '1.234,5');
});

await check('Intl: plural rules', () => {
  const de = new Intl.PluralRules('de');
  assert.match(de.resolvedOptions().locale, /^de/);
  assert.equal(de.select(1), 'one');
  assert.equal(de.select(2), 'other');
  assert.equal(new Intl.PluralRules('en', { type: 'ordinal' }).select(2), 'two');
});

await check('Intl: German list and relative time formatting', () => {
  assert.equal(new Intl.ListFormat('de', { type: 'conjunction' }).format(['a', 'b', 'c']), 'a, b und c');
  assert.equal(new Intl.RelativeTimeFormat('de').format(-1, 'day'), 'vor 1 Tag');
});

await check('Intl: Intl.getCanonicalLocales and Intl.Locale', () => {
  assert.deepEqual(Intl.getCanonicalLocales('DE-de'), ['de-DE']);
  assert.equal(new Intl.Locale('de-DE').language, 'de');
});

// luxon setZone(): IANA time zone rules must be complete
await check('Intl: time zone list', () => {
  const zones = Intl.supportedValuesOf('timeZone');
  assert.ok(zones.length > 350, `only ${zones.length} time zones`);
  // Canonical ICU IDs only (ICU lists Asia/Calcutta, not Asia/Kolkata)
  for (const zone of ['Europe/Berlin', 'America/New_York', 'Asia/Tokyo', 'Australia/Adelaide', 'America/Sao_Paulo']) {
    assert.ok(zones.includes(zone), `${zone} missing`);
  }
});

await check('Intl: time zone offsets', () => {
  const instant = new Date(Date.UTC(2026, 0, 15, 12, 0)); // winter, no DST in the north
  const expected = {
    'UTC': '12:00',
    'Europe/Berlin': '13:00',
    'America/New_York': '07:00',
    'Asia/Kolkata': '17:30',
    'Australia/Adelaide': '22:30', // DST in the south (+10:30)
  };
  for (const [timeZone, time] of Object.entries(expected)) {
    const parts = new Intl.DateTimeFormat('en', {
      timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    }).formatToParts(instant);
    const get = (type) => parts.find((p) => p.type === type).value;
    assert.equal(`${get('hour')}:${get('minute')}`, time, timeZone);
  }
});

await check('Intl: German time zone names', () => {
  const instant = new Date(Date.UTC(2026, 0, 15, 12, 0));
  const name = new Intl.DateTimeFormat('de-DE', { timeZone: 'Europe/Berlin', timeZoneName: 'long' })
    .formatToParts(instant).find((p) => p.type === 'timeZoneName').value;
  assert.match(name, /Mitteleurop/);
});

await check('Unicode: normalize and property escapes', () => {
  assert.equal('ä'.normalize('NFD').length, 2);
  assert.ok(/\p{L}/u.test('ä'));
  assert.equal(new TextDecoder('utf-8').decode(Buffer.from('ä')), 'ä');
});

// undici fetch (llhttp is WebAssembly), ssh2, zip.js
await check('WebAssembly', () => {
  const empty = new Uint8Array([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]);
  assert.ok(WebAssembly.validate(empty));
  assert.ok(new WebAssembly.Module(empty) instanceof WebAssembly.Module);
});

await check('fetch against a local HTTP server', async () => {
  const server = http.createServer((req, res) => res.end('pong'));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const res = await fetch(`http://127.0.0.1:${server.address().port}/`);
    assert.equal(await res.text(), 'pong');
  } finally {
    server.closeAllConnections();
    server.close();
  }
});

// osem REST API runs on http2 (allowHTTP1)
await check('http2 round trip (h2c)', async () => {
  const server = http2.createServer((req, res) => res.end('h2'));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const client = http2.connect(`http://127.0.0.1:${server.address().port}`);
  try {
    const body = await new Promise((resolve, reject) => {
      const req = client.request({ ':path': '/' });
      let data = '';
      req.setEncoding('utf8');
      req.on('data', (chunk) => { data += chunk; });
      req.on('end', () => resolve(data));
      req.on('error', reject);
      req.end();
    });
    assert.equal(body, 'h2');
  } finally {
    client.close();
    server.close();
  }
});

await check('tls and c-ares resolver available', () => {
  assert.equal(typeof tls.createSecureContext, 'function');
  assert.ok(tls.rootCertificates.length > 50);
  const resolver = new dns.promises.Resolver();
  resolver.setServers(['127.0.0.1']);
  assert.equal(typeof resolver.resolveTxt, 'function');
});

await check('worker_threads', async () => {
  const worker = new Worker("require('node:worker_threads').parentPort.postMessage(21 * 2)", { eval: true });
  const result = await new Promise((resolve, reject) => {
    worker.once('message', resolve);
    worker.once('error', reject);
  });
  assert.equal(result, 42);
  await worker.terminate();
});

await check('zlib gzip and deflateRaw', () => {
  const input = Buffer.from('osem'.repeat(100));
  assert.deepEqual(zlib.gunzipSync(zlib.gzipSync(input)), input);
  assert.deepEqual(zlib.inflateRawSync(zlib.deflateRawSync(input)), input);
});

await check('crypto: hashes and HMAC', () => {
  assert.equal(crypto.createHash('md5').update('osem').digest('hex').length, 32);
  assert.equal(crypto.createHash('sha512').update('osem').digest('hex').length, 128);
  assert.equal(crypto.createHmac('sha256', 'key').update('osem').digest('hex').length, 64);
  assert.equal(crypto.randomUUID().length, 36);
});

await check('crypto: aes-256-cbc round trip', () => {
  const key = crypto.randomBytes(32);
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
  const encrypted = Buffer.concat([cipher.update('osem'), cipher.final()]);
  const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
  assert.equal(Buffer.concat([decipher.update(encrypted), decipher.final()]).toString(), 'osem');
});

// backupRestore.js uses des-ede3, which needs the OpenSSL legacy provider
await check('crypto: des-ede3 (legacy provider)', () => {
  const key = crypto.randomBytes(24);
  const cipher = crypto.createCipheriv('des-ede3', key, null);
  const encrypted = Buffer.concat([cipher.update('osem'), cipher.final()]);
  const decipher = crypto.createDecipheriv('des-ede3', key, null);
  assert.equal(Buffer.concat([decipher.update(encrypted), decipher.final()]).toString(), 'osem');
});

await check('crypto: RSA sign/verify and WebCrypto', async () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const signature = crypto.sign('sha256', Buffer.from('osem'), privateKey);
  assert.ok(crypto.verify('sha256', Buffer.from('osem'), publicKey, signature));
  const digest = await crypto.webcrypto.subtle.digest('SHA-256', Buffer.from('osem'));
  assert.equal(digest.byteLength, 32);
  const ec = await crypto.webcrypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  assert.equal(ec.privateKey.algorithm.namedCurve, 'P-256');
});

// ---------------------------------------------------------------------------
// Part 2: features removed by configure
// ---------------------------------------------------------------------------

const vars = process.config.variables;
const isTrue = (v) => v === true || v === 'true' || v === 1;

await check('removed: full ICU (small-icu is used)', () => {
  assert.ok(isTrue(vars.icu_small), `icu_small = ${vars.icu_small}`);
});

await check('removed: inspector', async () => {
  assert.equal(process.features.inspector, false);
  await assert.rejects(import('node:inspector'));
});

await check('removed: TypeScript (amaro)', () => {
  assert.ok(!process.features.typescript, `process.features.typescript = ${process.features.typescript}`);
});

await check('removed: sqlite', async () => {
  assert.equal(process.versions.sqlite, undefined);
  await assert.rejects(import('node:sqlite'));
});

await check('removed: Temporal', () => {
  assert.equal(typeof globalThis.Temporal, 'undefined');
});

// Not every build variable is guaranteed to exist under this name. Check the
// ones that do.
await check('removed: build variables', () => {
  for (const key of ['node_use_amaro', 'node_use_sqlite', 'node_use_ffi', 'v8_enable_inspector', 'v8_enable_temporal_support']) {
    if (key in vars) assert.ok(!isTrue(vars[key]), `${key} = ${vars[key]}`);
  }
});

// ---------------------------------------------------------------------------

console.log(`\nnode ${process.version}, openssl ${process.versions.openssl}, icu ${process.versions.icu}, unicode ${process.versions.unicode}`);
if (failures > 0) {
  console.error(`${failures} check(s) failed`);
  process.exit(1);
}
console.log('all checks passed');
