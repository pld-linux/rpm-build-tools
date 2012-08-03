#!/bin/sh
# $Id$
#
# Sending by
MAILER='/usr/sbin/sendmail'
# MAILER='/usr/bin/msmtp'
# Sending via
VIA="SENDMAIL"
#VIA="localhost"
VIA_ARGS=""
#VIA_ARGS="some additional flags"
# e.g. for msmtp:
# VIA_ARGS='-a gmail'
#
# DISTFILES EMAIL
DMAIL="distfiles@pld-linux.org"
#
# CVS LOGIN or fill it by hand :)
tmp=$(git config user.email)
LOGIN=${tmp%@*}
#LOGIN="djrzulf"
#
# HOST
HOST=`hostname -f`
#HOST="knycz.net"
#
# functions

usage()
{
	echo "Usage: fetchsrc_request file.spec [BRANCH]"
	echo
}

#------------------
# main()
if [ "$#" = 0 ]; then
	usage
	exit 1
fi
if [ "$2" != "" ]; then
	BRANCH="$2"
else
	BRANCH="refs/heads/master"
fi
if [[ "$BRANCH" != refs/* ]]; then
	BRANCH="refs/heads/$BRANCH"
fi
SPEC="$(basename $1)"
SPEC=${SPEC%.spec}

if [ "$VIA" = "SENDMAIL" ]; then
	echo >&2 "Requesting $SPEC:$BRANCH via $MAILER ${VIA_ARGS:+ ($VIA_ARGS)}"
	cat <<EOF | "$MAILER" -t -i $VIA_ARGS
To: $DMAIL
From: $LOGIN <$LOGIN@$HOST>
Subject: fetchsrc_request notify
X-distfiles-request: yes
X-Login: $LOGIN
X-Package: $SPEC
X-Branch: $BRANCH
X-Flags: force-reply

.
EOF
else
	echo >&2 "Requesting $SPEC:$BRANCH via SMTP ($VIA:25)"
	cat <<EOF | /usr/bin/nc $VIA 25 > /dev/null
EHLO $HOST
MAIL FROM: $LOGIN <$LOGIN@$HOST>
RCPT TO: $DMAIL
DATA
To: $DMAIL
Subject: fetchsrc_request notify
X-distfiles-request: yes
X-Login: $LOGIN
X-Package: $SPEC
X-Branch: $BRANCH
X-Flags: force-reply

.
QUIT
EOF
fi

