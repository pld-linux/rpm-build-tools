#!/bin/sh
#
# Authors:
# 	Michał Kuratczyk <kura@pld.org.pl>
# 	Sebastian Zagrodzki <s.zagrodzki@mimuw.edu.pl>
# 	Tomasz Kłoczko <kloczek@rudy.mif.pg.gda.pl>
# 	Artur Frysiak <wiget@pld-linux.org>
# 	Michal Kochanowicz <mkochano@pld.org.pl>
# 	Elan Ruusamäe <glen@pld-linux.org>
#
# See cvs log adapter{,.awk} for list of contributors
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

RCSID='$Id$'
r=${RCSID#* * }
rev=${r%% *}
VERSION="v0.31/$rev"
VERSIONSTRING="\
Adapter adapts .spec files for PLD Linux.
$VERSION (C) 1999-2008 Free Penguins".

self=$(basename "$0")
adapter=$(dirname "$0")/adapter.awk
usage="Usage: $self [FLAGS] SPECFILE

-s|--no-sort|--skip-sort
	skip BuildRequires, Requires sorting
-m|--no-macros|--skip-macros
	skip use_macros() substitutions
-d|--skip-desc
	skip desc wrapping
-a|--skip-defattr
	skip %defattr corrections

"

if [ ! -x /usr/bin/getopt ]; then
	echo >&1 "You need to install util-linux to use adapter"
	exit 1
fi

if [ ! -x /usr/bin/patch ]; then
	echo >&1 "You need to install patch to use adapter"
	exit 1
fi

t=$(getopt -o hsmdaV --long help,version,sort,sort-br,no-macros,skip-macros,skip-desc,skip-defattr -n "$self" -- "$@") || exit $?
eval set -- "$t"

while true; do
	case "$1" in
	-h|--help)
 		echo 2>&1 "$usage"
		exit 1
	;;
	-s|--no-sort|--skip-sort)
		export SKIP_SORTBR=1
	;;
	-m|--no-macros|--skip-macros)
		export SKIP_MACROS=1
	;;
	-d|--skip-desc)
		export SKIP_DESC=1
	;;
	-a|--skip-defattr)
		export SKIP_DEFATTR=1
	;;
	-V|--version)
		echo "$VERSIONSTRING"
		exit 0
	;;
	--)
		shift
		break
	;;
	*)
		echo 2>&1 "$self: Internal error: [$1] not recognized!"
		exit 1
		;;
	esac
	shift
done

