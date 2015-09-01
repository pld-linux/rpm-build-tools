#!/bin/sh
# Update GeoIP packages to new version provided by MaxMind.
#
# Author: Elan Ruusamäe <glen@pld-linux.org>
#
# Changelog:
# 2012-07-04 Created initial version
# 2014-03-04 Rewritten to be smarter when checking for updates avoiding full download if no changes.
# 2014-06-06 Fix finding new versions if multiple previous archives were present
# 2015-08-25 Add auto commit support

set -e

update=false
status=false
commit=true
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

get_urls() {
	local specfile=$1 t url

	t=$(mktemp)
	builder -su $specfile 2>/dev/null > $t

	while read url; do
		# skip non-archives
		case "$url" in
		*.zip|*.gz|*.xz)
			echo "$url"
			;;
		esac
	done < $t
	rm -f $t
}

update_urls() {
	local specfile=$1 url fn z

	for url in "$@"; do
		# take output filename (anything after last slash)
		fn=${url##*/}
		# remove querystring for mtime match to work
		url=${url%\?*}
		test -e "$fn" && z= || unset z
		curl ${z+-z "$fn"} -o "$fn" "$url" -R -s
	done
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

commit_vcs() {
	local specfile="$1" version="$2"

	git commit -m "updated to $version" $specfile
}

# get version from package files
# set $version variable
version_from_files() {
	local pkg=$1 url fn dt d
	shift

	for url in "$@"; do
		# take output filename (anything after last slash)
		fn=${url##*/}
		# skip inexistent files
		test -e "$fn" || continue

		d=$(filedate "$fn")
		if [ "$(echo $d | tr -d -)" -gt "$(echo $dt | tr -d -)" ]; then
			dt=$d
		fi
	done

	case "$pkg" in
	xtables-geoip)
		version=$(echo "$dt" | tr -d -)
		;;
	*)
		version=$(echo "$dt" | tr - .)
		;;
	esac
}

dir=$(dirname "$0")
APPDIR=$(d=$0; [ -L "$d" ] && d=$(readlink -f "$d"); dirname "$d")
PATH=$APPDIR:$PATH
cd "$dir"

pkgs='GeoIP-db-City GeoIP-db-Country GeoIP-db-IPASNum xtables-geoip'
for pkg in ${*:-$pkgs}; do
	pkg=${pkg%.spec}
	$status && continue

	get_package $pkg
	cd $pkg
	specfile=*.spec

	urls=$(get_urls $specfile)
	update_urls $urls
	version_from_files $pkg $urls
	oldvers=$(awk '/^Version:[ 	]+/{print $NF}' $specfile)
	if [ "$oldvers" != "$version" ]; then
		update_version $specfile $version
		if $commit; then
			commit_vcs $specfile $version
		fi
	fi
	cd ..
done

# report each package git status
for pkg in ${*:-$pkgs}; do
	pkg=${pkg%.spec}
	cd $pkg
	git status --porcelain
	cd ..
done
