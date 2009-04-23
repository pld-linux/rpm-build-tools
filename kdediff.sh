#!/bin/sh

ver=3.5.10
pkg="$1"

# http://websvn.kde.org/tags/KDE/3.5.5/
# http://websvn.kde.org/branches/KDE/3.5/
# svn://anonsvn.kde.org/home/kde/trunk/KDE/kdelibs

svn diff \
	svn://anonsvn.kde.org/home/kde/tags/KDE/${ver}/$pkg \
	svn://anonsvn.kde.org/home/kde/branches/KDE/3.5/$pkg \
	> $pkg-branch.diff
