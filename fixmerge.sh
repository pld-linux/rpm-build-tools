#!/bin/sh

# Changes the order of parents and commitlog in the merge produced by git pull. It produces
# the nicer history with git log --first-parent

git filter-branch -f --parent-filter "tee ~/P.OUT | awk '{if(NF==4) print \$1,\$4,\$3,\$2;}'| tee -a ~/P.OUT" \
    --msg-filter "sed 's/\(Merge branch .*\) of/\1 into/'" HEAD^!
