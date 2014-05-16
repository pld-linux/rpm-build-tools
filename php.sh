#!/bin/sh
program=${0##*/}
program=${program%.sh}
dir=$(dirname "$0")
rpmdir=$(rpm -E %_topdir)
dist=th
suffix=${program#php}

specs=$*

exec $dir/make-request.sh -D "php_suffix $suffix" $specs -C "poldek -ev --noask php$suffix-devel" -n
