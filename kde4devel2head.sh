#!/bin/bash
# merge kde4@DEVEL with kde4@HEAD - actually it replaces HEAD with DEVEL
# so the actual merge must be done earlier manually.
#
# Author: Bartosz Swiatek (shadzik@pld-linux.org)

usage() {
	echo "Usage: $0 [-b] [-d] [-h] kde4-kdemodule[.spec]"
	echo ""
	echo "-b => merge also the branchdiff"
	echo "-d => debug mode \(set +e\)"
	echo "-h => show this help"
	echo ""
	exit 1
}

BRANCHDIFF=no
MODULE=$2

while [ $# -gt 0 ]; do
	case "$1" in
		-b )
			BRANCHDIFF=yes
			;;
		-d )
			set +e
			;;
		-h )
			usage
			;;
		-* )
			die "Unknown option: $1"
			;;
		* ) # no option, just module
			MODULE=$1
			;;
	esac
	shift
done

if [ "$MODULE" == "" ]; then
	usage
fi

kde4spec=`case "$MODULE" in
	*.spec )
		echo $MODULE
		;;
	* )
		echo $MODULE.spec
		;;
esac`
PKG=$(echo $kde4spec |sed -e 's/.spec//g')

# start

cvs get -r DEVEL packages/$PKG/$kde4spec
mv packages/$PKG/$kde4spec /tmp/$kde4spec-dev
cvs get packages/$PKG/$kde4spec
mv /tmp/$kde4spec-dev packages/$PKG/$kde4spec
echo "Changing to stable"
sed -i -e 's/unstable/stable/g' packages/$PKG/$kde4spec
echo "Done, seding"
cvs ci -m "- merged from DEVEL" packages/$PKG/$kde4spec
echo "Deleting DEVEL branch from spec"
cvs tag -B -d DEVEL packages/$PKG/$kde4spec

if [ "x$BRANCHDIFF" == "xyes" ]; then
	cvs get -r DEVEL packages/$PKG/$PKG-branch.diff
	mv packages/$PKG/$PKG-branch.diff /tmp/$PKG-branch.diff-dev
	cvs get packages/$PKG/$PKG-branch.diff
	mv /tmp/$PKG-branch.diff-dev packages/$PKG/$PKG-branch.diff
	cvs ci -m "- merged from DEVEL" packages/$PKG/$PKG-branch.diff
	echo "Deleting DEVEL branch from branchdiff"
	cvs tag -B -d DEVEL packages/$PKG/$PKG-branch.diff
fi
