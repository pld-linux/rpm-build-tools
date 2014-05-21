#!/bin/sh
program=${0##*/}
program=${program%.sh}
dir=$(dirname "$0")
rpmdir=$(rpm -E %_topdir)
dist=th
suffix=${program#php}
#post_command="poldek -ev --noask php$suffix-devel"

exec $dir/make-request.sh -D "php_suffix $suffix" ${post_command:+-C "$post_command"} -n "$@"
