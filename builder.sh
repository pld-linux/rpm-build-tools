#!/bin/sh
# -----------
# Exit codes:
#	0 - succesful
#	1 - help dispayed
#	2 - no spec file name in cmdl parameters
#	3 - spec file not stored in repo
#	4 - some source, apatch or icon files not stored in repo
#	5 - build package no succed

VERSION="\
Build package utility from PLD CVS repository
V 0.6 (C) 1999 Tomasz K�oczko".

PATH="/bin:/usr/bin:/usr/sbin:/sbin:/usr/X11R6/bin"

COMMAND="build"

SPECFILE=""
BE_VERBOSE=""
QUIET=""
CLEAN=""
DEBUG=""
CVSROOT=${CVSROOT:-""}
LOGFILE=""

PATCHES=""
SOURCES=""
ICONS=""
PACKAGE_RELEASE=""
PACKAGE_VERSION=""
PACKAGE_NAME=""

#---------------------------------------------
# functions

usage()
{
    if [ -n "$DEBUG" ]; then set -xv; fi
    echo "\
Usage: builder [-D] [--debug] [-V] [--version] [-a] [--as_anon] [-b]
	[--build] [-d <cvsroot>] [--cvsroot <cvsroot>] [-g] [--get] [-h]
	[--help] [-l <logfile>] [--logtofile <logfile>] [-q] [--quiet] [-r
	<cvstag>] [--cvstag <cvstag>] [-v] [--verbose] <package>.spec

	-D, --debug	- enable scrip debuging mode,
	-V, --version	- output builder version
	-a, --as_anon	- get files via pserver as cvs@cvs.pld.org.pl,
	-b, --build	- get all files from CVS repo and build
			  package from <package>.spec,
	-c, --clean	- clean all temporary maked files (in BUILD,
			  SOURCES, SPECS and $RPM_BUILD_ROOT),
	-d, --cvsroot	- setup \$CVSROOT,
	-g, --get	- get <package>.spec and all relayted files from
			  CVS repo,
	-h, --help	- this message,
	-l, --logtofile	- log all to file,
	-q, --quiet	- be quiet,
	-r, --cvstag	- build package using resources from specified CVS
			  tag,
	-v, --verbose	- be verbose,

"
}

parse_spec()
{
    if [ -n "$DEBUG" ]; then set -xv; fi

    sed -e "s#%prep#%dump#I" $SPECFILE | grep -v -i "^Icon\:" > $SPECFILE.__

    SOURCES="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ SOURCE[0-9]+/ {print $3}'|sed -e 's#.*/##g'`"
    PATCHES="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ PATCH[0-9]+/ {print $3}'|sed -e 's#.*/##g'`"
    ICONS="`awk '/^Icon:/ {print $2}' ${SPECFILE} |sed -e 's#.*/##g'`"
    PACKAGE_NAME="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ name/ {print $3}'`"
    PACKAGE_VERSION="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ PACKAGE_VERSION/ {print $3}'`"
    PACKAGE_RELEASE="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ PACKAGE_RELEASE/ {print $3}'`"

    rm -f $SPECFILE.__

    if [ -n "$BE_VERBOSE" ]; then
	echo "- Sources :  $SOURCES"
	echo "- Patches :  $PATCHES"
	if [ -n "$ICONS" ]; then
	    echo "- Icon    :  $ICONS"
	else
	    echo "- Icon    :  *no package icon*"
	fi
	echo "- Name    : $PACKAGE_NAME"
	echo "- Version : $PACKAGE_VERSION"
	echo "- Release : $PACKAGE_RELEASE"
    fi
}

Exit_error()
{
    if [ -n "$DEBUG" ]; then set -xv; fi

    cd $__PWD

    case "$@" in
    "err_no_spec_in_cmdl" )
	echo "ERROR: spec file name not specified.";
	exit 2 ;;
    "err_no_spec_in_repo" )
	echo "Error: spec file not stored in CVS repo.";
	exit 3 ;;
    "err_no_source_in_repo" )
	echo "Error: some source, apatch or icon files not stored in CVS repo.";
	exit 4 ;;
    "err_build_fail" )
	echo "Error: package build failed.";
	exit 5 ;;
    esac
}

