FROM opensuse/tumbleweed:latest AS base

COPY nodejs*tar.xz /tmp

ARG RELEASE
RUN tar --directory /usr -xvf /tmp/nodejs-$RELEASE-$(uname -p).tar.xz && \
    rpm -e --allmatches $(rpm -qa --qf "%{NAME}\n" | grep -v -E "bash|coreutils|filesystem|glibc$|libacl1|libattr1|libcap2|libgcc_s1|libgmp|libncurses|libpcre1|libreadline|libselinux|libstdc\+\+|openSUSE-release|system-user-root|terminfo-base|libpcre2") && \
    rm -Rf /etc/zypp && \
    rm -Rf /usr/lib/zypp* && \
    rm -Rf /var/{cache,log,run}/* && \
    rm -Rf /var/lib/zypp && \
    rm -Rf /usr/lib/rpm && \
    rm -Rf /usr/lib/sysimage/rpm && \
    rm -Rf /usr/share/man && \
    rm -Rf /usr/local && \
    rm -Rf /srv/www

COPY nodejs.cnf /usr/etc/nodejs.cnf

FROM scratch

COPY --from=base / /

ENV OPENSSL_CONF=/usr/etc/nodejs.cnf
ENV OPENSSL_MODULES=/usr/lib/openssl-modules

ENTRYPOINT [ "/bin/bash" ]
