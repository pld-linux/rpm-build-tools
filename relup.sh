#!/bin/sh
# script to run after "rel up" style change.
# takes Release from spec and creates commit with message
# "- rel $rel"

set -e
specfile="$1"

get_dump() {
	rpm --specfile "$specfile" --define 'prep %dump'  -q 2>&1
}

get_release() {
	awk '/PACKAGE_RELEASE/{print $NF; exit}'
}

rel=$(get_dump | get_release)
echo "Release: $rel"
if [ "$rel" ]; then
	cvs ci -m "- rel $rel" $specfile
fi
