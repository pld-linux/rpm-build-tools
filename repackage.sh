#!/bin/sh
# will build package, skipping %prep and %build stage
# i use it a lot!
#
# -glen 2005-03-03

set -e

rpmbuild() {
	set -x
	# i'd use ./builder to get all the ~/.bcondrc parsing,
    # but builder doesn't understand -bi
#	./builder -ncs -nc -nn --opts --short-circuit "$@"
	command rpmbuild --short-circuit "$@" || exit
}
rpmbuild -bi "$@"
rpmbuild -bb "$@"
