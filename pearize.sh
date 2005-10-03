#!/bin/sh
# updates php-pear .spec with Requires/Conflicts lines.
# the items are added randomly to the preamble, but once added their order is left intact.
# it is still better than nothing. if somebody wishes to add sorting in this
# script. i'd be just glad :)
#
# needs pear makerpm command.
# requires tarball to exist in ../SOURCES.
# you should have all pear packages installed to get best results
#
# todo: adjust similiarily noautoreqdeps
# bugs: the beta portions in version deps could be wrong (php-4.3.0b1 and alike)
# see php-pear-DBA_Relational.spec
# SOmething strange: Requires:	php-common < 4:3:5.1
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

rc=$(awk '/^%define.*_rc/{print $NF}' $spec)
pre=$(awk '/^%define.*_pre/{print $NF}' $spec)
beta=$(awk '/^%define.*_beta/{print $NF}' $spec)
tarball=$(rpm -q --qf "../SOURCES/%{name}-%{version}$rc$pre$beta.tgz\n" --specfile "$spec" | head -n 1 | sed -e 's,php-pear-,,')

stmp=$(mktemp "${TMPDIR:-/tmp}/fragXXXXXX")
cat > $stmp <<'EOF'
@extra_headers@
Optional: @optional@
License: @release_license@
State: @release_state@
EOF
pear makerpm --spec-template=$stmp $tarball
rm -f $stmp

template=$(rpm -q --qf "%{name}-%{version}$rc$pre$beta.spec\n" --specfile "$spec" | head -n 1)
mv $template .$template~
template=.$template~

# take as argument dependency in form NAME EQUALITY VERSION
# adds rpm epoch to VERSION if the package is installed and has epoch bigger than zero.
add_epoch() {
	local dep="$@"
	local pkg="$1"
	local ver="$3"

	# already have epoch
	if [[ "$ver" = *:* ]]; then
		echo "$dep"
		return
	fi

	query=$(rpm -q --qf '%{epoch}\n' $pkg || :)
 	epoch=$(echo "$query" | grep -v 'installed' || :)
	if [ "$epoch" ] && [ "$epoch" -gt 0 ]; then
		echo "$dep" | sed -e "s, [<>=] ,&$epoch:,"
	else
		echo "$dep"
	fi
}

preamble=$(mktemp "${TMPDIR:-/tmp}/fragXXXXXX")
# take just main package preamble, preamble of tests (and other) subpackage(s) just confuses things.
sed -ne '/^Name:/,/^BuildRoot/p' $spec > $preamble

# create backup
bak=$(cp -fbv $spec $spec | awk '{print $NF}' | tr -d "['\`]" )

# parse requires
requires=$(grep '^Requires:' $template || :)
if [ -n "$requires" ]; then
	echo "$requires" | while read tag dep; do
		dep=$(add_epoch $dep)
		if ! grep -q "^Requires:.*$dep" $preamble; then
			sed -i -e "/^BuildRoot/iRequires:\t$dep" $spec
		fi
	done
fi

# parse conflicts
conflicts=$(grep '^Conflicts:' $template || :)
if [ -n "$conflicts" ]; then
	echo "$conflicts" | while read tag dep; do
		dep=$(add_epoch $dep)
		if ! grep -q "^Conflicts:.*$req" $preamble; then
			sed -i -e "/^BuildRoot/iConflicts:\t$dep" $spec
		fi
	done
fi

# parse state
state=$(awk '/^State:/{print $2}' $template)
sed -i -e "/^%define.*_status/{
	/%define.*_status.*$state/!s/.*/%define\t\t_status\t\t$state/
}" $spec

rm -f $preamble

diff=$(mktemp "${TMPDIR:-/tmp}/fragXXXXXX")
if ! diff -u $bak $spec > $diff; then
	vim -o $spec $diff
	rm -f $diff
else
	echo "$spec: No diffs"
fi
#exit 1
