#!/bin/sh
# Update GeoIP packages to new version provided by MaxMind.
#
# Author: Elan Ruusamäe <glen@pld-linux.org>
# 2012-07-04 Created initial version
# 2014-03-04 Rewritten to be smarter when checking for updates avoiding full download if no changes.

set -e

update=false
status=false
while [ $# -gt 0 ]; do
	case "$1" in
	update|-u|-update|--update)
		update=true
		shift
		;;
	status|-s|-status|--status)
		status=true
		shift
		;;
	*)
		break
		;;
	esac
done

# get file DATE in GMT timezone
filedate() {
	local file="$1"
	TZ=GMT stat -c '%y' "$file" | awk '{print $1}'
}

# get package, no sources
get_package() {
	local pkg=$1 out
	out=$(builder -g -ns $pkg 2>&1) || echo "$out"
}

update_urls() {
	local specfile=$1 t fn z
	# update urls
	t=$(mktemp)
	builder -su $specfile > $t 2>/dev/null
	while read url; do
		# take output filename (anything after last slash)
		fn=${url##*/}
		# remove querystring for mtime match to work
		url=${url%\?*}
		test -e "$fn" && z= || unset z
		curl ${z+-z "$fn"} -o "$fn" "$url" -R -s
	done < $t
	rm -f $t
}

# set version to $version in $specfile and build the package
update_version() {
	local specfile="$1" version="$2" out

	# update version
	sed -i -e "
		s/^\(Version:[ \t]\+\)[.0-9]\+\$/\1$version/
		s/^\(Release:[ \t]\+\)[.0-9]\+\$/\11/
	" $specfile

	# update md5
	out=$(md5 -p1 $specfile 2>&1) || echo "$out"

	# build it
	out=$(builder -bb $specfile 2>&1) || echo "$out"
}

# get version from package files
# set $version variable
version_from_files() {
	local pkg=$1 dt4 dt6
	case "$pkg" in
	xtables-geoip)
		dt4=$(filedate *.zip | tr -d -)
		dt6=$(filedate *.gz | tr -d -)
		if [ "$dt4" -gt "$dt6" ]; then
			version=$dt4
		else
			version=$dt6
		fi
		;;
	GeoIP-db-City)
		dt4=$(filedate GeoLiteCity-*.dat.xz | tr - .)
		dt6=$(filedate GeoLiteCityv6-*.dat.gz | tr - .)
		if [ "$(echo $dt4 | tr -d .)" -gt "$(echo $dt6 | tr -d .)" ]; then
			version=$dt4
		else
			version=$dt6
		fi
		;;
	GeoIP-db-Country)
		dt4=$(filedate GeoIP-*.dat.gz | tr - .)
		dt6=$(filedate GeoIPv6-*.dat.gz | tr - .)
		if [ "$(echo $dt4 | tr -d .)" -gt "$(echo $dt6 | tr -d .)" ]; then
			version=$dt4
		else
			version=$dt6
		fi
		;;
	*)
		version=$(filedate *.gz | tr - .)
		;;
	esac
}

dir=$(dirname "$0")
APPDIR=$(d=$0; [ -L "$d" ] && d=$(readlink -f "$d"); dirname "$d")
PATH=$APPDIR:$PATH
cd "$dir"

pkgs='GeoIP-db-City GeoIP-db-Country GeoIP-db-IPASNum xtables-geoip'
for pkg in ${*:-$pkgs}; do
	$status && continue

	get_package $pkg
	cd $pkg
	specfile=*.spec

	update_urls $specfile
	version_from_files $pkg
	oldvers=$(awk '/^Version:[ 	]+/{print $NF}' $specfile)
	if [ "$oldvers" != "$version" ]; then
		update_version $specfile $version
	fi
	cd ..
done

# report each package git status
for pkg in ${*:-$pkgs}; do
	cd $pkg
	git status --porcelain
	cd ..
done
