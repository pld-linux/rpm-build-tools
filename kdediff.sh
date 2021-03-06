#!/bin/sh
ver=3.5.10
top=$(cd "$(dirname "$0")"; pwd)

# http://websvn.kde.org/tags/KDE/3.5.5/
# http://websvn.kde.org/branches/KDE/3.5/
# svn://anonsvn.kde.org/home/kde/trunk/KDE/kdelibs

rundiff() {
	local pkg=$1 ver=$2
	
	echo >&2 "Checkout $pkg"
	cd $top
	./builder -g -ns $pkg

	cd $top/$pkg
	echo >&2 "Running diff for $pkg-$ver"
	LC_ALL=C svn diff \
		svn://anonsvn.kde.org/home/kde/tags/KDE/$ver/$pkg \
		svn://anonsvn.kde.org/home/kde/branches/KDE/3.5/$pkg \
		> $pkg-branch.diff.tmp

	local c=$(grep -c '^--- ' $pkg-branch.diff.tmp)
	if [ "$c" = 0 ]; then
		echo >&2 "$pkg-branch.diff: empty, skipping"
		rm $pkg-branch.diff.tmp
		cvs remove -f $pkg-branch.diff 2>/dev/null
		return
	fi

	cvs up -A $pkg-branch.diff
	cvs add $pkg-branch.diff 2>/dev/null

	local d=$(interdiff $pkg-branch.diff{,.tmp} | wc -l)
	if [ "$d" = 0 ]; then
		echo >&2 "$pkg-branch.diff: no new changes, skip"
		rm $pkg-branch.diff.tmp
		return
	fi

	mv $pkg-branch.diff.tmp $pkg-branch.diff
	echo >&2 "Updated $pkg-branch.diff"
}

base="
	kdelibs
	kdebase
	kdenetwork
	kdepim
"

all="$base
	kdeaddons
	kdeadmin
	kdeartwork
	kdebindings
	kdeedu
	kdegames
	kdegraphics
	kdemultimedia
	kdesdk
	kdetoys
	kdeutils
	kdevelop
	kdewebdev
"

#	arts
#	kde-i18n
#	kdeaccessibility

for pkg in ${1:-$all}; do
	rundiff $pkg $ver
done
