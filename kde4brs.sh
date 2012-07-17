#!/bin/sh
#
# Inspect package source and find kde4 related build dependencies.
#
# NOTE: This script doesn't find all BRs. It finds those ones for which you already have
# the -devel subpackage installed on your system. So... the more -devel packages you have, the more
# BRs it finds.
#
# Author: shadzik@pld-linux.org

if [ $# = 0 ]; then
	echo "Usage: $0 <package>-<version>"
	exit 1
fi

t=$(mktemp)
rm -f $t
HEADERS=$(grep -E -r '^#include\ <.*' BUILD/$1 | awk '{print $2}' | sort -u | sed -e 's/<//g;s/>//g')

# there must be a better way to do this
for i in $HEADERS; do
	find /usr/include -print | grep $i |xargs rpm -qf >> $t 2>/dev/null
done

for i in $(cat $t 2>/dev/null | sort -u |grep kde4); do
	ver=$(echo $i | sed -e 's/[a-zA-Z].*-devel-//g;s/-[0-9].*//g')
	i=$(echo $i | sed -e "s/-[0-9].*//g")
	echo -e "BuildRequires:\t$i >= $ver"
done
rm -f $t
