#!/bin/sh
#
# This is adapter v0.27. Adapter adapts .spec files for PLD Linux.
#
# Copyright (C) 1999-2003 PLD-Team <feedback@pld-linux.org>
# Authors:
# 	Micha³ Kuratczyk <kura@pld.org.pl>
# 	Sebastian Zagrodzki <s.zagrodzki@mimuw.edu.pl>
# 	Tomasz K³oczko <kloczek@rudy.mif.pg.gda.pl>
# 	Artur Frysiak <wiget@pld-linux.org>
# 	Michal Kochanowicz <mkochano@pld.org.pl>
# 	Elan Ruusamäe <glen@pld-linux.org>
#
# See cvs log adapter{,.awk} for list of contributors
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

self=$(basename "$0")
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

t=`getopt -o hsmda --long help,sort,sort-br,no-macros,skip-macros,skip-desc,skip-defattr -n "$self" -- "$@"` || exit $?
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
	 s,,[44m^M[49m,g;
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

adapterize()
{
	 local tmpdir
	 tmpdir=$(mktemp -d ${TMPDIR:-/tmp}/adapter-XXXXXX) || exit
	 awk -f adapter.awk $SPECFILE > $tmpdir/$SPECFILE || exit

	 if [ "`diff --brief $SPECFILE $tmpdir/$SPECFILE`" ] ; then
		  diff -u $SPECFILE $tmpdir/$SPECFILE > $tmpdir/$SPECFILE.diff
		  if [ -t 1 ]; then
				diffcol $tmpdir/$SPECFILE.diff | less -r
				while : ; do
					 echo -n "Accept? (Yes, No, Confirm each chunk)? "
					 read ans
					 case "$ans" in
					 [yYoO]) # y0 mama
						  mv -f $tmpdir/$SPECFILE $SPECFILE
						  echo "Ok, adapterized."
						  break
					 ;;
					 [cC]) # confirm each chunk
						  diff2hunks $tmpdir/$SPECFILE.diff
						  for t in $(ls $tmpdir/$SPECFILE-*.diff); do
								diffcol $t | less -r
								echo -n "Accept? (Yes, [N]o)? "
								read ans
								case "$ans" in
								[yYoO]) # y0 mama
									patch < $t
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
				cat $tmpdir/$SPECFILE.diff
		  fi
	 else
		  echo "The SPEC is perfect ;)"
	 fi

	 rm -rf $tmpdir
}

if [ $# -ne 1 -o ! -f "$1" ]; then
	echo "$usage"
	exit 1
fi

SPECFILE="$1"
adapterize
