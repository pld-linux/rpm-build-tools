#!/bin/bash
# 

PATH="/bin:/usr/bin:/usr/sbin:/sbin:/usr/X11R6/bin"

SPECFILE=""
BE_VERBOSE=""

PATCHES=""
SOURCES=""
ICON=""
PACKAGE_RELEASE=""
PACKAGE_VERSION=""
PACKAGE_NAME=""

usage()
{
echo "\
Usage: builder [-V] [--version] [-a] [--as_anon] [-b] [--build]
	[-d <cvsroot>] [--cvsroot <cvsroot>] [-g] [--get] [-h] [--help]
	[-l <logfile>] [--logtofile <logfile>] [-q] [--quiet] 
	[-v] [--verbose] <package>.spec

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
    (echo "%dump"; cat $SPECFILE) > $SPECFILE.__

    SOURCES="`rpm -bp $SPECFILE.__ 2>&1 | awk '/ SOURCE[0-9]+/ {print $3}'`"
    PATCHES="`rpm -bp $SPECFILE.__ 2>&1 | awk '/ PATCH[0-9]+/ {print $3}'`"
    ICON="`rpm -bp $SPECFILE.__ 2>&1 | awk '/^Icon:/ {print $2}' ${SPEC}`"
    PACKAGE_NAME="`rpm -bp $SPECFILE.__ 2>&1 | awk '/ name/ {print $3}'`"
    PACKAGE_VERSION="`rpm -bp $SPECFILE.__ 2>&1 | awk '/ PACKAGE_VERSION/ {print $3}'`"
    PACKAGE_RELEASE="`rpm -bp $SPECFILE.__ 2>&1 | awk '/ PACKAGE_RELEASE/ {print $3}'`"

    rm -f $SPECFILE.__

    if [ "$BE_VERBOSE" != "" ]; then
	echo -e "- Sources :\n  " $SOURCES
	echo -e "- Patches :\n  " $PATCHES
	if [ "$ICON" != ""
	echo -e "- Icon    :\n  " $ICON
	echo -e "- Name    : " $PACKAGE_NAME
	echo -e "- Version : " $PACKAGE_VERSION
	echo -e "- Release : " $PACKAGE_RELEASE
    fi
}

get_spec()
{
    echo "get_spec"
}

get_all_files()
{
    echo "get_all_files"
}

build_package()
{
    echo "build_package"
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
	    BE_VERBOSE="1"; shift ;;
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
