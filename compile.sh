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
set -x
exec $dir/builder --no-md5 -ncs -nn --short-circuit -bc "$@"
