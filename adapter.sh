#!/bin/sh

self=$(basename "$0")
usage="Usage: $self [--sort[-br]|-s] filename"

t=`getopt -o hs --long help,sort,sort-br -n "$self" -- "$@"` || exit $?
eval set -- "$t"

while true; do
	case "$1" in
	-h|--help)
 		echo 2>&1 "$usage"
		exit 1
	;;
	--sort|--sort-br|-s)
		export SORTBR=1
	;;
	--)
		shift
	   	break
	;;
	*)
		echo 2>&1 "$self: Internal error: [$1] not recognized!"
		exit 1
	   	;;
	esac
	shift
done

if [ $# -ne 1 -o ! -f "$1" ]; then
	echo "$usage"
	exit 1
fi

./builder --adapter "$1"
