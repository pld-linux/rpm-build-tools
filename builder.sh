#!/bin/bash
# 

VERSION="\
Build package utility from PLD CVS repository
V 0.1 (C) 1999 Tomasz K³oczko".

PATH="/bin:/usr/bin:/usr/sbin:/sbin:/usr/X11R6/bin"

SPECFILE=""
BE_VERBOSE=""
QUIET=""
CVSROOT=${CVSROOT:-""}
LOGFILE=""

PATCHES=""
SOURCES=""
ICON=""
PACKAGE_RELEASE=""
PACKAGE_VERSION=""
PACKAGE_NAME=""

dumb_spec="\
Summary:	-
Name:		dumb
Version:	dumb
Release:	dumb
Copyright:	dumb
Group:		-
%description

%prep
echo SOURCEDIR=%{_sourcedir}
echo SPECS=%{_specdir}"

#---------------------------------------------
# functions

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
    sed -e "s/^Summary:*/Summary:\%dump/I" $SPECFILE > $SPECFILE.__

    SOURCES="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ SOURCE[0-9]+/ {print $3}'`"
    PATCHES="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ PATCH[0-9]+/ {print $3}'`"
    ICON="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/^Icon:/ {print $2}' ${SPEC}`"
    PACKAGE_NAME="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ name/ {print $3}'`"
    PACKAGE_VERSION="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ PACKAGE_VERSION/ {print $3}'`"
    PACKAGE_RELEASE="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ PACKAGE_RELEASE/ {print $3}'`"

    rm -f $SPECFILE.__

    if [ "$BE_VERBOSE" != "" ]; then
	echo -e "- Sources :\n  " $SOURCES
	echo -e "- Patches :\n  " $PATCHES
	if [ "$ICON" != "" ]; then
	    echo -e "- Icon    :\n  " $ICON
	else
	    echo -e "- Icon    :  *no package icon*"
	fi
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


#---------------------------------------------
# main()

if [ "$#" == 0 ]; then
    usage;
    exit
fi

while test $# -gt 0 ; do
    case "${1}" in
	-V | --version )
	    COMMAND="version"; shift ;;
	-a | --as_anon )
	    CVSROOT=":pserver:cvs@cvs.pld.org.pl:/cvsroot"; shift ;;
	-b | --build )
	    COMMAND="build"; shift ;;
	-d | --cvsroot )
	    shift; CVSROOT="${1}"; shift ;;
	-g | --get )
	    COMMAND="get"; shift ;;
	-h | --help )
	    COMMAND="usage"; shift ;;
	-l | --logtofile )
	    shift; LOGFILE="${1}"; shift ;;
	-q | --quiet )
	    QUIET="1"; shift ;;
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
    "version" )
	echo "$VERSION";;
esac