diffcol()
{
	 # vim like diff colourization
	 sed -e '
	 s,,[44m^[[49m,g;
	 s,,[44m^G[49m,g;
	 s,^\(Index:\|diff\|---\|+++\) .*$,[32m&,;
	 s,^@@ ,[33m&,g;
	 s,^-,[35m&,;
	 s,^+,[36m&,;
	 s,\r,[44m^M[49m,g;
	 s,	,    ,g;
	 s,\([^[:space:]]\)\([[:space:]]\+\)$,\1[41m\2[49m,g;
	 s,$,[0m,
	 ' "$@"
}

diff2hunks()
{
	 # diff2hunks orignally by dig
	 perl -e '
#! /usr/bin/perl -w

use strict;

for my $filename (@ARGV) {
	my $counter = 1;
	my $fh;
	open $fh, "<", $filename or die "$filename: open for reading: $!";
	my @lines = <$fh>;
	my @hunks;
	my @curheader;
	for my $i (0 ... $#lines) {
		next unless $lines[$i] =~ m/^\@\@ /;
		if ($i >= 2 and $lines[$i - 2] =~ m/^--- / and $lines[$i - 1] =~ m/^\+\+\+ /) {
			@curheader = @lines[$i - 2 ... $i - 1];
		}
		next unless @curheader;
		my $j = $i + 1;
		while ($j < @lines and $lines[$j] !~ m/^\@\@ /) {$j++}
		$j -= 2
			if $j >= 3 and $j < @lines
				and $lines[$j - 2] =~ m/^--- /
				and $lines[$j - 1] =~ m/^\+\+\+ /;
		$j--;
		$j-- until $lines[$j] =~ m/^[ @+-]/;
		my $hunkfilename = $filename;
		$hunkfilename =~ s/((\.(pat(ch)?|diff?))?)$/"-".sprintf("%03i",$counter++).$1/ei;
		my $ofh;
		open $ofh, ">", $hunkfilename or die "$hunkfilename: open for writing: $!";
		print $ofh @curheader, @lines[$i ... $j];
		close $ofh;
	}
}
' "$@"
}

# import selected macros for adapter.awk
# you should update the list also in adapter.awk when making changes here
import_rpm_macros() {
	macros="
	_sourcedir
	_prefix
	_bindir
	_sbindir
	_libdir
	_sysconfdir
	_datadir
	_includedir
	_mandir
	_infodir
	_examplesdir
	_defaultdocdir
	_kdedocdir
	_gtkdocdir
	_desktopdir
	_pixmapsdir
	_javadir

	perl_sitearch
	perl_archlib
	perl_privlib
	perl_vendorlib
	perl_vendorarch
	perl_sitelib

	py_sitescriptdir
	py_sitedir
	py_scriptdir
	py_ver

	ruby_archdir
	ruby_ridir
	ruby_rubylibdir
	ruby_sitearchdir
	ruby_sitelibdir

	php_pear_dir
	php_data_dir
	tmpdir
"
	eval_expr=""
	for macro in $macros; do
		eval_expr="$eval_expr\nexport $macro='%{$macro}'"
	done


	# get cvsaddress for changelog section
	# using rpm macros as too lazy to add ~/.adapterrc parsing support.
	eval_expr="$eval_expr
	export _cvsmaildomain='%{?_cvsmaildomain}%{!?_cvsmaildomain:@pld-linux.org}'
	export _cvsmailfeedback='%{?_cvsmailfeedback}%{!?_cvsmailfeedback:PLD Team <feedback@pld-linux.org>}'
	"

	eval $(rpm --eval "$(echo -e $eval_expr)")
}

adapterize() {
	local workdir
	workdir=$(mktemp -d ${TMPDIR:-/tmp}/adapter-XXXXXX) || exit
	if grep -q '\.UTF-8' $SPECFILE; then
		awk=gawk
	else
		awk=awk
	fi

	local tmp=$workdir/$(basename $SPECFILE) || exit

	import_rpm_macros

	$awk -f $adapter $SPECFILE > $tmp || exit

	if [ "$(diff --brief $SPECFILE $tmp)" ]; then
		diff -u $SPECFILE $tmp > $tmp.diff
		if [ -t 1 ]; then
				diffcol $tmp.diff | less -r
				while : ; do
					echo -n "Accept? (Yes, No, Confirm each chunk)? "
					read ans
					case "$ans" in
					[yYoO]) # y0 mama
						mv -f $tmp $SPECFILE
						echo "Ok, adapterized."
						break
					;;
					[cC]) # confirm each chunk
						diff2hunks $tmp.diff
						for t in $(ls $tmp-*.diff); do
								diffcol $t | less -r
								echo -n "Accept? (Yes, [N]o, Quit)? "
								read ans
								case "$ans" in
								[yYoO]) # y0 mama
									patch < $t
									;;
								[Q]) # Abort
									break
									;;
								esac
						done
						break
					;;
					[QqnNsS])
						echo "Ok, exiting."
						break
					;;
					esac
				done
		else
				cat $tmp.diff
		fi
	else
		echo "The SPEC is perfect ;)"
	fi

	rm -rf $workdir
}

SPECFILE="$1"
[ -f "$SPECFILE" ] || SPECFILE="$(basename $SPECFILE .spec).spec"

if [ $# -ne 1 -o ! -f "$SPECFILE" ]; then
	echo "$usage"
	exit 1
fi

adapterize
