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
	/usr/bin/rpmbuild ${TARGET:+--target $TARGET} --short-circuit --define '_source_payload w9.gzdio' "$@" || exit
}

bconds=$(./builder --show-bconds "$@")
# ignore output from older builders whose output is not compatible.
if [ "$(echo "$bconds" | wc -l)" -gt 1 ]; then
	bconds=""
fi

SPECFILE="$1"
tmp=$(awk '/^BuildArch:/ { print $NF}' $SPECFILE)
if [ "$tmp" ]; then
	TARGET="$tmp"
fi

# just create the rpm's if -bb is somewhere in the args
if [[ *$@* != *-bb* ]]; then
	rpmbuild -bi $bconds "$@"
fi
rpmbuild -bb --define 'clean %{nil}' $bconds "$@"
