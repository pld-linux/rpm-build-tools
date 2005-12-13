#!/bin/sh

self=$(basename "$0")
usage="Usage: $self [FLAGS] SPECFILE

-s|--no-sort|--skip-sort
	skip BuildRequires, Requires sorting
-m|--no-macros|--skip-macros
	skip use_macros() substitutions
-d|--skip-desc
	skip desc wrapping
-a|--skip-defattr
	skip %defattr corrections

"

t=`getopt -o hsmda --long help,sort,sort-br,no-macros,skip-macros,skip-desc,skip-defattr -n "$self" -- "$@"` || exit $?
eval set -- "$t"

while true; do
	case "$1" in
	-h|--help)
 		echo 2>&1 "$usage"
		exit 1
	;;
	-s|--no-sort|--skip-sort)
		export SKIP_SORTBR=1
	;;
	-m|--no-macros|--skip-macros)
		export SKIP_MACROS=1
	;;
	-d|--skip-desc)
		export SKIP_DESC=1
	;;
	-a|--skip-defattr)
		export SKIP_DEFATTR=1
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

exec ./builder --adapter "$1"
