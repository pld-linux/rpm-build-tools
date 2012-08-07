#!/bin/sh
set -e

dist=$(rpm -E %pld_release)
arch=$(rpm -E %_target_cpu)
dest=~/public_html/$dist/$arch/
rpmdir=$(rpm -E %_rpmdir)

rm -vf $rpmdir/*-debuginfo*.rpm
chmod 644 $rpmdir/*.rpm
umask 022
mv -v $rpmdir/*.rpm $dest/
echo ""
poldek --cachedir=$HOME/tmp --mkidx -s $dest --mt=pndir
