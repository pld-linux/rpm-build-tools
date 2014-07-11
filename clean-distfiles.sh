#!/bin/sh
# cleanup distfiles-like files, i.e archives that can be likely be
# re-downloaded.
#
# TODO:
# - make it smarter:
#   - consult .gitignore of each package first
#   - do not clean NoSource files
#   - do not clean proprietary License packages
set -e

# be sure we are in right dir
topdir="${1:-$(rpm -E %_topdir)}"
topdir=$(readlink -f "$topdir")
purgedir=$topdir/df-purge

if [ -d "$purgedir" ]; then
	echo >&2 "Previous pruge dir exists: $purgedir, remove it to resume"
	exit 1
fi

cd "$topdir"

ext=bz2,gz,rar,tgz,tbz2,zip,jar,Z,tar,png,ico,xpm,gif,rpm,bin,run,exe,iso,xpi,ZIP,dll,pdf,xz,deb,crx
ls -ldrSh */*.{$ext} || :
echo */*.{$ext} | xargs stat -c %s | awk '{s+=$1} END {printf("Total: %d MiB\n", s/1014/1024)}'

echo remove? ctrl+c to abort
read a

install -d $purgedir
mv */*.{$ext} $purgedir
rmdir $purgedir || :
