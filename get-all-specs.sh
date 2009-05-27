#!/bin/sh
# get only *.spec files from packages/
# thx SamChi,pawelz

# run script in ./packages directory

# change cvs to your login name
CVSUSER=cvs

export CVSROOT=:pserver:"${CVSUSER}"@cvs.pld-linux.org:/cvsroot
cvs login
cd .. 
wget http://cvs.pld-linux.org/cgi-bin/cvsweb.cgi/packages/ -O - | sed '/<a href="\./!d' | sed 's,^.*<a href="\./\(.*\)/".*$,/\1/\1.spec,' | xargs cvs get
