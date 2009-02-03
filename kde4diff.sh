#!/bin/sh

set -x
ver=4.2.0

prog="$1"
diffprog="$1"

# http://websvn.kde.org/tags/KDE/3.5.5/
# http://websvn.kde.org/branches/KDE/3.5/
# svn://anonsvn.kde.org/home/kde/trunk/KDE/kdelibs

[ "$diffprog" = "kdebase-workspace" -o "$diffprog" = "kdebase-runtime" ] && diffprog="kdebase"

filter() {
	set -x
	case "$1" in
		kdebase)
		cat - | filterdiff -x "workspace/*" | filterdiff -x "runtime/*"
		;;
		kdebase-workspace)
		cat - | filterdiff -i "workspace/*"
		;;
		kdebase-runtime)
		cat - | filterdiff -i "runtime/*"
		;;
		*)
		cat -
		;;
	esac
}

svn diff \
	svn://anonsvn.kde.org/home/kde/tags/KDE/${ver}/$diffprog \
	svn://anonsvn.kde.org/home/kde/branches/KDE/4.2/$diffprog \
	| filter "$prog" \
	> $HOME/rpm/SOURCES/kde4-$prog-branch.diff

