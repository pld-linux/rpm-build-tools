#!/bin/sh -e

# Usage:
#   Just run this script in your rpm/packages/rpm-build-tools directory.

die() {
	>&2 printf '*** '${1:+"$@\n"}
	return 1
}

msg() {
	printf '	'${1:+"$@\n"}
}

[ -f "/etc/shrc.d/rpm-build.sh" ] || die "Install rpm-build-macros package"
. /etc/shrc.d/rpm-build.sh

src[0]=adapter
src[1]=adapter.awk
src[2]=builder
src[3]=pldnotify.awk
src[4]=rpm-build-tools.spec

dst[0]=adapter.sh
dst[1]=${src[1]}
dst[2]=builder.sh
dst[3]=${src[3]}

#
# Checkout on involved files and check for local modifications.
#

for I in 0 1 2 3; do
	msg "Checking out packages/rpm-build-tools/${dst[$I]} file."
	rs=$(cvs up ${dst[$I]})
	case "$rs" in
		"M "*) die "You have local modifications in packages/rpm-build-tools/${dst[$I]} file.\nCommit it first." ;;
	esac
done
cd ..;
for I in 0 1 2 3; do
	msg "Checking out packages/${src[$I]} file."
	rs=$(cvs up ${src[$I]})
	case "$rs" in
		"M "*) die "You have local modifications in packages/${src[$I]} file.\nCommit it first." ;;
	esac
done

#
# Check working revisions of src files
#

msg "Checking revisions."
for I in 0 1 2 3; do
	rev[$I]=$(cvs stat ${src[$I]} \
		| sed -ne 's/^[[:blank:]]*Working revision:[[:blank:]]*\([[:digit:]]\.[[:digit:]]\+\).*/\1/p')
done

>/dev/null cd -

#
# Check wich dst files need updating, update them and prepare msglog
#

LOG=""
msg "Checking wich files need update."
for I in 0 1 2 3; do
	if [ "$(diff -q ../${src[$I]} ${dst[$I]})" ]; then
	  cat ../${src[$I]} > ${dst[$I]}
		LOG="$LOG- ${dst[$I]} up to ${rev[$I]}\n"
	fi
done

[ "$LOG" ] || die "Nothing to update!"

minor_ver=$(sed -n 's/^\Version:.*\.\([[:digit:]]\+\)/\1/p' rpm-build-tools.spec)
minor_ver=$(($minor_ver + 1))
sed -i 's/^\(Version:.*\.\)\([[:digit:]]\+\)$/\1'$minor_ver'/' rpm-build-tools.spec
sed -i 's/^Release:.*$/Release:	1/' rpm-build-tools.spec
ver=$(sed -n 's/^\Version:[[:blank:]]\(.*\)$/\1/p' rpm-build-tools.spec)
LOG="- up to $ver\n$LOG"

#
# Show changes and ask user for confirmation.
#

cvs di -u | diffcol | ${PAGER:-'less -r'}

printf "Commit log:\n$LOG\nCommit (Yes, No)? "
read ans
case "$ans" in
	[yY])
		cvs ci -m "$(printf $LOG)" ${dst[0]} ${dst[1]} ${dst[2]} ${dst[3]} ;;
	*)
		msg ":(" ;;
esac

# vim: tabstop=2