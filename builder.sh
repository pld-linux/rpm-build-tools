#!/bin/ksh
#
# This program is free software, distributed under the terms of
# the GNU General Public License Version 2.
#
# -----------
# Exit codes:
#	  0 - succesful
#	  1 - help displayed
#	  2 - no spec file name in cmdl parameters
#	  3 - spec file not stored in repo
#	  4 - some source, patch or icon files not stored in repo
#	  5 - package build failed
#	  6 - spec file with errors
#	  7 - wrong source in /etc/poldek.conf
#	  8 - Failed installing buildrequirements and subrequirements
#	  9 - Requested tag already exist
#	 10 - Refused to build fractional release
#	100 - Unknown error (should not happen)
#   110 - Functions not yet implemented

# Notes (todo/bugs):
# - when Icon: field is present, -5 and -a5 doesn't work
# - builder -R skips installing BR if spec is not present before builder invocation (need to run builder twice)
# - does not respect NoSource: X, and tries to cvs up such files [ example: VirtualBox-bin.spec and its Source0 ]
# TODO:
# - ability to do ./builder -bb foo.spec foo2.spec foo3.spec
# - funny bug, if source-md5 is set then builder will download from distfiles even if there is no url present:
#   Source10:	forwardfix.pl
#   # Source10-md5:	8bf85f7368933a4e0cb4f875bac28733
# - builder --help:
#	basename: missing operand
#	Try `basename --help' for more information.
#	-- and the normal usage info --

PROGRAM=${0##*/}
APPDIR=$(d=$0; [ -L "$d" ] && d=$(readlink -f "$d"); dirname "$d")
VERSION="v0.35"
VERSIONSTRING="\
Build package utility from PLD Linux Packages repository
$VERSION (C) 1999-2021 Free Penguins".

# Clean PATH without /usr/local or user paths
CLEAN_PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/X11R6/bin"

# required rpm-build-macros
RPM_MACROS_VER=1.534

COMMAND="build"
TARGET=""

SPECFILE=""
BE_VERBOSE=""
QUIET=""
CLEAN=""
DEBUG=""
NOURLS=""
NOCVSSPEC=""
NODIST=""
NOINIT=""
PREFMIRRORS=""
UPDATE=""
ADD5=""
NO5=""
ALWAYS_CVSUP=${ALWAYS_CVSUP:-"yes"}

# use rpm 4.4.6+ digest format instead of comments if non-zero
USEDIGEST=

# user agent when fetching files
USER_AGENT="PLD/Builder($VERSION)"

# It can be used i.e. in log file naming.
# See LOGFILE example.
DATE=`date +%Y-%m-%d_%H-%M-%S`

# target arch, can also be used for log file naming
TARGET=$(rpm -E %{_target})

# Note the *single* quotes, this allows using shell variables expanded at build time
# Example: LOGFILE='../log.$PACKAGE_NAME'
# Example: LOGFILE='../LOGS/log.$PACKAGE_NAME.$DATE'
# Example: LOGFILE='$PACKAGE_NAME/$PACKAGE_NAME.$DATE.log'
# Example: LOGFILE='$PACKAGE_NAME.$DATE.log'
# Example: LOGFILE='.log.$PACKAGE_NAME-$PACKAGE_VERSION-$PACKAGE_RELEASE.$TARGET.$DATE'
LOGFILE=''

# use teeboth Perl wrapper
# temporary option to disable if broken
command -v perl > /dev/null 2>&1 && USE_TEEBOTH=yes || USE_TEEBOTH=no

LOGDIR=""
LOGDIROK=""
LOGDIRFAIL=""
LASTLOG_FILE=""

CHMOD="no"
CHMOD_MODE="0644"
RPMOPTS=""
RPMBUILDOPTS=""
BCOND=""
GROUP_BCONDS="no"

# create symlinks for tools in PACKAGE_DIR, see get_spec()
SYMLINK_TOOLS="no"

PATCHES=""
SOURCES=""
ICONS=""
PACKAGE_RELEASE=""
PACKAGE_VERSION=""
PACKAGE_NAME=""
ASSUMED_NAME=""
PROTOCOL="http"
IPOPT=""

# use lftp by default when available
test -z "${USE_LFTP+x}" && lftp --version > /dev/null 2>&1 && USE_LFTP=yes
PARALLEL_DOWNLOADS=10

WGET_RETRIES=${MAX_WGET_RETRIES:-0}

CVS_FORCE=""
CVSIGNORE_DF="yes"
CVSTAG=""
GIT_SERVER="git://git.pld-linux.org"
GIT_PUSH="git@git.pld-linux.org"
PACKAGES_DIR="packages"
HEAD_DETACHED=""
DEPTH=""
ALL_BRANCHES=""
REMOTE_PLD="origin"
NEW_REPO=""

RES_FILE=""

DISTFILES_SERVER="://distfiles.pld-linux.org"
ATTICDISTFILES_SERVER="://attic-distfiles.pld-linux.org"

DEF_NICE_LEVEL=19
SCHEDTOOL="auto"

FAIL_IF_NO_SOURCES="yes"

# let get_files skip over files which are present to get those damn files fetched
SKIP_EXISTING_FILES="no"

TRY_UPGRADE=""
# should the specfile be restored if upgrade failed?
REVERT_BROKEN_UPGRADE="yes"

# disable network for rpm build tool
NONETWORK="unshare --user --net --map-current-user"

if rpm --specsrpm 2>/dev/null; then
	FETCH_BUILD_REQUIRES_RPMSPECSRPM="yes"
	FETCH_BUILD_REQUIRES_RPMSPEC_BINARY="no"
	FETCH_BUILD_REQUIRES_RPMGETDEPS="no"
elif [ -x /usr/bin/rpmspec ]; then
	FETCH_BUILD_REQUIRES_RPMSPECSRPM="no"
	FETCH_BUILD_REQUIRES_RPMSPEC_BINARY="yes"
	FETCH_BUILD_REQUIRES_RPMGETDEPS="no"
else
	if [ -x /usr/bin/rpm-getdeps ]; then
		FETCH_BUILD_REQUIRES_RPMGETDEPS="yes"
	else
		FETCH_BUILD_REQUIRES_RPMGETDEPS="no"
	fi
fi

UPDATE_POLDEK_INDEXES_OPTS=""

# Here we load saved user environment used to
# predefine options set above, or passed to builder
# in command line.
# This one reads global system environment settings:
if [ -f ~/etc/builderrc ]; then
	. ~/etc/builderrc
fi
# And this one cascades settings using user personal
# builder settings.
# Example of ~/.builderrc:
#
#UPDATE_POLDEK_INDEXES="yes"
#UPDATE_POLDEK_INDEXES_OPTS="--mo=nodiff"
#FETCH_BUILD_REQUIRES="yes"
#REMOVE_BUILD_REQUIRES="force"
#GROUP_BCONDS="yes"
#LOGFILE='../LOGS/log.$PACKAGE_NAME.$DATE'
#TITLECHANGE=no

if [ "$(id -u )" != "0" ]; then
	SU_SUDO="sudo"
fi

if [ -n "$HOME_ETC" ]; then
	USER_CFG="$HOME_ETC/.builderrc"
	BUILDER_MACROS="$HOME_ETC/.builder-rpmmacros"
else
	USER_CFG=~/.builderrc
	BUILDER_MACROS=~/.builder-rpmmacros
fi

[ -f "$USER_CFG" ] && . "$USER_CFG"

if [ "$SCHEDTOOL" = "auto" ]; then
	if [ -x /usr/bin/schedtool ] && schedtool -B -e echo >/dev/null; then
		SCHEDTOOL="schedtool -B -e"
	else
		SCHEDTOOL="no"
	fi
fi

if [ -n "$USE_PROZILLA" ]; then
	GETURI=download_proz
elif [ -n "$USE_AXEL" ]; then
	GETURI=download_axel
elif [ -n "$USE_LFTP" ]; then
	GETURI=download_lftp
else
	GETURI=download_wget
fi

GETLOCAL=${GETLOCAL:-cp -a}

RPM="rpm"
RPMBUILD="rpmbuild"

#
# sanity checks
#
if [ -d $HOME/rpm/SOURCES ]; then
	echo "ERROR: ~/rpm/{SPECS,SOURCES} structure is obsolete" >&2
	echo "ERROR: get rid of your ~/rpm/SOURCES" >&2
	exit 1
fi

POLDEK_INDEX_DIR="$($RPM --eval %_rpmdir)/"
POLDEK_CMD="$SU_SUDO /usr/bin/poldek"

# TODO: add teeboth
# TODO: what this function does?
run_poldek() {
	RES_FILE=$(tempfile)
	if [ -n "$LOGFILE" ]; then
		LOG=`eval echo $LOGFILE`
		if [ -n "$LASTLOG_FILE" ]; then
			echo "LASTLOG=$LOG" > $LASTLOG_FILE
		fi
		(${NICE_COMMAND} ${POLDEK_CMD} --noask `while test $# -gt 0; do echo "$1 ";shift;done` ; echo $? > ${RES_FILE})|tee -a $LOG
		# FIXME $exit_pldk undefined
		return $exit_pldk
	else
		(${NICE_COMMAND} ${POLDEK_CMD} --noask `while test $# -gt 0; do echo "$1 ";shift;done` ; echo $? > ${RES_FILE}) 1>&2 >/dev/null
		return `cat ${RES_FILE}`
		rm -rf ${RES_FILE}
	fi
}

#---------------------------------------------
# functions

download_prozilla() {
	local outfile=$1 url=$2 retval

	proz --no-getch -r -P ./ -t$WGET_RETRIES $PROZILLA_OPTS -O "$outfile" "$url"
	retval=$?

	return $retval
}

download_axel() {
	local outfile=$1 url=$2 retval

	axel -a $AXEL_OPTS -o "$outfile" "$url"
	retval=$?

	return $retval
}

download_wget() {
	local outfile=$1 url=$2 retval wget_help
	if [ -z "${WGET_OPTS_SET+x}" ]; then
		wget_help="$(wget --help 2>&1)"
		echo "$wget_help" | grep -q -- ' --inet ' && WGET_OPTS="$WGET_OPTS --inet"
		echo "$wget_help" | grep -q -- ' --retry-connrefused ' && WGET_OPTS="$WGET_OPTS --retry-connrefused"
		echo "$wget_help" | grep -q -- ' --no-iri ' && WGET_OPTS="$WGET_OPTS --no-iri"
		WGET_OPTS="-c -nd -t$WGET_RETRIES $WGET_OPTS --user-agent=$USER_AGENT $IPOPT --passive-ftp"
		WGET_OPTS_SET=1
	fi

	wget $WGET_OPTS -O "$outfile" "$url"
	retval=$?
	if [ $retval -ne 0 ]; then
		if [ "`echo $url | grep -E 'ftp://'`" ]; then
			${GETURI} -O "$outfile" "$url"
			retval=$?
		fi
	fi
	return $retval
}

download_lftp() {
	local outfile=$1 url=$2 retval tmpfile
	tmpfile=$(tempfile) || exit 1
	lftp -c "
		$([ "$DEBUG" = "yes" ] && echo "debug 5;")
		$([ "$IPOPT" = "-4" ] && echo "set dns:order \"inet\";")
		$([ "$IPOPT" = "-6" ] && echo "set dns:order \"inet6\";")
		set ssl:verify-certificate no;
		set net:max-retries $WGET_RETRIES;
		set http:user-agent \"$USER_AGENT\";
		pget -n $PARALLEL_DOWNLOADS -c \"$url\" -o \"$tmpfile\"
	"

	retval=$?
	if [ $retval -eq 0 ]; then
		mv -f "$tmpfile" "$outfile"
	else
		rm -f "$tmpfile"
	fi
	return $retval
}

usage() {
	if [ -n "$DEBUG" ]; then set -xv; fi
# NOTE:
# to make this output parseable by bash-completion _parse_help()
# if the line contains short and long option, it will take only the long option
# but if you want both being completed, put the short option to separate line
	echo "\
Usage: builder [--all-branches] [-D|--debug] [-V|--version] [--short-version]  [-a|--add_cvs] [-b|-ba|--build]
[-bb|--build-binary] [-bs|--build-source] [-bc] [-bi] [-bl] [-u|--try-upgrade]
[{-cf|--cvs-force}] [{-B|--branch} <branch>] [--depth <number>]
[-g|--get] [-h|--help] [--ftp] [--http] [{-l|--logtofile} <logfile>] [-m|--mr-proper]
[-q|--quiet] [--date <yyyy-mm-dd> [-r <tag>] [{-T|--tag <tag>]
[-Tvs|--tag-version-stable] [-Ts|--tag-stable] [-Tv|--tag-version]
[{-Tp|--tag-prefix} <prefix>] [{-tt|--test-tag}]
[-nu|--no-urls] [-v|--verbose] [--opts <rpm opts>] [--short-circuit]
[--show-bconds] [--with/--without <feature>] [--define <macro> <value>]
<package>[.spec][:tag]

-4                  - force IPv4 when transferring files
-6                  - force IPv6 when transferring files
-5,
--update-md5        - update md5 comments in spec, implies -nd -ncs
-a5,
--add-md5           - add md5 comments to URL sources, implies -nc -nd -ncs
--all-branches      - make shallow fetch of all branches; --depth required
-n5, --no-md5       - ignore md5 comments in spec
-D, --debug         - enable builder script debugging mode,
-debug              - produce rpm debug package (same as --opts -debug)
-V, --version       - output builder version string
--short-version     - output builder short version
-a                  - try add new package to PLD repo.
-b,
-ba
                    - get all files from PLD repo or HTTP/FTP and build package
                      from <package>.spec,
-bb                 - get all files from PLD repo or HTTP/FTP and build binary
                      only package from <package>.spec,
-bp                 - execute the %prep phase of <package>.spec,
-bc                 - execute the %build phase of <package>.spec,
-bi                 - execute the %install phase of <package>.spec
-bl                 - execute the %files phase of <package>.spec
-bs                 - get all files from PLD repo or HTTP/FTP and only pack
                      them into src.rpm,
--bnet				- enable network access for rpm build tool
--short-circuit     - short-circuit build
-B, --branch        - add branch
-c,
--clean             - clean all temporarily created files (in BUILD\$RPM_BUILD_ROOT) after rpmbuild commands.
                      may be used with building process.
-m, --mr-proper     - clean all temporarily created files (in BUILD, SOURCES,
                      SPECS and \$RPM_BUILD_ROOT). Doesn't run any rpm building.
-cf, --cvs-force    - use -f when tagging
--define '<macro> <value>'
                    - define a macro <macro> with value <value>,
--depth <number>    - make shallow fetch
--alt_kernel <kernel>
                    - same as --define 'alt_kernel <kernel>'
--nodeps            - rpm won't check any dependences
-g
--get               - get <package>.spec and all related files from PLD repo
-h, --help          - this message,
-j N                - set %_smp_mflags to propagate concurrent jobs
--ftp               - use FTP protocol to access distfiles server
--http              - use HTTP protocol to access distfiles server
-l <logfile>, --logtofile=<logfile>
                    - log all to file,
-ncs, --no-cvs-specs
                    - don't pull from PLD repo
-nd, --no-distfiles - don't download from distfiles
-nm, --no-mirrors   - don't download from mirror, if source URL is given,
-nu, --no-urls      - don't try to download from FTP/HTTP location,
-ns, --no-srcs      - don't download Sources/Patches
-ns0, --no-source0  - don't download Source0
-nn, --no-net       - don't download anything from the net
-p N                - set PARALLEL_DOWNLOADS to N (default $PARALLEL_DOWNLOADS)
-pm, --prefer-mirrors
                    - prefer mirrors (if any) over distfiles for SOURCES
--no-init           - don't initialize builder paths (SPECS and SOURCES)
-ske,
--skip-existing-files
                    - skip existing files in get_files
--opts <rpm opts>   - additional options for rpm
-q, --quiet         - be quiet,
--date yyyy-mm-dd   - build package using resources from specified date,
-r <tag>, --cvstag <ref>
                    - build package using resources from specified branch/tag,
-A                  - build package using master branch as any sticky tags/branch/date being reset.
-R, --fetch-build-requires
                    - fetch what is BuildRequired,
-RB, --remove-build-requires
                    - remove all you fetched with -R or --fetch-build-requires
                      remember, this option requires confirmation,
-FRB, --force-remove-build-requires
                    - remove all you fetched with -R or --fetch-build-requires
                      remember, this option works without confirmation,
-sd, --source-distfiles
                    - list sources available from distfiles (intended for offline
                      operations; does not work when Icon field is present
                      but icon file is absent),
-sc, --source-cvs   - list sources available from PLD repo
-sdp, --source-distfiles-paths
                    - list sources available from distfiles -
                      paths relative to distfiles directory (intended for offline
                      operations; does not work when Icon field is present
                      but icon file is absent),
-sf, --source-files - list sources - bare filenames (intended for offline
                      operations; does not work when Icon field is present
                      but icon file is absent),
-lsp, --source-paths
                    - list sources - filenames with full local paths (intended for
                      offline operations; does not work when Icon field is present
                      but icon file is absent),
-su, --source-urls  - list urls - urls to sources and patches
                      intended for copying urls with spec with lots of macros in urls
-T <tag> , --tag <tag>
                    - add git tag <tag> for files,
-Tvs, --tag-version-stable
                    - add git tags STABLE and NAME-VERSION-RELEASE for files,
-Ts, --tag-stable
                    - add git tag STABLE for files,
-Tv,
--tag-version       - add git tag NAME-VERSION-RELEASE for files,
-Tp, --tag-prefix <prefix>
                    - add <prefix> to NAME-VERSION-RELEASE tags,
-tt, --test-tag <prefix>
                    - fail if tag is already present,
-ir, --integer-release-only
                    - allow only integer and snapshot releases
-v, --verbose       - be verbose,
-u, --try-upgrade   - check version, and try to upgrade package
-un, --try-upgrade-with-float-version
                    - as above, but allow float version
                      php-pear-Services_Digg/
--upgrade-version   - upgrade to specified version in try-upgrade
-U, --update        - refetch sources, don't use distfiles, and update md5 comments
-Upi, --update-poldek-indexes
                    - refresh or make poldek package index files.
-sp <patchnumber>,
--skip-patch <patchnumber>
                    - don't apply <patchnumber>. may be repeated.
-np <patchnumber>,
--nopatch <patchnumber>
                    - abort instead of applying patch <patchnumber>
--noinit
                    - do not initialize SPECS_DIR and SOURCES_DIR (set them to .)
--show-bconds       - show available conditional builds, which can be used
                    - with --with and/or --without switches.
--show-bcond-args   - show active bconds, from ~/.bcondrc. this is used by ./repackage.sh script.
                      In other words, the output is parseable by scripts.
--show-avail-bconds - show available bconds
--with <feature>,
--without <feature>
                    - conditional build package depending on %_with_<feature>/
                      %_without_<feature> macro switch.  You may now use
                      --with feat1 feat2 feat3 --without feat4 feat5 --with feat6
                      constructions. Set GROUP_BCONDS to yes to make use of it.
--target <platform>, --target=<platform>
                    - build for platform <platform>.
--init-rpm-dir, --init
                    - initialize ~/rpm directory structure
"
}

is_rpmorg() {
	local v

	v=$(LC_ALL=C LANG=C rpm --version 2>&1)
	v=${v#RPM version } # rpm 4
	v=${v#rpm \(RPM\) } # rpm 5

	case "$v" in
		4.5|5.*)
			return 1
			;;
		4.*)
			return 0;
			;;
		*)
			echo "ERROR: unsupported RPM version $v" >&2
			exit 1
	esac
}

# create tempfile. as secure as possible
tempfile() {
	local prefix=builder.$PACKAGE_NAME${1:+.$1}
	mktemp --tmpdir -t $prefix.XXXXXX || echo ${TMPDIR:-/tmp}/$prefix.$RANDOM.$$
}

tempdir() {
	local prefix=builder.$PACKAGE_NAME${1:+.$1}
	mktemp --tmpdir -d $prefix.XXXXXX
}

# inserts git log instead of %changelog
# @output directory containing modified specfile
insert_gitlog() {
	local SPECFILE=$1 specdir=$(tempdir) gitlog=$(tempfile) speclog=$(tempfile)

	# allow this being customized
	local log_entries=$(rpm -E '%{?_buildchangelogtruncate}')

	# rpm5.org/rpm.org do not parse any other date format than 'Wed Jan 1 1997'
	# otherwise i'd use --date=iso here
	# http://rpm5.org/cvs/fileview?f=rpm/build/parseChangelog.c&v=2.44.2.1
	# http://rpm.org/gitweb?p=rpm.git;a=blob;f=build/parseChangelog.c;h=56ba69daa41d65ec9fd18c9f371b8ff14118cdca;hb=a113baa510a004476edc44b5ebaaf559238a18b6#l33
	# NOTE: changelog date is always in UTC for rpmbuild
	# * 1265749244 +0000 Random Hacker <nikt@pld-linux.org> 9370900
	git rev-list --date-order -${log_entries:-20} HEAD 2>/dev/null | while read sha1; do
		local logfmt='%B%n'
		git notes list $sha1 > /dev/null 2>&1 && logfmt='%N'
		git log -n 1 $sha1 --format=format:"* %ad %an <%ae> %h%n- ${logfmt}%n" --date=raw | sed -re 's/^- +- */- /'| sed '/^$/q'
	done > $gitlog

	# add link to full git logs
	local giturl="http://git.pld-linux.org/?p=packages/${SPECFILE%.spec}.git;a=log"
	if [ -n "$CVSTAG" ]; then
		giturl="$giturl;h=$CVSTAG"
	fi
	local gitauthor="PLD Linux Team <feedback@pld-linux.org>"
	LC_ALL=C gawk -vgiturl="$giturl" -vgitauthor="$gitauthor" -vpackage=$PACKAGE_NAME 'BEGIN{
		printf("* %s %s\n- For complete changelog see: %s\n", strftime("%a %b %d %Y"), gitauthor, giturl);
		print;
		exit
	}' > $speclog

	LC_ALL=C gawk '/^\* /{printf("* %s %s\n", strftime("%a %b %d %Y", $2), substr($0, length($1)+length($2)+length($3)+4)); next}{print}' $gitlog >> $speclog
	sed '/^%changelog/,$d' $SPECFILE | sed -e "\${
			a%changelog
			r $speclog
		}
	" > $specdir/$SPECFILE
	rm -f $gitlog $speclog
	echo $specdir
}

