FROM opensuse/tumbleweed:latest AS app

SHELL ["/bin/bash", "-c"]

ENV PREFIX=/usr/local

WORKDIR /opt

ARG NODE_SOURCE_VERSION
RUN zypper update --no-confirm && \
    zypper install --no-confirm gawk git python314 python314-pkgconfig gcc gcc16 gcc-c++ gcc16-c++ perl make nasm perl-Text-Template unzip autoconf libtool findutils && \
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
RUN ./configure --shared-openssl-libpath=${PREFIX}/lib64 --shared-openssl-includes=${PREFIX}/include --shared-openssl-libname=crypto,ssl --openssl-is-fips --disable-single-executable-application --without-corepack --without-node-snapshot && \
    make -j$(nproc) && \
    make install

FROM opensuse/tumbleweed:latest AS base

RUN rpm -e --allmatches $(rpm -qa --qf "%{NAME}\n" | grep -v -E "bash|coreutils|filesystem|glibc$|libacl1|libattr1|libcap2|libgcc_s1|libgmp|libncurses|libpcre|libreadline|libselinux|libstdc\+\+|openSUSE-release|system-user-root|terminfo-base") && \
    rm -Rf /etc/zypp && \
    rm -Rf /usr/lib/zypp* && \
    rm -Rf /var/{cache,log,run}/* && \
    rm -Rf /var/lib/zypp && \
    rm -Rf /usr/lib/rpm && \
    rm -Rf /usr/lib/sysimage/rpm && \
    rm -Rf /usr/share/man && \
    rm -Rf /usr/local && \
    rm -Rf /srv/www

COPY --from=app /usr/local/bin/ /usr/local/bin/
COPY --from=app /usr/local/lib/ /usr/local/lib/
COPY --from=app /usr/local/lib64/ /usr/local/lib64/
COPY --from=app /usr/local/ssl/ /usr/local/ssl/
COPY openssl.cnf /usr/local/ssl/openssl.cnf
COPY --chown=root:root --chmod=744 entrypoint.sh /entrypoint.sh

FROM scratch AS image

COPY --from=base / /

ENV OPENSSL_CONF=/usr/local/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/local/lib64/ossl-modules
ENV LD_LIBRARY_PATH=/usr/local/lib64

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]

FROM scratch AS artifacts
COPY --from=app /usr/local/bin/node /usr/bin/node
