#!/bin/sh
# -----------
# $Revision$, $Date$
# Exit codes:
#	0 - succesful
#	1 - help dispayed
#	2 - no spec file name in cmdl parameters
#	3 - spec file not stored in repo
#	4 - some source, apatch or icon files not stored in repo
#	5 - build package no succed

VERSION="\
Build package utility from PLD CVS repository
V 0.8 (C) 1999 Tomasz K³oczko".

PATH="/bin:/usr/bin:/usr/sbin:/sbin:/usr/X11R6/bin"
 
COMMAND="build"

SPECFILE=""
BE_VERBOSE=""
QUIET=""
CLEAN=""
DEBUG=""
NOURLS=""
NOCVS=""
ALLWAYS_CVSUP="yes"
CVSROOT=${CVSROOT:-""}
LOGFILE=""
CHMOD="yes"
RPMOPTS=""

PATCHES=""
SOURCES=""
ICONS=""
PACKAGE_RELEASE=""
PACKAGE_VERSION=""
PACKAGE_NAME=""

DEF_NICE_LEVEL=0

GETURI="wget -c -nd -t0"

if [ -f ~/etc/builderrc ]; then
  . ~/etc/builderrc
elif [ -f ~/.builderrc ]; then
  . ~/.builderrc
fi

#---------------------------------------------
# functions

usage()
{
    if [ -n "$DEBUG" ]; then set -xv; fi
    echo "\
Usage: builder [-D] [--debug] [-V] [--version] [-a] [--as_anon] [-b] [-ba]
	[--build] [-bb] [--build-binary] [-bs] [--build-source]
	[-d <cvsroot>] [--cvsroot <cvsroot>] [-g] [--get] [-h] [--help]
	[-l <logfile>] [-m] [--mr-proper] [--logtofile <logfile>] [-q] [--quiet]
	[-r <cvstag>] [--cvstag <cvstag>] [-u] [--no-urls] [-v] [--verbose]
	[--opts <rpm opts>] <package>.spec

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
	-m, --mr-proper - only remove all files related to spec file and
			  all work resources,
	-nc, --no-cvs	- don't download from CVS, if source URL is given,
	-nu, --no-urls	- don't try to download from FTP/HTTP location,
	-ns, --no-srcs  - don't downland Sources
	--opts		- additional options for rpm
	-q, --quiet	- be quiet,
	-r, --cvstag	- build package using resources from specified CVS
			  tag,
	-v, --verbose	- be verbose,

"
}

parse_spec()
{
    if [ -n "$DEBUG" ]; then 
	set -x;
	set -v;
    fi

    if [ "$NOSRCS" != "yes" ]; then
        SOURCES="`rpm -bp --nobuild --define "prep %dump" $SPECFILE 2>&1 | awk '/SOURCEURL[0-9]+/ {print $3}'`"
    fi

    PATCHES="`rpm -bp --nobuild --define "prep %dump" $SPECFILE 2>&1 | awk '/PATCHURL[0-9]+/ {print $3}'`"
    ICONS="`awk '/^Icon:/ {print $2}' ${SPECFILE}`"
    PACKAGE_NAME="`rpm -bp --nobuild $SPECFILE.__ 2>&1 | awk '/ name/ {print $3}'`"
    PACKAGE_VERSION="`rpm -bp --nobuild $SPECFILE.__ 2>&1 | awk '/ PACKAGE_VERSION/ {print $3}'`"
    PACKAGE_RELEASE="`rpm -bp --nobuild $SPECFILE.__ 2>&1 | awk '/ PACKAGE_RELEASE/ {print $3}'`"

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
    if [ -n "$DEBUG" ]; then 
    	set -x;
	set -v; 
    fi

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
    if [ -n "$DEBUG" ]; then 
    	set -x;
	set -v; 
    fi

    SOURCE_DIR="`rpm --eval "%{_sourcedir}"`"
    SPECS_DIR="`rpm --eval "%{_specdir}"`"

    __PWD=`pwd`
}

get_spec()
{
    if [ -n "$DEBUG" ]; then 
    	set -x;
	set -v; 
    fi

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
    
    if [ "$CHMOD" = "yes" ]; then
        chmod 444 $SPECFILE
    fi
    unset OPTIONS
}

get_all_files()
{
    if [ -n "$DEBUG" ]; then 
    	set -x;
	set -v; 
    fi

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
	for i in $SOURCES $PATCHES $ICONS; do
	    if [ ! -f `nourl $i` ] || [ $ALLWAYS_CVSUP = "yes" ] 
	      then
		if 
			echo $i | grep -vE '(http|ftp|https|cvs)://' |\
			grep -qE '\.(gz|bz2)$'
		then
			echo "Warning: no URL given for $i"
		fi
		
		if	[ -z "$NOCVS" ]||\
			[ `echo $i | grep -vE '(ftp|http|https)://'` ]
		then
			cvs $OPTIONS `nourl $i`
		fi
		
		if 	[ -z "$NOURLS" ]&&[ ! -f "`nourl $i`" ]&&\
			[ `echo $i | grep -E 'ftp://|http://|https://'` ]
		then
			${GETURI} "$i"
		fi

		if [ ! -f "`nourl $i`" ]; then
			Exit_error err_no_source_in_repo;
		fi
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
    if [ -n "$DEBUG" ]; then 
    	set -x;
	set -v; 
    fi

    cd $SPECS_DIR
    case "$COMMAND" in
	build )
            BUILD_SWITCH="-ba" ;;
	build-binary )
	    BUILD_SWITCH="-bb" ;;
	build-source )
	    BUILD_SWITCH="-bs --nodeps" ;;
    esac
    nice -n ${DEF_NICE_LEVEL} rpm $BUILD_SWITCH -v $QUIET $CLEAN $RPMOPTS $SPECFILE 

    if [ "$?" -ne "0" ]; then
	Exit_error err_build_fail;
    fi
    unset BUILD_SWITCH
}

nourl()
{
	echo "$@" | sed 's#\<\(ftp\|http\|https\|cvs\)://.*/##g'
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
	-ni| --nice )
	    shift; DEF_NICE_LEVEL=${1}; shift ;;
	-m | --mr-proper )
	    COMMAND="mr-proper"; shift ;;
	-nc | --no-cvs )
	    NOCVS="yes"; shift ;;
	-nu | --no-urls )
	    NOURLS="yes"; shift ;;
	-ns | --no-srcs )
	    NOSRCS="yes"; shift ;;
	--opts )
	    shift; RPMOPTS="${1}"; shift ;;
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

if [ -n "$DEBUG" ]; then 
	set -x;
	set -v; 
fi

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
    "mr-proper" )
	rpm --clean --rmsource --rmspec --force --nodeps $SPECFILE
	;;
    "usage" )
	usage;;
    "version" )
	echo "$VERSION";;
esac

cd $__PWD