init_builder()
{
    if [ -n "$DEBUG" ]; then set -xv; fi

    DUMB_SPEC_FILE=`mktemp -q /tmp/bilder.XXXXXX`
    echo "\
Summary:	-
Name:		dumb
Version:	dumb
Release:	dumb
Copyright:	dumb
Group:		-
%description

%prep
echo SOURCE_DIR=%{_sourcedir}
echo SPECS_DIR=%{_specdir}" > $DUMB_SPEC_FILE

    SOURCE_DIR=`rpm -bp $DUMB_SPEC_FILE 2>&1 | grep "^SOURCE_DIR" | sed "s/SOURCE_DIR\=//"`
    SPECS_DIR=`rpm -bp $DUMB_SPEC_FILE 2>&1 | grep "^SPECS_DIR" |sed "s/SPECS_DIR\=//"`

    rm -f $DUMB_SPEC_FILE

    __PWD=`pwd`
}

get_spec()
{
    if [ -n "$DEBUG" ]; then set -xv; fi

    cd $SPECS_DIR

    OPTIONS="up "

    if [ -n "$CVSROOT" ]; then
	OPTIONS="-d $CVSROOT $OPTIONS"
    fi
    if [ -n "$CVSTAG" ]; then
	OPTIONS="$OPTIONS -r $CVSTAG"
    else
	OPTIONS="$OPTIONS -A"
    fi

    cvs $OPTIONS $SPECFILE
    if [ "$?" -ne "0" ]; then
	Exit_error err_no_spec_in_repo;
    fi

    chmod 444 $SPECFILE
    unset OPTIONS
}

get_all_files()
{
    if [ -n "$DEBUG" ]; then set -xv; fi

    if [ -n "$SOURCES$PATCHES$ICONS" ]; then
	cd $SOURCE_DIR

	OPTIONS="up "
	if [ -n "$CVSROOT" ]; then
	    OPTIONS="-d $CVSROOT $OPTIONS"
	fi
	if [ -n "$CVSTAG" ]; then
	    OPTIONS="$OPTIONS -r $CVSTAG"
	else
	    OPTIONS="$OPTIONS -A"
	fi

	cvs $OPTIONS $SOURCES $PATCHES $ICONS
	if [ "$?" -ne "0" ]; then
	    Exit_error err_no_source_in_repo;
	fi

	chmod 444 $SOURCES $PATCHES $ICONS
	unset OPTIONS
    fi
}

build_package()
{
    if [ -n "$DEBUG" ]; then set -xv; fi

    cd $SPECS_DIR
    rpm -ba -v $QUIET $CLEAN $SPECFILE

    if [ "$?" -ne "0" ]; then
	Exit_error err_build_fail;
    fi
}


#---------------------------------------------
# main()

if [ "$#" = 0 ]; then
    usage;
    exit 1
fi

while test $# -gt 0 ; do
    case "${1}" in
	-D | --debug )
	    DEBUG="yes"; shift ;;
	-V | --version )
	    COMMAND="version"; shift ;;
	-a | --as_anon )
	    CVSROOT=":pserver:cvs@cvs.pld.org.pl:/cvsroot"; shift ;;
	-b | --build )
	    COMMAND="build"; shift ;;
	-c | --clean )
	    CLEAN="--clean --rmspec --rmsource"; shift ;;
	-d | --cvsroot )
	    shift; CVSROOT="${1}"; shift ;;
	-g | --get )
	    COMMAND="get"; shift ;;
	-h | --help )
	    COMMAND="usage"; shift ;;
	-l | --logtofile )
	    shift; LOGFILE="${1}"; shift ;;
	-q | --quiet )
	    QUIET="--quiet"; shift ;;
	-r | --cvstag )
	    shift; CVSTAG="${1}"; shift ;;
	-v | --verbose )
	    BE_VERBOSE="1"; shift ;;
	* )
	    SPECFILE="${1}"; shift ;;
    esac
done

if [ -n "$DEBUG" ]; then set -xv; fi

case "$COMMAND" in
    "build" )
	init_builder;
	if [ -n "$SPECFILE" ]; then
	    get_spec;
	    parse_spec;
	    get_all_files;
	    build_package;
	else
	    Exit_error err_no_spec_in_cmdl;
	fi
	;;
    "get" )
	init_builder;
	if [ -n "$SPECFILE" ]; then
	    get_spec;
	    parse_spec;
	    get_all_files;
	else
	    Exit_error err_no_spec_in_cmdl;
	fi
	;;
    "usage" )
	usage;;
    "version" )
	echo "$VERSION";;
esac

cd $__PWD
