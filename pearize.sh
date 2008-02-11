#!/bin/sh
# updates php-pear .spec with Requires/Conflicts lines.
# the items are added randomly to the preamble, but once added their order is left intact.
# it is still better than nothing. if somebody wishes to add sorting in this
# script. i'd be just glad :)
#
# needs 'pear' for 'pear makerpm' command, ./builder for fetching sources.
# You should have all PEAR packages installed to get best results (needed for epoch autodetection)
#
# todo: adjust similiarily noautoreqdeps
# bugs: the beta portions in version deps could be wrong (php-4.3.0b1 and alike)
# see php-pear-DBA_Relational.spec
# Something strange: Requires:	php-common < 4:3:5.1
#
# NOTE: old version of this script which was used to convert to new package format is in CVS branch MIGRATE.
#
# Send blames and beerideas to glen@pld-linux.org

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

if [[ "$(rpm -q php-pear-PEAR_Command_Packaging)" == *is?not* ]]; then
	echo >&2 "Please install php-pear-PEAR_Command_Packaging"
	exit 1
fi
echo "Processing $spec"

getsource() {
	local spec="$1"
	local NR="$2"
	rpmbuild --nodigest --nosignature -bp --define 'prep %dump' $spec 2>&1 | awk  "/SOURCE$NR\t/ {print \$3}"
}

tarball=$(getsource $spec 0)
if [ -z "$tarball" ]; then
	echo >&2 "Spec is missing Source0!"
	exit 1
fi

if [ ! -f $tarball ]; then
	./builder -g "$spec"
fi

stmp=$(mktemp "${TMPDIR:-/tmp}/fragXXXXXX")
cat > $stmp <<'EOF'
@extra_headers@
Optional: @optional@
@optional-pkg@
@optional-ext@
License: @release_license@
State: @release_state@
EOF
pear make-rpm-spec --spec-template=$stmp --output=pearize.spec $tarball
template=pearize.spec
rm -f $stmp

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
		echo "$dep" | sed -e "s, [<>=]\+ ,&$epoch:,"
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

# parse optional deps
optional=$(grep '^Optional:' $template || :)
if [ -n "$optional" ]; then
	echo "$optional" | while read tag dep; do
		for req in $dep; do
			m=$(grep "^%define.*_noautoreq" $spec || :)
			if [ -z "$m" ]; then
				sed -i -e "/^BuildRoot:/{
					a
					a# exclude optional dependencies
					a%define\	\	_noautoreq\	$req
				}
				" $spec
			else
				m=$(echo "$m" | grep -o "$req" || :)
				if [ -z "$m" ]; then
					sed -i -e "/^%define.*_noautoreq/s,$, $req," $spec
				fi
			fi
		done
	done
fi
has_opt=$(egrep -c '^Optional-(pkg|ext):' $template || :)
if [ "$has_opt" -gt 0 ]; then
	if ! grep -q '%{_docdir}/.*/optional-packages.txt' $spec; then
		sed -i -e '
		/^%files$/{
			i%post
			iif [ -f %{_docdir}/%{name}-%{version}/optional-packages.txt ]; then
			i\	cat %{_docdir}/%{name}-%{version}/optional-packages.txt
			ifi
			i
		}
		' $spec
	fi
	if ! grep -q '%doc.*optional-packages.txt' $spec; then
		sed -i -e '
		/^%doc install.log/{
		s/$/ optional-packages.txt/
		}
		' $spec
	fi
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