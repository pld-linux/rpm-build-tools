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
	/usr/bin/rpmbuild --short-circuit --define '_source_payload w9.gzdio' "$@" || exit
}

# just create the rpm's if -bb is somewhere in the args
if [[ *$@* != *-bb* ]]; then
	rpmbuild -bi "$@"
fi
rpmbuild -bb --define 'clean %{nil}' "$@"
