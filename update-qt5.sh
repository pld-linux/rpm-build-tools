#!/bin/sh
# Update qt5 packages
#
# Author: Elan Ruusamäe <glen@pld-linux.org>
# 2015-06-13 Created initial version

set -e

# grep Version:.*5.4 ~/all-specs/qt5*.spec -l|xargs -I {} basename {} .spec
packages="
qt5-qtbase

qt5-qtconnectivity
qt5-qtdeclarative
qt5-qtdoc
qt5-qtenginio
qt5-qtgraphicaleffects
qt5-qtimageformats
qt5-qtlocation
qt5-qtmultimedia
qt5-qtscript
qt5-qtsensors
qt5-qtserialport
qt5-qtsvg
qt5-qttools
qt5-qtwayland
qt5-qtwebchannel
qt5-qtwebkit-examples
qt5-qtwebkit
qt5-qtwebsockets
qt5-qtx11extras
qt5-qtxmlpatterns

qt5-qtquick1
qt5-qtquickcontrols
"

dir=$(dirname "$0")
APPDIR=$(d=$0; [ -L "$d" ] && d=$(readlink -f "$d"); dirname "$d")
PATH=$APPDIR:$PATH
topdir=$(rpm -E '%{_topdir}')
dist=th

# get package, no sources
get_package() {
	local pkg=$1 out
	out=$(builder -g -ns $pkg 2>&1) || echo "$out"
}

# get version fron $specfile
get_version() {
	local specfile="$1"

	awk '/^Version:[ 	]+/{print $NF}' $specfile | tail -n1
}

# displays latest used tag for a specfile
autotag() {
	local out s
	for s in "$@"; do
		# strip branches
		s=${s%:*}
		# ensure package ends with .spec
		s=${s%.spec}.spec
		git fetch --tags
		out=$(git for-each-ref --count=1 --sort=-authordate refs/tags/auto/$dist \
			--format='%(refname:short)')
		echo "$s:$out"
	done
}

# get $pkg, setup $package, $version, $tag
setup_package() {
	local package=$1
	local specfile=$package.spec
	get_package $package
	version=$(cd $package && get_version $specfile)
	tag=$(cd $package && autotag $specfile)
}

cd "$topdir"

# get new version from qtbase package
setup_package qt5-qtbase
echo "Updating version to $version (based on qt5-qtbase)"
set_version=$version

for pkg in ${*:-$packages}; do
	pkg=${pkg%.spec}
	echo -n "* $pkg ... "

	setup_package $pkg
	echo "$version $tag"
done