# @param string logfile
# @param varargs... commands to execute
teeboth() {
	local rc
	# use teeboth from toys/cleanbuild, if available and enabled
	if [ "$USE_TEEBOTH" = "yes" ] && [ -x $APPDIR/teeboth ]; then
		$APPDIR/teeboth "$@"
		rc=$?
	else
		local efile rc logfile=$1; shift
		if [ "$logfile" ]; then
			efile=$(tempfile)
			{ "$@" 2>&1; echo $? > $efile; } | tee -a $logfile
			rc=$(< $efile)
			rm -f $efile
		else
			"$@"
			rc=$?
		fi
	fi
	return $rc
}

# change dependency to specname
# common changes:
# - perl(Package::Name) -> perl-Package-Name
depspecname() {
	local DEPS

	if [ $# -gt 0 ]; then
		DEPS="$@"
	else
		DEPS=$(cat)
	fi

	echo "$DEPS" | tr ' ' '\n' | sed -re '
		# perl virtual deps
		/perl\(.*\)/{
			s/perl\((.*)\)/perl-\1/
			s/::/-/g
		}

		s/apache\(EAPI\)-devel/apache-devel/

		s/^db-devel/db5.3-devel/
		s/libjpeg-devel/libjpeg-turbo-devel/
	'
}

update_shell_title() {
	[ -t 2 ] || return
	local len=${COLUMNS:-80}
	local msg="$(echo "$*" | cut -c-$len)"

	if [ -n "$BE_VERBOSE" ]; then
		echo >&2 "$(date +%s.%N) $*"
	fi

	if [ "x$TITLECHANGE" = "xyes" -o "x$TITLECHANGE" = "x" ]; then
		local pkg
		if [ -n "$PACKAGE_NAME" ]; then
			pkg=${PACKAGE_NAME}-${PACKAGE_VERSION}-${PACKAGE_RELEASE}
		else
			pkg=${SPECFILE}
		fi

		msg="$pkg: ${SHELL_TITLE_PREFIX:+$SHELL_TITLE_PREFIX }$msg"
		msg=$(echo $msg | tr -d '\n\r')
		case "$TERM" in
			cygwin|xterm*)
			echo >&2 -ne "\033]1;$msg\007\033]2;$msg\007"
		;;
			screen*)
			echo >&2 -ne "\033]0;$msg\007"
		;;
		esac
	fi
}

