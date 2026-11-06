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

# Build image (<version>-r<release>-builder): full tumbleweed with bash, git and
# npm, meant as the first stage of multi-stage builds. node, the FIPS provider
# and its configuration are identical to the runtime image and live at the same
# paths, so build results can be copied into the runtime image unchanged.
# Shared libraries come from the tumbleweed packages, not from /rootfs.
FROM opensuse/tumbleweed:latest AS builder

SHELL ["/bin/bash", "-c"]

RUN zypper update --no-confirm && \
    zypper install --no-confirm --no-recommends git-core libstdc++6 && \
    zypper clean --all

COPY --from=rootfs /rootfs/usr/local/bin/node /usr/local/bin/node
COPY --from=rootfs /rootfs/usr/local/lib64/ossl-modules/ /usr/local/lib64/ossl-modules/
COPY --from=rootfs /rootfs/usr/local/ssl/ /usr/local/ssl/

# npm module. /usr/bin/env exists here, so the stock shebangs work as they are.
COPY --from=app /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN rm -Rf /usr/local/lib/node_modules/npm/{docs,man} && \
    ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

ENV OPENSSL_CONF=/usr/local/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/local/lib64/ossl-modules

# Smoke test, fails the build on missing libraries or a broken npm
RUN node --version && npm --version && git --version

CMD ["/bin/bash"]

# Runtime image (<version>-r<release>-tumbleweed): node only, no shell, no npm
FROM scratch AS image

COPY --from=rootfs /rootfs/ /

ENV OPENSSL_CONF=/usr/local/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/local/lib64/ossl-modules

CMD ["/usr/local/bin/node"]

FROM scratch AS artifacts
COPY --from=app /usr/local/bin/node /usr/bin/node
