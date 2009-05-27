#!/bin/sh
# get only *.spec files from packages/
# thx SamChi,pawelz

cd .. ; wget http://cvs.pld-linux.org/cgi-bin/cvsweb.cgi/packages/ -O - | sed '/<a href="\./!d' | sed 's,^.*<a href="\./\(.*\)/".*$,\packages/\1/\1.spec,' | xargs cvs get
