# shell aliases and functions for PLD Developer

# set $dist, used by functions below
[ -n "$dist" ] || dist=$(awk '/PLD Linux/ {print tolower($NF)}' /etc/pld-release 2>/dev/null | tr -d '()')

case "$dist" in
ac|th|ti)
	;;
*)
	# invalid one ;)
	dist=
esac

if [ "$dist" ]; then

alias ipoldek-$dist="poldek -q --sn $dist --cmd"
alias $dist-provides="ipoldek-$dist what-provides"
alias $dist-verify=dist-verify
alias $dist-requires=dist-requires

# move AC-branch tag to current checkout
# if AC-branch as branch exists, it is first removed
ac-tag() {
	# see if remote has branch present
	local branch=AC-branch
	if git show-ref -q refs/remotes/origin/$branch; then
		git fetch --tags
		if [ -z "$(git tag --points-at origin/$branch 2>/dev/null)" ]; then
			echo >&2 "There's no tag pointing to current $branch; refusing to delete branch"
			return 1
		fi
		# delete local branch if exists
		git show-ref -q refs/heads/$branch && git branch -d $branch

		# drop remote branch
		git push --delete origin $branch
	fi

	git tag -f $branch
	git push -f origin $branch
}

alias q='rpm -q --qf "%{N}-%|E?{%{E}:}|%{V}-%{R}.%{ARCH}\n"'

# undo spec utf8
# note: it will do it blindly, so any lang other than -pl is most likely broken
specutfundo() {
	local spec="$1"
	iconv -futf8 -tlatin2 "$spec" > m
	sed -e 's/\.UTF-8//' m > "$spec"
	rm -f m
}

dist-requires() {
	local opts deps
	while [ $# -gt 0 ]; do
		case "$1" in
		--sn)
			opts="$opts $1 $2"
			shift
			;;
		-*)
			opts="$opts $1"
			;;
		*)
			deps="$deps $1"
			;;
		esac
		shift
	done

	case "$dist" in
	ac)
		opts="$opts --sn=$dist-updates"
		;;
	esac

	poldek -q -Q --sn $dist $opts --cmd what-requires $deps
}

dist-verify() {
	local args sn
	sn="--sn $dist"

	case "$dist" in
	ac)
		sn="$sn --sn $dist-updates"

		local a ignore
		# typo
		ignore="$ignore kdenetwork-kopete-tool-conectionstatus"
		# obsoleted
		ignore="$ignore gimp-plugin-swfdec wine-drv-arts ntp-ntptrace"
		# quake2@MAIN is now quake2forge, original quake2 restored to quake2
		ignore="$ignore quake2-3dfx quake2-sdl quake2-sgl quake2-snd-alsa quake2-snd-ao quake2-snd-oss quake2-snd-sdl quake2-static"
		# obsoleted
		ignore="$ignore mozilla-firefox-lang-en apache1-mod_perl-devel libyasm-static"
		# renamed (courier-authlib.spec, r1.54)
		ignore="$ignore courier-authlib-userdb courier-authlib-pipe"
		# obsoleted, squid 2.6
		ignore="$ignore squid-winbind_acl squid-winbind_auth"
		# obsoleted with 1.0.4
		ignore="$ignore python-numpy-FFT python-numpy-MA python-numpy-RNG"
		# subpkgs renamed
		ignore="$ignore apache1-doc apache1-index"
		# obsoleted by kadu-module-mediaplayer-amarok
		ignore="$ignore kadu-module-amarok"
		# obsoleted by kadu-module-mediaplayer-xmms
		ignore="$ignore kadu-module-xmms"
		# obsoleted by kadu 0.6.0
		ignore="$ignore kadu-theme-icons-crystal16 kadu-theme-icons-crystal22 kadu-theme-icons-nuvola16 kadu-theme-icons-nuvola22 kadu-module-iwait4u"
		# obsoleted pear test packages
		ignore="$ignore php-*-tests"
		# obsoleted
		ignore="$ignore nmap-X11"
		# mksd dependency not distributale
		ignore="$ignore samba-vfs-vscan-mks"
		# ibbackup is not distributale
		ignore="$ignore innobackup"
		# use ac-updates
		ignore="$ignore ntp-client ntp"
		# php4 only(php-pecl-tidy), for php<5.2(php-pecl-filter)
		ignore="$ignore php-pecl-tidy php-pecl-filter"

		# renamed to vim-syntax-txt2tags
		ignore="$ignore txt2tags-vim"

		for a in $ignore; do
			args="$args --ignore=$a"
		done
		;;
	esac

	poldek $sn --up --upa -q "$@"
	poldek $sn --uniq --noignore --verify=deps $args "$@"
}

