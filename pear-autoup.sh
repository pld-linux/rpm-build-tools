#!/bin/sh
# Try to update pear packages from current distro repos to latest in
# pear.php.net.
#
# $Id$
# Author: Elan Ruusamäe <glen@pld-linux.org>

set -e

# test that php is working
php -r 'echo "PHP is working OK\n";'

# test that pear is working
pear info PEAR >/dev/null

# needed pkgs for upgrade test
rpm -q php-packagexml2cl php-pear-PEAR_Command_Packaging

[ -s pear.ls ] || { poldek --upa; poldek -q -Q --skip-installed --cmd 'ls php-pear-*' > pear.ls; }
[ -s pear.desc ] || {
	for pkg in $(cat pear.ls); do
		poldek -q --skip-installed --cmd "desc $pkg"
	done
} > pear.desc
[ -s pear.pkgs ] || {
	awk '/^Source.package:/{print $3}' < pear.desc | sed -re 's,-[^-]+-[^-]+.src.rpm$,,' | sort -u > pear.pkgs

	# filter out tests, see https://bugs.launchpad.net/poldek/+bug/620362
	sed -i -e '/-tests/d' pear.pkgs
	# more packages affected
	sed -i -e '/php-pear-Auth_Container_ADOdb/d' pear.pkgs
	sed -i -e '/php-pear-DB_DataObject-cli/d' pear.pkgs
	# not pear pkg
	sed -i -e '/^php-pear$/d' pear.pkgs
}

[ -f pear.installed ] || {
	sudo poldek  --update --upa
	sed -e 's,^,install ,' pear.pkgs | sudo poldek
	touch pear.installed
}
[ -s pear.upgrades ] || pear list-upgrades > pear.upgrades

for pkg in $(cat pear.pkgs); do
	# check if there's update in channel
	pearpkg=${pkg#php-pear-}
	ver=$(awk -vpkg=$pearpkg '$2 == pkg {print $5}' pear.upgrades)
	[ "$ver" ] || continue

	# skip already processed packages
	[ -d $pkg ] && continue

	# try upgrading with specified version
	# pldnotify.awk uses "pear remote-info" which does not respect preferred package states
	./builder -bb -u $pkg --upgrade-version $ver --define "_unpackaged_files_terminate_build 1" || {
		cat >&2 <<-EOF

		$pkg failed

		EOF
		exit 1
	}

	# check for bad versions (which needs macros
	ver=$(awk '/^Version:/{print $2; exit}' $pkg/$pkg.spec)
	case "$ver" in
	*RC* | *a* | *b* | *alpha* | *beta* | *dev*)
		cat >&2 <<-EOF

		Package $pkg contains bad version: $ver
		Update it to use %subver macro instead.

		EOF
		exit 1
		;;
	esac
done
