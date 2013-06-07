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

skip_dep_generators() {
	local dep
	for dep in \
		font \
		gstreamer \
		java \
		kernel \
		libtool \
		mimetype \
		mono \
		perl \
		php \
		pkgconfig \
		python \
		ruby \
	; do
		printf "--define __%s_provides%%{nil}\n" $dep
		printf "--define __%s_requires%%{nil}\n" $dep
	done
}

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
		--define '_enable_debug_packages 0' \
		${bb+$(skip_dep_generators)} \
		${bb+--define '%py_postclean() %{nil}'} \
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
else
	# $1 must be spec, ensure it has .spec ext
	spec=$1; shift
	set -- ${spec%.spec}.spec "$@"
fi

tmp=$(specdump "$@" | awk '$2 == "_target_cpu" {print $3}')
if [ "$tmp" ]; then
	TARGET="$tmp"
fi

# skip -bi if -bb is somewhere in the args
if [[ *$@* = *-bb* ]]; then
	bb=
else
	bb= rpmbuild -bi "$@"
	unset bb
fi
rpmbuild -bb "$@"
