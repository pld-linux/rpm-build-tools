#!/bin/sh
program=${0##*/}
program=${program%.sh}
dir=$(dirname "$0")
suffix=${program#php}

# if called as php.sh, invoke all php versions
if [ "$suffix" = "" ]; then
	for php in $dir/php??.sh; do
		$php "$@"
	done
	exit 0
fi

exec $dir/make-request.sh -D "php_suffix $suffix" ${post_command:+-C "$post_command"} "$@"
