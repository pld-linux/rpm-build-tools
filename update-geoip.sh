#!/bin/sh
set -x
set -e
pkgs='GeoIP-db-City GeoIP-db-Country GeoIP-db-IPASNum xtables-geoip'
for pkg in ${*:-$pkgs}; do
	./builder -g -ns $pkg
	cd $pkg
	rm -vf *.gz *.zip
	specfile=*.spec
	../md5 -p1 $specfile
	version=$(awk '/^Version:[ 	]+/{print $NF}' $specfile)
	if [ $pkg = "xtables-geoip" ]; then
		dt4=$(stat -c '%y' *.zip | awk '{print $1}' | tr -d -)
		dt6=$(stat -c '%y' *.gz | awk '{print $1}' | tr -d -)
		if [ "$dt4" -gt "$dt6" ]; then
			dt=$dt4
		else
			dt=$dt6
		fi
	else
		dt=$(stat -c %y *.gz | awk '{print $1}' | tr - .)
	fi
	if [ "$version" != "$dt" ]; then
		version=$dt
		sed -i -e "
			s/^\(Version:[ \t]\+\)[.0-9]\+\$/\1$version/
			s/^\(Release:[ \t]\+\)[.0-9]\+\$/\11/
		" $specfile
	fi

	../builder -bb *.spec
	cd ..
done
