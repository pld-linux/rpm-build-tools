#!/bin/sh
# script to run after "release bump" style change.
# takes Release from spec and creates commit with message
# groups similiar commits together.
# "- release $rel"

set -e

get_dump() {
	local specfile="$1"
	if ! out=$(rpm --specfile "$specfile" --define 'prep %dump' -q 2>&1); then
		echo >&2 "$out"
		echo >&2 "You need icon files being present in SOURCES."
		exit 1
	fi
	echo "$out"
}

usage="Usage:
${0##*/} [-i] [-u] [-t] [-n] [-m <MESSAGE>] <SPECLIST>

Options:
-i
  Try to increment package release
-u
  git pull first
-t | -n
  Test mode (dry-run). do not commit
-m
  Specify commit message

"

get_release() {
	local specfile="$1"
	rel=$(awk '/^%define[ 	]+_?rel[ 	]+/{print $NF}' $specfile)
	if [ -z "$rel" ]; then
		dump=$(get_dump "$specfile")
		rel=$(echo "$dump" | awk '/PACKAGE_RELEASE/{print $NF; exit}')
	fi
	echo $rel
}

set_release() {
	local specfile="$1"
	local rel="$2"
	local newrel="$3"
	sed -i -e "
		s/^\(%define[ \t]\+_\?rel[ \t]\+\)$rel\$/\1$newrel/
		s/^\(Release:[ \t]\+\)$rel\$/\1$newrel/
	" $specfile
}

bump_release() {
	local release=$1 rel

	rel=$(expr ${release} + 1)
	echo $rel
}

# normalize spec
# takes as input:
# - PACKAGE/
# - ./PACKAGE/
# - PACKAGE
# - PACKAGE.spec
# - ./PACKAGE.spec
# - PACKAGE/PACKAGE
# - PACKAGE/PACKAGE.spec
# - ./PACKAGE/PACKAGE.spec
# - rpm/PACKAGE/PACKAGE
# - rpm/PACKAGE/PACKAGE.spec
# - ./rpm/PACKAGE/PACKAGE.spec
# returns PACKAGE
package_name() {
	local specfile="${1%/}" package

	# basename
	specfile=${specfile##*/}
	# strip .spec
	package=${specfile%.spec}

	echo $package
}

if [ ! -x /usr/bin/getopt ]; then
	echo >&1 "You need to install util-linux to use relup.sh"
	exit 1
fi

t=$(getopt -o 'm:inuth' -n "${0##*/}" -- "$@") || exit $?
# Note the quotes around `$t': they are essential!
eval set -- "$t"

while true; do
	case "$1" in
	-i)
		inc=1
		;;
	-u)
		update=1
		;;
	-t | -n)
		test=1
		;;
	-m)
		shift
		message="${1#- }"
		;;
	-h)
		echo "$usage"
		exit 0
		;;
	--)
		shift
	   	break
	;;
	*)
	   	echo 2>&1 "Internal error: [$1] not recognized!"
		exit 1
	   	;;
	esac
	shift
done

topdir=$(rpm -E '%{_topdir}')

n="$(echo -e '\nn')"
n="${n%%n}"

cd "$topdir"
for pkg in "$@"; do
	# pkg: package %{name}
	pkg=$(package_name "$pkg")

	# spec: package/package.spec
	spec=$(rpm -D "name $pkg" -E '%{_specdir}/%{name}.spec')
	spec=${spec#$topdir/}

	# pkgdir: package/
	pkgdir=${spec%/*}

	# start real work
	echo "$pkg ..."

	# get package
	if [ "$update" = "1" ]; then
		./builder -g -ns "$spec"
	fi

	# update .spec files
	rel=$(get_release "$spec")
	if [ "$inc" = 1 ]; then
		if [[ $rel = *%* ]]; then
			relmacro=${rel#*%}
			newrel=$(bump_release ${rel%%%*})
			set_release "$spec" $rel "${newrel}%${relmacro}"
		else
			newrel=$(bump_release ${rel})
			set_release "$spec" $rel $newrel
		fi
	fi

	# commit the changes
	msg=""
	[ -n "$message" ] && msg="$msg- $message$n"
	msg="$msg- release ${rel%%%*} (by relup.sh)"
	echo git commit -m "$msg" $spec
	if [ "$test" != 1 ]; then
		cd $pkgdir
		git commit -m "$msg" $spec
		git push
		cd ..
	fi
done
