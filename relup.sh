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

get_release() {
	local specfile="$1"
	rel=$(awk '/^%define[ 	]*_rel[ 	]/{print $NF}' $specfile)
	if [ -z "$rel" ]; then
		dump=$(get_dump "$specfile")
		rel=$(echo "$dump" | awk '/PACKAGE_RELEASE/{print $NF; exit}')
	fi
	echo $rel
}

if [ ! -x /usr/bin/getopt ]; then
	echo >&1 "You need to install util-linux to use relup.sh"
	exit 1
fi

t=`getopt -o 'm:' -n $(dirname "$0") -- "$@"` || exit $?
# Note the quotes around `$TEMP': they are essential!
eval set -- "$t"

while true; do
	case "$1" in
	-m)
		shift
		message="$1"
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
	echo "$spec" >> "$tmpd/$rel"
done

for file in $(ls "$tmpd" 2>/dev/null); do
	files=$(cat "$tmpd/$file")
	rel=$(basename "$file")
	msg="- rel $rel${message:+ ($message)}"
	echo cvs ci -m "'$msg'"
	cvs ci -m "$msg" $files
done
rm -rf $tmpd
