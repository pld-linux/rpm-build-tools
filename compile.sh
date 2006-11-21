#!/bin/sh
# will build package, skipping %prep and %build stage
# i use it a lot!
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

BCONDS=$(./builder --show-bcond-args $specfile)

rpmbuild -bc "$@"
