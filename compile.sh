#!/bin/sh
# will build package, skipping %prep and %build stage
# i use it a lot!
#
# Usage:
# do do only %build stage (ie after %prep has been done), for example after
# modifying some sources for more complicated specs wholse %build is not just
# %{__make}:
# SPECS$ ./compile.sh kdelibs.spec
#
# See also: SPECS/repackage.sh
#
# -glen 2005-03-03

set -x
exec ./builder -ncs -nn --short-circuit -bc "$@"
