#!/bin/sh

set -x
ver=4.4.2

prog="$1"
diffprog="$1"

# http://websvn.kde.org/tags/KDE/3.5.5/
# http://websvn.kde.org/branches/KDE/3.5/
# svn://anonsvn.kde.org/home/kde/trunk/KDE/kdelibs

# anonsvn.kde.org has few IP addresses which causes
# that svn connects to two different servers which may
# not be in sync. That causes problems with missing revisions.
# Resolve to one IP and use that in both svn arguments.

ANONSVN=$(host anonsvn.kde.org | awk ' { print $4; exit; } ' 2> /dev/null)
[ -z "$ANONSVN" ] && ANONSVN="anonsvn.kde.org"

[ "$diffprog" = "kdebase-workspace" -o "$diffprog" = "kdebase-runtime" ] && diffprog="kdebase"
[ "$diffprog" = "kdepim-runtime" ] && diffprog="kdepim"

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
		kdepim)
		cat - | filterdiff -x "akonadi/*" | filterdiff -x "runtime/*"
		;;
		kdepim-runtime)
		cat - | filterdiff -i "runtime/*"
		;;
		*)
		cat -
		;;
	esac
}

svn diff \
	svn://${ANONSVN}/home/kde/tags/KDE/${ver}/$diffprog \
	svn://${ANONSVN}/home/kde/branches/KDE/4.4/$diffprog \
	| filter "$prog" \
	> kde4-$prog-branch.diff

