#!/bin/sh
# creates .spec using pear makerpm command.
# requires tarball to exist in ../SOURCES.
#
set -e
spec="$1"
tarball=$(rpm -q --qf '../SOURCES/%{name}-%{version}.tgz' --specfile "$spec" | sed -e 's,php-pear-,,')
template=$(rpm -q --qf '%{name}-%{version}.spec' --specfile "$spec")

pear makerpm $tarball
ls -l $template
# remove false sectons
sed -i -e '/^%if 0/,/%endif/d' $template
# and reversed true sections
sed -i -e '/^%if !1/,/%endif/d' $template
# kill consequtive blank lines
# http://info.ccone.at/INFO/Mail-Archives/procmail/Jul-2004/msg00132.html
sed -i -e '/./,$ !d;/^$/N;/\n$/D' $template
vim -o $spec $template
