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
	# preprocess args, we must have --target as first arg to rpmbuild
	# we need to grab also dir where spec resides
	local a spec specdir
	while [ $# -gt 0 ]; do
		case "$1" in
		--target)
			shift
			TARGET=$1
			;;
		*.spec)
			spec="$1"
			a="$a $1"
			;;
		*)
			a="$a $1"
			;;
		esac
		shift
	done

    specdir=$(dirname "$(pwd)/${spec:-.}")

	# use gz payload as time is what we need here, not compress ratio

	# we use %__ldconfig variable to test are we on rpm 4.4.9
	# on 4.4.9 we should not redefine %clean to contain %clean, and redefine %__spec_clean_body instead
	# on 4.4.2 we must redefine %clean to contain %clean
	set -x
	/usr/bin/rpmbuild \
		${TARGET:+--target $TARGET} \
		--short-circuit \
		--define "_specdir $specdir" --define "_sourcedir $specdir" \
		--define 'clean %%%{!?__ldconfig:clean}%{?__ldconfig:check} \
		exit 0%{nil}' \
		--define 'check %%check \
		exit 0%{nil}' \
		--define '_source_payload w5.gzdio' \
		--define '_binary_payload w5.gzdio' \
		--define '__spec_install_pre %___build_pre' \
		--define '__spec_clean_body %{nil}' \
		$a || exit
}

specdump() {
	local a
	while [ $# -gt 0 ]; do
		case "$1" in
		--target|--with|--without)
			a="$a $1 $2"
			shift
			;;
		--define)
			a="$a $1 \"$2\""
			shift
			;;
		-*)
			;;
		*)
			a="$a $1"
			;;
		esac
		shift
	done
	set -x
	eval rpm-specdump $a || echo >&2 $?
}

if [ $# = 0 ]; then
	# if no spec name passed, glob *.spec
	set -- *.spec
	if [ ! -f "$1" -o $# -gt 1 ]; then
		echo >&2 "ERROR: Too many or too few .spec files found"
		echo >&2 "Usage: ${0##*/} PACKAGE.spec"
		exit 1
	fi
fi

tmp=$(specdump "$@" | awk '$2 == "_target_cpu" {print $3}')
if [ "$tmp" ]; then
	TARGET="$tmp"
fi

# just create the rpm's if -bb is somewhere in the args
if [[ *$@* != *-bb* ]]; then
	rpmbuild -bi "$@"
fi
rpmbuild -bb "$@"
