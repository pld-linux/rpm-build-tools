#!/bin/sh
set -e

dir=$(cd "$(dirname "$0")"; pwd)
rpmdir=$(rpm -E %_topdir)
dist=th

# userspace+kernel:
# crash
# dahdi-linux
# ipset
# linux-fusion
# open-vm-tools
# spl
# tpm_emulator
# VirtualBox
# vpb-driver
# xorg-driver-video-fglrx
# xorg-driver-video-nvidia
# xorg-driver-video-nvidia-legacy3
# xorg-driver-video-nvidia-legacy-304xx
# xtables-addons
#
# lirc
# madwifi-ng
#
# kernel:
# e1000e
# igb
# ixgbe
# lin_tape
# lttng-modules
# nvidiabl
# r8168
# wl
#
# linuxrdac

pkgs_all="
	crash
	dahdi-linux
	e1000e
	igb
	ipset
	ixgbe
	wl
	lin_tape
	linux-fusion
	lttng-modules
	nvidiabl
	open-vm-tools
	r8168
	spl
	tpm_emulator
	VirtualBox
	vpb-driver
	xorg-driver-video-fglrx
	xorg-driver-video-nvidia
	xorg-driver-video-nvidia-legacy3
	xorg-driver-video-nvidia-legacy-304xx
"

pkgs_head="
	xtables-addons:master
"

pkgs_3_14="
	xtables-addons:master
"

pkgs_3_10="
	xtables-addons:master
"

pkgs_3_4="
	lirc
	madwifi-ng
	linuxrdac
	xtables-addons:XTADDONS_1
"

