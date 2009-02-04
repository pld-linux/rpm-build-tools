#!/bin/sh

ver=3.5.9

# http://websvn.kde.org/tags/KDE/3.5.5/
# http://websvn.kde.org/branches/KDE/3.5/
# svn://anonsvn.kde.org/home/kde/trunk/KDE/kdelibs

svn diff \
	svn://anonsvn.kde.org/home/kde/tags/KDE/${ver}/$1 \
	svn://anonsvn.kde.org/home/kde/branches/KDE/3.5/$1 \
	> $1-branch.diff
