#!/bin/sh

KDEPKGS="
kde4-kdelibs
kde4-kdegraphics-mobipocket
kde4-kfilemetadata
kde4-kdepimlibs
kde4-baloo
kde4-baloo-widgets
kde4-nepomuk-core
kde4-nepomuk-widgets
kde4-kactivities
kde4-oxygen-icons
kde4-kdebase
kde4-libkdeedu
kde4-kdebase-runtime
python-PyKDE4
kde4-kate
kde4-libkscreen
kde4-okular
kde4-smokegen
kde4-smokeqt
kde4-smokekde
perl-Qt4
perl-KDE4
kde4-analitza
kde4-libkexiv2
kde4-libkcddb
kde4-libkdcraw
kde4-libkipi
kde4-libksane
kde4-marble
kde4-qyoto
kde4-ark
kde4-libkcompactdisc
kde4-audiocd-kio
kde4-blinken
kde4-cantor
kde4-dragon
kde4-ffmpegthumbs
kde4-filelight
kde4-gwenview
kde4-jovie
kde4-juk
kde4-kaccessible
kde4-kalgebra
kde4-kalzium
kde4-kamera
kde4-kanagram
kde4-kbruch
kde4-kcalc
kde4-kcharselect
kde4-kcolorchooser
kde4-kdebase-artwork
kde4-wallpapers
kde4-kdeartwork
kde4-kdegraphics-strigi-analyzer
kde4-kdegraphics-thumbnailers
kde4-kdepim
kde4-kdepim-runtime
kde4-kdeplasma-addons
kde4-kdewebdev
kde4-kdf
kde4-kgamma
kde4-kgeography
kde4-kgpg
kde4-khangman
kde4-kig
kde4-kimono
kde4-kiten
kde4-klettres
kde4-kmag
kde4-kmix
kde4-kmousetool
kde4-kmouth
kde4-kmplot
kde4-kolourpaint
kde4-konsole
kde4-kremotecontrol
kde4-kruler
kde4-ksaneplugin
kde4-kscd
kde4-ksnapshot
kde4-kstars
kde4-ktimer
kde4-ktouch
kde4-kturtle
kde4-kwallet
kde4-kwordquiz
kde4-mplayerthumbs
kde4-pairs
kde4-parley
kde4-print-manager
kde4-rocs
kde4-step
kde4-superkaramba
kde4-svgpart
kde4-sweeper
kde4-libkdegames
kde4-libkmahjongg
kde4-bomber
kde4-bovo
kde4-granatier
kde4-kajongg
kde4-kapman
kde4-katomic
kde4-kblackbox
kde4-kblocks
kde4-kbounce
kde4-kbreakout
kde4-kdiamond
kde4-kfourinline
kde4-kgoldrunner
kde4-kigo
kde4-killbots
kde4-kiriki
kde4-kjumpingcube
kde4-klickety
kde4-klines
kde4-kmahjongg
kde4-kmines
kde4-knavalbattle
kde4-knetwalk
kde4-kolf
kde4-kollision
kde4-konquest
kde4-kpat
kde4-kreversi
kde4-kshisen
kde4-ksirk
kde4-ksnakeduel
kde4-kspaceduel
kde4-ksquares
kde4-ksudoku
kde4-ktuberling
kde4-kubrick
kde4-lskat
kde4-palapeli
kde4-picmi
kde4-amor
kde4-kteatime
kde4-ktux
kde4-cervisia
kde4-dolphin-plugins
kde4-kapptemplate
kde4-kcachegrind
kde4-kde-dev-scripts
kde4-kde-dev-utils
kde4-kdesdk-kioslaves
kde4-kdesdk-strigi-analyzers
kde4-kdesdk-thumbnailers
kde4-libkomparediff2
kde4-kompare
kde4-lokalize
kde4-poxml
kde4-umbrello
kde4-kuser
kde4-ksystemlog
kde4-kdenetwork-filesharing
kde4-kdenetwork-strigi-analyzers
kde4-kopete
kde4-kcron
kde4-kdnssd
kde4-kget
kde4-krdc
kde4-krfb
kde4-okteta
"

#kde4-kfloppy
#kde4-korundum
#kde4-kppp
#kde4-kross-interpreters
##kde4-kdebase-workspace

newver="4.13.1"

topdir=$(rpm -E '%{_topdir}')

n="$(echo -e '\nn')"
n="${n%%n}"
#test=1

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

cd "$topdir"
for pkg in $KDEPKGS ; do
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
	echo $ver-$rel

	set_release "$spec" $rel "1"
	set_version "$spec" $ver $newver

	# update md5sums
	./builder -U "$spec"

	# commit the changes
	msg=""
	[ -n "$message" ] && msg="$msg- $message$n"
	msg="$msg- updated to $newver (by update-kde4.sh)"
	echo git commit -m "$msg" $spec
	if [ "$test" != 1 ]; then
		cd $pkgdir
		git commit -m "$msg" $specname
		git push
		cd ..
	fi
done
