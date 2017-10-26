#!/bin/bash

PKGS="
kf5-extra-cmake-modules
kf5-attica
kf5-karchive
kf5-kcoreaddons
kf5-kauth
kf5-kcodecs
kf5-kconfig
kf5-kwidgetsaddons
kf5-kcompletion
kf5-ki18n
kf5-kdoctools
kf5-kguiaddons
kf5-kconfigwidgets
kf5-kdbusaddons
kf5-kwindowsystem
kf5-kcrash
kf5-kglobalaccel
kf5-kitemviews
kf5-kiconthemes
kf5-kservice
kf5-sonnet
kf5-ktextwidgets
kf5-kxmlgui
kf5-kbookmarks
kf5-kjobwidgets
kf5-knotifications
kf5-kwallet
kf5-solid
kf5-kio
kf5-kfilemetadata
kf5-kidletime
kf5-baloo
kf5-bluez-qt
kf5-breeze-icons
kf5-frameworkintegration
kf5-kpackage
kf5-kdeclarative
kf5-kcmutils
kf5-kactivities
kf5-kactivities-stats
kf5-kapidox
kf5-kinit
kf5-kded
kf5-kparts
kf5-kdewebkit
kf5-kplotting
kf5-kdesignerplugin
kf5-kemoticons
kf5-kunitconversion
kf5-kdelibs4support
kf5-kpty
kf5-kdesu
kf5-kdnssd
kf5-kjs
kf5-khtml
kf5-kimageformats
kf5-kirigami2
kf5-kitemmodels
kf5-kjsembed
kf5-kmediaplayer
kf5-knewstuff
kf5-knotifyconfig
kf5-kpeople
kf5-kross
kf5-plasma-framework
kf5-threadweaver
kf5-krunner
kf5-syntax-highlighting
kf5-ktexteditor
kf5-kwayland
kf5-kxmlrpcclient
kf5-modemmanager-qt
kf5-networkmanager-qt
kf5-prison
kf5-qqc2-desktop-style
"

newver="5.40.0"
topdir=$(rpm -E '%{_topdir}')

n="$(echo -e '\nn')"
n="${n%%n}"
test=0
get=0

get_dump() {
	local specfile="$1"
	if ! out=$(rpm --specfile "$specfile" --define 'prep %dump' -q 2>&1); then
		echo >&2 "$out"
		echo >&2 "You need icon files being present in SOURCES."
		exit 1
	fi
	echo "$out"
}

set_release() {
	local specfile="$1"
	local rel="$2"
	local newrel="$3"
	sed -i -e "
		s/^\(%define[ \t]\+_\?rel[ \t]\+\)$rel\$/\1$newrel/
		s/^\(Release:[ \t]\+\)$rel\$/\1$newrel/
	" $specfile
}

set_version() {
	local specfile="$1"
	local rel="$2"
	local newrel="$3"
	sed -i -e "
		s/^\(%define[ \t]\+_\?ver[ \t]\+\)$rel\$/\1$newrel/
		s/^\(Version:[ \t]\+\)$rel\$/\1$newrel/
	" $specfile
}

set_framever() {
	local specfile="$1"
	local rel="$2"
	local newrel="$3"
	sed -i -e "
		s/^\(%define[ \t]\+_\?kdeframever[ \t]\+\)$rel\$/\1$newrel/
	" $specfile
}

while [ -n "$1" ]
do
	case "$1" in
	"--help")
		echo "Usage: $0 [--help] [--get] [--test] [--message message] newversion"
		exit 0
		;;
	"--get")
		get=1
		;;
	"--test")
		test=1
		;;
	"--message")
		shift
		message="$1"
		;;
	*)
		newver="$1"
		;;
	esac
	shift
done

cd "$topdir"
for pkg in $PKGS ; do
	# spec: package/package.spec
	spec=$(rpm -D "name $pkg" -E '%{_specdir}/%{name}.spec')
	spec=${spec#$topdir/}

	# pkgdir: package/
	pkgdir=${spec%/*}

	# specname: only spec filename
	specname=${spec##*/}

	# start real work
	echo "$pkg ..."

	# get package
	[ "$get" = 1 -a -d "$pkgdir" ] && continue

	if [ "$update" = "1" -o "$get" = "1" ]; then
		./builder -g -ns "$spec"
	fi

	[ "$get" = 1 ] && continue

	# update .spec files
	dump=$(get_dump "$spec")

	ver=$(awk '/^%define[ 	]+_?rel[ 	]+/{print $NF}' $spec)
	if [ -z "$ver" ]; then
		ver=$(echo "$dump" | awk '/PACKAGE_VERSION/{print $NF; exit}')
	fi
	rel=$(awk '/^%define[ 	]+_?rel[ 	]+/{print $NF}' $spec)
	if [ -z "$rel" ]; then
		rel=$(echo "$dump" | awk '/PACKAGE_RELEASE/{print $NF; exit}')
	fi
	framever=$(awk '/^%define[ 	]+_?kdeframever[ 	]+/{print $NF}' $spec)
	newframever=$(echo "$newver" | awk -F. '{printf "%s.%s", $1, $2}')

	echo $ver-$rel

	set_release "$spec" $rel "1"
	set_version "$spec" $ver $newver
	set_framever "$spec" $framever $newframever

	# update md5sums
	./builder -U "$spec"

	# commit the changes
	msg=""
	[ -n "$message" ] && msg="$msg- $message$n"
	msg="$msg- updated to $newver (by update-kf5up.sh)"
	echo git commit -m "$msg" $spec
	if [ "$test" != 1 ]; then
		cd $pkgdir
		git commit -m "$msg" $specname
		git push
		cd ..
	fi
done
