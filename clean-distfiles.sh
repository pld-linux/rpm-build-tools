#!/bin/sh
# cleanup distfiles like files, i.e archives that can be likely be
# re-downloaded.

# be sure we are in right dir
dir=$(dirname "$0")
cd "$dir"

ext=bz2,gz,rar,tgz,tbz2,zip,jar,Z,tar,png,ico,xpm,gif,rpm,bin,run,exe,iso,xpi,ZIP,dll
ls -ld */*.{$ext}

echo remove? ctrl+c to abort
read a

rm -vf */*.{$ext}