# set TARGET from BuildArch: from SPECFILE
set_spec_target() {
	if [ -n "$SPECFILE" ] && [ -z "$TARGET" ]; then
		local tmp=$(awk '/^BuildArch:/ { print $NF; exit }' $ASSUMED_NAME/$SPECFILE)
		if [ "$tmp" ]; then
				local target_platform=$(rpm -E '%{_target_vendor}-%{_target_os}%{?_gnu}')
				TARGET="$tmp"
				case "$RPMBUILD" in
				"rpmbuild")
					TARGET_SWITCH="--target ${TARGET}-${target_platform}" ;;
				"rpm")
					TARGET_SWITCH="--target=$TARGET" ;;
				esac
		fi
	fi
}

# runs rpm with minimal macroset
minirpm() {
	# TODO: move these to /usr/lib/rpm/macros
	cat > $BUILDER_MACROS <<'EOF'
%x8664 x86_64 amd64 ia32e
%alt_kernel %{nil}
%_alt_kernel %{nil}
%bootstrap_release() %{1}
%requires_releq_kernel_up(s:n:) %{nil}
%requires_releq_kernel_smp(s:n:) %{nil}
%requires_releq_kernel(s:n:) %{nil}
%requires_releq() %{nil}
%pyrequires_eq() %{nil}
%requires_eq() %{nil}
%requires_eq_to() %{nil}
%requires_ge() %{nil}
%requires_ge_to() %{nil}
%requires_ge() %{nil}
%releq_kernel_up(n:) ERROR
%releq_kernel_smp(n:) ERROR
%releq_kernel(n:) ERROR
%py_postclean(x:) ERROR
%kgcc_package ERROR
%_fontsdir ERROR
%ruby_version ERROR
%ruby_ver_requires_eq() %{nil}
%ruby_mod_ver_requires_eq() %{nil}
%__php_api_requires() %{nil}
%php_major_version ERROR
%php_api_version ERROR
%requires_xorg_xserver_extension %{nil}
%requires_xorg_xserver_xinput %{nil}
%requires_xorg_xserver_font %{nil}
%requires_xorg_xserver_videodrv %{nil}
%py_ver ERROR
%perl_vendorarch ERROR
%perl_vendorlib ERROR
# damn. need it here! - copied from /usr/lib/rpm/macros.build
%tmpdir		%(echo "${TMPDIR:-/tmp}")
%patchset_source(f:b:) %(
	base=%{-b*}%{!-b*:10000};
	start=$(expr $base + %1);
	end=$(expr $base + %{?2}%{!?2:%{1}});
	# we need to call seq twice as it doesn't allow two formats
	seq -f 'Patch%g:' $start $end > %{tmpdir}/__ps1;
	seq -f '%{-f*}' %1 %{?2}%{!?2:%{1}} > %{tmpdir}/__ps2;
	paste %{tmpdir}/__ps{1,2};
	rm -f %{tmpdir}/__ps{1,2};
) \
%{nil}
%add_etc_shells(p) %{p:<lua>}
%remove_etc_shells(p) %{p:<lua>}
%lua_add_etc_shells()  %{nil}
%lua_remove_etc_shells() %{nil}
%required_jdk jdk
%buildrequires_jdk %{nil}
%pear_package_print_optionalpackages %{nil}
EOF
	if [ "$NOINIT" = "yes" ] ; then
		cat >> $BUILDER_MACROS <<'EOF'
%_specdir ./
%_sourcedir ./
EOF
	fi
	if ! is_rpmorg; then
		local safe_macrofiles
		safe_macrofiles=$(rpm $TARGET_SWITCH --showrc | awk -F: '/^macrofiles/ { gsub(/^macrofiles[ \t]+:/, "", $0); print $0 } ')
		eval PATH=$CLEAN_PATH $RPMBUILD $TARGET_SWITCH --macros "$safe_macrofiles:$BUILDER_MACROS" $QUIET $RPMOPTS $RPMBUILDOPTS $BCOND $* 2>&1
	else
		eval PATH=$CLEAN_PATH $RPMBUILD $TARGET_SWITCH --load "$BUILDER_MACROS" $QUIET $RPMOPTS $RPMBUILDOPTS $BCOND $* 2>&1
	fi
}

cache_rpm_dump() {
	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	if [ -x /usr/bin/rpm-specdump ]; then
		update_shell_title "cache_rpm_dump using rpm-specdump command"
		rpm_dump_cache=$(rpm-specdump $TARGET_SWITCH $BCOND --define "_specdir $PACKAGE_DIR" --define "_sourcedir $PACKAGE_DIR" $PACKAGE_DIR/$SPECFILE)
	else
		update_shell_title "cache_rpm_dump using rpmbuild command"
		local rpm_dump
		rpm_dump=`
			# what we need from dump is NAME, VERSION, RELEASE and PATCHES/SOURCES.
			dump='%{echo:dummy: PACKAGE_NAME %{name} }%dump'
			case "$RPMBUILD" in
			rpm)
				ARGS='-bp'
				;;
			rpmbuild)
				ARGS='--nodigest --nosignature --nobuild'
				;;
			esac
			minirpm $ARGS --define "'prep $dump'" --nodeps $SPECFILE
		`
		if [ $? -gt 0 ]; then
			error=$(echo "$rpm_dump" | sed -ne '/^error:/,$p')
			echo "$error" >&2
			Exit_error err_build_fail
		fi

		# make small dump cache
		rpm_dump_cache=`echo "$rpm_dump" | awk '
			$2 ~ /^SOURCEURL/ {print}
			$2 ~ /^PATCHURL/  {print}
			$2 ~ /^nosource/ {print}
			$2 ~ /^PACKAGE_/ {print}
		'`
	fi

	update_shell_title "cache_rpm_dump: OK!"
}

rpm_dump() {
	if [ -z "$rpm_dump_cache" ] ; then
		echo >&2 "internal error: cache_rpm_dump not called! (missing %prep?)"
	fi
	echo "$rpm_dump_cache"
}

get_icons() {
	update_shell_title "get icons"
	ICONS=$(awk '/^Icon:/ {print $2}' $PACKAGE_DIR/${SPECFILE})
	if [ -z "$ICONS" ]; then
		return
	fi

	rpm_dump_cache="kalasaba" NODIST="yes" get_files $ICONS
}

parse_spec() {
	update_shell_title "parsing specfile"
	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	# icons are needed for successful spec parse
	get_icons

	cd $PACKAGE_DIR
	cache_rpm_dump

	if rpm_dump | grep -qEi ":.*nosource.*1"; then
		FAIL_IF_NO_SOURCES="no"
	fi

	if [ "$NOSRCS" != "yes" ]; then
		SOURCES=$(rpm_dump | awk '$2 ~ /^SOURCEURL[0-9]+/ {print substr($2, length("SOURCEURL") + 1), $3}' | LC_ALL=C sort -n | awk '{print $2}')
		PATCHES=$(rpm_dump | awk '$2 ~ /^PATCHURL[0-9]+/ {print substr($2, length("PATCHURL") + 1), $3}' | LC_ALL=C sort -n | awk '{print $2}')
		ICONS=$(awk '/^Icon:/ {print $2}' ${SPECFILE})
	fi

	PACKAGE_NAME=$(rpm_dump | awk '$2 == "PACKAGE_NAME" { print $3; exit}')
	PACKAGE_VERSION=$(rpm_dump | awk '$2 == "PACKAGE_VERSION" { print $3; exit}')
	PACKAGE_RELEASE=$(rpm_dump | awk '$2 == "PACKAGE_RELEASE" { print $3; exit}')

	if [ "$PACKAGE_NAME" != "$ASSUMED_NAME" ]; then
		echo >&2 "WARNING! Spec name ($ASSUMED_NAME) does not agree with package name ($PACKAGE_NAME)"
	fi

	if [ -n "$BE_VERBOSE" ]; then
		echo "- Sources :  `nourl $SOURCES`"
		if [ -n "$PATCHES" ]; then
			echo "- Patches :  `nourl $PATCHES`"
		else
			echo "- Patches :  *no patches needed*"
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

	update_shell_title "parse_spec: OK!"
}

# aborts program abnormally
die() {
	local rc=${2:-1}
	echo >&2 "$PROGRAM: ERROR: $*"
	exit $rc
}

Exit_error() {
	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	cd "$__PWD"

	case "$1" in
		"err_no_spec_in_cmdl" )
			remove_build_requires
			echo >&2 "ERROR: spec file name not specified."
			exit 2 ;;
		"err_invalid_cmdline" )
			echo >&2 "ERROR: invalid command line arg ($2)."
			exit 2 ;;
		"err_no_spec_in_repo" )
			remove_build_requires
			echo >&2 "Error: spec file not stored in repository."
			if [ -n "$2" ]; then
				echo >&2 "Tried: $2"
			fi

			exit 3 ;;
		"err_no_source_in_repo" )
			remove_build_requires
			echo >&2 "Error: some source, patch or icon files not stored in PLD repo. ($2)"
			exit 4 ;;
		"err_cvs_add_failed" )
			echo >&2 "Error: failed to add package to PLD repo."
			exit 4 ;;
		"err_build_fail" )
			remove_build_requires
			echo >&2 "Error: package build failed. (${2:-no more info})"
			exit 5 ;;
		"err_no_package_data" )
			remove_build_requires
			echo >&2 "Error: couldn't get out package name/version/release from spec file."
			exit 6 ;;
		"err_tag_exists" )
			remove_build_requires
			echo >&2 "Tag ${2} already exists"
			exit 9 ;;
		"err_fract_rel" )
			remove_build_requires
			echo >&2 "Release ${2} not integer and not a snapshot."
			exit 10 ;;
		"err_branch_exists" )
			remove_build_requires
			echo >&2 "Tree branch already exists (${2})."
			exit 11 ;;
		"err_acl_deny" )
			remove_build_requires
			echo >&2 "Error: conditions reject building this spec (${2})."
			exit 12 ;;
		"err_remote_problem" )
			remove_build_requires
			echo >&2 "Error: problem with remote (${2})"
			exit 13 ;;
		"err_no_checkut" )
			echo >&2 "Error: cannot checkout $2"
			exit 14 ;;
		"err_not_implemented" )
			remove_build_requires
			echo >&2 "Error: functionality not yet imlemented"
			exit 110 ;;
	esac
	echo >&2 "Unknown error."
	exit 100
}

