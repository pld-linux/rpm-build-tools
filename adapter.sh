#!/bin/bash

if [ $# -ne 1 -o ! -f "$1" ]; then
  echo "Usage: $0 filename"
  exit 1
fi

./adapter.awk "$1" > "$1.adapter"
diff -u "$1" "$1.adapter"|less
echo -n "Are the changes OK? [yNso] "

read -n 1 OK
echo

if [ "$OK" == "y" -o "$OK" == "Y" ]; then
  mv "$1.adapter" "$1"
  cvs ci "$1"
elif [ "$OK" != "o" -a "$OK" != "O" ];then
  mv "$1.adapter" "$1"
elif [ "$OK" != "s" -a "$OK" != "S" ];then
  rm "$1.adapter"
fi
