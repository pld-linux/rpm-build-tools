#!/bin/sh
# -----------
# $Id$
# Exit codes:
#	0 - succesful
#	1 - help dispayed
#	2 - no spec file name in cmdl parameters
#	3 - spec file not stored in repo
#	4 - some source, apatch or icon files not stored in repo
#	5 - build package no succed

VERSION="\
Build package utility from PLD CVS repository
V 0.9 (C) 1999-2001 Tomasz K³oczko".

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
if [ -s CVS/Root ]; then
    CVSROOT=$(cat CVS/Root)
else
    CVSROOT=${CVSROOT:-""}
fi
LOGFILE=""
CHMOD=${CHMOD:-"yes"}
CHMOD_MODE=${CHMOD_MODE:-444}
RPMOPTS=""
BCOND=""

PATCHES=""
SOURCES=""
ICONS=""
PACKAGE_RELEASE=""
PACKAGE_VERSION=""
PACKAGE_NAME=""
WGET_RETRIES=${MAX_WGET_RETRIES:-0}

DEF_NICE_LEVEL=0

FAIL_IF_NO_SOURCES="yes"

GETURI="wget -c -nd -t$WGET_RETRIES"

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
	[-B <branch>] [--branch <branch>] [-d <cvsroot>] [--cvsroot <cvsroot>] 
	[-g] [--get] [-h] [--help] [-l <logfile>] [-m] [--mr-proper] 
	[--logtofile <logfile>] [-q] [--quiet] [-r <cvstag>] [--cvstag <cvstag>] 
	[-u] [--no-urls] [-v] [--verbose] [--opts <rpm opts>] 
	[--with/--without pkg] <package>.spec

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
	-B, --branch	- add branch
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
	-T, --tag	- add cvs tags for files,
	-v, --verbose	- be verbose,

"
}

parse_spec()
{
    if [ -n "$DEBUG" ]; then 
	set -x;
	set -v;
    fi

    cd $SPECS_DIR

    if [ "$NOSRCS" != "yes" ]; then
        SOURCES="`rpm -bp --nobuild --define 'prep %dump' $SPECFILE 2>&1 | awk '/SOURCEURL[0-9]+/ {print $3}'`"
    fi
    if (rpm -bp --nobuild --define 'prep %dump' $SPECFILE 2>&1 | grep -qEi ":.*nosource.*1"); then
	FAIL_IF_NO_SOURCES="no"
    fi


    PATCHES="`rpm -bp --nobuild --define 'prep %dump' $SPECFILE 2>&1 | awk '/PATCHURL[0-9]+/ {print $3}'`"
    ICONS="`awk '/^Icon:/ {print $2}' ${SPECFILE}`"
    PACKAGE_NAME="`rpm -q --qf '%{NAME}\n' --specfile ${SPECFILE} 2> /dev/null | head -1`"
    PACKAGE_VERSION="`rpm -q --qf '%{VERSION}\n' --specfile ${SPECFILE} 2> /dev/null| head -1`"
    PACKAGE_RELEASE="`rpm -q --qf '%{RELEASE}\n' --specfile ${SPECFILE} 2> /dev/null | head -1`"

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

    case "$1" in
    "err_no_spec_in_cmdl" )
	echo "ERROR: spec file name not specified.";
	exit 2 ;;
    "err_no_spec_in_repo" )
	echo "Error: spec file not stored in CVS repo.";
	exit 3 ;;
    "err_no_source_in_repo" )
	echo "Error: some source, patch or icon files not stored in CVS repo. ($2)";
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

    SOURCE_DIR="`rpm --eval '%{_sourcedir}'`"
    SPECS_DIR="`rpm --eval '%{_specdir}'`"

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
    
    if [ "$CHMOD" = "yes" -a -n "$SPECFILE" ]; then
        chmod $CHMOD_MODE $SPECFILE
    fi
    unset OPTIONS
}

get_files()
{
    GET_FILES="$@"

    if [ -n "$DEBUG" ]; then 
    	set -x;
	set -v; 
    fi

    if [ -n "$1$2$3$4$5$6$7$8$9${10}" ]; then
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
	for i in $GET_FILES; do
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

		if [ ! -f "`nourl $i`" -a "$FAIL_IF_NO_SOURCES" != "no" ]; then
			Exit_error err_no_source_in_repo $i;
		fi
	    fi
	done
	
	if [ "$CHMOD" = "yes" ]; then
	    CHMOD_FILES="`nourl $GET_FILES`"
	    if [ -n "$CHMOD_FILES" ]; then
		    chmod $CHMOD_MODE $CHMOD_FILES
	    fi
	fi
	unset OPTIONS
    fi
}

tag_files()
{
    TAG_FILES="$@"

    if [ -n "$DEBUG" ]; then 
    	set -x;
	set -v; 
    fi

    if [ -n "$1$2$3$4$5$6$7$8$9${10}" ]; then
	echo $PACKAGE_VERSION
	echo $PACKAGE_RELEASE
	TAG=$PACKAGE_NAME-`echo $PACKAGE_VERSION | sed -e "s/\./\_/g"`-`echo $PACKAGE_RELEASE | sed -e "s/\./\_/g"`
	echo "CVS tag: $TAG"

	OPTIONS="tag -F"
	if [ -n "$CVSROOT" ]; then
	    OPTIONS="-d $CVSROOT $OPTIONS"
	fi

	cd $SOURCE_DIR
	for i in $TAG_FILES; do
	    if [ -f `nourl $i` ]; then
		cvs $OPTIONS $TAG `nourl $i`
		cvs $OPTIONS STABLE `nourl $i`
	    else
		Exit_error err_no_source_in_repo $i
	    fi
	done

	cd $SPECS_DIR
	cvs $OPTIONS $TAG $SPECFILE
	cvs $OPTIONS STABLE $SPECFILE

	unset OPTIONS
    fi
}

