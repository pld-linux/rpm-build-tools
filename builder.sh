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
V 0.7 (C) 1999 Tomasz K³oczko".

PATH="/bin:/usr/bin:/usr/sbin:/sbin:/usr/X11R6/bin"

COMMAND="build"

SPECFILE=""
BE_VERBOSE=""
QUIET=""
CLEAN=""
DEBUG=""
NOURLS=""
CVSROOT=${CVSROOT:-""}
LOGFILE=""
CHMOD="yes"

PATCHES=""
SOURCES=""
ICONS=""
PACKAGE_RELEASE=""
PACKAGE_VERSION=""
PACKAGE_NAME=""

if [ -f ~/.builderrc ]; then
  . ~/.builderrc
fi

#---------------------------------------------
# functions

usage()
{
    if [ -n "$DEBUG" ]; then set -xv; fi
    echo "\
Usage: builder [-D] [--debug] [-V] [--version] [-a] [--as_anon] [-b] [-ba]
	[--build] [-bb] [--build-binary] [-bs] [--build-source] [-d <cvsroot>]
	[--cvsroot <cvsroot>] [-g] [--get] [-h] [--help] [-l <logfile>]
	[--logtofile <logfile>] [-q] [--quiet] [-r <cvstag>]
	[--cvstag <cvstag>] [-v] [--verbose] <package>.spec

	-D, --debug	- enable script debugging mode,
	-V, --version	- output builder version
	-a, --as_anon	- get files via pserver as cvs@anoncvs.pld.org.pl,
	-b, -ba,
	--build		- get all files from CVS repo or HTTP/FTP and build
			  package from <package>.spec,
	-bb,
	--build-binary	- get all files from CVS repo or HTTP/FTP and build
			  binary only package from <package>.spec,
	-bs,
	--build-source	- get all files from CVS repo or HTTP/FTP and only
			  pack them into src.rpm,
	-c, --clean     - clean all temporarily created files (in BUILD,
			  SOURCES, SPECS and \$RPM_BUILD_ROOT),
			  SOURCES, SPECS and \$RPM_BUILD_ROOT),
	-d, --cvsroot	- setup \$CVSROOT,
	-g, --get       - get <package>.spec and all related files from
			  CVS repo or HTTP/FTP,
	-h, --help	- this message,
	-l, --logtofile	- log all to file,
	-q, --quiet	- be quiet,
	-r, --cvstag	- build package using resources from specified CVS
			  tag,
	-u, --no_urls	- try to get sources only from CVS repo,
	-v, --verbose	- be verbose,

"
}

parse_spec()
{
    if [ -n "$DEBUG" ]; then set -xv; fi

    sed -e "s#%prep#%dump#I" $SPECFILE | grep -v -i "^Icon\:" > $SPECFILE.__

    SOURCES="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ SOURCEURL[0-9]+/ {print $3}'`"
    PATCHES="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ PATCHURL[0-9]+/ {print $3}'`"
    ICONS="`awk '/^Icon:/ {print $2}' ${SPECFILE}`"
    PACKAGE_NAME="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ name/ {print $3}'`"
    PACKAGE_VERSION="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ PACKAGE_VERSION/ {print $3}'`"
    PACKAGE_RELEASE="`rpm -bp --test $SPECFILE.__ 2>&1 | awk '/ PACKAGE_RELEASE/ {print $3}'`"

    rm -f $SPECFILE.__

    if [ -n "$BE_VERBOSE" ]; then
	echo "- Sources :  `nourl $SOURCES`" 
	if [ -n "$PATCHES" ]; then
		echo "- Patches :  `nourl $PATCHES`"
	else
		echo "- Patches	:  *no patches needed*"
	fi
	if [ -n "$ICONS" ]; then
	    echo "- Icon    :  `nourl $ICONS`"
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
	echo "Error: some source, patch or icon files not stored in CVS repo.";
	exit 4 ;;
    "err_build_fail" )
	echo "Error: package build failed.";
	exit 5 ;;
    esac
}

init_builder()
{
    if [ -n "$DEBUG" ]; then set -xv; fi

    SOURCE_DIR="`rpm --eval "%{_sourcedir}"`"
    SPECS_DIR="`rpm --eval "%{_specdir}"`"

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
	if [ ! -f "$SPECFILE" ]; then
	Exit_error err_no_spec_in_repo;
	fi
    
    if [ "$CHMODE" = "yes" ]; then
        chmod 444 $SPECFILE
    fi
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

	cvs $OPTIONS `nourl $SOURCES $PATCHES $ICONS`
	
	if [ -z "$NOURLS" ]; then
		for i in $SOURCES $PATCHES $ICONS; do
			if [ ! -f "`nourl $i`" ]&&\
			[ `echo $i | grep 'ftp://\|http://'` ]; then
				wget -c -t0 "$i"
			fi
		done
	fi
	
	for i in $SOURCES $PATCHES $ICONS; do
		if [ ! -f "`nourl $i`" ]; then
			Exit_error err_no_source_in_repo;
		fi
	done

	if [ "$CHMOD" = "yes" ]; then
	    chmod 444 `nourl $SOURCES $PATCHES $ICONS`
	fi
	unset OPTIONS
    fi
}

build_package()
{
    if [ -n "$DEBUG" ]; then set -xv; fi

    cd $SPECS_DIR
    case "$COMMAND" in
	build )
            BUILD_SWITCH="-ba" ;;
	build-binary )
	    BUILD_SWITCH="-bb" ;;
	build-source )
	    BUILD_SWITCH="-bs" ;;
    esac
    rpm $BUILD_SWITCH -v $QUIET $CLEAN $SPECFILE

    if [ "$?" -ne "0" ]; then
	Exit_error err_build_fail;
    fi
    unset BUILD_SWITCH
}

nourl()
{
	echo "$@" | sed 's#\<\(ftp\|http\)://.*/##g'
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
	    CVSROOT=":pserver:cvs@anoncvs.pld.org.pl:/cvsroot"; shift ;;
	-b | -ba | --build )
	    COMMAND="build"; shift ;;
	-bb | --build-binary )
	    COMMAND="build-binary"; shift ;;
	-bs | --build-source )
	    COMMAND="build-source"; shift ;;
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
	-u | --no_urls )
	    NOURLS="yes"; shift ;;
	* )
	    SPECFILE="${1}"; shift ;;
    esac
done

if [ -n "$DEBUG" ]; then set -xv; fi

case "$COMMAND" in
    "build" | "build-binary" | "build-source" )
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
