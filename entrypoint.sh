#!/bin/bash
set -e

rm -Rf /usr/local/ssl/fipsmodule.cnf
/usr/local/bin/openssl fipsinstall -out /usr/local/ssl/fipsmodule.cnf -module /usr/local/lib64/ossl-modules/fips.so > /dev/null 2>&1

exec "$@"
