#!/bin/bash
# 

PATH="/bin:/usr/bin:/usr/sbin:/sbin:/usr/X11R6/bin"
SPECFILE=""

usage()
{
echo "\
Usage: builder [-h] [--help] [-q] <package>.spec

	-V, --version	- output builder version
	-a, --as_anon	- get files via pserver as cvs@cvs.pld.org.pl,
	-b, --build	- get all files from CVS repo and build
			  package from <package>.spec,
	-d, --cvsroot	- setup \$CVSROOT,
	-g, --get	- get <package>.spec and all relayted files from
			  CVS repo,
	-h, --help	- this message,
	-l, --logtofile	- log all to file,
	-q, --quiet	- be quiet,
	-v, --verbose	- be verbose,

"
}

while test $# -gt 0 ; do
    case "${1}" in
	-V | --version )
	    shift ;;
	-a | --as_anon )
	    shift ;;
	-b | --build )
	    shift ;;
	-d | --cvsroot )
	    shift ;;
	-g | --get )
	    COMMAND="get"; shift ;;
	-h | --help )
	    COMMAND="usage"; shift ;;
	-l | --logtofile )
	    shift ;;
	-q | --quiet )
	    shift ;;
	-v | --verbose )
	    shift ;;
	* )
	    SPECFILE="${1}";;
    esac
done

case "$COMMAND" in
    "get" )
	if [ "$SPECFILE" == "" ]; then

	else

	fi
	;;
    "usage" )
	usage;;
esac
