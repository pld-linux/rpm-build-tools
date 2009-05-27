#!/bin/sh
# get only *.spec files from packages/
# thx SamChi,pawelz

# run script in ./packages directory

# change cvs to your login name
CVSUSER=cvs

export CVSROOT=:pserver:"${CVSUSER}"@cvs.pld-linux.org:/cvsroot
cvs login
cd .. 
wget http://cvs.pld-linux.org/cgi-bin/cvsweb.cgi/packages/ -O - \
	| perl -p -e 'if(m#a href="\./(.*?)/"#){$_=$1;s/%(..)/chr hex $1/eg;$_="packages/$_/$_.spec\0"}else{$_=undef}' \
	| xargs -0 cvs -z3 get
