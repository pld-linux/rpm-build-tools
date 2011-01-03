#!/bin/sh
#
# Find short descriptions from .desktop files
#
# Author: Bartosz Świątek (shadzik@pld-linux.org)

if [ "x$1" == "x" ]; then
	echo "Usage: $0 kdemodule-version"
	exit 1
fi

KDEMOD=$1
BUILDDIR=./BUILD

template() {
	local l=$1; shift
	cat <<-EOF
	%package $l
	Summary:	$l
	Group:		X11/Applications

	%description $l

	$*.

EOF
}

DESKTOPS=$(find $BUILDDIR/$KDEMOD -name '*.desktop' | sed -e "s@$BUILDDIR/$KDEMOD@@;s@/@ @g;s/^ //" |awk '{if ($1".desktop" == $2) print $1"/"$2}')

for DESKTOP in $DESKTOPS; do
	NAME=$(echo $DESKTOP |sed 's@/@ @' |awk '{print $1}')
	DESC=$(grep -E "(Comment=|GenericName=)" $BUILDDIR/$KDEMOD/$DESKTOP |sed "s/Comment=//;s/GenericName=//")
	template $NAME $DESC
done
