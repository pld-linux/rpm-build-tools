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

parse_spec()
{
}

get_spec()
{
}

get_all_files()
{
}

build_package()
{
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
	    SPECFILE="${1}"; shift ;;
    esac
done

case "$COMMAND" in
    "build" )
	if [ "$SPECFILE" != "" ]; then
	    get_spec;
	    parse_spec;
	    get_all_files;
	    build_package;
	else
	    echo "ERROR: spec file name not specified.";
	    usage;
	fi
	;;
    "get" )
	if [ "$SPECFILE" != "" ]; then
	    get_spec;
	    parse_spec;
	    get_all_files;
	else
	    echo "ERROR: spec file name not specified.";
	    usage;
	fi
	;;
    "usage" )
	usage;;
esac