init_builder() {
	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	if [ "$NOINIT" != "yes" ] ; then
		TOP_DIR=$(eval $RPM $RPMOPTS --eval '%{_topdir}')

		local macros_ver=$(rpm -E %?rpm_build_macros)
		if [ -z "$macros_ver" ]; then
			REPO_DIR=$TOP_DIR/packages
			PACKAGE_DIR=$TOP_DIR/packages/$ASSUMED_NAME
		else
			if awk "BEGIN{exit($macros_ver>=$RPM_MACROS_VER)}"; then
				echo >&2 "builder requires rpm-build-macros >= $RPM_MACROS_VER"
				exit 1
			fi
			REPO_DIR=$TOP_DIR
			PACKAGE_DIR=$REPO_DIR/$ASSUMED_NAME
		fi
	else
		TOP_DIR=$(pwd)
		PACKAGE_DIR=$TOP_DIR
		REPO_DIR=$PACKAGE_DIR
		RPMBUILDOPTS="$RPMBUILDOPTS --define '_topdir $TOP_DIR' --define '_builddir %_topdir' --define '_rpmdir %_topdir' --define '_srcrpmdir %_topdir'"
	fi
	export GIT_WORK_TREE=$PACKAGE_DIR
	export GIT_DIR=$PACKAGE_DIR/.git

	if [ -d "$GIT_DIR" ] &&  [ -z "$CVSTAG" ] && git rev-parse --verify -q HEAD > /dev/null; then
		if CVSTAG=$(GIT_DIR=$GIT_DIR git symbolic-ref HEAD) 2>/dev/null; then
			CVSTAG=${CVSTAG#refs/heads/}
			if [ "$CVSTAG" != "master" ]; then
				echo >&2 "builder: Active branch $CVSTAG. Use -r BRANCHNAME to override"
			fi
		else
			echo >&2 "On detached HEAD. Use -r BRANCHNAME to override"
			HEAD_DETACHED="yes"
		fi
	elif [ "$CVSTAG" = "HEAD" ]; then
		# assume -r HEAD is same as -A
		CVSTAG="master"
	fi

	__PWD=$(pwd)
}

create_git_repo() {
	update_shell_title "add_package"

	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	cd "$REPO_DIR"
	SPECFILE=$(basename $SPECFILE)
	if [ ! -f "$ASSUMED_NAME/$SPECFILE" ]; then
		echo "ERROR: No package to add ($ASSUMED_NAME/$SPECFILE)" >&2
		exit 101
	fi
	[ -d "$ASSUMED_NAME/.git" ] || NEW_REPO=yes
	ssh $GIT_PUSH create ${ASSUMED_NAME} || Exit_error err_cvs_add_failed
	(
	set -e
	git init
	git remote add $REMOTE_PLD ${GIT_SERVER}/${PACKAGES_DIR}/${ASSUMED_NAME}.git
	git remote set-url --push $REMOTE_PLD ssh://${GIT_PUSH}/${PACKAGES_DIR}/${ASSUMED_NAME}

	git config --local push.default current
	git config --local branch.master.remote $REMOTE_PLD
	git config --local branch.master.merge refs/heads/master
	)
	test $? = 0 || Exit_error err_remote_problem $REMOTE_PLD
}

get_spec() {

	update_shell_title "get_spec"

	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	cd "$REPO_DIR"
	SPECFILE=$(basename $SPECFILE)
	if [ "$NOCVSSPEC" != "yes" ]; then
		if [ -z "$DEPTH" ]; then
			if [ -d "$PACKAGE_DIR/.git" ]; then
				git fetch $IPOPT $REMOTE_PLD || Exit_error err_no_spec_in_repo
			elif [ "$ADD_PACKAGE_CVS" = "yes" ]; then
				if [ ! -r "$PACKAGE_DIR/$SPECFILE" ]; then
					echo "ERROR: No package to add ($PACKAGE_DIR/$SPECFILE)" >&2
					exit 101
				fi
				Exit_error err_not_implemented
			else
				(
					unset GIT_WORK_TREE
					git clone $IPOPT -o $REMOTE_PLD ${GIT_SERVER}/${PACKAGES_DIR}/${ASSUMED_NAME}.git || {
						# softfail if new package, i.e not yet added to PLD rep
						[ ! -f "$PACKAGE_DIR/$SPECFILE" ] && Exit_error err_no_spec_in_repo
						echo "Warning: package not in Git - assuming new package"
						NOCVSSPEC="yes"
					}
					git config --local --add "remote.$REMOTE_PLD.fetch" 'refs/notes/*:refs/notes/*'
					git config --local --add "remote.$REMOTE_PLD.push" 'refs/notes/*:refs/notes/*'
					git config --local --add "remote.$REMOTE_PLD.push" HEAD
					git config --local push.default current
					git remote set-url --push  $REMOTE_PLD ssh://${GIT_PUSH}/${PACKAGES_DIR}/${ASSUMED_NAME}
				)
			fi
		else
			if [ ! -d "$PACKAGE_DIR/.git" ]; then
				if [ ! -d "$PACKAGE_DIR" ]; then
					install -d $PACKAGE_DIR
				fi
				git init
				git remote add $REMOTE_PLD ${GIT_SERVER}/${PACKAGES_DIR}/${ASSUMED_NAME}.git
				git config --local --add "remote.$REMOTE_PLD.fetch" 'refs/notes/*:refs/notes/*'
				git config --local --add "remote.$REMOTE_PLD.push" 'refs/heads/*:refs/remotes/origin/*'
				git config --local --add "remote.$REMOTE_PLD.push" HEAD
				git config --local push.default current
				git remote set-url --push  $REMOTE_PLD ssh://${GIT_PUSH}/${PACKAGES_DIR}/${ASSUMED_NAME}
				CVSTAG=${CVSTAG:-"master"}
			fi
			local refs=''
			if [ -z "$ALL_BRANCHES" ]; then
				refs="${CVSTAG}:remotes/${REMOTE_PLD}/${CVSTAG}"
			fi
			git fetch $IPOPT $DEPTH $REMOTE_PLD $refs || {
				echo >&2 "Error: branch $CVSTAG does not exist"
				exit 3
			}
		fi
		git fetch $IPOPT $REMOTE_PLD 'refs/notes/*:refs/notes/*'

		cvsignore_df .gitignore

		# add default log format to .gitignore if it is relative to package dir
		if [ -n "$LOGFILE" -a "$LOGFILE" = "${LOGFILE##*/}" ]; then
			# substitute known "macros" to glob
			local logfile=$(echo "$LOGFILE" | sed -r -e 's,\$(PACKAGE_(NAME|VERSION|RELEASE)|DATE|TARGET),*,g')
			if [ "$logfile" ]; then
				cvsignore_df "$logfile"
			fi
		fi

		# create symlinks for tools
		if [ "$SYMLINK_TOOLS" != "no" -a -d "$PACKAGE_DIR" ]; then
			for a in dropin md5 builder {relup,compile,repackage,rsync,pearize}.sh; do
				# skip tools that don't exist in top dir
				[ -f $a ] || continue
				# skip tools that already exist
				[ -f $PACKAGE_DIR/$a ] && continue
				ln -s ../$a $PACKAGE_DIR
				cvsignore_df $a
			done
		fi
	fi

	if [ -n "$CVSTAG" ]; then
		if git rev-parse --verify -q "$CVSTAG" >/dev/null; then
			# checkout only if differs, so this will not trash git reflog
			if [ $(git rev-parse "$CVSTAG") != $(git rev-parse HEAD) ]; then
				git checkout "$CVSTAG" --
			fi
		elif git rev-parse --verify -q "refs/remotes/${REMOTE_PLD}/$CVSTAG"; then
			git checkout -t "refs/remotes/${REMOTE_PLD}/$CVSTAG" > /dev/null
		fi
		if [ $(git rev-parse "$CVSTAG") != $(git rev-parse HEAD) ]; then
			Exit_error "err_no_checkut" "$CVSTAG"
		fi

		git merge --ff-only '@{u}'
		git symbolic-ref -q HEAD > /dev/null && [ "$NOCVSSPEC" != "yes" ] &&
		if [ -n "$CVSDATE" ]; then
			git checkout $(git rev-list -n1 --before="'$CVSDATE'" $CVSTAG) || exit 1
		fi
	fi

	if [ ! -f "$PACKAGE_DIR/$SPECFILE" ]; then
		Exit_error err_no_spec_in_repo "$PACKAGE_DIR/$SPECFILE"
	fi

	if [ "$CHMOD" = "yes" -a -n "$SPECFILE" ]; then
		chmod $CHMOD_MODE $PACKAGE_DIR/$SPECFILE
	fi
	unset OPTIONS
	[ -n "$DONT_PRINT_REVISION" ] || grep -E -m 1 "^#.*Revision:.*Date" $PACKAGE_DIR/$SPECFILE

	set_spec_target
}

# find mirrors in this order. first match wins:
# - package dir (~/rpm/packages/foo)
# - repository dir (~/rpm/packages)
# - tools dir dir (~/rpm/packages/rpm-build-tools)
find_mirror() {
	local url="$1"

	update_shell_title "find_mirror[$url][$REPO_DIR]"

	# NOTE: as while loop runs in subshell,
	# we use exit 2 to indicate  that the match was found
	# otherwise we end up outputing mirror url and origin url.

	local origin mirror name rest ol prefix
	IFS="|"
	cat "$PACKAGE_DIR/mirrors" "$REPO_DIR/mirrors" "$REPO_DIR/../rpm-build-tools/mirrors" /dev/null 2>/dev/null | \
	while read origin mirror name rest; do
		# skip comments and empty lines
		if [ -z "$origin" ] || [ "${origin#\#}" != "$origin" ]; then
			continue
		fi
		ol=$(echo -n "$origin" | wc -c)
		prefix=$(echo -n "$url" | head -c $ol)
		if [ "$prefix" = "$origin" ] ; then
			suffix=$(echo "$url" | cut -b $((ol+1))-)
			echo -n "$mirror$suffix"
			exit 2
		fi
	done && echo "$url"
}

# Warning: unpredictable results if same URL used twice
src_no() {
	local file="$1"
	# escape some regexp characters if part of file name
	file=$(echo "$file" | sed -e 's#\([\+\*\.\&\#\?]\)#\\\1#g')
	cd $PACKAGE_DIR
	rpm_dump | \
	grep -E "(SOURCE|PATCH)URL[0-9]*[ 	]*${file}""[ 	]*$" | \
	sed -e 's/.*\(SOURCE\|PATCH\)URL\([0-9][0-9]*\).*/\1\2/' | \
	head -n 1 | tr OURCEATH ourceath | xargs
}

src_md5() {
	[ "$NO5" = "yes" ] && return
	no=$(src_no "$1")
	[ -z "$no" ] && return
	cd $PACKAGE_DIR
	local md5

	# use "sources" file from package dir, like vim
	if [ -f sources ]; then
		md5=$(grep -s -v '^#' sources | \
		grep -E "[ 	*]$(basename "$1")([ 	,]|\$)" | \
		sed -e 's/^\([0-9a-f]\{32\}\).*/\1/' | \
		grep -E '^[0-9a-f]{32}$')

		if [ "$md5" ]; then
			if [ $(echo "$md5" | wc -l) != 1 ] ; then
				echo "$SPECFILE: more then one entry in sources for $1" 1>&2
			fi
			echo "$md5" | tail -n 1
			return
		fi
	fi

	source_md5=$(grep -iE "^#[ 	]*(No)?$no-md5[ 	]*:" $SPECFILE | sed -e 's/.*://')
	if [ -n "$source_md5" ]; then
		echo $source_md5
	else
		source_md5=`grep -i "BuildRequires:[ 	]*digest(%SOURCE$no)[ 	]*=" $SPECFILE | sed -e 's/.*=//'`
		if [ -n "$source_md5" ]; then
			echo $source_md5
		else
			# we have empty SourceX-md5, but it is still possible
			# that we have NoSourceX-md5 AND NoSource: X
			nosource_md5=`grep -i "^#[	 ]*No$no-md5[	 ]*:" $SPECFILE | sed -e 's/.*://'`
			if [ -n "$nosource_md5" -a -n "`grep -i "^NoSource:[	 ]*$no$" $SPECFILE`" ] ; then
				echo $nosource_md5
			fi
		fi
	fi
}

distfiles_path() {
	echo "by-md5/$(src_md5 "$1" | sed -e 's|^\(.\)\(.\)|\1/\2/&|')/$(basename "$1")"
}

distfiles_url() {
	echo "$PROTOCOL$DISTFILES_SERVER/distfiles/$(distfiles_path "$1")"
}

distfiles_attic_url() {
	echo "$PROTOCOL$ATTICDISTFILES_SERVER/distfiles/Attic/$(distfiles_path "$1")"
}

good_md5() {
	md5=$(src_md5 "$1")
	[ "$md5" = "" ] || \
	[ "$md5" = "$(md5sum $(nourl "$1") 2> /dev/null | sed -e 's/ .*//')" ]
}

good_size() {
	size=$(find $(nourl "$1") -printf "%s" 2>/dev/null)
	[ -n "$size" -a "$size" -gt 0 ]
}

cvsignore_df() {
	if [ "$CVSIGNORE_DF" != "yes" ]; then
		return
	fi
	local cvsignore=${PACKAGE_DIR}/.git/info/exclude

	# add only if not yet there
	if ! awk -vf="$1" -vc=1 '$0 == f { c = 0 } END { exit c }' $cvsignore 2>/dev/null; then
		echo "$1" >> $cvsignore
	fi
}

# returns true if "$1" is ftp, http or https protocol url
is_url() {
	case "$1" in
	ftp://*|http://*|https://*)
		return 0
	;;
	esac
	return 1
}

update_md5() {
	if [ $# -eq 0 ]; then
		return
	fi

	update_shell_title "update md5"
	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	cd "$PACKAGE_DIR"

	# pass 1: check files to be fetched
	local todo
	local need_files
	for i in "$@"; do
		local fp=$(nourl "$i")
		local srcno=$(src_no "$i")
		if [ -n "$ADD5" ]; then
			[ "$fp" = "$i" ] && continue # FIXME what is this check doing?
			grep -qiE '^#[ 	]*'$srcno'-md5[ 	]*:' $PACKAGE_DIR/$SPECFILE && continue
			grep -qiE '^BuildRequires:[ 	]*digest[(]%SOURCE'$srcno'[)][ 	]*=' $PACKAGE_DIR/$SPECFILE && continue
		else
			grep -qiE '^#[ 	]*'$srcno'-md5[ 	]*:' $PACKAGE_DIR/$SPECFILE || grep -qiE '^BuildRequires:[ 	]*digest[(]%SOURCE'$srcno'[)][ 	]*=' $PACKAGE_DIR/$SPECFILE || continue
		fi
		if [ ! -f "$fp" ] || [ $ALWAYS_CVSUP = "yes" ]; then
			need_files="$need_files $i"
		fi
	done

	# pass 1a: get needed files
	if [ "$need_files" ]; then
		get_files $need_files
	fi

	# pass 2: proceed with md5 adding or updating
	for i in "$@"; do
		local fp=$(nourl "$i")
		local srcno=$(src_no "$i")
		local md5=$(grep -iE '^#[ 	]*(No)?'$srcno'-md5[ 	]*:' $PACKAGE_DIR/$SPECFILE )
		if [ -z "$md5" ]; then
			md5=$(grep -iE '^[ 	]*BuildRequires:[ 	]*digest[(]%SOURCE'$srcno'[)][ 	]*=' $PACKAGE_DIR/$SPECFILE )
		fi
		if [ -n "$ADD5" ] && is_url $i || [ -n "$md5" ]; then
			local tag="# $srcno-md5:\t"
			if [[ "$md5" == *NoSource* ]]; then
				tag="# No$srcno-md5:\t"
			elif [ -n "$USEDIGEST" ]; then
				tag="BuildRequires:\tdigest(%SOURCE$srcno) = "
			fi
			md5=$(md5sum "$fp" | cut -f1 -d' ')
			echo "Updating $srcno ($md5: $fp)."
			sed -i \
				-e '/^\(\s*#\s*\(No\)\?'$srcno'-md5\s*:\|\s*BuildRequires:\s*digest(%SOURCE'$srcno')\)/Id' \
				-e '/^'$srcno'\s*:\s\+/Ia \
'"$tag$md5" \
				$PACKAGE_DIR/$SPECFILE
		fi
	done
}

check_md5() {
	local bad
	[ "$NO5" = "yes" ] && return

	update_shell_title "check md5"

	for i in "$@"; do
		bad=0
		if ! good_md5 "$i"; then
			echo -n "MD5 sum mismatch."
			bad=1
		fi
		if ! good_size "$i"; then
			echo -n "0 sized file."
			bad=1
		fi

		if [ $bad -eq 1 ]; then
			echo " Use -U to refetch sources,"
			echo "or -5 to update md5 sums, if you're sure files are correct."
			Exit_error err_no_source_in_repo $i
		fi
	done
}

get_files() {
	update_shell_title "get_files"

	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	if [ $# -gt 0 ]; then
		cd "$PACKAGE_DIR"

		local nc=0
		local get_files_cvs=""
		for i in "$@"; do
			nc=$((nc + 1))
			local cvsup=0
			SHELL_TITLE_PREFIX="get_files[$nc/$#]"
			update_shell_title "$i"
			local fp=`nourl "$i"`
			if [ "$SKIP_EXISTING_FILES" = "yes" ] && [ -f "$fp" ]; then
				continue
			fi

			FROM_DISTFILES=0
			local srcmd5=$(src_md5 "$i")

			# we know if source/patch is present in cvs/distfiles
			# - has md5 (in distfiles)
			# - in cvs... ideas?

			# CHECK: local file didn't exist or always cvs up (first) requested.
			if [ ! -f "$fp" ] || [ $ALWAYS_CVSUP = "yes" ]; then
				if echo $i | grep -vE '(http|ftp|https|cvs|svn)://' | grep -qE '\.(gz|bz2)$']; then
					echo "Warning: no URL given for $i"
				fi
				target="$fp"

				if [ -z "$NODIST" ] && [ -n "$srcmd5" ]; then
					if good_md5 "$i" && good_size "$i"; then
						echo "$fp having proper md5sum already exists"
						continue
					fi

					# optionally prefer mirror over distfiles if there's mirror
					# TODO: build url list and then try each url from the list
					if [ -n "$PREFMIRRORS" ] && [ -z "$NOMIRRORS" ] && im=$(find_mirror "$i") && [ "$im" != "$i" ]; then
						url="$im"
					else
						url=$(distfiles_url "$i")
					fi

					url_attic=$(distfiles_attic_url "$i")
					FROM_DISTFILES=1
					# is $url local file?
					if [[ "$url" = [./]* ]]; then
						update_shell_title "${GETLOCAL%% *}: $url"
						${GETLOCAL} $url $target
					else
						local uri=${url}
						# make shorter message for distfiles urls
						if [[ "$uri" = ${PROTOCOL}${DISTFILES_SERVER}* ]] || [[ "$uri" = ${PROTOCOL}${ATTICDISTFILES_SERVER}* ]]; then
							uri=${uri#${PROTOCOL}${DISTFILES_SERVER}/distfiles/by-md5/?/?/*/}
							uri=${uri#${PROTOCOL}${ATTICDISTFILES_SERVER}/distfiles/by-md5/?/?/*/}
							uri="df: $uri"
						fi
						update_shell_title "${GETURI%% *}: $uri"
						${GETURI} "$target" "$url"
					fi

					# is it empty file?
					if [ ! -s "$target" ]; then
						rm -f "$target"
						if [ `echo $url_attic | grep -E '^(\.|/)'` ]; then
							update_shell_title "${GETLOCAL%% *}: $url_attic"
							${GETLOCAL} $url_attic $target
						else
							update_shell_title "${GETURI%% *}: $url_attic"
							${GETURI} "$target" "$url_attic"
							test -s "$target" || rm -f "$target"
						fi
					fi

					if [ -s "$target" ]; then
						cvsignore_df $target
					else
						rm -f "$target"
						FROM_DISTFILES=0
					fi
				fi

				if [ -z "$NOURLS" ] && [ ! -f "$fp" -o -n "$UPDATE" ] && [ "`echo $i | grep -E 'ftp://|http://|https://'`" ]; then
					if [ -z "$NOMIRRORS" ]; then
						im=$(find_mirror "$i")
					else
						im="$i"
					fi
					update_shell_title "${GETURI%% *}: $im"
					${GETURI} "$target" "$im"
					test -s "$target" || rm -f "$target"
				fi

				if [ "$cvsup" = 1 ]; then
					continue
				fi

			fi

			# the md5 check must be moved elsewhere as if we've called from update_md5 the md5 is wrong.
			if [ ! -f "$fp" -a "$FAIL_IF_NO_SOURCES" != "no" ]; then
				Exit_error err_no_source_in_repo $i
			fi

			# we check md5 here just only to refetch immediately
			if good_md5 "$i" && good_size "$i"; then
				:
			elif [ "$FROM_DISTFILES" = 1 ]; then
				# wrong md5 from distfiles: remove the file and try again
				# but only once ...
				echo "MD5 sum mismatch. Trying full fetch."
				FROM_DISTFILES=2
				rm -f $target
				update_shell_title "${GETURI%% *}: $url"
				${GETURI} "$target" "$url"
				if [ ! -s "$target" ]; then
					rm -f "$target"
					update_shell_title "${GETURI%% *}: $url_attic"
					${GETURI} "$target" "$url_attic"
				fi
				test -s "$target" || rm -f "$target"
			fi
		done
		SHELL_TITLE_PREFIX=""


		if [ "$CHMOD" = "yes" ]; then
			CHMOD_FILES=$(nourl "$@")
			if [ -n "$CHMOD_FILES" ]; then
				chmod $CHMOD_MODE $CHMOD_FILES
			fi
		fi
	fi
}

tag_exist() {
# If tag exists and points to other commit exit with error
# If it existsts and points to HEAD return 1
# If it doesn't exist return 0
	local _tag="$1"
	local sha1=$(git rev-parse HEAD)
	echo "Searching for tag $_tag..."
	if [ -n "$DEPTH" ]; then
		local ref=$(git ls-remote $REMOTE_PLD "refs/tags/$_tag"  | cut -c -40)
	else
		local ref=$(git show-ref -s "refs/tags/$_tag")
	fi
	[ -z "$ref" ] && return 0
	[ "$ref" = "$sha1" ] || Exit_error err_tag_exists "$_tag"
	return 1
}

make_tagver() {
	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	# Check whether first character of PACKAGE_NAME is legal for tag name
	if [ -z "${PACKAGE_NAME##[_0-9]*}" -a -z "$TAG_PREFIX" ]; then
		TAG_PREFIX=tag_
	fi

	# NOTE: CVS tags may must not contain the characters `$,.:;@'
	TAGVER=$(echo $TAG_PREFIX$PACKAGE_NAME-$PACKAGE_VERSION-$PACKAGE_RELEASE)

	# Remove @kernel.version_release from TAGVER because tagging sources
	# could occur with different kernel-headers than kernel-headers used at build time.
	# besides, %{_kernel_ver_str} is not expanded.

	# TAGVER=auto-ac-madwifi-ng-0-0_20070225_1@%{_kernel_ver_str}
	# TAGVER=auto-ac-madwifi-ng-0-0_20070225_1

	TAGVER=${TAGVER%@*}
	echo -n "$TAGVER"
}

tag_files() {
	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	echo "Version: $PACKAGE_VERSION"
	echo "Release: $PACKAGE_RELEASE"

	local _tag
	if [ "$TAG_VERSION" = "yes" ]; then
		_tag=`make_tagver`
	fi
	if [ -n "$TAG" ]; then
		_tag="$TAG"
	fi
	echo "tag: $_tag"

	local OPTIONS="tag $CVS_FORCE"

	cd "$PACKAGE_DIR"

	if tag_exist $_tag || [ -n "$CVS_FORCE" ]; then
		update_shell_title "tag sources: $_tag"
		git $OPTIONS $_tag || exit
		git push $IPOPT $CVS_FORCE $REMOTE_PLD tag $_tag || Exit_error err_remote_problem $REMOTE_PLD
	else
		echo "Tag $_tag already exists and points to the same commit"
	fi
}

branch_files() {
	TAG=$1
	echo "Git branch: $TAG"
	shift

	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	local OPTIONS="branch $CVS_FORCE"

	cd "$PACKAGE_DIR"
	git $OPTIONS $TAG || exit
}


# this function should exit early if package can't be built for this arch
# this avoids unneccessary BR filling.
check_buildarch() {
	local out ret
	out=$(minirpm --short-circuit -bp --define "'prep exit 0'" --nodeps $SPECFILE 2>&1)
	ret=$?
	if [ $ret -ne 0 ]; then
		echo >&2 "$out"
		exit $ret
	fi
}

# from relup.sh
set_release() {
	local specfile="$1"
	local rel="$2"
	local newrel="$3"
	sed -i -e "
		s/^\(%define[ \t]\+_\?rel[ \t]\+\)$rel\$/\1$newrel/
		s/^\(Release:[ \t]\+\)$rel\$/\1$newrel/
	" $specfile
}

set_version() {
	local specfile="$1"
	local ver="$2" subver=$ver
	local newver="$3" newsubver=$newver

	# try handling subver, everything that's not numeric-dotted in version
	if grep -Eq '%define\s+subver' $specfile; then
		subver=$(echo "$ver" | sed -re 's,^[0-9.]+,,')
		ver=${ver%$subver}
		newsubver=$(echo "$newver" | sed -re 's,^[0-9.]+,,')
		newver=${newver%$newsubver}
	fi
	sed -i -e "
		s/^\(%define[ \t]\+_\?ver[ \t]\+\)$ver\$/\1$newver/
		s/^\(%define[ \t]\+subver[ \t]\+\)$subver\$/\1$newsubver/
		s/^\(Version:[ \t]\+\)$ver\$/\1$newver/
	" $specfile
}

# try to upgrade .spec to new version
# if --upgrade-version is specified, use that as new version, otherwise invoke pldnotify to find new version
#
# return 1: if .spec was updated
# return 0: no changes to .spec
# exit 1 in case of error
try_upgrade() {
	if [ -z "$TRY_UPGRADE" ]; then
		return 0
	fi

	local TNOTIFY TNEWVER TOLDVER
	update_shell_title "build_package: try_upgrade"

	cd "$PACKAGE_DIR"

	if [ "$UPGRADE_VERSION" ]; then
		TNEWVER=$UPGRADE_VERSION
		echo "Updating spec file to version $TNEWVER"
	else
		if [ -n "$FLOAT_VERSION" ]; then
			TNOTIFY=$(pldnotify ${BE_VERBOSE:+-vDEBUG=1} $SPECFILE -n) || exit 1
		else
			TNOTIFY=$(pldnotify ${BE_VERBOSE:+-vDEBUG=1} $SPECFILE) || exit 1
		fi

		# pldnotify does not set exit codes, but it has match for ERROR
		# in output which means so.
		if [[ "$TNOTIFY" = *ERROR* ]]; then
			echo >&2 "$TNOTIFY"
			exit 1
		fi

		TOLDVER=`echo $TNOTIFY | awk '{ print $3; }'`
		echo "New version found, updating spec file from $TOLDVER to version $TNEWVER"

		TNEWVER=$(echo $TNOTIFY | awk '{ match($4,/\[NEW\]/); print $5 }')
	fi

	if [ -z "$TNEWVER" ]; then
		return 0
	fi

	if [ "$REVERT_BROKEN_UPGRADE" = "yes" ]; then
		cp -f $SPECFILE $SPECFILE.bak
	fi
	chmod +w $SPECFILE
	set_version $SPECFILE $PACKAGE_VERSION $TNEWVER
	set_release $SPECFILE $PACKAGE_RELEASE 1
	parse_spec
	if [ "$PACKAGE_VERSION" != "$TNEWVER" ]; then
		echo >&2 "Upgrading version failed, you need to update spec yourself"
		exit 1
	fi
	return 1
}

build_package() {
	update_shell_title "build_package"
	if [ -n "$DEBUG" ]; then
		set -x
		set -v
	fi

	cd "$PACKAGE_DIR"

	case "$COMMAND" in
		build )
			BUILD_SWITCH="-ba" ;;
		build-binary )
			BUILD_SWITCH="-bb" ;;
		build-source )
			BUILD_SWITCH="-bs --nodeps" ;;
		build-prep )
			BUILD_SWITCH="-bp --nodeps" ;;
		build-build )
			BUILD_SWITCH="-bc" ;;
		build-install )
			BUILD_SWITCH="-bi" ;;
		build-list )
			BUILD_SWITCH="-bl" ;;

	esac

	update_shell_title "build_package: $COMMAND"
	local logfile retval
	if [ -n "$LOGFILE" ]; then
		logfile=`eval echo $LOGFILE`
		if [ -d "$logfile" ]; then
			echo "Log file $logfile is a directory."
			echo "Parse error in the spec?"
			Exit_error err_build_fail
		fi
		if [ -n "$LASTLOG_FILE" ]; then
			echo "LASTLOG=$logfile" > $LASTLOG_FILE
		fi
	fi

	# unset these, should not be exposed to builder shell!
	unset GIT_WORK_TREE GIT_DIR
	# these are set by jenkins
	unset GIT_PREVIOUS_COMMIT GIT_URL GIT_PREVIOUS_SUCCESSFUL_COMMIT GIT_BRANCH GIT_COMMIT
	# this may be set by user
	unset GIT_SSH
	# may be set by user
	unset GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_TESTING_PORCELAIN_COMMAND_LIST GIT_EDITOR
	# fail if something still set
	env | grep -vE "^($(echo GIT_ENV_WHITELIST $GIT_ENV_WHITELIST | tr ' ' '|'))=" | grep ^GIT_ && Exit_error err_build_fail "One of GIT_* env variables is still set. The builder script needs to be updated to unset that variable. In the meantime, unset it manually."

	local specdir=$(insert_gitlog $SPECFILE)
	ulimit -c unlimited
	# FIXME: eval here is exactly why?
	PATH=$CLEAN_PATH eval teeboth "'$logfile'" ${TIME_COMMAND} ${NICE_COMMAND} ${NONETWORK} $RPMBUILD $TARGET_SWITCH $BUILD_SWITCH -v $QUIET $CLEAN $RPMOPTS $RPMBUILDOPTS $BCOND --define \'_specdir $PACKAGE_DIR\' --define \'_sourcedir $PACKAGE_DIR\' $specdir/$SPECFILE
	retval=$?
	rm -r $specdir

	if [ -n "$logfile" ] && [ -n "$LOGDIROK" ] && [ -n "$LOGDIRFAIL" ]; then
		if [ "$retval" -eq "0" ]; then
			mv $logfile $LOGDIROK
		else
			mv $logfile $LOGDIRFAIL
		fi
	fi

	if [ "$retval" -ne "0" ]; then
		if [ -n "$TRY_UPGRADE" ]; then
			echo "\nUpgrade package to new version failed."
			if [ "$REVERT_BROKEN_UPGRADE" = "yes" ]; then
				echo "Restoring old spec file."
				mv -f $SPECFILE.bak $SPECFILE
			fi
			echo ""
		fi
		Exit_error err_build_fail
	fi
	unset BUILD_SWITCH
}