# displays latest used tag for a specfile
autotag() {
	local out s
	for s in "$@"; do
		# strip branches
		s=${s%:*}
		# ensure package ends with .spec
		s=${s%.spec}.spec
		git fetch --tags
		out=$(git for-each-ref --count=1 --sort=-authordate refs/tags/auto/$dist \
			--format='%(refname:short)')
		echo "$s:$out"
	done
}

get-buildlog() {
	local p=$1
	if [ -z "$p" ]; then
		echo >&2 "Usage: get-buildlog PACKAGE"
		echo >&2 ""
		echo >&2 "Grabs buildlogs from pld builder for all arch."
		return
	fi

	local archlist
	case "$dist" in
	ac)
		archlist='i686 i586 i386 athlon alpha sparc amd64 ppc'
		;;
	th)
		archlist='x86_64 i486 i686'
		;;
	*)
		echo >&2 "get-buildlog: $dist buildlogs are /dev/null"
		return
	esac

	local url arch path ftp=ftp://buildlogs.pld-linux.org
	for arch in $archlist; do
		[ "$arch" ] || continue
		path=${url#$ftp}
		echo -n "Checking $p.$arch... "
		url=$(lftp -c "debug 0;open $ftp; cls --sort=date -r /$dist/$arch/OK/$p,*.bz2 /$dist/$arch/FAIL/$p,*.bz2 | tail -n1")
		url=$ftp$url

		echo -n "$url... "
		if wget -q $url -O .$p~; then
			echo "OK"
			mv -f .$p~ $p.$arch.bz2
		else
			echo "SKIP"
			rm -f .$p~
		fi
	done
}

fi # no $dist set

alias adif="dif -x '*.m4' -x ltmain.sh -x install-sh -x depcomp -x 'Makefile.in' -x compile -x 'config.*' -x configure -x missing -x mkinstalldirs -x autom4te.cache"
alias pclean="sed -i~ -e '/^\(?\|=\+$\|unchanged:\|diff\|only\|Only\|Tylko\|Files\|Common\|Index:\|RCS file\|retrieving\)/d'"

# merges two patches
# requires: patchutils
pmerge() {
	combinediff -p1 $1 $2 > m.patch || return
	pclean m.patch
	dif $1 m.patch
}

# downloads sourceforge url from specific mirror
sfget() {
	local url="$1"
	url="${url%?download}"
	url="${url%?use_mirror=*}"
	url="${url#http://downloads.}"
	url="http://dl.${url#http://prdownloads.}"
	# use mirror
	local mirror="http://nchc.dl.sourceforge.net"
	url="$mirror/sourceforge/${url#http://dl.sourceforge.net/}"
	wget -c "$url"
}

dif() {
	if [ -t 1 ]; then
		diff -ur -x .svn -x .git -x .bzr -x CVS "$@" | diffcol | less -R
	else
		diff -ur -x .svn -x .git -x .bzr -x CVS "$@"
	fi
}