branch_files()
{
	TAG=$1
	echo "CVS branch tag: $TAG"
	shift;

	TAG_FILES="$@"

	if [ -n "$DEBUG" ]; then
		set -x;
		set -v;
	fi

	if [ -n "$1$2$3$4$5$6$7$8$9${10}" ]; then
		
		OPTIONS="tag -b"
		if [ -n "$CVSROOT" ]; then
			OPTIONS="-d $CVSROOT $OPTIONS"
		fi
		cd $SOURCE_DIR
		for i in $TAG_FILES; do
			if [ -f `nourl $i` ]; then
				cvs $OPTIONS $TAG `nourl $i`
			else
				Exit_error err_no_source_in_repo $i
			fi
		done
		cd $SPECS_DIR
		cvs $OPTIONS $TAG $SPECFILE

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
    nice -n ${DEF_NICE_LEVEL} rpm $BUILD_SWITCH -v $QUIET $CLEAN $RPMOPTS $BCOND $SPECFILE 

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
	-B | --branch )
	    COMMAND="branch"; shift; TAG="${1}"; shift;;
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
	--with | --without )
	    BCOND="$BCOND $1 $2" ; shift 2 ;;
	-q | --quiet )
	    QUIET="--quiet"; shift ;;
	-r | --cvstag )
	    shift; CVSTAG="${1}"; shift ;;
	-T | --tag )
	    COMMAND="tag"; shift;;
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
	    if [ -n "$ICONS" ]; then
	    	get_files $ICONS;
	    	parse_spec;
	    fi
	    get_files "$SOURCES $PATCHES";
	    build_package;
	else
	    Exit_error err_no_spec_in_cmdl;
	fi
	;;
    "branch" )
    	init_builder;
	if [ -n "$SPECFILE" ]; then
		get_spec;
		parse_spec;
		if [ -n "$ICONS" ]; then
			get_files $ICONS
			parse_spec;
		fi
		get_files $SOURCES $PATCHES;
		branch_files $TAG "$SOURCES $PATCHES $ICONS";
	else
		Exit_error err_no_spec_in_cmdl;
	fi
    	;;
    "get" )
	init_builder;
	if [ -n "$SPECFILE" ]; then
	    get_spec;
	    parse_spec;
	    if [ -n "$ICONS" ]; then
		    get_files $ICONS
		    parse_spec;
	    fi
	    get_files $SOURCES $PATCHES
	else
	    Exit_error err_no_spec_in_cmdl;
	fi
	;;
    "tag" )
	init_builder;
	if [ -n "$SPECFILE" ]; then
	    get_spec;
	    parse_spec;
	    if [ -n "$ICONS" ]; then
		    get_files $ICONS
		    parse_spec;
	    fi
	    get_files $SOURCES $PATCHES;
	    tag_files "$SOURCES $PATCHES $ICONS";
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

# $Log$
# Revision 1.85  2001/11/19 23:02:06  blues
# - added raw branching support
#
# Revision 1.84  2001/11/07 22:08:48  ankry
# - make builder's chmod configurable
#
# Revision 1.83  2001/10/10 08:41:32  misiek
# - allow more bconds than one
#
# Revision 1.82  2001/09/18 10:55:37  ankry
# - added support for limitting number of wget retries when fetching a file
#   from ftp/http server via environment variable MAX_WGET_RETRIES.
#   Defaults to infinite (0).
#
# Revision 1.81  2001/07/06 16:52:30  misiek
# - by default use CVSroot from CVS/Root and if it doesn't exist use from CVSROOT variable
#
# Revision 1.80  2001/06/22 18:52:39  misiek
# - added support for --with/--without options
#
# Revision 1.79  2001/05/28 14:44:16  baggins
# - if file is not in repo TELL which fucking file it is!
#
# Revision 1.78  2001/05/13 19:04:44  misiek
# fixes for ksh93
#
# Revision 1.77  2001/05/13 10:51:30  misiek
# don't fail if no sources found (hack to allow build nosrc packages)
#
# Revision 1.76  2001/04/19 23:24:06  misiek
# fix chmod again
#
# Revision 1.75  2001/04/19 23:14:25  misiek
# redirect errors from query to /dev/null
#
# Revision 1.74  2001/04/02 15:39:29  misiek
# fix problems with get_files when no files passed
#
# Revision 1.73  2001/03/30 14:06:10  wiget
# massive typo by kloczek
#
# Revision 1.72  2001/03/26 22:16:22  kloczek
# - fixed grabbing name, version and release in parse_spec(),
# - added -T option (tag) (temporary it tags also additional STABLE tag - must
#   be added -Ts for separate tagging as STABLE).
#
# Revision 1.71  2001/03/05 14:12:27  misiek
# fix chmod
#
# Revision 1.70  2001/03/03 19:55:42  misiek
# workaround for problems with rpm when icons isn't cvs up'ed
#
#
