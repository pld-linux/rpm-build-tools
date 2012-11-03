#!/bin/sh
# Try to update pear packages from current distro repos to latest in
# pear.php.net.
#
# Created Date: 2010-08-19
# Author: Elan Ruusamäe <glen@pld-linux.org>

set -e

builder=builder

if [ "$1" = "clean" ]; then
	rm -rf php-pear-* php-phpunit-* php-symfony-* php-symfony2-* php-firephp-* php-horde-* php-phpdocs-* pear.* BUILD/* RPMS/*
	exit 0
fi

# test that php is working
php -r 'echo "PHP is working OK\n";'

# test that pear is working
pear info PEAR >/dev/null

# needed pkgs for upgrade test
rpm -q php-packagexml2cl php-pear-PEAR_Command_Packaging

[ -s pear.desc ] || { poldek --upa; poldek -q -Q --skip-installed --cmd 'search -r php-pear | desc' > pear.desc; }
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
	# as sudo & poldek don't allow us to capture (no pipe or redirection work),
	# we create markers which we could grab when invoked via "script"
	echo "BEGIN INSTALL PACKAGES"
	sed -e 's,^,install ,' pear.pkgs | sudo poldek
	echo "END INSTALL PACKAGES"
	# rm -f pear.installed && script -c ./pear-autoup.sh pear.install.log
	# sed -ne '/BEGIN INSTALL PACKAGES/,/END INSTALL PACKAGES/p' pear.install.log | grep -vE 'poldek:/.*install|: ambiguous name|equal version installed, skipped|Nothing to do' | less
	touch pear.installed
}
[ -s pear.upgrades ] || pear list-upgrades > pear.upgrades

subst=$(pear list-channels | awk -vORS="|" '/^[a-z]/{print $2}')
subst="s/^php-(${subst%\|})-//"

# clear it if you do not want to upgrade pkgs. i.e bring ac to sync
do_upgrade=1
#do_upgrade=

topdir=$(rpm -E %_topdir)
for pkg in $(cat pear.pkgs); do
	# check if there's update in channel
	pearpkg=$(echo "$pkg" | sed -re "$subst")
	ver=$(awk -vpkg=$pearpkg '$2 == pkg {print $5}' pear.upgrades)
	[ "$ver" ] || continue

	# skip already processed packages
	[ -d $pkg ] && continue

	# try upgrading with specified version
	# pldnotify.awk uses "pear remote-info" which does not respect preferred package states
	$builder -bb $pkg ${do_upgrade:+-u --upgrade-version $ver} --define "_unpackaged_files_terminate_build 1" || {
		cat >&2 <<-EOF

		$pkg failed

		EOF
		exit 1
	}

	# check for bad versions (which needs macros
	ver=$(awk '/^Version:/{print $2; exit}' $topdir/$pkg/$pkg.spec)
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
