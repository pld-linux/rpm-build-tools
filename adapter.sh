#!/bin/bash

if [[ $# -ne 1 || ! -f $1 ]]; then
  echo "Usage: $0 filename"
  exit 1
fi

./adapter.awk "$1" > "$1.adapter"
diff -urN "$1" "$1.adapter"|less
echo -n "Are the changes OK? [yN] "

read -n 1 OK

if [[ $OK == "y" || $OK == "Y" ]]; then
  mv "$1.adapter" "$1"
  cvs ci "$1"
else
  rm "$1.adapter"
fi
