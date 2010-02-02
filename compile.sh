#!/bin/sh
# will build package, skipping %prep and %build stage
# i use it a lot!
#
# Usage:
# make only %build stage (i.e. after %prep has been done), for example after
# modifying some sources for more complicated specs whose %build is not just
# %{__make}:
# SPECS$ ./compile.sh kdelibs.spec
#
# See also: SPECS/repackage.sh
#
# -glen 2005-03-03

dir=$(dirname "$0")
if [ $# = 0 ]; then
	# if no spec name passed, glob *.spec
	set -- *.spec
	if [ ! -f "$1" -o $# -gt 1 ]; then
		echo >&2 "ERROR: Too many or too few .spec files found"
		echo >&2 "Usage: ${0##*/} PACKAGE.spec"
		exit 1
	fi
fi
exec $dir/builder --no-md5 -ncs -nn --short-circuit -bc "$@"
