#!/bin/sh
# updates php-pear .spec with Requires/Conflicts lines.
# the items are added randomly to the preamble, but once added their order is left intact.
# it is still better than nothing. if somebody wishes to add sorting in this
# script. i'd be just glad :)
#
# needs 'pear' for 'pear make-rpm-spec' command, ./builder for fetching sources.
# You should have all PEAR packages installed to get best results (needed for epoch autodetection)
# So far there are 3 packages with epoch > 0:
# $ grep ^Epoch:.* php-pear-*.spec | grep -v 'Epoch:.*0'
# php-pear-MDB2.spec:Epoch:               1
# php-pear-MDB.spec:Epoch:                1
# php-pear-PEAR.spec:Epoch:               1
#
# To create completely new PEAR package spec, follow something like this:
# $ pear download RDF-alpha
# File RDF-0.1.0alpha1.tgz downloaded
# $ pear make-rpm-spec RDF-0.1.0alpha1.tgz
# Wrote RPM spec file php-pear-RDF.spec
# $
#
# TODO: adjust similiarily noautoreqdeps
# BUGS: the beta portions in version deps could be wrong (php-4.3.0b1 and alike)
# see php-pear-DBA_Relational.spec
# Something strange: Requires:	php-common < 4:3:5.1
#
# NOTE: old version of this script which was used to convert to new package format is in CVS branch MIGRATE.
#
# Send blames and beerideas to glen@pld-linux.org

PROGRAM=${0##*/}
APPDIR=$(d=$0; [ -L "$d" ] && d=$(readlink -f "$d"); dirname "$d")

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
	$APPDIR/builder -g "$spec"
fi

stmp=$(mktemp "${TMPDIR:-/tmp}/fragXXXXXX")
template=pearize.spec
cat > $stmp <<'EOF'
@extra_headers@
License: @release_license@
State: @release_state@
EOF
pear make-rpm-spec --spec-template=$stmp --output=$template $tarball
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

# ensure rpm-build-macros is present
if ! grep -q "^BuildRequires:.*rpmbuild(macros)" $preamble; then
	sed -i -e "/^BuildRequires:.*rpm-php-pearprov/aBuildRequires:\trpmbuild(macros) >= 1.300" $spec
fi
# parse requires
requires=$(grep '^BuildRequires:' $template || :)
if [ -n "$requires" ]; then
	echo "$requires" | while read tag dep; do
		dep=$(add_epoch $dep)
		if ! grep -q "^BuildRequires:.*$dep" $preamble; then
			sed -i -e "/^BuildRoot/iBuildRequires:\t$dep" $spec
		fi
	done
fi

requires=$(grep '^Requires:' $template || :)
if [ -n "$requires" ]; then
	echo "$requires" | while read tag dep; do
		dep=$(add_epoch $dep)
		if ! grep -q "^Requires:.*$dep" $preamble; then
			dep=$(echo "$dep" | sed -e 's,php-pear-PEAR\b,php-pear-PEAR-core,')
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
optional=$(grep '^Suggests:' $template || :)
if [ -n "$optional" ]; then
	echo "$optional" | while read tag dep; do
		dep=$(add_epoch $dep)
		if ! grep -q "^Suggests:.*$dep" $preamble; then
			sed -i -e "/^BuildRoot/iSuggests:\t$dep" $spec
		fi

		for req in $dep; do
			case "$req" in
			php-pear-*)
				# convert pear package name to file pattern
				req=$(echo "$req" | sed -e 's,^php-pear-,pear(,;y,_,/,;s,$,.*),')
				;;
			*)
				# process only php-pear-* packages
				continue
				;;
			esac

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

optional=$(grep '^Optional-ext:' $template || :)
if [ -n "$optional" ]; then
	tmp=$(mktemp "${TMPDIR:-/tmp}/fragXXXXXX")
	echo "$optional" | while read tag ext; do
		grep -q "PHP extension .$ext" && continue
		cat > $tmp <<-EOF
		echo '%{name} can optionally use PHP extension "$ext"' >> optional-packages.txt
		EOF
		sed -i -e "
		/%pear_package_setup/ {
			r $tmp
		}
		" $spec
	done
	rm -f .ext.tmp
fi

has_opt=$(grep -Ec '^Optional-(pkg|ext):' $template || :)
if [ "$has_opt" -gt 0 ]; then
	if ! grep -q 'rpmbuild(macros)' $spec; then
		sed -i -e '
		/rpm-php-pearprov/{
			aBuildRequires:	rpmbuild(macros) >= 1.300
		}
		' $spec
	fi
	if ! grep -Eq '%{_docdir}/.*/optional-packages.txt|%pear_package_print_optionalpackages' $spec; then
		sed -i -e '
		/^%files$/{
			i%post -p <lua>
			i%pear_package_print_optionalpackages
			i
		}
		/rpmbuild(macros)/{
			s/>=.*/>= 1.571/
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
sed -i -e "/^%define.*_\?status/{
	s/%define[[:space:]]*_status.*/%define\t\t_status\t\t$state/
	s/%define[[:space:]]*status.*/%define\t\tstatus\t\t$state/
}" $spec

# parse license
#license=$(awk '/^License:/{print $2}' $template)
#sed -i -e "s/^License:.*/License:\t$license/" $spec

rm -f $preamble

diff=$(mktemp "${TMPDIR:-/tmp}/fragXXXXXX")
if ! diff -u $bak $spec > $diff; then
	vim -o $spec $diff
	rm -f $diff
else
	echo "$spec: No diffs"
fi