nourl() {
	echo "$@" | sed 's#\<\(ftp\|http\|https\|cvs\|svn\)://[^ ]*/##g'
}

install_required_packages() {
	run_poldek -vi $1
	return $?
}

find_spec_bcond() { # originally from /usr/lib/rpm/find-spec-bcond
	local SPEC="$1"
	awk -F"\n" '
	/^%changelog/ { exit }
	/^%bcond_with/{
		match($0, /bcond_with(out)?[ \t]+[_a-zA-Z0-9]+/);
		bcond = substr($0, RSTART + 6, RLENGTH - 6);
		gsub(/[ \t]+/, "_", bcond);
		print bcond
	}' $SPEC | LC_ALL=C sort -u
}

process_bcondrc() {
	# expand bconds from ~/.bcondrc
	# The file structure is like gentoo's package.use:
	# ---
	# * -selinux
	# samba -mysql -pgsql
	# w32codec-installer license_agreement
	# php +mysqli
	# ---
	if [ -f $HOME/.bcondrc ] || ([ -n $HOME_ETC ] && [ -f $HOME_ETC/.bcondrc ]); then
		:
	else
		return
	fi

	SN=${SPECFILE%%\.spec}

	local bcondrc=$HOME/.bcondrc
	[ -n $HOME_ETC ] && [ -f $HOME_ETC/.bcondrc ] && bcondrc=$HOME_ETC/.bcondrc

	local bcond_avail=$(find_spec_bcond $SPECFILE)

	while read pkg flags; do
		# ignore comments
		[[ "$pkg" == \#* ]] && continue

		# any package or current package?
		if [ "$pkg" = "*" ] || [ "$pkg" = "$PACKAGE_NAME" ] || [ "$pkg" = "$SN" ]; then
			for flag in $flags; do
				local opt=${flag#[+-]}

				# use only flags which are in this package.
				if [[ $bcond_avail = *${opt}* ]]; then
					if [[ $flag = -* ]]; then
						if [[ $BCOND != *--with?${opt}* ]]; then
							BCOND="$BCOND --without $opt"
						fi
					else
						if [[ $BCOND != *--without?${opt}* ]]; then
							BCOND="$BCOND --with $opt"
						fi
					fi
				fi
			done
		fi
	done < $bcondrc
	update_shell_title "parse ~/.bcondrc: DONE!"
}

set_bconds_values() {
	update_shell_title "set bcond values"

	AVAIL_BCONDS_WITHOUT=""
	AVAIL_BCONDS_WITH=""

	if grep -Eq '^# *_with' ${SPECFILE}; then
		echo >&2 "ERROR: This spec has old style bconds."
		exit 1
	fi

	if ! grep -q '^%bcond' ${SPECFILE}; then
		return
	fi

	local bcond_avail=$(find_spec_bcond $SPECFILE)
	process_bcondrc "$SPECFILE"

	update_shell_title "parse bconds"

	local opt bcond
	for opt in $bcond_avail; do
		case "$opt" in
		without_*)
			bcond=${opt#without_}
			case "$BCOND" in
			*--without?${bcond}\ *|*--without?${bcond})
				AVAIL_BCONDS_WITHOUT="$AVAIL_BCONDS_WITHOUT <$bcond>"
				;;
			*)
				AVAIL_BCONDS_WITHOUT="$AVAIL_BCONDS_WITHOUT $bcond"
				;;
			esac
			;;
		with_*)
			bcond=${opt#with_}
			case "$BCOND" in
			*--with?${bcond}\ *|*--with?${bcond})
				AVAIL_BCONDS_WITH="$AVAIL_BCONDS_WITH <$bcond>"
				;;
			*)
				AVAIL_BCONDS_WITH="$AVAIL_BCONDS_WITH $bcond"
				;;
			esac
			;;
		*)
			echo >&2 "ERROR: unexpected '$opt' in set_bconds_values"
			exit 1
			;;
		esac
	done
}

