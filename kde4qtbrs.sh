#!/bin/sh
#
# Inspect package source and find Qt related build dependencies.
#
# NOTE: You need to install all Qt*-devel packages for the script to report
# success.
#
# Author: shadzik@pld-linux.org

if [ $# = 0 ]; then
	echo "Usage: $0 <kdemodule>-<version>"
	exit 1
fi

t=$(mktemp)
rm -f $t
HEADERS=$(grep -E -r '^#include\ <Q.*' BUILD/$1 | awk '{print $2}' | sort -u | sed -e 's/<//g;s/>//g')

for i in $HEADERS; do
   	find /usr/include/qt4 -print | grep $i |xargs rpm -qf >> $t
done

for i in $(cat $t | sort -u); do
	ver=$(echo $i | sed -e 's/[a-zA-Z].*-devel-//g;s/-[0-9].*//g')
	i=$(echo $i | sed -e "s/-[0-9].*//g")
	echo -e "BuildRequires:\t$i >= $ver"
done
rm -f $t
