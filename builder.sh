#!/bin/bash
# 

PATH="/bin:/usr/bin:/usr/sbin:/sbin:/usr/X11R6/bin"

usage()
{
echo "\
Usage: builder [-h] [--help] [-q] <package>.spec

	-V, --version	- output builder version
	-a, --as_anon	- get files via pserver as cvs@cvs.pld.org.pl,
	-b, --build	- get all files from CVS repo and build
			  package from <package>.spec,
	-d, --cvsroot	- setup \$CVSROOT,
	-g, --get	- get <package>.spec amd all relayted files from
			  CVS repo,
	-h, --help	- this message,
	-l, --logtofile	- log all to file,
	-q, --quiet	- be quiet,
	-v, --verbose	- be verbose,

"
}

while test $# -gt 0 ; do
    case "${1}" in
	-h | --help )
	    usage; exit 0 ;
	    shift ;;
	-q | --quiet )
	    shift ;;
	-d | --cvsroot )
	    shift ;;
	-v | --verbose )
	    shift ;;
	-l | --logtofile )
	    shift ;;
	-V | --version )
	    shift ;;
    esac
done

