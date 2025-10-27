#!/bin/ksh

SHELL=/bin/ksh
IP=/sbin/ip

TEST_NS=""
DEBUG=""

usage() {
  echo "Usage: $0 [-t] [-D] [-h] <command> [args...]"
  echo "Run <command> without network access"
  echo
  echo "\t-t\t\ttest support for creating namespaces"
  echo "\t-D\t\tenable debug mode"
  echo "\t-h\t\tprint this help"
}

while getopts tDh OPTNAME; do
  case $OPTNAME in
    t)
      TEST_NS=1
      ;;
    D)
      DEBUG=1
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

if [ -n "$TEST_NS" ]; then
  unshare --user --net --map-current-user true 2> /dev/null
  exit $?
fi

if [ $# -eq 0 ]; then
  echo "ERROR: no command given" >&2
  exit 1
fi

if [ -n "$DEBUG" ]; then
  set -x
  set -v
fi

exec unshare --user --net --map-root-user $SHELL -s${DEBUG:+xv} "$@" <<EOF
if test -x $IP; then
  $IP a add 127.0.0.1/8 dev lo 2> /dev/null && addr=1
  $IP a add ::1/128 dev lo noprefixroute 2> /dev/null && addr=1
  if test -n "\$addr"; then
    $IP l set lo up
  fi
  unset addr
  exec unshare --map-user $(id -un) "\$@"
fi
EOF
