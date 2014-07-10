#!/bin/sh
program=${0##*/}
program=${program%.sh}
dir=$(dirname "$0")
suffix=${program#php}

exec $dir/make-request.sh -D "php_suffix $suffix" ${post_command:+-C "$post_command"} "$@"
