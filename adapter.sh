#!/bin/sh

if [ $# -ne 1 -o ! -f "$1" ]; then
  echo "Usage: $0 filename"
  exit 1
fi

./adapter.awk "$1" > "$1.adapter"
diff -u "$1" "$1.adapter" | less
echo -n "Are the changes OK? [yNso] "

read OK

if [ "$OK" = "y" -o "$OK" = "Y" ]; then
  echo "Committing..."
  mv "$1.adapter" "$1"
  cvs ci "$1"
elif [ "$OK" = "o" -o "$OK" = "O" ];then
  echo "Saving changes..."
  mv "$1.adapter" "$1"
elif [ "$OK" != "s" -a "$OK" != "S" ];then
  echo "Ignoring changes..."
  rm "$1.adapter"
else
  echo "Did nothing."
fi
