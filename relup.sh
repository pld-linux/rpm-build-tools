#!/bin/bash
# script to run after "release bump" style change.
# takes Release from spec and creates commit with message
# groups similiar commits together.
# "- release $rel"

set -e

get_dump() {
	local specfile="$1"
	local rpm_dump
	local success="y"
	if [ -x /usr/bin/rpm-specdump ]; then
		rpm_dump=$(rpm-specdump "$specfile" 2>&1) || success="n"
	else
		rpm_dump=$(rpm --specfile "$specfile" --define 'prep %dump' -q 2>&1) || success="n"
	fi
	if [ "$success" != "y" ]; then
		echo >&2 "$rpm_dump"
		echo >&2 "You need icon files being present in SOURCES."
		exit 1
	fi
	echo "$rpm_dump"
}

usage="Usage:
${0##*/} [-i] [-g] [-u] [-t|-n] [-m <MESSAGE>] <SPECLIST>

Options:
-i
  Try to increment package release
-g
 get packages if missing, do nothing else
-u
 update packages (git pull)
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
		rel=$(echo "$dump" | awk '$2~/^(PACKAGE_)?RELEASE$/{print $NF; exit}')
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

	# strip branch
	specfile=${specfile%:*}
	# basename
	specfile=${specfile##*/}
	# strip .spec
	package=${specfile%.spec}

	echo $package
}

get_branch() {
	local specfile="${1%/}" branch

	branch=${specfile#*:}

	if [ "$branch" != "$specfile" ]; then
		echo "$branch"
	else
		echo ""
	fi
}

if [ ! -x /usr/bin/getopt ]; then
	echo >&1 "You need to install util-linux to use relup.sh"
	exit 1
fi

t=$(getopt -o 'm:inguth' -n "${0##*/}" -- "$@") || exit $?
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
	-g)
		get=1
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
	branch=$(get_branch "$pkg")
	# pkg: package %{name}
	pkg=$(package_name "$pkg")

	# spec: package/package.spec
	spec=$(rpm -D "name $pkg" -E '%{_specdir}/%{name}.spec')
	spec=${spec#$topdir/}

	# pkgdir: package/
	pkgdir=${spec%/*}

	# specname: only spec filename
	specname=${spec##*/}

	# start real work
	if [ -n "$branch" ]; then
		echo "$pkg:$branch ..."
	else
		echo "$pkg ..."
	fi

	# get package
	[ "$get" = 1 -a -d "$pkgdir" ] && continue

	if [ "$update" = "1" -o "$get" = "1" ]; then
		if [ -n "$branch" ]; then
			./builder -g -ns "$spec" -r $branch
		else
			./builder -g -ns "$spec"
		fi
	fi

	[ "$get" = 1 ] && continue

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

		# refetch release
		rel=$(get_release "$spec")
	fi

	# commit the changes
	msg=""
	[ -n "$message" ] && msg="${msg}$message$n$n"
	msg="${msg}Release ${rel%%%*} (by relup.sh)"

	echo git commit -m "$msg" $spec
	if [ "$test" != 1 ]; then
		cd $pkgdir
		git commit -m "$msg" $specname
		git push
		cd ..
	fi
done
