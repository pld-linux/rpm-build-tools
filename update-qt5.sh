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

# get package, no sources
get_package() {
	local pkg=$1 out
	out=$(builder -g -ns $pkg 2>&1) || echo "$out"
}

cd "$topdir"
for pkg in ${*:-$packages}; do
	pkg=${pkg%.spec}
	echo "* $pkg"

	get_package $pkg
	cd $pkg
	specfile=*.spec

	cd ..
done
