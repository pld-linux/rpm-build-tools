#!/bin/sh

usage() {
  echo "Usage: $0 [-p <package_name>] [-o <crates_file>] [-f] [-v] [-h] [<pkg_name>.spec]"
  echo
  echo "\t-p <package_name>\tforce cargo <package_name> for version override instead of automatic detection"
  echo "\t-o <crates_file>\tforce output file name instead of automatically determined name"
  echo "\t-f\t\t\toverwrite creates file if it already exists"
  echo "\t-v\t\t\tset cargo package version to @@VERSION@@ for easier crates tarball reuse"
  echo "\t-h\t\t\tprint this help"
  echo
  echo "\t<pkg_name>.spec is optional and defaults to package found in current working directory"
}

for cmd in bsdtar rpm-specdump cargo perl awk; do
  if ! command -v $cmd > /dev/null 2> /dev/null; then
    not_installed="$not_installed$cmd "
  fi
done

if [ -n "$not_installed" ]; then
  echo "ERROR: required commands not found: $not_installed" >&2
  exit 1
fi

while getopts :p:o:fvh OPTNAME; do
  case $OPTNAME in
    p)
      force_cargo_package="$OPTARG"
      ;;
    f)
      overwrite=1
      ;;
    o)
      crates_file="$OPTARG"
      ;;
    v)
      version_override=1
      ;;
    h)
      usage
      exit 0
      ;;
    ?)
      echo "ERROR: unknown option '-$OPTARG'" >&2
      usage
      exit 1
      ;;
  esac
done

shift $(($OPTIND - 1))

rpm_topdir=$(rpm -E %{_topdir})

if [ -n "$1" ]; then
  pkg_name=$(basename "$1")
  pkg_name=${pkg_name%.spec}
  pkg_dir="$rpm_topdir/$pkg_name"
  if [ ! -f "$pkg_dir/$pkg_name.spec" ]; then
    echo "ERROR: no package $pkg_name found" >&2
    exit 1
  fi
else
  pkg_dir="$(pwd)"
  pkg_name=$(basename "$pkg_dir")
  if [ "$(readlink -f "$rpm_topdir")" != "$(readlink -f "$(dirname "$pkg_dir")")" ] || [ ! -f "$pkg_dir/$pkg_name.spec" ]; then
    echo "ERROR: failed to determine package name" >&2
    exit 1
  fi
fi

spec_dump=$(rpm-specdump "$pkg_dir/$pkg_name.spec")
pkg_version=$(echo "$spec_dump" | grep PACKAGE_VERSION | cut -f3 -d' ')
pkg_src=$(basename $(echo "$spec_dump" | grep SOURCEURL0 | cut -f3- -d' '))
if [ -z "$crates_file" ]; then
  crates_file="$pkg_name-crates-$pkg_version.tar.xz"
fi

if [ -e "$pkg_dir/$crates_file" ] && [ -z "$overwrite" ]; then
  echo "ERROR: crates file $crates_file already exists" >&2
  exit 1
fi

if [ ! -f "$pkg_dir/$pkg_src" ]; then
  echo "ERROR: source file $pkg_src not found" >&2
  exit 1
fi

tmpdir=$(mktemp -d)

rm_tmpdir() {
  if [ -n "$tmpdir" -a -d "$tmpdir" ]; then
    rm -rf "$tmpdir"
  fi
}

trap rm_tmpdir EXIT INT HUP

cd "$tmpdir"
bsdtar xf "$pkg_dir/$pkg_src"
src_dir=$(ls)
if [ $(echo "$src_dir" | wc -l) -ne 1 ]; then
  echo "ERROR: unexpected source structure:\n$src_dir" >&2
  exit 1
fi

cd "$src_dir"
cargo vendor
if [ $? -ne 0 ]; then
  echo "ERROR: cargo vendor failed" >&2
  exit 1
fi

if [ -n "$version_override" ]; then
  if [ -n "$force_cargo_package" ]; then
    cargo_package=$force_cargo_package
  else
    cargo_package=$(awk '/^[[:space:]]*\[package\]/ { in_package=1; } /^[[:space:]]*name[[:space:]]*=/ { if (in_package) { gsub("^[[:space:]]*name[[:space:]]*=[[:space:]]*","");gsub("(^\"|\"$)","");print; exit; } }' Cargo.toml)
  fi

  if [ -z "$cargo_package" ]; then
    echo "ERROR: failed to determine cargo package name" >&2
    exit 1
  fi

  # replace cargo package version with @@VERSION@@
  perl -pi -e 'BEGIN { undef $/;} s/(\[\[package\]\]\nname\s*=\s*"'"$cargo_package"'"\nversion\s*=\s*")[^"]+/$1\@\@VERSION\@\@/m' Cargo.lock
fi

cd ..
tar cJf "$pkg_dir/$crates_file" "$src_dir"/{Cargo.lock,vendor}
echo "Created $pkg_dir/$crates_file"

# vim: expandtab shiftwidth=2 tabstop=2
