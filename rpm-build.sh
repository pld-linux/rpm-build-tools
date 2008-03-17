# shell aliases and functions for PLD Developer
# $Id$

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
alias $dist-tag="./builder -cf -T $(echo $dist | tr '[a-z]' '[A-Z]')-branch -r HEAD"
alias $dist-verify=dist-verify
alias $dist-requires=dist-requires

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
	poldek -q --sn $dist $opts --cmd what-requires $deps
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
		# obsoleted
		ignore="$ignore php-pear-Net_Ping-tests"
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
	local out
	for a in "$@"; do
		s=${a%.spec}.spec
		out=$(cvs status -v $s | awk "!/Sticky/&&/auto-$dist-/{if (!a++) print \$1}")
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
	r2=${r2%%[&;]*}
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
	#  http://websvn.kde.org/branches/KDE/3.5/kdenetwork/kopete/protocols/oscar/aim/aimcontact.cpp?r1=609808&r2=673027&view=patch
	url=http://websvn.kde.org/${url% *}
	url="$url?r1=$r1&r2=$r2&view=patch"

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

# does diff between FILE and FILE~
# the diff can be applied with patch -p1
d() {
	local file="$1"
	local dir
	if [[ "$file" = /* ]]; then
		# full path -- no idea where to strip
		dir=.
		diff=$file
	else
		# relative path -- keep one path component from current dir
		dir=..
		diff=${PWD##*/}/${file}
	fi

	(builtin cd "$dir"; dif $diff{~,})
}
