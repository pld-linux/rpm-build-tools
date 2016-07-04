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
else
	pre_command='for a in php4-common php52-common php53-common php54-common php55-common php56-common php70-common hhvm; do poldek -e $a --noask; done'
fi

exec $dir/make-request.sh -D "php_suffix $suffix" ${pre_command:+-c "$pre_command"} ${post_command:+-C "$post_command"} "$@"
