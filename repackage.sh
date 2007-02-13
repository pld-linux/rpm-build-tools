#!/bin/sh
# will build package, skipping %prep and %build stage
# i use it a lot!
#
# -glen 2005-03-03
#
# TODO
# - make builder to understand -bi and use builder for short-circuit

set -e

rpmbuild() {
	set -x
	/usr/bin/rpmbuild ${TARGET:+--target $TARGET} $BCONDS --short-circuit --define '_source_payload w9.gzdio' "$@" || exit
}

specfile="${1%.spec}.spec"; shift
set -- "$specfile" "$@"

tmp=$(awk '/^BuildArch:/ { print $NF}' $specfile)
if [ "$tmp" ]; then
	TARGET="$tmp"
fi

BCONDS=$(./builder -nn -ncs --show-bcond-args $specfile)

# just create the rpm's if -bb is somewhere in the args
if [[ *$@* != *-bb* ]]; then
	rpmbuild -bi "$@"
fi
rpmbuild -bb --define 'clean %{nil}' "$@"
