#!/bin/awk -f
#
# This is adapter v0.6. Adapter adapts .spec files for PLD.
# Copyright (C) 1999 Micha� Kuratczyk <kura@pld.org.pl>

BEGIN {
	preamble = 1;
	bof = 1;	# Beggining of file
	boc = 2;	# Beggining of %changelog
}

# There should be a comment with CVS keywords on the first line of file.
bof == 1 {
	if (!/# \$Revision:/)
		 print "# $" "Revision:$, " "$" "Date:$";
	bof = 0;
}

# descriptions:
/%description/, (/^%[a-z]+/ && !/%description/) {
	preamble = 0;
	
	# Define _prefix and _mandir if it is X11 application
	if (/^%description$/ && x11 == 1) {
		print "%define\t\t_prefix\t\t/usr/X11R6";
		print "%define\t\t_mandir\t\t%{_prefix}/man\n";
		x11 == 2;
	}
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
		
	# no '-u root' or '-g root' for 'install'
	if (/^install/ && /-[ug][ \t]*root/)
		gsub(/-[ug][ \t]*root /, "");
	
	if (/^install/ && /-m[ \t]*644/)
		gsub(/-m[ \t]*644 /, "");
	
	# no lines contain 'chown' or 'chgrp', which changes
	# owner/group to 'root'
	if ($1 ~ /chown|chgrp/ && $2 ~ /root|root.root/)
		noprint = 1;
	
	# no lines contain 'chmod' if it sets the modes to '644'
	if ($1 ~ /chmod/ && $2 ~ /644/)
		noprint = 1;
	
	# 'gzip -9nf' for compressing
	if ($1 ~ /gzip|bzip2/) {
		if ($2 ~ /^-/)
			sub(/-[A-Za-z0-9]+ /, "", $0);
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
	if (boc == 1) {
		if (!/PLD Team/) {
			print "* %{date} PLD Team <pld-list@pld.org.pl>";
			printf "All below listed persons can be reached on ";
			print "<cvs_login>@pld.org.pl\n";
			print "$" "Log:$";
		}
		boc = 0;
	}
	
	# Define date macro.
	if (boc == 2 && date == 0) {
		printf "%%define date\t%%(echo `LC_ALL=\"C\"";
	       	print " date +\"%a %b %d %Y\"`)"
		boc--;
	}
}

# preambles:
preamble == 1 {
	# There should not be a space after the name of field
	# and before the colon.
	sub(/[ \t]*:/, ":");
	
	field = tolower($1);

	if (field ~ /packager:|distribution:|prefix:/)
		next;
	
	if (field ~ /buildroot:/)
		$2 = "/tmp/%{name}-%{version}-root";

	# Is it X11 application?
	if (field ~ /group/ && $2 ~ /^X11/ && x11 == 0)
		x11 = 1;
		
	# Use "License" instead of "Copyright" if it is (L)GPL or BSD
	if (field ~ /copyright:/ && $2 ~ /GPL|BSD/)
		$1 = "License:";
	
	if (field ~ /name:/)
		name = $2;

	if (field ~ /version:/)
		version = $2;

	# Use %{name} and %{version} in the filenames in "Source:"
	if (field ~ /source/ && $2 ~ /^ftp:|^http:/) {
		n = split($2, url, /\//);
		filename = url[n];
		sub(name, "%{name}", url[n]);
		sub(version, "%{version}", url[n]);
		sub(filename, url[n], $2);
	}
		
	# There should be one or two tabs after the colon.
	sub(/:[ \t]*/, ":");
	if (match($0, /[A-Za-z0-9()# \t]+[ \t]*:[ \t]*/) == 1) {
		if (RLENGTH < 8)
			sub(/:/, ":\t\t");
		else
			sub(/:/, ":\t");
	}
	
	# Do not add %define of _prefix if it already is.
	if ($1 ~ /%define/ && $2 ~ /_prefix/)
		x11 = 2;
			
}


# If redundant_line is zero, print this line, otherwise do not print,
# but set the redundant_line to 0.
{
	preamble = 1;
	
	# Macro 'date' already defined.
	if (/%define date/)
		date = 1;
	
	if (noprint == 0)
		print;
	else
		noprint = 0;
}

