#!/bin/sh
# script to run after "rel up" style change.
# takes Release from spec and creates commit with message
# groups similiar commits together.
# "- rel $rel"
# - fails when specfile defines Icon: but the icon is not present in SOURCES
# TODO
# - optional message after rel: "- rel 9 (rebuild with foolib)"

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
${0##*/} [-i] [-u] [-t] [-m <MESSAGE>] <SPECLIST>

Options:
-i
  Try to increment package release
-u
  cvs update first
-t
  Test mode. do not commit
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

if [ ! -x /usr/bin/getopt ]; then
	echo >&1 "You need to install util-linux to use relup.sh"
	exit 1
fi

t=$(getopt -o 'm:iuth' -n "${0##*/}" -- "$@") || exit $?
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
	-t)
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

tmpd=$(mktemp -d "${TMPDIR:-/tmp}/relXXXXXX")
for spec in "$@"; do
	spec=${spec%.spec}.spec
	rel=$(get_release "$spec")
	if [ "$inc" = 1 ]; then
		newrel=$(expr $rel + 1)
		set_release "$spec" $rel $newrel

		# refetch release
		rel=$(get_release "$spec")
	fi
	echo "$spec" >> "$tmpd/$rel"
done

for file in $(ls "$tmpd" 2>/dev/null); do
	files=$(cat "$tmpd/$file")
	rel=$(basename "$file")
	msg="- release $rel${message:+ ($message)}"
	echo cvs ci -m "'$msg'"
	if [ "$test" != 1 ]; then
		if [ "$update" = "1" ]; then
			cvs up $files
		fi
		cvs ci -m "$msg" $files
	fi
done
rm -rf $tmpd
