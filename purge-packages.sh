#!/bin/sh
# Purges packages/ checkouts
#
# - if package has clean state, the dir is cleaned up (moved to purge dir)
# - otherwise git gc is called if CALL_GC=yes
# Stashes aside packages/ that do not have .git dir
# - these dirs are usually created by rpmbuild if Name does not match .spec file

set -e

CALL_GC=${CALL_GC:-no}

topdir="${1:-$(rpm -E %_topdir)}"
topdir=$(readlink -f "$topdir")
purgedir=$topdir/purged
stashdir=$topdir/stashed
cd "$topdir"

echo "Purging in $topdir, press ENTER to continue"
read a

if [ -d "$purgedir" ]; then
	echo >&2 "Previous pruge dir exists: $purgedir, remove it to continue"
	exit 1
fi

install -d $purgedir
for pkg in */.git; do
	continue
	pkg=${pkg%/.git}
	cd "$pkg"
	purge='yes'

	status=$(git status --porcelain)
	stash=$(git stash list)

	# FIXME: does not currently handle if some pushes are not made!
	if [ -n "$status" ] || [ -n "$stash" ]; then
		cat <<-EOF
		* Package $pkg - Untracked files or stash not empty.
		$status
		EOF
		purge='no'
		[ "$CALL_GC" != 'no' ] && git gc
	fi
	git show-ref --heads |\
	{ while read sha1 branch; do
		short_branch=${branch#refs/heads/}
		if ! upstream=$(git rev-parse -q --verify $short_branch@{u}) 2>/dev/null; then
			echo "* Package $pkg - Branch $short_branch has not defined upstream"
			purge='no'
			continue
		fi
		if [ -n "$(git rev-list "$upstream..$branch")" ]; then
			echo "* Package $pkg - Branch $short_branch is not fully merged to its upstream"
			purge='no'
			continue
		fi
	done
	if [ "$purge" = 'yes' ]; then
		cat <<-EOF
		* Package $pkg - State clean. Purging
		EOF
		mv ../$pkg $purgedir
	fi }
	cd ..
done

rmdir --ignore-fail-on-non-empty $purgedir

# go over packages that do not have .git
if [ -d "$stashdir" ]; then
	echo >&2 "Previous stash dir exists: $stashdir, remove it to continue"
	exit 1
fi
install -d $stashdir
stashdir=$(readlink -f $stashdir)
for pkg in */; do
	# skip symlinks
	test -L "${pkg%/}" && continue
	# skip packages which do have .git
	test -d "$pkg/.git" && continue
	# skip if it's the stash dir itself
	pkg=$(readlink -f $pkg)
	test "$pkg" = "$stashdir" && continue

	echo "* Package $pkg does not have .git, stashing"
	mv $pkg $stashdir
done
rmdir --ignore-fail-on-non-empty $stashdir

# vi:syntax=sh:ts=4:sw=4:noet
