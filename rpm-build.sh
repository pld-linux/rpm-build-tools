# shell aliases and functions for PLD Developer
# $Id$

alias cv='cvs status -v'
alias ac='poldek -q --sn ac --cmd'
alias ac-requires='ac what-requires'
alias ac-provides='ac what-provides'
alias ac-verify='poldek --sn ac --sn ac-ready -V'
alias ac-tag='./builder -cf -T AC-branch -r HEAD'
alias adif="dif -x '*.m4' -x ltmain.sh -x install-sh -x depcomp -x 'Makefile.in' -x compile -x 'config.*' -x configure -x missing -x mkinstalldirs -x autom4te.cache"
alias pclean="sed -i~ -e '/^\(?\|=\+$\|unchanged:\|diff\|only\|Only\|Files\|Common\|Index:\|RCS file\|retrieving\)/d'"

# merges two patches
# requires: patchutils
pmerge() {
	combinediff -p1 $1 $2 > m.patch || return
	pclean m.patch
	dif $1 m.patch
}

# makes diff from PLD CVS urls
urldiff() {
	local url="$1"
	if [ -z "$url" ]; then
		echo >&2 "Reading STDIN"
		read url
	fi

	echo >&2 "Process $url"
	local file="$url"
	file=${file#*SPECS/}
	file=${file#*SOURCES/}
	file=${file##*/}
	local r1=${file#*r1=}
	local r2=${r1#*r2=}
	r2=${r2%&*}
	r1=${r1%%&*}
	file=${file%\?*}

	echo >&2 "$file: $r1 -> $r2"

	if [ -t 1 ]; then
		pipe=' | tee m.patch | diffcol'
	fi
	cvs diff -u -r$r1 -r$r2 $file $pipe
}

# downloads sourceforge url from specific mirror
sfget() {
	local url="$1"
	url="${url%?download}"
	url="http://dl.${url#http://prdownloads.}"
	# use mirror
	local mirror="http://nchc.dl.sourceforge.net"
	url="$mirror/sourceforge/${url#http://dl.sourceforge.net/}"
	wget -c "$url"
}

# displays latest used tag for a specfile
autotag() {
	local out
	for a in "$@"; do
		out=$(cvs status -v $a | awk '/auto-ac-/{if (!a++) print $1}')
		echo "$a:$out"
	done
}

dif() {
	if [ -t 1 ]; then
		diff -ur "$@" | diffcol | less -R
	else
		diff -ur "$@"
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
	s,,[44m^M[49m,g;
	s,	,    ,g;
	s,\([^[:space:]]\)\([[:space:]]\+\)$,\1[41m\2[49m,g;
	s,$,[0m,
' "$@"
}
