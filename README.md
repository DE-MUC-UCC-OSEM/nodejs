[![Build Docker Image](https://github.com/DE-MUC-UCC-OSEM/nodejs/actions/workflows/build.yml/badge.svg)](https://github.com/DE-MUC-UCC-OSEM/nodejs/actions/workflows/build.yml)

## Information
Nodejs running in a minimal OpenSUSE Docker Image

Using a pre-built Nodejs executable version. Everything put into a minimal Container image built from an OpenSUSE tumbleweed image

## Images

Each release publishes two images:

| Tag | Content | Use |
| --- | --- | --- |
| `<version>-r<release>-tumbleweed` | Stripped OpenSUSE tumbleweed with bash, node and the FIPS provider. No npm. | Runtime image |
| `<version>-r<release>-builder` | Full OpenSUSE tumbleweed with bash, git, npm and the same node / FIPS setup | Build stage of multi-stage builds |

Both images contain node at `/usr/local/bin/node` with the same OpenSSL configuration, so build results from the builder image run unchanged in the runtime image.

## Build profile

Node is built for osem and is trimmed for size. The images and the `nodejs-binary` RPM all contain the same stripped binary, built with:

```
--shared-openssl-* --openssl-is-fips
--disable-single-executable-application --without-node-snapshot
--with-intl=small-icu --with-icu-locales=en,de
--without-inspector --without-amaro --without-sqlite --without-ffi
--v8-disable-temporal-support --v8-enable-snapshot-compression --enable-lto
```

Not available in this build:

| Missing | Effect |
| --- | --- |
| Locales other than `en` and `de` | Formatting for other locales silently falls back to English. Time zone data is complete. |
| Inspector | No `--inspect`, `--cpu-prof`, `--heap-prof`, `node:inspector` or `NODE_V8_COVERAGE` (c8, `--experimental-test-coverage`) |
| TypeScript (amaro) | `node app.ts` fails with `ERR_NO_TYPESCRIPT` |
| SQLite | No `node:sqlite`, `localStorage` or `sessionStorage` |
| FFI, Temporal, SEA | No `node:ffi`, no `Temporal`, no `--build-sea` |

The build runs `smoke-test.mjs`. It fails the build if a feature osem needs is missing (German Intl data, time zones, WebAssembly/fetch, http2, legacy crypto, ...) or if a removed feature is still compiled in.

Check a build with:
```
node -p process.features
node -p process.config.variables
```

## Run the image

You can run the image via Docker
```
docker run -dit ghcr.io/de-muc-ucc-osem/nodejs:26.13.0-r0-tumbleweed
```

## Build an application image

```Dockerfile
FROM ghcr.io/de-muc-ucc-osem/nodejs:26.13.0-r0-builder AS build
WORKDIR /app
COPY . .
RUN npm ci --omit=dev

FROM ghcr.io/de-muc-ucc-osem/nodejs:26.13.0-r0-tumbleweed
COPY --from=build /app /app
CMD ["/usr/local/bin/node", "/app/index.js"]
```
## Configuration
