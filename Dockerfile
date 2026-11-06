FROM opensuse/tumbleweed:latest AS app

SHELL ["/bin/bash", "-c"]

ENV PREFIX=/usr/local

WORKDIR /opt

ARG NODE_SOURCE_VERSION
RUN zypper update --no-confirm && \
    zypper install --no-confirm gawk git python314 python314-pkgconfig gcc gcc16 gcc-c++ gcc16-c++ perl make nasm perl-Text-Template unzip autoconf libtool findutils rust cargo && \
    git -C /opt clone --depth 1 --branch v$NODE_SOURCE_VERSION https://github.com/nodejs/node.git nodejs

# Build and Install OpenSSL FIPS module
ARG OPENSSL_FIPS_VERSION
RUN curl -LO https://www.openssl.org/source/openssl-${OPENSSL_FIPS_VERSION}.tar.gz && \
    tar xzf openssl-${OPENSSL_FIPS_VERSION}.tar.gz && \
    cd openssl-${OPENSSL_FIPS_VERSION} && \
    ./Configure linux-x86_64 shared enable-fips --prefix=/fips-provider && \
    make -j$(nproc) && \
    make install_engines install_modules install_ssldirs install_fips

# Build and Install regular OpenSSL version for node build
ARG OPENSSL_VERSION
RUN curl -LO https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz && \
    tar xzf openssl-${OPENSSL_VERSION}.tar.gz && \
    cd openssl-${OPENSSL_VERSION} && \
    ./Configure linux-x86_64 shared --prefix=${PREFIX} && \
    make -j$(nproc) && \
    make install_programs install_engines install_modules install_ssldirs

RUN cp /fips-provider/lib64/ossl-modules/fips.so /usr/local/lib64/ossl-modules/fips.so && \
    /usr/local/bin/openssl fipsinstall -out /usr/local/ssl/fipsmodule.cnf -module /usr/local/lib64/ossl-modules/fips.so

ENV OPENSSL_CONF=${PREFIX}/ssl/openssl.cnf
ENV OPENSSL_MODULES=${PREFIX}/lib64/ossl-modules
ENV LD_LIBRARY_PATH=${PREFIX}/lib64
WORKDIR /opt/nodejs
RUN ./configure --shared-openssl-libpath=${PREFIX}/lib64 --shared-openssl-includes=${PREFIX}/include --shared-openssl-libname=crypto,ssl --openssl-is-fips --disable-single-executable-application --without-node-snapshot && \
    make -j$(nproc) && \
    make install

# Assemble the complete file system of the final image in /rootfs. Everything
# that is not copied here (shell, coreutils, openssl CLI, ...) does not exist
# in the final image.
FROM app AS rootfs

RUN mkdir -p /rootfs/usr/lib64 \
             /rootfs/usr/local/bin \
             /rootfs/usr/local/lib/node_modules \
             /rootfs/usr/local/lib64/ossl-modules \
             /rootfs/usr/local/ssl \
             /rootfs/etc \
             /rootfs/root \
             /rootfs/tmp && \
    chmod 700 /rootfs/root && \
    chmod 1777 /rootfs/tmp && \
    ln -s usr/lib64 /rootfs/lib64

# node binary
RUN cp /usr/local/bin/node /rootfs/usr/local/bin/node && \
    strip --strip-all /rootfs/usr/local/bin/node

# npm module. There is no /usr/bin/env in the final image, so the scripts have
# to point to the node binary directly.
RUN cp -a /usr/local/lib/node_modules/npm /rootfs/usr/local/lib/node_modules/npm && \
    rm -Rf /rootfs/usr/local/lib/node_modules/npm/{docs,man} && \
    sed -i '1s|^#!.*|#!/usr/local/bin/node|' /rootfs/usr/local/lib/node_modules/npm/bin/{npm,npx}-cli.js && \
    ln -s ../lib/node_modules/npm/bin/npm-cli.js /rootfs/usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /rootfs/usr/local/bin/npx

# FIPS provider and its configuration. OpenSSL itself is linked statically into
# node, so neither libcrypto/libssl nor the openssl CLI are needed at runtime.
# fipsmodule.cnf only contains fixed settings and the MAC of fips.so, it was
# generated in the app stage. Do not strip fips.so, this would invalidate the MAC.
COPY openssl.cnf /rootfs/usr/local/ssl/openssl.cnf
RUN cp /usr/local/lib64/ossl-modules/fips.so /rootfs/usr/local/lib64/ossl-modules/fips.so && \
    cp /usr/local/ssl/fipsmodule.cnf /rootfs/usr/local/ssl/fipsmodule.cnf

# Shared libraries required by node and the FIPS provider
RUN set -o pipefail && \
    ldd /rootfs/usr/local/bin/node /rootfs/usr/local/lib64/ossl-modules/fips.so | \
    awk '$2 == "=>" && $3 ~ /^\// { print $3 } $1 ~ /^\// && $1 !~ /:$/ { print $1 }' | \
    sort -u | \
    xargs -I{} cp -L {} /rootfs/usr/lib64/

# Without these entries os.userInfo() fails
RUN echo 'root:x:0:0:root:/root:/sbin/nologin' > /rootfs/etc/passwd && \
    echo 'root:x:0:' > /rootfs/etc/group

FROM scratch AS image

COPY --from=rootfs /rootfs/ /

ENV OPENSSL_CONF=/usr/local/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/local/lib64/ossl-modules

CMD ["/usr/local/bin/node"]

FROM scratch AS artifacts
COPY --from=app /usr/local/bin/node /usr/bin/node
