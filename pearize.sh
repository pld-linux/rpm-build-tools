#!/bin/sh
# updates php-pear .spec with Requires/Conflicts lines.
# the items are added randomly to the preamble, but once added their order is left intact.
# it is still better than nothing. if somebody wishes to add sorting in this
# script. i'd be just glad :)
#
# needs pear makerpm command.
# requires tarball to exist in ../SOURCES.
#
# bugs: will not find tarball for packages with 'beta' and 'alpha' in version.
#
# todo: adjust similiarily noautoreqdeps
#
# note: old version pf this script which was used to convert to new package format is in CVS branch MIGRATE
# send blames and beerideas to glen@pld-linux.org

set -e
spec="$1"
if [ -z "$spec" ]; then
	echo >&2 "Usage: $0 SPECFILE"
	exit 0
fi
if [ ! -f "$spec" ]; then
	echo >&2 "$spec doesn't exist?"
	exit 1
fi
echo "Processing $spec"
tarball=$(rpm -q --qf '../SOURCES/%{name}-%{version}.tgz\n' --specfile "$spec" | head -n 1 | sed -e 's,php-pear-,,')
template=$(rpm -q --qf '%{name}-%{version}.spec\n' --specfile "$spec" | head -n 1)

pear makerpm --spec-template=template.spec $tarball
ls -l $spec $template

requires=$(grep '^Requires:' $template || :)
conflicts=$(grep '^Conflicts:' $template || :)
preamble=$(mktemp "${TMPDIR:-/tmp}/fragXXXXXX")
# take just main package preamble, preamble of tests (and other) subpackage(s) just confuses things.
sed -ne '/^Name:/,/^BuildRoot/p' $spec > $preamble

# take as argument dependency in form NAME EQUALITY VERSION
# adds rpm epoch to VERSION if the package is installed and has epoch bigger than zero.
add_epoch() {
	local dep="$@"
	local pkg="$1"
	query=$(rpm -q --qf '%{epoch}\n' $pkg || :)
 	epoch=$(echo "$query" | grep -v 'installed' || :)
	if [ "$epoch" ] && [ "$epoch" -gt 0 ]; then
		echo "$dep" | sed -e "s, [<>=] ,&$epoch:,"
	else
		echo "$dep"
	fi
}

# create backup
bak=$(cp -fbv $spec $spec | awk '{print $NF}' | tr -d "['\`]" )

if [ -n "$requires" ]; then
	echo "$requires" | while read tag dep; do
		dep=$(add_epoch $dep)
		if ! grep -q "^Requires:.*$dep" $preamble; then
			sed -i -e "/^BuildRoot/iRequires:\t$dep" $spec
		fi
	done
fi

if [ -n "$conflicts" ]; then
	echo "$conflicts" | while read tag reqc; do
		dep=$(add_epoch $dep)
		if ! grep -q "^Conflicts:.*$req" $preamble; then
			sed -i -e "/^BuildRoot/iConflicts:\t$dep" $spec
		fi
	done
fi

rm -f $preamble

set -e
diff=$(mktemp "${TMPDIR:-/tmp}/fragXXXXXX")
if ! diff -u $bak $spec > $diff; then
	vim -o $spec $diff
	rm -f $diff
else
	echo "$spec: No diffs"
fi
