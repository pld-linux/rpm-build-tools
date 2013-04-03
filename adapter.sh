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

REVISION=1.50
VERSION="v0.35/$REVISION"
VERSIONSTRING="\
Adapter adapts .spec files for PLD Linux.
$VERSION (C) 1999-2013 Free Penguins".

PROGRAM=${0##*/}
dir=$(d=$0; [ -L "$d" ] && d=$(readlink -f "$d"); dirname "$d")
adapter=$dir/adapter.awk
usage="Usage: $PROGRAM [FLAGS] SPECFILEs

-s|--no-sort|--skip-sort
	skip BuildRequires, Requires sorting
-m|--no-macros|--skip-macros
	skip use_macros() substitutions
-d|--skip-desc
	skip desc wrapping
-a|--skip-defattr
	skip %defattr corrections
-o
	do not do any diffing, just dump the output
"

if [ ! -x /usr/bin/getopt ]; then
	echo >&2 "You need to install util-linux to use adapter"
	exit 1
fi

if [ ! -x /usr/bin/patch ]; then
	echo >&2 "You need to install patch to use adapter"
	exit 1
fi

[ -n "$PAGER" ] || PAGER="/usr/bin/less -r"

if [ -n "$CONFIG_DIR" ]; then
	USER_CFG="$CONFIG_DIR/.adapterrc"
elif [ -n "$HOME_ETC" ]; then
	USER_CFG="$HOME_ETC/.adapterrc"
else
	USER_CFG=~/.adapterrc
fi

[ -f $USER_CFG ] && . $USER_CFG

t=$(getopt -o hsomdaV --long help,version,sort,sort-br,no-macros,skip-macros,skip-desc,skip-defattr -n "$PROGRAM" -- "$@") || exit $?
eval set -- "$t"

while :; do
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
	-o)
		outputonly=1
	;;
	--)
		shift
		break
	;;
	*)
		echo >&2 "$PROGRAM: Internal error: \`$1' not recognized!"
		exit 1
		;;
	esac
	shift
done

diffcol()
{
	# vim like diff colourization
LC_ALL=en_US.UTF-8 gawk ' {
	split( $0, S, /\t/ );
	$0 = S[ 1 ];
	for ( i = 2; i in S; i++ ) {
		spaces = 7 - ( (length( $0 ) - 1) % 8 );
		$0 = $0 "\xE2\x9E\x94";
		for ( y = 0; y < spaces; y++ )
			$0 = $0 "\xE2\x87\xBE";
		$0 = $0 S[ i ];
	}
	gsub( /\033/, "\033[44m^[\033[49m" );
	cmd = "";
	if ( sub( /^ /, "" ) )
		cmd = " ";
	sub( /(\xE2\x9E\x94(\xE2\x87\xBE)*| )+$/, "\033[31;41m&\033[39;49m" );
	gsub( /\xE2\x9E\x94(\xE2\x87\xBE)*/, "\033[7m&\033[27m" );
	gsub( /\xE2\x87\xBE/, " " );
	# uncomment if you do not like utf-8 arrow
	# gsub( /\xE2\x9E\x94/, ">" );
	$0 = cmd $0;
	gsub( /\007/, "\033[44m^G\033[49m" );
	gsub( /\r/, "\033[44m^M\033[49m" );
}
/^(Index:|diff|---|\+\+\+) / { $0 = "\033[32m" $0 }
/^@@ / { $0 = "\033[33m" $0 }
/^-/ { $0 = "\033[35m" $0 }
/^+/ { $0 = "\033[36m" $0 }
{ $0 = $0 "\033[0m"; print }
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
	_topdir
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
	_pkgconfigdir
	_npkgconfigdir
	_localedir

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

	py3_sitescriptdir
	py3_sitedir
	py3_scriptdir
	py3_ver

	ruby_archdir
	ruby_libdir 
	ruby_sitedir  
	ruby_sitearchdir
	ruby_sitelibdir
	ruby_vendordir 
	ruby_vendorarchdir
	ruby_vendorlibdir
	ruby_rubylibdir
	ruby_rdocdir
	ruby_ridir

	php_pear_dir
	php_data_dir
	tmpdir

	systemdunitdir
	systemdtmpfilesdir
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

	export ADAPTER_REVISION=$REVISION

	eval $(rpm --eval "$(echo -e $eval_expr)")
}

adapterize() {
	local SPECFILE="$1"
	[ -f "$SPECFILE" ] || SPECFILE="$(basename $SPECFILE .spec).spec"

	local workdir
	workdir=$(mktemp -d ${TMPDIR:-/tmp}/adapter-XXXXXX) || exit $?
	awk=gawk

	local tmp=$workdir/$(basename $SPECFILE) || exit $?

	import_rpm_macros

	LC_ALL=en_US.UTF-8 $awk -f $adapter $SPECFILE > $tmp || exit $?

	if [ "$outputonly" = 1 ]; then
		cat $tmp

	elif [ "$(diff --brief $SPECFILE $tmp)" ]; then
		diff -u $SPECFILE $tmp > $tmp.diff
		if [ -t 1 ]; then
				diffcol $tmp.diff | $PAGER
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
								diffcol $t | $PAGER
								echo -n "Accept? (Yes, [N]o, Quit)? "
								read ans
								case "$ans" in
								[yYoO]) # y0 mama
									patch -p0 < $t
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
		echo "The spec $SPECFILE is perfect ;)"
	fi

	rm -rf $workdir
}

if [ $# -eq 0 ]; then
	echo "$usage"
	exit 1
fi

for SPECFILE in "$@"; do
	adapterize $SPECFILE
done

# vim: ts=4:sw=4