diffcol() {
sed -e '
	s,,[44m^[[49m,g;
	s,,[44m^G[49m,g;
	s,^\(Index:\|diff\|---\|+++\) .*$,[32m&,;
	s,^@@ ,[33m&,;
	s,^-,[35m&,;
	s,^+,[36m&,;
	s,\r,[44m^M[49m,g;
	s,	,    ,g;
	s,\([^[:space:]]\)\([[:space:]]\+\)$,\1[41m\2[49m,g;
	s,$,[0m,
' ${1:+"$@"}
}

# does diff between FILE~ and FILE
# the diff can be applied with patch -p1
d() {
	local file="$1" dir
	shift
	if [[ "$file" = /* ]]; then
		# full path -- no idea where to strip
		dir=.
		diff=$file
	else
		# relative path -- keep one path component from current dir
		dir=..
		diff=${PWD##*/}/${file}
	fi

	(builtin cd "$dir"; dif $diff{~,} "$@")
}

# spec name from NVR
rpm2spec() {
	sed -re 's,^(.+)-[^-]+-[^-]+$,\1.spec,'
}


#
# A colorized bash prompt
# - shows curret branch
# - shows if branch is up to date/ahead/behind
# - shows if last command exited with error (red)
#
# To use it, set $PROMPT_COMMAND env var:
# PROMPT_COMMAND=__bash_prompt_command
#
__bash_prompt_command() {
	local previous_return_value=$?

	local RED="\[\033[0;31m\]"
	local YELLOW="\[\033[0;33m\]"
	local GREEN="\[\033[0;32m\]"
	local BLUE="\[\033[0;34m\]"
	local LIGHT_RED="\[\033[1;31m\]"
	local LIGHT_GREEN="\[\033[1;32m\]"
	local WHITE="\[\033[1;37m\]"
	local LIGHT_GRAY="\[\033[0;37m\]"
	local COLOR_NONE="\[\e[0m\]"

	# if we are in rpm subdir and have exactly one .spec in the dir, include package version
	__package_update_rpmversion
	local rpmver=$(__package_rpmversion)

	local prompt="${BLUE}[${RED}\w${GREEN}${rpmver:+($rpmver)}$(__bash_parse_git_branch)${BLUE}]${COLOR_NONE} "
	if [ $previous_return_value -eq 0 ]; then
		PS1="${prompt}➔ "
	else
		PS1="${prompt}${RED}➔${COLOR_NONE} "
	fi
}

# helper for __bash_prompt_command
# command line (git) coloring
# note we use "\" here to avoid any "git" previous alias/func
__bash_parse_git_branch() {
	# not in git dir. return early
	\git rev-parse --git-dir &> /dev/null || return

	local git_status branch_pattern remote_pattern diverge_pattern
	local state remote branch

	git_status=$(\git -c color.ui=no status 2> /dev/null)
	branch_pattern="^On branch ([^${IFS}]*)"
	remote_pattern="Your branch is (behind|ahead) "
	diverge_pattern="Your branch and (.*) have diverged"

	if [[ ! ${git_status} =~ "working directory clean" ]]; then
		state="${RED}⚡"
	fi

	# add an else if or two here if you want to get more specific
	if [[ ${git_status} =~ ${remote_pattern} ]]; then
		if [[ ${BASH_REMATCH[1]} == "ahead" ]]; then
			remote="${YELLOW}↑"
		else
			remote="${YELLOW}↓"
		fi
	fi

	if [[ ${git_status} =~ ${diverge_pattern} ]]; then
		remote="${YELLOW}↕"
	fi

	if [[ ${git_status} =~ ${branch_pattern} ]]; then
		branch=${BASH_REMATCH[1]}
		echo " (${branch})${remote}${state}"
	fi
}

# cache requires bash 4.x
declare -A __package_update_rpmversion_cache
__package_update_rpmversion() {
	# extract vars from cache
	set -- ${__package_update_rpmversion_cache[$PWD]}
	local specfile=$1 version=$2 mtime=$3

	# invalidate cache
	if [ -f "$specfile" ]; then
		local stat
		stat=$(stat -c %Y $specfile)
		if [ $mtime ] && [ $stat -gt $mtime ]; then
			unset version
		fi
		mtime=$stat
	else
		# reset cache, .spec may be renamed
		unset version specfile
	fi

	# we have cached version
	test -n "$version" && return

	# needs to be one file
	specfile=${specfile:-$(\ls *.spec 2>/dev/null)}
	if [ ! -f "$specfile" ]; then
		unset __package_update_rpmversion_cache[$PWD]
		return
	fi

	mtime=${mtime:-$(stat -c %Y $specfile)}

	# give only first version (ignore subpackages)
	version=$(rpm --define "_specdir $PWD" --specfile $specfile -q --qf '%{VERSION}\n' | head -n1)
	__package_update_rpmversion_cache[$PWD]="$specfile ${version:-?} $mtime"
}

__package_rpmversion() {
	# extract vars from cache
	set -- ${__package_update_rpmversion_cache[$PWD]}
	# print version
	echo $2
}
