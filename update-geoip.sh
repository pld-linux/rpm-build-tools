#!/bin/sh
set -e

update=false
status=false
while [ $# -gt 0 ]; do
	case "$1" in
	update|-update|--update)
		update=true
		shift
		;;
	status|-status|--status)
		status=true
		shift
		;;
	*)
		break
		;;
	esac
done

dir=$(dirname "$0");
cd "$dir"

pkgs='GeoIP-db-City GeoIP-db-Country GeoIP-db-IPASNum xtables-geoip'
for pkg in ${*:-$pkgs}; do
	$status && continue

	out=$(./builder -g -ns $pkg 2>&1) || echo "$out"
	cd $pkg

	$update && rm -vf *.gz *.zip *.xz

	specfile=*.spec

	out=$(../md5 -p1 $specfile 2>&1) || echo "$out"

	version=$(awk '/^Version:[ 	]+/{print $NF}' $specfile)
	case "$pkg" in
	xtables-geoip)
		dt4=$(TZ=GMT stat -c '%y' *.zip | awk '{print $1}' | tr -d -)
		dt6=$(TZ=GMT stat -c '%y' *.gz | awk '{print $1}' | tr -d -)
		if [ "$dt4" -gt "$dt6" ]; then
			dt=$dt4
		else
			dt=$dt6
		fi
		;;
	GeoIP-db-City)
		dt=$(TZ=GMT stat -c %y *.xz | awk '{print $1}' | tr - .)
		;;
	*)
		dt=$(TZ=GMT stat -c %y *.gz | awk '{print $1}' | tr - .)
		;;
	esac

	if [ "$version" != "$dt" ]; then
		version=$dt
		sed -i -e "
			s/^\(Version:[ \t]\+\)[.0-9]\+\$/\1$version/
			s/^\(Release:[ \t]\+\)[.0-9]\+\$/\11/
		" $specfile
	fi

	out=$(../builder -bb *.spec 2>&1) || echo "$out"
	cd ..
done

for pkg in ${*:-$pkgs}; do
	cd $pkg
	git status --porcelain
	cd ..
done