run_sub_builder() {
	package_name="${1}"
	update_shell_title "run_sub_builder $package_name"
	#
	# No i tutaj bym chciał zrobić sztuczną inteligencję, która spróbuje tego
	# pakieta zbudować. Aktualnie niewiele dziala, bo generalnie nie widze do
	# konca algorytmu... Ale damy rade. :) Na razie po prostu sie wyjebie tak samo
	# jakby nie bylo tego kawalka kodu.
	#
	# Update: Poprawiłem parę rzeczy i zaczęło generować pakiety spoza zadanej listy.
	#         Jednym słowem budowanie niespoldkowanych zależności działa w paru przypadkach.
	#
	#
	# y0shi.
	# kurwa. translate that ^^^^

	parent_spec_name=''

	# Istnieje taki spec? ${package}.spec
	if [ -f "${PACKAGE_DIR}/${package}.spec" ]; then
		parent_spec_name=${package}.spec
	elif [ -f "${PACKAGE_DIR}/$(echo ${package_name} | sed -e s,-devel.*,,g -e s,-static,,g).spec" ]; then
		parent_spec_name="$(echo ${package_name} | sed -e s,-devel.*,,g -e s,-static,,g).spec"
	else
		for provides_line in $(grep -r ^Provides:.*$package ${PACKAGE_DIR}); do
			echo $provides_line
		done
	fi

	if [ "${parent_spec_name}" != "" ]; then
		spawn_sub_builder $parent_spec_name
	fi
	NOT_INSTALLED_PACKAGES="$NOT_INSTALLED_PACKAGES $package_name"
}

# install package with poldek
# @return exit code from poldek
#
# this requires following sudo rules:
# - poldek --noask --caplookup -ug
poldek_install() {
	LC_ALL=C LANG=C $POLDEK_CMD --noask --caplookup --uniq -ug "$@"
}

# install packages
#
# this requires following sudo rules:
# - poldek -q --update --upa
install_packages() {
	# sync poldek indexes once per invocation
	if [ -z "$package_indexes_updated" ]; then
		update_shell_title "poldek: update indexes"
		$POLDEK_CMD -q --update --upa --mo=nodesc
		package_indexes_updated=true
	fi

	update_shell_title "install packages: $*"
	poldek_install "$@" && return

	# retry install, install packages one by one
	# this is slower one
	local rc=0 package
	for package in $*; do
		package=$(depspecname $package)
		update_shell_title "install package: $package"
		poldek_install "$package" || rc=$?
	done
	return $rc
}

uninstall_packages() {
	update_shell_title "uninstall packages: $*"
	$POLDEK_CMD --noask --nofollow -ev "$@"
}

spawn_sub_builder() {
	package_name="${1}"
	update_shell_title "spawn_sub_builder $package_name"

	sub_builder_opts=''
	if [ "${FETCH_BUILD_REQUIRES}" = "yes" ]; then
		sub_builder_opts="${sub_builder_opts} -R"
	fi
	if [ "${REMOVE_BUILD_REQUIRES}" = "nice" ]; then
		sub_builder_opts="${sub_builder_opts} -RB"
	elif [ "${REMOVE_BUILD_REQUIRES}" = "force" ]; then
		sub_builder_opts="${sub_builder_opts} -FRB"
	fi
	if [ "${UPDATE_POLDEK_INDEXES}" = "yes" ]; then
		sub_builder_opts="${sub_builder_opts} -Upi"
	fi

	cd "${PACKAGE_DIR}"
	./builder ${sub_builder_opts} "$@"
}

remove_build_requires() {
	if [ "$INSTALLED_PACKAGES" != "" ]; then
		case "$REMOVE_BUILD_REQUIRES" in
			"force")
				run_poldek --noask -ve $INSTALLED_PACKAGES
				;;
			"nice")
				run_poldek --ask -ve $INSTALLED_PACKAGES
				;;
			*)
				echo You may want to manually remove following BuildRequires fetched:
				echo $INSTALLED_PACKAGES
				echo "Try poldek -e \`cat $(pwd)/.${SPECFILE}_INSTALLED_PACKAGES\`"
				;;
		esac
	fi
}

display_bconds() {
	if [ "$AVAIL_BCONDS_WITH" -o "$AVAIL_BCONDS_WITHOUT" ]; then
		if [ "$BCOND" ]; then
			echo ""
			echo "Building $SPECFILE with the following conditional flags:"
			echo -n "$BCOND"
		else
			echo ""
			echo "No conditional flags passed"
		fi
		echo ""
		echo "from available:"
		echo "--with   :\t$AVAIL_BCONDS_WITH"
		echo "--without:\t$AVAIL_BCONDS_WITHOUT"
		echo ""
	fi
}

display_branches() {
	echo -n "Available branches: "
	git branch -r 2>/dev/null | grep "^  ${REMOTE_PLD}" | grep -v ${REMOTE_PLD}/HEAD | sed "s#^ *${REMOTE_PLD}/##" | xargs
}

