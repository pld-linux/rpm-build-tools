#!/bin/sh
# Walks your %_topdir (or any other dir specified by $1) and checks with pldnotify.awk for updates
# and shows only relevant diffs of those packages only.
#
# Setup your cron to give you work early morning :)
# 6 30 * * * /some/path/pldnotify.sh
#
# Idea based on PLD-doc/notify-specsupdate.sh script
# Author: Elan Ruusamäe <glen@pld-linux.org>

set -e
dir=$(dirname "$0")
topdir=${1:-$(rpm -E %_topdir)}
pldnotify=${0%/*}/pldnotify.awk
debug=0

# run pldnotify with debug mode if this script executed with "-x"
case "$-" in
*x*)
	debug=1
	;;
esac

xtitle() {
	local prefix="[$(date '+%Y-%m-%d %H:%M:%S')] pldnotify: "
	local msg="$prefix"$(echo "$*" | tr -d '\r\n')
	case "$TERM" in
	cygwin|xterm*)
		echo >&2 -ne "\033]1;$msg\007\033]2;$msg\007"
	;;
	screen*)
		echo >&2 -ne "\033]0;$msg\007"
	;;
	esac
	echo "$msg"
}

xtitle "Checking packages in $topdir/*"
for spec in $topdir/*/*.spec; do
	pkg=${spec##*/}

	xtitle "Checking $pkg"
	out=$($pldnotify -vDEBUG=$debug < $spec); rc=$?
	if [ $rc != 0 ]; then
		echo >&2 "$out"
		continue
	fi

	echo "$out" | grep -v "seems ok" || :
done
