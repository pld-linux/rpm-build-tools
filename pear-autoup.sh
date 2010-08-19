#!/bin/sh
# Try to update pear packages from current distro repos to latest in
# pear.php.net.
#
# $Id$
# Author: Elan Ruusamäe <glen@pld-linux.org>

set -e

[ -f pear.ls ] || poldek -q --skip-installed --cmd 'ls php-pear-* | desc'
[ -f pear.pkgs ] || awk '/^Source.package:/{print $3}' < pear.ls | sort -u | sed -re 's,-[^-]+-[^-]+.src.rpm$,,' > pear.pkgs

# filter out tests, see https://bugs.launchpad.net/poldek/+bug/620362
sed -i -e '/-tests/d' pear.pkgs
# more packages affected
sed -i -e '/php-pear-Auth_Container_ADOdb/d' pear.pkgs
sed -i -e '/php-pear-DB_DataObject-cli/d' pear.pkgs

for pkg in $(cat pear.pkgs); do
	[ -d $pkg ] && continue
	./builder -bb -u $pkg || {
		cat >&2 <<-EOF

		$pkg failed

		EOF
		exit 1
	}

	# check for bad versions (which needs macros
	ver=$(awk '/^Version:/{print $2; exit}' $pkg/$pkg.spec);
	case "$ver" in
	*RC* | *a* | *b* | *alpha* | *beta*)
		cat >&2 <<-EOF

		Package $pkg contains bad version: $ver
		Update it to use %subver macro instead.

		EOF
		exit 1
		;;
	esac

done
