#!/bin/sh
# script to run after "rel up" style change.
# takes Release from spec and creates commit with message
# groups similiar commits to gether.
# "- rel $rel"

set -e
specfile="$1"

get_dump() {
	local specfile="$1"
	rpm --specfile "$specfile" --define 'prep %dump'  -q 2>&1
}

get_release() {
	awk '/PACKAGE_RELEASE/{print $NF; exit}'
}


tmpd=$(mktemp -d "${TMPDIR:-/tmp}/relXXXXXX")
for spec in "$@"; do
	rel=$(get_dump "$spec" | get_release)
	echo "$spec" >> "$tmpd/$rel"
done

for file in $(ls "$tmpd" 2>/dev/null); do
	files=$(cat "$tmpd/$file")
	rel=$(basename "$file")
	cvs ci -m "- rel $rel" $files
done
rm -rf $tmpd
