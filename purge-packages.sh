#!/bin/sh
# Purges packages/ checkouts
# - if package has clean state, the dir is removed
# - otherwise git gc is called
set -e

topdir=$(rpm -E %_topdir)
purgedir=$topdir/purged
cd "$topdir"

if [ -d "$purgedir" ]; then
	echo >&2 "Previous pruge dir exists: $purgedir, remove it to resume"
	exit 1
fi

install -d $purgedir
for pkg in */.git; do
	pkg=${pkg%/.git}
	cd "$pkg"
	status=$(git status -s)

	# FIXME: does not currently handle if some pushes are not made!
	if [ -n "$status" ]; then
		cat <<-EOF
		* Package $pkg - Untracked files. Invoke gc

		$status
		EOF
		git gc
	else
		cat <<-EOF
		* Package $pkg - State clean. Removing
		EOF
		mv ../$pkg $purgedir
	fi
	cd ..
done