# checks a given list of packages/files/provides against current rpmdb.
# outputs all dependencies which current rpmdb doesn't satisfy.
# input can be either STDIN or parameters
_rpm_prov_check() {
	local deps out

	if [ $# -gt 0 ]; then
		deps="$@"
	else
		deps=$(cat)
	fi

	out=$(LC_ALL=C rpm -q --whatprovides $deps 2>&1)

	# packages
	echo "$out" | awk '/^no package provides/ { print $NF }'

	# other deps (files)
	echo "$out" | sed -rne 's/file (.*): No such file or directory/\1/p'
}

# checks if given package/files/provides exists in rpmdb.
# input can be either stdin or parameters
# returns packages which are present in the rpmdb
_rpm_cnfl_check() {
	local DEPS

	if [ $# -gt 0 ]; then
		DEPS="$@"
	else
		DEPS=$(cat)
	fi

	LC_ALL=C LANG=C rpm -q --whatprovides $DEPS 2>/dev/null | awk '!/no package provides/ { print }'
}

# install deps via information from 'rpm-getdeps' or 'rpm --specsrpm'
install_build_requires_rpmdeps() {
	local DEPS CNFL
	if [ "$FETCH_BUILD_REQUIRES_RPMGETDEPS" = "yes" ]; then
		# TODO: Conflicts list doesn't check versions
		CNFL=$(eval rpm-getdeps $BCOND $RPMOPTS $SPECFILE 2> /dev/null | awk '/^\-/ { print $3 } ' | _rpm_cnfl_check | xargs)
		DEPS=$(eval rpm-getdeps $BCOND $RPMOPTS $SPECFILE 2> /dev/null | awk '/^\+/ { print $3 } ' | _rpm_prov_check | xargs)
	fi
	if [ "$FETCH_BUILD_REQUIRES_RPMSPEC_BINARY" = "yes" ]; then
		CNFL=$(eval rpmspec --query --buildconflicts     $BCOND $RPMOPTS $SPECFILE 2> /dev/null | awk '{print $1}' | _rpm_cnfl_check | xargs);
		DEPS=$(eval rpmspec --query --buildrequires $BCOND $RPMOPTS $SPECFILE 2> /dev/null | awk '{print $1}' | _rpm_prov_check | xargs);
	fi
	if [ "$FETCH_BUILD_REQUIRES_RPMSPECSRPM" = "yes" ]; then
		CNFL=$(eval rpm -q --specsrpm --conflicts $BCOND $RPMOPTS $SPECFILE | awk '{print $1}' | _rpm_cnfl_check | xargs)
		DEPS=$(eval rpm -q --specsrpm --requires $BCOND $RPMOPTS $SPECFILE | awk '{print $1}' | _rpm_prov_check | xargs)
	fi

	if [ -n "$CNFL" ]; then
		echo "Uninstall conflicting packages: $CNFL"
		uninstall_packages $CNFL
	fi

	if [ -n "$DEPS" ]; then
		echo "Install dependencies: $DEPS"
		install_packages $DEPS
	fi
}

fetch_build_requires()
{
	if [ "${FETCH_BUILD_REQUIRES}" != "yes" ]; then
		return
	fi

	update_shell_title "fetch build requires"
	if [ "$FETCH_BUILD_REQUIRES_RPMGETDEPS" = "yes" ] || [ "$FETCH_BUILD_REQUIRES_RPMSPECSRPM" = "yes" ] || [ "$FETCH_BUILD_REQUIRES_RPMSPEC_BINARY" = "yes" ]; then
		install_build_requires_rpmdeps
		return
	fi

	die "need rpm-getdeps tool"
}

init_repository() {
	local remoterepo=$1
	local localrepo=$2

	if [ ! -e $localrepo ]; then
		git clone $IPOPT -o $REMOTE_PLD ${GIT_SERVER}/$remoterepo $localrepo
		git --git-dir=$localrepo/.git remote set-url --push  $REMOTE_PLD ssh://${GIT_PUSH}/$remoterepo
	fi
}

init_rpm_dir() {
	local TOP_DIR=$(eval $RPM $RPMOPTS --eval '%{_topdir}')
	local rpmdir=$(eval $RPM $RPMOPTS --eval '%{_rpmdir}')
	local buildir=$(eval $RPM $RPMOPTS --eval '%{_builddir}')
	local srpmdir=$(eval $RPM $RPMOPTS --eval '%{_srcrpmdir}')
	local TEMPLATES=template-specs
	local tmp

	echo "Initializing rpm directories to $TOP_DIR from $GIT_SERVER"
	mkdir -p $TOP_DIR $rpmdir $buildir $srpmdir

	cd "$TOP_DIR"
	init_repository ${PACKAGES_DIR}/rpm-build-tools.git ../rpm-build-tools
	init_repository projects/$TEMPLATES ../$TEMPLATES
	for a in builder fetchsrc_request compile repackage; do
		ln -sf ../rpm-build-tools/${a}.sh $a
	done
	for a in md5; do
		ln -sf ../rpm-build-tools/${a} $a
	done
	ln -sf ../rpm-build-tools/mirrors mirrors
	init_builder
}

mr_proper() {
	init_builder
	NOCVSSPEC="yes"
	DONT_PRINT_REVISION="yes"

	# remove spec and sources
	PATH=$CLEAN_PATH $RPMBUILD --clean --rmsource --rmspec --nodeps --define "__urlgetfile() %nil" --define "_specdir $PACKAGE_DIR" --define "_sourcedir $PACKAGE_DIR" --define "_builddir $builddir" $PACKAGE_DIR/$SPECFILE
	rm -rf $PACKAGE_DIR/{.git,.gitignore}
	rmdir --ignore-fail-on-non-empty $PACKAGE_DIR
}

#---------------------------------------------
# main()

if [ $# = 0 ]; then
	usage
	exit 1
fi

# stuff global $BUILDER_OPTS from env as args
if [ "$BUILDER_OPTS" ]; then
	set -- "$BUILDER_OPTS" "$@"
fi

while [ $# -gt 0 ]; do
	case "${1}" in
		-4|-6)
			IPOPT="${1}"
			shift
			;;
		-5 | --update-md5)
			COMMAND="update_md5"
			NODIST="yes"
			NOCVSSPEC="yes"
			shift ;;
		-a5 | --add-md5 )
			COMMAND="update_md5"
			NODIST="yes"
			NOCVSSPEC="yes"
			ADD5="yes"
			shift ;;
		-n5 | --no-md5 )
			NO5="yes"
			shift ;;
		-D | --debug )
			DEBUG="yes"; shift ;;
		-V | --version )
			COMMAND="version"; shift ;;
		--short-version )
			COMMAND="short-version"; shift ;;
		-a | --add_cvs)
			COMMAND="add_cvs";
			shift ;;
		--all-branches )
			ALL_BRANCHES="yes"
			shift ;;
		-b | -ba | --build )
			COMMAND="build"; shift ;;
		-bb | --build-binary )
			COMMAND="build-binary"; shift ;;
		-bc )
			COMMAND="build-build"; shift ;;
		-bi )
			COMMAND="build-install"; shift ;;
		-bl )
			COMMAND="build-list"; shift ;;
		-bp | --build-prep )
			COMMAND="build-prep"; shift ;;
		-bs | --build-source )
			COMMAND="build-source"; shift ;;
		-B | --branch )
			COMMAND="branch"; shift; TAG="${1}"; shift;;
		-c | --clean )
			CLEAN="--clean"; shift ;;
		-cf | --cvs-force )
			CVS_FORCE="-f"; shift;;
		--depth )
			DEPTH="--depth=$2"
			shift 2
			;;
		-g | --get )
			COMMAND="get"; shift ;;
		-gs | --get-spec )
			COMMAND="get_spec"; shift ;;
		-h | --help )
			COMMAND="usage"; shift ;;
		--ftp )
			PROTOCOL="ftp"; shift ;;
		--http )
			PROTOCOL="http"; shift ;;
		-j)
			RPMOPTS="${RPMOPTS} --define \"__jobs $2\""
			shift 2
			;;
		-j[0-9]*)
			RPMOPTS="${RPMOPTS} --define \"__jobs ${1#-j}\""
			shift
			;;
		-p)
			PARALLEL_DOWNLOADS=$2
			shift 2
			;;
		-p[0-9])
			PARALLEL_DOWNLOADS=${1#-p}
			shift
			;;
		-l | --logtofile )
			shift; LOGFILE="${1}"; shift ;;
		-ni| --nice )
			shift; DEF_NICE_LEVEL=${1}; shift ;;
		-ske | --skip-existing-files)
			SKIP_EXISTING_FILES="yes"; shift ;;
		-m | --mr-proper )
			COMMAND="mr-proper"; shift ;;
		-ncs | --no-cvs-specs )
			NOCVSSPEC="yes"; shift ;;
		-nd | --no-distfiles )
			NODIST="yes"; shift ;;
		-nm | --no-mirrors )
			NOMIRRORS="yes"; shift ;;
		-nu | --no-urls )
			NOURLS="yes"; shift ;;
		-ns | --no-srcs )
			NOSRCS="yes"; shift ;;
		-ns0 | --no-source0 )
			NOSOURCE0="yes"; shift ;;
		-nn | --no-net )
			NOCVSSPEC="yes"
			NODIST="yes"
			NOMIRRORS="yes"
			NOURLS="yes"
			NOSRCS="yes"
			ALWAYS_CVSUP="no"
			shift;;
		--bnet )
			NONETWORK="";
			shift;;
		-pm | --prefer-mirrors )
			PREFMIRRORS="yes"
			shift;;
		--noinit | --no-init )
			NOINIT="yes"
			shift;;
		--opts )
			shift; RPMOPTS="${RPMOPTS} ${1}"; shift ;;
		--nopatch | -np )
			shift; RPMOPTS="${RPMOPTS} --define \"patch${1} : ignoring patch${1}; exit 1; \""; shift ;;
		--skip-patch | -sp )
			shift; RPMOPTS="${RPMOPTS} --define \"patch${1} : skiping patch${1}\""; shift ;;
		--topdir)
			RPMOPTS="${RPMOPTS} --define \"_topdir $2\""
			shift 2
			;;
		--with | --without )
			case $GROUP_BCONDS in
				"yes")
					COND=${1}
					shift
					# XXX: broken: ./builder -bb ucspi-tcp.spec --without mysql
					while ! `echo ${1}|grep -qE '(^-|spec)'`
					do
						BCOND="$BCOND $COND $1"
						shift
					done;;
				"no")
					if [[ "$2" = *,* ]]; then
						for a in $(echo "$2" | tr , ' '); do
							BCOND="$BCOND $1 $a"
						done
					else
						BCOND="$BCOND $1 $2"
					fi
					shift 2 ;;
			esac
			;;
		--target )
			shift; TARGET="${1}"; shift ;;
		--target=* )
			TARGET=$(echo "${1}" | sed 's/^--target=//'); shift ;;
		-q | --quiet )
			QUIET="--quiet"; shift ;;
		--date )
			CVSDATE="${2}"; shift 2
			date -d "$CVSDATE" > /dev/null 2>&1 || { echo >&2 "No valid date specified"; exit 3; }
			;;
		-r | --cvstag )
			CVSTAG="$2"
		   	shift 2
		   	;;
		-A)
			shift
			CVSTAG="master"
		   	;;
		-R | --fetch-build-requires)
			FETCH_BUILD_REQUIRES="yes"
			NOT_INSTALLED_PACKAGES=
			shift ;;
		-RB | --remove-build-requires)
			REMOVE_BUILD_REQUIRES="nice"
			shift ;;
		-FRB | --force-remove-build-requires)
			REMOVE_BUILD_REQUIRES="force"
			shift ;;
		-sc | --source-cvs)
			COMMAND="list-sources-cvs"
			shift ;;
		-sd | --source-distfiles)
			COMMAND="list-sources-distfiles"
			shift ;;
		-sdp | --source-distfiles-paths)
			COMMAND="list-sources-distfiles-paths"
			shift ;;
		-sf | --source-files)
			COMMAND="list-sources-files"
			shift ;;
		-lsp | --source-paths)
			COMMAND="list-sources-local-paths"
			shift ;;
		-su | --source-urls)
			COMMAND="list-sources-urls"
			shift ;;
		-Tvs | --tag-version-stable )
			COMMAND="tag"
			TAG="STABLE"
			TAG_VERSION="yes"
			shift;;
		-Ts | --tag-stable )
			COMMAND="tag"
			TAG="STABLE"
			TAG_VERSION="no"
			shift;;
		-Tv | --tag-version )
			COMMAND="tag"
			TAG=""
			TAG_VERSION="yes"
			shift;;
		-Tp | --tag-prefix )
			TAG_PREFIX="$2"
			shift 2;;
		-tt | --test-tag )
			TEST_TAG="yes"
			shift;;
		-T | --tag )
			COMMAND="tag"
			shift
			TAG="$1"
			TAG_VERSION="no"
			shift;;
		-ir | --integer-release-only )
			INTEGER_RELEASE="yes"
			shift;;
		-U | --update )
			COMMAND="update_md5"
			UPDATE="yes"
			NOCVSSPEC="yes"
			NODIST="yes"
			shift ;;
		-Upi | --update-poldek-indexes )
			UPDATE_POLDEK_INDEXES="yes"
			shift ;;
		--init-rpm-dir|--init)
			COMMAND="init_rpm_dir"
			shift ;;
		-u | --try-upgrade )
			TRY_UPGRADE="1"; shift ;;
		--upgrade-version )
			shift; UPGRADE_VERSION="$1"; shift;;
		-un | --try-upgrade-with-float-version )
			TRY_UPGRADE="1"; FLOAT_VERSION="1"; shift ;;
		-v | --verbose )
			BE_VERBOSE="1"; shift ;;
		--define)
			shift
			MACRO="${1}"
			shift
			if echo "${MACRO}" | grep -q '\W'; then
				RPMOPTS="${RPMOPTS} --define \"${MACRO}\""
			else
				VALUE="${1}"
				shift
				RPMOPTS="${RPMOPTS} --define \"${MACRO} ${VALUE}\""
			fi
			;;
		--alt_kernel)
			shift
			RPMOPTS="${RPMOPTS} --define \"alt_kernel $1\" --define \"build_kernels $1\""
			shift
			;;
		--short-circuit)
			RPMBUILDOPTS="${RPMBUILDOPTS} --short-circuit"
			shift
			;;
		--show-bconds | -show-bconds | -print-bconds | --print-bconds | -display-bconds | --display-bconds )
			COMMAND="show_bconds"
			shift
			;;
		--show-bcond-args)
			COMMAND="show_bcond_args"
			shift
			;;
		--show-avail-bconds)
			COMMAND="show_avail_bconds"
			shift
			;;
		--nodeps)
			shift
			RPMOPTS="${RPMOPTS} --nodeps"
			;;
		--noclean)
			shift
			RPMBUILDOPTS="${RPMBUILDOPTS} --noclean"
			;;
		-debug)
			RPMBUILDOPTS="${RPMBUILDOPTS} -debug"; shift
			;;
		-*)
			Exit_error err_invalid_cmdline "$1"
			;;
		*)
			SPECFILE=${1%/}; shift
			# check if specname was passed as specname:cvstag
			if [ "${SPECFILE##*:}" != "${SPECFILE}" ]; then
				CVSTAG="${SPECFILE##*:}"
				SPECFILE="${SPECFILE%%:*}"
			fi
			# always have SPECFILE ending with .spec extension
			SPECFILE=${SPECFILE%%.spec}.spec
			ASSUMED_NAME=$(basename ${SPECFILE%%.spec})
	esac
