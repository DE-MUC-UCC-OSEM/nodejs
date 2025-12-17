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

%description
Installing NodeJS binary version __VERSION__-__RELEASE__

%files
%attr(0755, root, root) "/usr/bin/node"
