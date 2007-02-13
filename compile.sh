#!/bin/sh
# will build package, skipping %prep and %build stage
# i use it a lot!
#
# Usage:
# do do only %build stage (ie after %prep has been done), for example after
# modifying some sources for more complicated specs wholse %build is not just
# %{__make}:
# SPECS$ ./compile.sh kdelibs.spec
#
# See also: SPECS/repackage.sh
#
# -glen 2005-03-03

set -e

rpmbuild() {
	set -x
	/usr/bin/rpmbuild ${TARGET:+--target $TARGET} $BCONDS --short-circuit "$@" || exit
}

specfile="${1%.spec}.spec"; shift
set -- "$specfile" "$@"

tmp=$(awk '/^BuildArch:/ { print $NF}' $specfile)
if [ "$tmp" ]; then
	TARGET="$tmp"
fi

BCONDS=$(./builder -nn -ncs --show-bcond-args $specfile)

rpmbuild -bc "$@"
