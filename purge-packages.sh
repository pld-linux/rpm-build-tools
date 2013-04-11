#!/bin/sh
# Purges packages/ checkouts
# - if package has clean state, the dir is removed
# - otherwise git gc is called
set -e

CALL_GC=${CALL_GC:-'no'}

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
		* Package $pkg - State clean. Removing
		EOF
		mv ../$pkg $purgedir
	fi }
	cd ..
done

rmdir --ignore-fail-on-non-empty $purgedir

# vi:syntax=sh:ts=4:sw=4:noet
