#!/bin/awk -f
#
# This is adapter v0.1. Adapter adapts .spec files for PLD.
# Copyright (C) 1999 Micha³ Kuratczyk <kura@pld.org.pl>

BEGIN {
	preamble = 1;
	BOF = 1;	# Beggining of file
	BOC = 2;	# Beggining of %changelog
}

# There should be a comment with CVS keywords on the first line of file.
BOF == 1 {
	if (!/# \$Revision:/)
		 print "# $Revision$, $Date$";
	BOF = 0;
}

# descriptions:
/%description/, (/^%[a-z]+/ && !/%description/) {
	preamble = 0;

	# I have not idea what to put here, but it is possible that some
	# descriptions contain lines with "Word:" on the beggining of line,
	# so for %descriptions preamble is zero.
}

# %prep section:
/%prep/, (/^%[a-z]+$/ && !/%prep/) {
	preamble = 0;
	
	# add '-q' to %setup
	if (/%setup/ && !/-q/)
		sub(/%setup/, "%setup -q");
}

# %build section:
/%build/, (/^%[a-z]+$/ && !/%build/) {
	preamble = 0;

	# Any ideas?
}

# %install section:
/%install/, (/^[a-z]+$/ && !/%install/) {
	preamble = 0;
	
	# 'install -d' instead 'mkdir -p'
	if (/mkdir -p/)
		sub(/mkdir -p/, "install -d");
		
	# no '-m', '-u' or '-g' for 'install'
	if (/^install/ && /-[mug][ \t]*[a-z0-7]+/)
		gsub(/-[mug][ \t]*[a-z0-7]+/, "\b");
	
	# no lines contain either of 'chmod', 'chown' or 'chgrp'
	if ($1 ~ /chmod|chown|chgrp/)
		noprint = 1;
	
	# 'gzip -9nf' for compressing
	if ($1 ~ /gzip|bzip2/) {
		if ($2 ~ /^-/)
			sub($2, "\b");
		sub($1, "gzip -9nf");
	}
}

# %files section:
/%files/, (/^%[a-z]+$/ && !/%files/) {
	preamble = 0;
	
	if (/%defattr/)
		$0 = "%defattr(644,root,root,755)";
}

# %changelog section:
/%changelog/, (/^%[a-z]+$/ && !/%changelog/) {
	preamble = 0;
	
	# There should be some CVS keywords on the first line of %changelog.
	if (BOC == 1) {
		if (!/PLD Team/) {
			print "* %{date} PLD Team <pld-list@pld.org.pl>";
			printf "All below listed persons can be reached on";
			print "<_login>@pld.org.pl\n"
		}
		BOC = 0;
	}
	
	if (BOC == 2)
		BOC--;
}

# preambles:
preamble == 1 {
	if (tolower($1) ~ /buildroot:/)
		$2 = "/tmp/%{name}-%{version}-root";
	
	# There should not be a space after the name of field and before the
	# colon, but there should be one or two tabs after the colon.
	sub(/[ \t]*:/, ":");
	sub(/:[ \t]*/, ":");
	if (match($0, /[#A-Z][A-Za-z0-9()]+[ \t]*:[ \t]*/) == 1) {
		if (RLENGTH < 8)
			sub(/:/, ":\t\t");
		else
			sub(/:/, ":\t");
	}
}


# If redundant_line is zero, print this line, otherwise do not print,
# but set the redundant_line to 0.
{
	preamble = 1;
	if (noprint == 0)
		print;
	else
		noprint = 0;
}