# autotag from rpm-build-macros
# displays latest used tag for a specfile
autotag() {
	local out spec pkg ref headobj githead
	for spec in "$@"; do
		# strip branches
		pkg=${spec%:*}
		githead=${spec#*:}
		if [ "$githead" = "$spec" ]; then
			githead=
		fi
		# ensure package ends with .spec
		spec=${pkg%.spec}.spec
		# and pkg without subdir
		pkg=${pkg#*/}
		# or .ext
		pkg=${pkg%%.spec}
		cd $pkg
		git fetch --tags
		if [ -n "$alt_kernel" ]; then
			ref="refs/tags/auto/${dist}/${pkg}-${alt_kernel}-[0-9]*"
		else
			ref="refs/tags/auto/${dist}/${pkg}-[0-9]*"
		fi
		if [ -n "$githead" ]; then
			headobj=$(git for-each-ref refs/heads/$githead --format='%(objectname)')
		fi
		if [ -n "$headobj" ]; then
			out=$(git for-each-ref $ref --sort=authordate --format='%(objectname) %(refname:short)' | grep "$headobj" | cut -f 2 -d ' ' | tail -n 1)
		else
			out=$(git for-each-ref $ref --sort=-authordate --format='%(refname:short)' --count=1)
		fi
		echo "$spec:$out"
		cd - >/dev/null
	done
}

get_last_tags() {
	local pkg spec pkgname pkgbranch

	echo >&2 "Fetching package tags: $*..."
	for pkg in "$@"; do
		echo >&2 "$pkg... "
		# strip branches
		pkgname=${pkg%:*}
		pkgbranch=${pkg#*:}
		if [ "$pkgbranch" = "$pkg" ]; then
			pkgbranch="master"
		fi
		$rpmdir/builder -g $pkgname -ns -r $pkgbranch 1>&2
		if [ ! -e $pkgname/$pkgname.spec ]; then
			# just print it out, to fallback to base pkg name
			echo "$pkg"
		else
			spec=$(autotag $pkgname/$pkg)
			spec=${spec#*/}
			echo >&2 "... $spec"
			echo $spec
		fi
	done
}

cd $rpmdir
case "$1" in
	all)
		srcpkgs=
		for v in "-" "-3.4-" "-3.10-" "-3.14-"; do
			srcpkgs="$srcpkgs kernel${v}headers kernel${v}module-build"
		done
		$dir/make-request.sh -b th-src -t -c "poldek -n th -n th-ready -n th-test --up ; poldek -uGv $srcpkgs"
		echo press enter after src builder updates kernel packages
		read
		specs=$(get_last_tags $pkgs_all)
		$dir/make-request.sh -nd -r -d $dist --define 'build_kernels 3.4,3.10,3.14' --without userspace $specs
		if [ -n "$pkgs_head" ]; then
			specs=$(get_last_tags $pkgs_head)
			$dir/make-request.sh -nd -r -d $dist --without userspace $specs
		fi
		if [ -n "$pkgs_3_14" ]; then
			specs=$(get_last_tags $pkgs_3_14)
			$dir/make-request.sh -nd -r -d $dist --kernel 3.14 --without userspace $specs
		fi
		if [ -n "$pkgs_3_10" ]; then
			specs=$(get_last_tags $pkgs_3_10)
			$dir/make-request.sh -nd -r -d $dist --kernel 3.10 --without userspace $specs
		fi
		if [ -n "$pkgs_3_4" ]; then
			specs=$(get_last_tags $pkgs_3_4)
			$dir/make-request.sh -nd -r -d $dist --kernel 3.4 --without userspace $specs
		fi
		;;
	head)
		$dir/make-request.sh -b th-src -t -c 'poldek -n th -n th-ready -n th-test --up ; poldek -uGv kernel-headers kernel-module-build'

		kernel=$(get_last_tags kernel)
		kernel=$(echo ${kernel#*auto/??/} | tr _ .)
		echo $kernel
		echo press enter after src builder updates kernel packages
		read
		specs=$(get_last_tags $pkgs_all)
		$dir/make-request.sh -nd -r -d $dist --define 'build_kernels 3.4,3.10,3.14' --without userspace $specs
		if [ -n "$pkgs_head" ]; then
			specs=$(get_last_tags $pkgs_head)
			$dir/make-request.sh -nd -r -d $dist --without userspace $specs
		fi
		;;
	3.14)
		$dir/make-request.sh -b th-src -t -c 'poldek -n th -n th-ready -n th-test --up ; poldek -uGv kernel-3.14-headers kernel-3.14-module-build'

		kernel=$(alt_kernel=3.14 get_last_tags kernel)
		kernel=$(echo ${kernel#*auto/??/} | tr _ .)
		echo $kernel
		echo press enter after src builder updates kernel packages
		read
		specs=$(get_last_tags $pkgs_all)
		$dir/make-request.sh -nd -r -d $dist --define 'build_kernels 3.4,3.10,3.14' --without userspace $specs
		if [ -n "$pkgs_3_14" ]; then
			specs=$(get_last_tags $pkgs_3_14)
			$dir/make-request.sh -nd -r -d $dist --kernel 3_14 --without userspace $specs
		fi
		;;
	3.10)
		$dir/make-request.sh -b th-src -t -c 'poldek -n th -n th-ready -n th-test --up ; poldek -uGv kernel-3.10-headers kernel-3.10-module-build'

		kernel=$(alt_kernel=3.10 get_last_tags kernel)
		kernel=$(echo ${kernel#*auto/??/} | tr _ .)
		echo $kernel
		echo press enter after src builder updates kernel packages
		read
		specs=$(get_last_tags $pkgs_all)
		$dir/make-request.sh -nd -r -d $dist --define 'build_kernels 3.4,3.10,3.14' --without userspace $specs
		if [ -n "$pkgs_3_10" ]; then
			specs=$(get_last_tags $pkgs_3_10)
			$dir/make-request.sh -nd -r -d $dist --kernel 3_10 --without userspace $specs
		fi
		;;
	3.4)
		$dir/make-request.sh -b th-src -t -c 'poldek -n th -n th-ready -n th-test --up ; poldek -uGv kernel-3.4-headers kernel-3.4-module-build'

		kernel=$(alt_kernel=3.4 get_last_tags kernel)
		kernel=$(echo ${kernel#*auto/??/} | tr _ .)
		echo $kernel
		echo press enter after src builder updates kernel packages
		read
		specs=$(get_last_tags $pkgs_all)
		$dir/make-request.sh -nd -r -d $dist --define 'build_kernels 3.4,3.10,3.14' --without userspace $specs
		if [ -n "$pkgs_3_4" ]; then
			specs=$(get_last_tags $pkgs_3_4)
			$dir/make-request.sh -nd -r -d $dist --kernel 3_4 --without userspace $specs
		fi
		;;
	*)
		# try to parse all args, filling them with last autotag
		while [ $# -gt 0 ]; do
			case "$1" in
			--kernel|--with|--without)
				args="$1 $2"
				shift
				;;
			-*)
				args="$args $1"
				;;
			*)
				specs="$specs $1"
				;;
			esac
			shift
		done
		specs=$(get_last_tags $specs)
		$dir/make-request.sh -nd -r -d $dist $args $specs
		;;
esac
