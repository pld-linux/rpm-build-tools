#!/bin/bash
#
# You need to install all Qt*-devel packages
#
# auth: shadzik@pld-linux.org

if [ "$1" == "" ]; then
	echo "Usage: $0 <kdemodule>-<version>"
	exit 0
fi

rm -f /tmp/qtbrs
HEADERS=$(grep -E -r '^#include\ <Q.*' BUILD/$1 |awk '{print $2}' |sort -u |sed -e 's/<//g;s/>//g')

for i in $HEADERS; do find /usr/include/qt4 -print |grep $i |xargs rpm -qf >>/tmp/qtbrs; done

for i in $(cat /tmp/qtbrs |sort -u); do ver=$(echo $i|sed -e 's/[a-zA-Z].*-devel-//g;s/-[0-9].*//g');i=$(echo $i|sed -e "s/-[0-9].*//g");echo -e "BuildRequires:\t$i >= $ver"; done
rm -f /tmp/qtbrs
