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
	# use gz payload as time is what we need here, not compress ratio

	# we use %__ldconfig variable to test are we on rpm 4.4.9
	# on 4.4.9 we should not redefine %clean to contain %clean, and redefine %__spec_clean_body instead
	# on 4.4.2 we must redefine %clean to contain %clean
	set -x
	/usr/bin/rpmbuild \
		${TARGET:+--target $TARGET} \
		$BCONDS \
		--short-circuit \
		--define 'clean %%%{!?__ldconfig:clean}%{?__ldconfig:check} \
		exit 0%{nil}' \
		--define 'check %%check \
		exit 0%{nil}' \
		--define '_source_payload w9.gzdio' \
		--define '__spec_install_pre %___build_pre' \
		--define '__spec_clean_body %{nil}' \
		"$@" || exit
}

specfile="${1%.spec}.spec"; shift
set -- "$specfile" "$@"

tmp=$(rpm-specdump "$@" | awk '$2 == "_target_cpu" {print $3}')
if [ "$tmp" ]; then
	TARGET="$tmp"
fi

BCONDS=$(./builder -nn -ncs --show-bcond-args $specfile)

# just create the rpm's if -bb is somewhere in the args
if [[ *$@* != *-bb* ]]; then
	rpmbuild -bi "$@"
fi
rpmbuild -bb "$@"
