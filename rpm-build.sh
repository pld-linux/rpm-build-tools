# shell aliases and functions for PLD Developer
# $Id$

# set $dist, used by functions below
[ -n "$dist" ] || dist=$(awk /PLD Linux/ '{print tolower($NF)}' /etc/pld-release 2>/dev/null | tr -d '()')

if [ "$dist" ]; then

alias ipoldek-$dist="poldek -q --sn $dist --cmd"
alias $dist-requires="ipoldek-$dist what-requires"
alias $dist-provides="ipoldek-$dist what-provides"
alias $dist-tag="./builder -cf -T $(echo $dist | tr '[a-z]' '[A-Z]')-branch -r HEAD"
alias $dist-verify=dist-verify

dist-verify() {
	poldek --sn $dist --sn $dist-ready --up
	poldek --sn $dist --sn $dist-ready --verify=deps "$@"
}

# displays latest used tag for a specfile
autotag() {
	local out
	for a in "$@"; do
		s=${a%.spec}.spec
		out=$(cvs status -v $s | awk "/auto-$dist-/{if (!a++) print \$1}")
		echo "$s:$out"
	done
}

fi # no $dist set

alias cv='cvs status -v'
alias adif="dif -x '*.m4' -x ltmain.sh -x install-sh -x depcomp -x 'Makefile.in' -x compile -x 'config.*' -x configure -x missing -x mkinstalldirs -x autom4te.cache"
alias pclean="sed -i~ -e '/^\(?\|=\+$\|unchanged:\|diff\|only\|Only\|Files\|Common\|Index:\|RCS file\|retrieving\)/d'"

# makes diff from PLD CVS urls
# requires: cvs, tee
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
	r2=${r2%[&;]*}
	r1=${r1%%[&;]*}
	file=${file%\?*}
	file=${file%.diff}

	echo >&2 "$file: $r1 -> $r2"

	if [ -t 1 ]; then
		cvs diff -u -r$r1 -r$r2 $file | tee m.patch | diffcol
	else
		cvs diff -u -r$r1 -r$r2 $file
	fi
}

# makes diff from kde svn path
# requires: wget, tee
kdediff() {
	local url="$1"
	# --- branches/KDE/3.5/kdepim/kpilot/conduits/vcalconduit/vcalRecord.cc #624744:624745
	url=${url#*--- }
	echo >&2 "Process $url"
	r1=${url#*#}
	r2=${r1#*:}
	r1=${r1%:*}

	#  http://websvn.kde.org/branches/KDE/3.5/kdepim/kpilot/conduits/vcalconduit/vcalRecord.cc?rev=624745&r1=612579&r2=624745&makepatch=1&diff_format=u
	url=http://websvn.kde.org/${url% *}
	url="$url?r1=$r1&r2=$r2&makepatch=1&diff_format=u"

	if [ -t 1 ]; then
		wget "$url" -O -| tee m.patch | diffcol
	else
		wget "$url" -O -
	fi
}

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
	url="http://dl.${url#http://prdownloads.}"
	# use mirror
	local mirror="http://nchc.dl.sourceforge.net"
	url="$mirror/sourceforge/${url#http://dl.sourceforge.net/}"
	wget -c "$url"
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

# chdir to file location and do 'cvs log'
cvslog() {
	local f="$1"
	local d="${f%/*}"
	[ "$d" = "$f" ] && d=.
	(builtin cd $d && cvs log ${f##*/})
}