done

if [ "$CVSTAG" ]; then
	# pass $CVSTAG used by builder to rpmbuild too, so specs could use it
	RPMOPTS="$RPMOPTS --define \"_cvstag $CVSTAG\""
fi

if [ -n "$ALL_BRANCHES" -a -z "$DEPTH" ]; then
	echo >&2 "--all branches requires --depth <number>"
	Exit_error err_invalid_cmdline
fi

if [ -n "$DEBUG" ]; then
	set -x
	set -v
fi

if [ -n "$TARGET" ]; then
	case "$RPMBUILD" in
		"rpmbuild")
			TARGET_SWITCH="--target $TARGET" ;;
		"rpm")
			TARGET_SWITCH="--target=$TARGET" ;;
	esac
fi

if [ "$SCHEDTOOL" != "no" ]; then
	NICE_COMMAND="$SCHEDTOOL"
else
	NICE_COMMAND="nice -n ${DEF_NICE_LEVEL}"
fi

# see time(1) for output format that could be used
TIME_COMMAND="time -p"

update_shell_title "$COMMAND"
case "$COMMAND" in
	"show_bconds")
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi
		get_spec > /dev/null
		parse_spec
		set_bconds_values
		display_bconds
		;;
	"show_bcond_args")
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi
		get_spec > /dev/null
		parse_spec
		set_bconds_values
		echo "$BCOND"
		;;
	"show_avail_bconds")
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi

		get_spec > /dev/null
		parse_spec
		local bcond_avail=$(find_spec_bcond $SPECFILE)
		local opt bcond bconds
		for opt in $bcond_avail; do
			case "$opt" in
			without_*)
				bcond=${opt#without_}
				bconds="$bconds $bcond"
				;;
			with_*)
				bcond=${opt#with_}
				bconds="$bconds $bcond"
				;;
			*)
				echo >&2 "ERROR: unexpected '$opt' in show_avail_bconds"
				exit 1
				;;
			esac
		done
		echo $bconds

		;;
	"build" | "build-binary" | "build-source" | "build-prep" | "build-build" | "build-install" | "build-list")
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi

		# display SMP make flags if set
		smp_mflags=$(rpm -E %{?_smp_mflags})
		if [ "$smp_mflags" ]; then
			echo "builder: SMP make flags are set to $smp_mflags"
		fi

		get_spec
		parse_spec
		set_bconds_values
		display_bconds
		display_branches
		if [ "$COMMAND" != "build-source" ]; then
			check_buildarch
		fi
		fetch_build_requires
		if [ "$INTEGER_RELEASE" = "yes" ]; then
			echo "Checking release $PACKAGE_RELEASE..."
			if echo $PACKAGE_RELEASE | grep -q '^[^.]*\.[^.]*$' 2>/dev/null ; then
				Exit_error err_fract_rel "$PACKAGE_RELEASE"
			fi
		fi

		# ./builder -bs test.spec -r AC-branch -Tp auto-ac- -tt
		if [ -n "$TEST_TAG" ]; then
			local TAGVER=`make_tagver`
			tag_exist $TAGVER || [ $TAGVER = $CVSTAG ] || Exit_error err_tag_exists $TAGVER
			# check also tags created in CVS
			local TAGVER_CVS=$(echo $TAGVER | tr '[.@]' '[_#]')
			local CVSTAG_CVS=$(echo $CVSTAG | tr '[.@]' '[_#]')
			tag_exist $TAGVER_CVS || [ $TAGVER_CVS = $CVSTAG_CVS ] \
				|| Exit_error err_tag_exists $TAGVER_CVS
			# - do not allow to build from HEAD when XX-branch exists
			TREE_PREFIX=$(echo "$TAG_PREFIX" | sed -e 's#^auto/\([a-zA-Z]\+\)/.*#\1#g')
			if [ "$TAGVER" != "$CVSTAG" -a "$TAGVER_CVS" != "$CVSTAG" -a  "$TREE_PREFIX" != "$TAG_PREFIX" ]; then
				TAG_BRANCH="${TREE_PREFIX}-branch"
				if [ -n "$DEPTH" ]; then
					cmd_branches="git ls-remote --heads"
					ref_prefix=refs/heads
				else
					cmd_branches="git show-ref"
					ref_prefix=refs/remotes/${REMOTE_PLD}
				fi
				TAG_STATUS=$($cmd_branches | grep -i "${ref_prefix}/$TAG_BRANCH$" | cut -c'-40')
				if [ -n "$TAG_STATUS" -a "$TAG_STATUS" != $(git rev-parse "$CVSTAG") ]; then
					Exit_error err_branch_exists "$TAG_STATUS"
				fi
			fi

		fi

		if [ -n "$NOSOURCE0" ] ; then
			SOURCES=`echo $SOURCES | xargs | sed -e 's/[^ ]*//'`
		fi
		try_upgrade
		case $? in
			0)
				get_files $SOURCES $PATCHES
				check_md5 $SOURCES $PATCHES
				;;
			*)
				NODIST="yes" get_files $SOURCES $PATCHES
				update_md5 $SOURCES $PATCHES
				;;
		esac
		build_package
		if [ "$UPDATE_POLDEK_INDEXES" = "yes" ] && [ "$COMMAND" = "build" -o "$COMMAND" = "build-binary" ]; then
			run_poldek --sdir="${POLDEK_INDEX_DIR}" ${UPDATE_POLDEK_INDEXES_OPTS} --mkidxz
		fi
		remove_build_requires
		;;
	"branch" )
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi

		get_spec
		parse_spec
		branch_files $TAG
		;;
	"add_cvs" )
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi

		create_git_repo
		if [ -n "$NEW_REPO" ]; then
			parse_spec
			local file
			for file in $SOURCES $PATCHES; do
				if [ -z $(src_md5 "$file") ]; then
					git add $file || Exit_error err_no_source_in_repo $file
				else
					cvsignore_df `nourl $file`
				fi
			done
			git add $SPECFILE
			echo "When you are ready commit your changes and run git push origin master"
		else
			echo "You had already git repository. Push chosen branches to remote: ${REMOTE_PLD}"
		fi
		;;
	"get" )
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi

		get_spec
		parse_spec

		if [ -n "$NOSOURCE0" ] ; then
			SOURCES=`echo $SOURCES | xargs | sed -e 's/[^ ]*//'`
		fi
		get_files $SOURCES $PATCHES
		check_md5 $SOURCES
		fetch_build_requires
		;;
	"get_spec" )
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi

		get_spec
		;;
	"update_md5" )
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi

		get_spec
		parse_spec

		if [ -n "$NOSOURCE0" ] ; then
			SOURCES=`echo $SOURCES | xargs | sed -e 's/[^ ]*//'`
		fi
		update_md5 $SOURCES $PATCHES
		;;
	"tag" )
		NOURLS=1
		NODIST="yes"
		init_builder
		if [ -z "$SPECFILE" ]; then
			Exit_error err_no_spec_in_cmdl
		fi

		parse_spec
		if  [ ! -d .git ]; then
			echo "No git reposiotory" >&2
			exit 101
		fi
		tag_files
		;;
	"mr-proper" )
		mr_proper
		;;
	"list-sources-files" )
		init_builder
		NOCVSSPEC="yes"
		DONT_PRINT_REVISION="yes"
		get_spec
		parse_spec
		for SAP in $SOURCES $PATCHES; do
			echo $SAP | awk '{gsub(/.*\//,"") ; print}'
		done
		;;
	"list-sources-urls" )
		init_builder >&2
		NOCVSSPEC="yes"
		DONT_PRINT_REVISION="yes"
		get_spec >&2
		parse_spec >&2
		SAPS="$SOURCES $PATCHES"
		for SAP in $SAPS; do
			echo $SAP
		done
		;;
	"list-sources-local-paths" )
		init_builder
		NOCVSSPEC="yes"
		DONT_PRINT_REVISION="yes"
		get_spec
		parse_spec
		for SAP in $SOURCES $PATCHES; do
			echo $PACKAGE_DIR/$(echo $SAP | awk '{gsub(/.*\//,"") ; print }')
		done
		;;
	"list-sources-distfiles-paths" )
		init_builder
		NOCVSSPEC="yes"
		DONT_PRINT_REVISION="yes"
		get_spec
		parse_spec
		for SAP in $SOURCES $PATCHES; do
			if [ -n "$(src_md5 "$SAP")" ]; then
				distfiles_path "$SAP"
			fi
		done
		;;
	"list-sources-distfiles" )
		init_builder
		NOCVSSPEC="yes"
		DONT_PRINT_REVISION="yes"
		get_spec
		parse_spec
		for SAP in $SOURCES $PATCHES; do
			if [ -n "$(src_md5 "$SAP")" ]; then
				distfiles_url "$SAP"
			fi
		done
		;;
	"list-sources-cvs" )
		init_builder
#		NOCVSSPEC="yes"
		DONT_PRINT_REVISION="yes"
		get_spec
		parse_spec
		for SAP in $SOURCES $PATCHES; do
			if [ -z "$(src_md5 "$SAP")" ]; then
				echo $SAP | awk '{gsub(/.*\//,"") ; print}'
			fi
		done
		;;
	"init_rpm_dir")
		init_rpm_dir
		;;
	"usage" )
		usage
		;;
	"short-version" )
		echo "$VERSION"
		;;
	"version" )
		echo "$VERSIONSTRING"
		;;
esac
if [ -f "`pwd`/.${SPECFILE}_INSTALLED_PACKAGES" -a "$REMOVE_BUILD_REQUIRES" != "" ]; then
	rm "`pwd`/.${SPECFILE}_INSTALLED_PACKAGES"
fi

# vi:syntax=sh:ts=4:sw=4:noet
