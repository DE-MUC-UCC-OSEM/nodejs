#
# spec file for package nodejs
#

Name:           nodejs-binary
Version:        __VERSION__
Release:        __RELEASE__
Summary:        NodeJS binary
License:        MIT
URL:            https://mitel.com

Provides:      nodejs-binary = __VERSION__
Requires:      /bin/sh

# zstd payload: smaller RPM file (needs rpm >= 4.14 to build and install)
%define _binary_payload w19.zstdio

%description
Installing NodeJS binary version __VERSION__-__RELEASE__

%files
%attr(0755, root, root) "/usr/bin/node"
