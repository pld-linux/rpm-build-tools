#!/bin/sh
program=${0##*/}
program=${program%.sh}
dir=$(dirname "$0")
rpmdir=$(rpm -E %_topdir)
dist=th
suffix=${program#php}

# get_last_specs and autotag copied from rebuild-th-kernel.sh
# autotag from rpm-build-macros

# displays latest used tag for a specfile
autotag() {
	local out spec pkg ref
	for spec in "$@"; do
		# strip branches
		pkg=${spec%:*}
		# ensure package ends with .spec
		spec=${pkg%.spec}.spec
		# and pkg without subdir
		pkg=${pkg#*/}
		# or .ext
		pkg=${pkg%%.spec}
		cd $rpmdir/$pkg
		git fetch --tags
		if [ -n "$alt_kernel" ]; then
			ref="refs/tags/auto/${dist}/${pkg}-${alt_kernel}-[0-9]*"
		else
			ref="refs/tags/auto/${dist}/${pkg}-[0-9]*"
		fi
		out=$(git for-each-ref $ref --sort=-authordate --format='%(refname:short)' --count=1)
		echo "$spec:$out"
		cd - >/dev/null
	done
}

get_last_tags() {
	local pkg spec

	echo >&2 "Fetching package tags..."
	for pkg in "$@"; do
		# skip options (proxy them)
		if [[ $pkg = -* ]]; then
			echo "$pkg"
			continue
		fi

		echo >&2 "$pkg... "
		if [ ! -e $rpmdir/$pkg/$pkg.spec ]; then
			$rpmdir/builder -g $pkg -ns -r HEAD 1>&2
		fi
		if [ ! -e $rpmdir/$pkg/$pkg.spec ]; then
			# just print it out, to fallback to base pkg name
			echo >&2 "... $pkg"
			echo "$pkg"
		else
			spec=$(autotag $pkg/$pkg.spec)
			spec=${spec#*/}
			# update progress
			echo >&2 "... $spec"
			# output
			echo $spec
		fi
	done
}

specs=$(get_last_tags "$@")

exec $dir/make-request.sh -D "php_suffix $suffix" $specs -C "poldek -ev --noask php$suffix-devel"
