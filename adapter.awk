#!/bin/awk -f
#
# This is adapter v1.0. Adapter adapts .spec files for PLD.
# Copyright (C) 1999 Micha³ Kuratczyk <kura@pld.org.pl>

BEGIN {
	preamble = 1;
	boc = 2;			# Beggining of %changelog
	bod = 0;			# Beggining of %description
	tw = 77;        		# Descriptions width
	groups_file = ENVIRON["HOME"] "/rpm/groups" # File with rpm groups
	
	# Is 'date' macro already defined?
	if (is_there_line("%define date"))
		date = 1;
	
	"rpm --eval %_prefix"	| getline prefix
	"rpm --eval %_bindir"	| getline bindir
	"rpm --eval %_sbindir"	| getline sbindir
	"rpm --eval %_libdir"	| getline libdir
	"rpm --eval %_sysconfdir" | getline sysconfdir
	"rpm --eval %_datadir"	| getline datadir
	"rpm --eval %_includedir" | getline includedir
	"rpm --eval %_mandir"	| getline mandir
	"rpm --eval %_infodir"	| getline infodir
}

# There should be a comment with CVS keywords on the first line of file.
FNR == 1 {
	if (!/# \$Revision:/)		# If this line is already OK?
		print "# $" "Revision:$, " "$" "Date:$";	# No
	else {
		print $0;						# Yes
		next;				# It is enough for first line
	}
}

# If the latest line matched /%files/
defattr == 1 {
	if ($0 !~ /defattr/)	# If no %defattr
		print "%defattr(644,root,root,755)";	# Add it
	else
		$0 = "%defattr(644,root,root,755)";	# Correct mistakes (if any)
	defattr = 0;
}

# descriptions:
/%description/, (/^%[a-z]+/ && !/%description/) {
	preamble = 0;

	if (/^%description/)
		bod++;
	
	# Define _prefix and _mandir if it is X11 application
	if (/^%description$/ && x11 == 1) {
		print "%define\t\t_prefix\t\t/usr/X11R6";
		print "%define\t\t_mandir\t\t%{_prefix}/man\n";
		prefix = "/usr/X11R6";
		x11 = 2;
	}

        # Collect whole text of description
	if (description == 1 && !/^%[a-z]+/ && !/%description/) {
		description_text = description_text $0 " ";
		next;
	}
 
	# Formt description to the length of tw (default == 77)
	if (/^%[a-z]+/ && (!/%description/ || bod == 2)) {
		n = split(description_text, dt, / /);
		for (i = 1; i <= n; i++) {
			if (length(line) + length(dt[i]) + 1 < tw)
				line = line dt[i] " ";
			else {
				sub(/[ ]+$/, "", line);
				print line;
				line = "";
				i--;
			}
		}

		sub(/[ ]+$/, "", line);
		print line "\n";
		line = "";
		delete dt;
		description_text = "";
		if (bod == 2) {
			bod = 1;
			description = 1;
		} else {
			bod = 0;
			description = 0;
		}
	} else
		description = 1;
}

# %prep section:
/%prep/, (/^%[a-z]+$/ && !/%prep/) {
	preamble = 0;
	
	# Add '-q' to %setup
	if (/%setup/ && !/-q/)
		sub(/%setup/, "%setup -q");
}

# %build section:
/%build/, (/^%[a-z]+$/ && !/%build/) {
	preamble = 0;

	use_macros();
}

# %install section:
/%install/, (/^[a-z]+$/ && !/%install/) {
	preamble = 0;
	
	use_macros();

	# 'install -d' instead 'mkdir -p'
	if (/mkdir -p/)
		sub(/mkdir -p/, "install -d");
		
	# No '-u root' or '-g root' for 'install'
	if (/^install/ && /-[ug][ \t]*root/)
		gsub(/-[ug][ \t]*root /, "");
	
	if (/^install/ && /-m[ \t]*644/)
		gsub(/-m[ \t]*644 /, "");
	
	# No lines contain 'chown' or 'chgrp', which changes
	# owner/group to 'root'
	if (($1 ~ /chown/ && $2 ~ /root\.root/) || ($1 ~ /chgrp/ && $2 ~ /root/))
		next;
	
	# No lines contain 'chmod' if it sets the modes to '644'
	if ($1 ~ /chmod/ && $2 ~ /644/)
		next;
	
	# 'gzip -9nf' for compressing
	if ($1 ~ /gzip|bzip2/) {
		if ($2 ~ /^-/)
			sub(/-[A-Za-z0-9]+ /, "", $0);
		sub($1, "gzip -9nf");
	}
}

# %files section:
/%files/, (/^%[a-z \-]+$/ && !/%files/) {
	preamble = 0;
	
	if ($0 ~ /%files/)
		defattr = 1;
	
	use_macros();
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
	if (boc == 2) {
		if (date == 0) {
			printf "%%define date\t%%(echo `LC_ALL=\"C\"";
			print " date +\"%a %b %d %Y\"`)"
		}
	boc--;
	}
}

# preambles:
preamble == 1 {
	# There should not be a space after the name of field
	# and before the colon.
	sub(/[ \t]*:/, ":");
	
	field = tolower($1);

	if (field ~ /packager:|distribution:|prefix:|vendor:/)
		next;
	
	if (field ~ /buildroot:/)
		$2 = "/tmp/%{name}-%{version}-root";

	if (field ~ /group:/) {
		format_preamble();
		print $0;
		
		translate_group($2);
		close(groups_file);
		
		if ($2 ~ /^X11/ && x11 == 0)	# Is it X11 application?
		       x11 = 1;

		next;	# Line is already formatted and printed
	}
		
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

	format_preamble();
	
	if ($1 ~ /%define/) {
		# Do not add %define of _prefix if it already is.
	       	if ($2 ~ /_prefix/) {
			prefix = $3;
			x11 = 2;
		}
		if ($2 ~ /_bindir/ && !/_sbindir/)
			bindir = $3;
		if ($2 ~ /_sbindir/)
			sbindir = $3;
		if ($2 ~ /_libdir/)
			libdir = $3;
		if ($2 ~ /_sysconfdir/)
			sysconfdir = $3;
		if ($2 ~ /_datadir/)
			datadir = $3;
		if ($2 ~ /_includedir/)
			includedir = $3;
		if ($2 ~ /_mandir/)
			mandir = $3;
		if ($2 ~ /_infodir/)
			infodir = $3;
	}
}

{
	preamble = 1;
	
	print;
}

END {
	if (boc == 1) {
		print "* %{date} PLD Team <pld-list@pld.org.pl>";
		printf "All below listed persons can be reached on ";
		print "<cvs_login>@pld.org.pl\n";
		print "$" "Log:$";
	}
}

# This function uses grep to determine if there is line (in the current file)
# which matches regexp.
function is_there_line(line, l)
{
	command = "grep \"" line "\" " ARGV[1];
	command	| getline l;
	close(ARGV[1]);

	if (l != "")
		return 1;
	else
		return 0;
}

# This function prints translated names of groups.
function translate_group(group)
{
	for(;;) {
		result = getline line < groups_file;
		
		if (result == -1) {
			print "######\t\t" groups_file ": no such file";
			return;
		}

		if (result == 0) {
			print "######\t\t" "Unknown group!";
			return;
		}
		
		if (line ~ group) {
			found = 1;
			continue;
		}

		if (found == 1)
			if (line ~ /\[[a-z][a-z]\]:/) {
				split(line, g, /\[|\]|\:/);
				if (!is_there_line("^Group(" g[2] "):"))
						printf("Group(%s):%s\n", g[2], g[4]);
			} else {
				found = 0;
				return;
			}
	}
}

# There should be one or two tabs after the colon.
function format_preamble()
{
	sub(/:[ \t]*/, ":");
	if (match($0, /[A-Za-z0-9()# \t]+[ \t]*:[ \t]*/) == 1) {
		if (RLENGTH < 8)
			sub(/:/, ":\t\t");
		else
			sub(/:/, ":\t");
	}
}

# Replace directly specified directories with macros
function use_macros()
{
	gsub(bindir, "%{_bindir}");
	gsub(sbindir, "%{_sbindir}");
	gsub(libdir, "%{_libdir}");
	gsub(sysconfdir, "%{_sysconfdir}");
	gsub(datadir, "%{_datadir}");
	gsub(includedir, "%{_includedir}");
	gsub(mandir, "%{_mandir}");
	gsub(infodir, "%{_infodir}");
	gsub(prefix, "%{_prefix}");
}

