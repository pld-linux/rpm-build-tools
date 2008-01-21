#!/bin/sh
# will build package, skipping %prep and %build stage
# i use it a lot!
#
# -glen 2005-03-03
#
# Usage:
# do %install and rpm package, skips %clean
# SPECS$ ./repackage.sh kdelibs.spec
#
# after that is done you could try only package creation (as %clean was
# skipped), for adjusting %files lists:
# SPECS$ ./repackage.sh kdelibs.spec -bb
#
# See also: SPECS/compile.sh
#
# TODO
# - make builder to understand -bi and use builder for short-circuit

set -e

rpmbuild() {
	set -x
	/usr/bin/rpmbuild \
		--define '_source_payload w9.gzdio' \
		--define 'clean exit 0; %{nil}' \
		--define 'check exit 0; %{nil}' \
		${TARGET:+--target $TARGET} \
		$BCONDS \
		--short-circuit \
		"$@" || exit
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
rpmbuild -bb "$@"
