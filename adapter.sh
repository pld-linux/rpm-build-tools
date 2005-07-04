#!/bin/sh

if [ $# -ne 1 -o ! -f "$1" ]; then
  echo "Usage: $0 filename"
  exit 1
fi

./builder -a "$1"
