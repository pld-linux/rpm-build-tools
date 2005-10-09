#!/bin/awk -f
#
# This is adapter v0.27. Adapter adapts .spec files for PLD.
#
# Copyright (C) 1999-2003 PLD-Team <feedback@pld-linux.org>
# Authors:
# 	Micha³ Kuratczyk <kura@pld.org.pl>
# 	Sebastian Zagrodzki <s.zagrodzki@mimuw.edu.pl>
# 	Tomasz K³oczko <kloczek@rudy.mif.pg.gda.pl>
# 	Artur Frysiak <wiget@pld-linux.org>
# 	Michal Kochanowicz <mkochano@pld.org.pl>
# 	Elan Ruusamäe <glen@pld-linux.org>
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# TODO
# - parse ../PLD-doc/BuildRequires.txt and setup proper BR epoches?
# - add "-nc" option to skip CVS interaction
# - sort Summary(XX)
# - sort Requires, BuildRequires

BEGIN {
	preamble = 1		# Is it part of preamble? Default - yes
	boc = 4			# Beggining of %changelog
	bod = 0			# Beggining of %description
	tw = 70			# Descriptions width

	b_idx = 0		# index of BR/R arrays

	# If variable removed, then 1 (for removing it from export)
	removed["LDFLAGS"] = 0
	removed["CFLAGS"] = 0
	removed["CXXFLAGS"] = 0

	# get cvsaddress for changelog section
	# using rpm macros as too lazy to add ~/.adapterrc parsing support.
	"rpm --eval '%{?_cvsmaildomain}%{!?_cvsmaildomain:@pld-linux.org}'" | getline _cvsmaildomain
	"rpm --eval '%{?_cvsmailfeedback}%{!?_cvsmailfeedback:PLD Team <feedback@pld-linux.org>}'" | getline _cvsmailfeedback

	# If 1, we are inside of comment block (started with /^#%/)
	comment_block = 0

	# File with rpm groups
	"rpm --eval %_sourcedir" | getline groups_file
	groups_file = groups_file "/rpm.groups"
	system("cd `rpm --eval %_sourcedir`; cvs up rpm.groups >/dev/null")

	# Temporary file for changelog section
	changelog_file = ENVIRON["HOME"] "/tmp/adapter.changelog"

	# Load rpm macros
	"rpm --eval %_prefix"	| getline prefix
	"rpm --eval %_bindir"	| getline bindir
	"rpm --eval %_sbindir"	| getline sbindir
	"rpm --eval %_libdir"	| getline libdir
	"rpm --eval %_sysconfdir" | getline sysconfdir
	"rpm --eval %_datadir"	| getline datadir
	"rpm --eval %_includedir" | getline includedir
	"rpm --eval %_mandir"	| getline mandir
	"rpm --eval %_infodir"	| getline infodir
	"rpm --eval %_examplesdir"	| getline examplesdir

	"rpm --eval %perl_sitearch" | getline perl_sitearch
	"rpm --eval %perl_archlib" | getline perl_archlib
	"rpm --eval %perl_privlib" | getline perl_privlib
	"rpm --eval %perl_vendorlib" | getline perl_vendorlib
	"rpm --eval %perl_vendorarch" | getline perl_vendorarch
	"rpm --eval %perl_sitelib" | getline perl_sitelib

	"rpm --eval %py_sitescriptdir" | getline py_sitescriptdir
}

# There should be a comment with CVS keywords on the first line of file.
FNR == 1 {
	if (!/# \$Revision:/)	# If this line is already OK?
		print "# $" "Revision:$, " "$" "Date:$"	# No
	else {
		print $0				# Yes
		next		# It is enough for first line
	}
}

# If the latest line matched /%files/
defattr == 1 {
	if ($0 !~ /defattr/)	# If no %defattr
		print "%defattr(644,root,root,755)"	# Add it
	else
		$0 = "%defattr(644,root,root,755)"	# Correct mistakes (if any)
	defattr = 0
}

function b_makekey(a, b,	s) {
	s = a "" b;
	# kill bcond
	gsub("%{\\?[_a-zA-Z0-9]+:", "", s);
	return s;
}

# sort BR/R!
#
# NOTES:
# - mixing BR/R and anything else confuses this (all will be sorted together)
#   so don't do that.
# - comments leading the BR/R can not be associated,
#   so don't adapterize when the BR/R are mixed with comments
ENVIRON["SORTBR"] == 1 && preamble == 1 && /(Build)?Requires/, /(Build)?Requires/ { # && !/^%/) {
	b_idx++;
	l = substr($0, index($0, $2));
	b_ktmp = b_makekey($1, l);
	b_key[b_idx] = b_ktmp;
	b_val[b_ktmp] = $0;

	next;
}

/^%bcond_/ {
	# do nothing
	print
	next
}

preamble == 1 {
	if (b_idx > 0) {
		isort(b_key, b_idx);
		for (i = 1; i <= b_idx; i++) {
			print "" b_val[b_key[i]];
		}
		b_idx = 0
	}
}

# Comments
/^#/ && (description == 0) {
	if (/This file does not like to be adapterized!/) {
		print			# print this message
		while (getline)		# print the rest of spec as it is
			print
		do_not_touch_anything = 1 # do not touch anything in END()
		exit 0
	}

	# Generally, comments are printed without touching
	sub(/[ \t]+$/, "")
	print $0
	next
}

# Remove defining _applnkdir (this macro has been included in rpm-3.0.4)
/^%define/ {
	if ($2 == "_applnkdir")
		next
	if ($2 == "date")
		date = 1
}

# Obsolete
/^%include.*\/usr\/lib\/rpm\/macros\.python$/ {
	next
}

################
# %description #
################
/^%description/, (/^%[a-z]+/ && !/^%description/ && !/^%((end)?if|else)/) {
	preamble = 0

	if (/^%description/) {
		bod++
		format_line = ""
		format_indent = -1
	}

	# Format description
	if (description == 1 && !/^%[a-z]+/ && !/^%description/) {
		if (/^[ \t]*$/) {
			format_flush(format_line, format_indent)
			print ""
			format_line = ""
			format_indent = -1
		} else if (/^[ \t]*[-\*][ \t]*/) {
			format_flush(format_line, format_indent)
			match($0, /^[ \t]*/)
			format_indent = RLENGTH
			match($0, /^[ \t]*[-\*][ \t]/)
			format_line = substr($0, RLENGTH)
		} else
			format_line = format_line " " $0
		next
	}

	if (/^%[a-z]+/ && (!/^%description/ || bod == 2)) {
		if (NF > 3 && $2 == "-l") {
			ll = $1
			for (i = 4; i <= NF; i++)
				ll = ll " " $i
			$0 = ll " -l " $3
		}
		format_flush(format_line, format_indent)
		if (bod == 2) {
			bod = 1
			description = 1
		} else {
			bod = 0
			description = 0
		}
	} else
		description = 1
}

#########
# %prep #
#########
/^%prep/, (/^%[a-z]+$/ && !/^%prep/ && !/^%((end)?if|else)/) {
	preamble = 0

	use_macros()

	# Add '-q' to %setup
	if (/^%setup/ && !/-q/) {
		sub(/^%setup/, "%setup -q")
	}

	if (/^%setup/) {
		gsub(name, "%{name}");
		gsub(version, "%{version}");
		if (_beta) {
			gsub(_beta, "%{_beta}");
		}
		if (_rc) {
			gsub(_rc, "%{_rc}");
		}
		if (_snap) {
			gsub(_snap, "%{_snap}");
		}
	}

	if (/^%setup/ && /-n %{name}-%{version}( |$)/) {
		sub(/ -n %{name}-%{version}/, "")
	}

	# invalid in %prep
	sub("^rm -rf \$RPM_BUILD_ROOT.*", "");
}

##########
# %build #
##########
/^%build/, (/^%[a-z]+$/ && !/^%build/ && !/^%((end)?if|else)/) {
	preamble = 0

	use_macros()

	if (/^automake$/)
		sub(/$/, " -a -c")

	if (/LDFLAGS/) {
		if (/LDFLAGS="-s"/) {
			removed["LDFLAGS"] = 1
			next
		} else {
			split($0, tmp, "LDFLAGS=")
			count = split(tmp[2], flags, "\"")
			if (flags[1] != "" && flags[1] !~ "!?debug") {
				sub(/-s[" ]?/, "%{rpmldflags} ", flags[1])
				$0 = tmp[1] line[1] "LDFLAGS=" flags[1] "\""
				for (i = 2; i < count; i++)
					$0 = $0 flags[i] "\""
			}
		}
	}

	if (/CFLAGS=/)
		if (cflags("CFLAGS") == 0)
			next

	if (/CXXFLAGS=/)
		if (cflags("CXXFLAGS") == 0)
			next

	if (/^export /) {
		if (removed["LDFLAGS"])
			sub(" LDFLAGS", "")
		if (removed["CFLAGS"])
			sub(" CFLAGS", "")
		if (removed["CXXFLAGS"])
			sub(" CXXFLAGS", "")
		# Is there still something?
		if (/^export[ ]*$/)
			next
	}
	
	# use macros
	$0 = fixedsub("glib-gettextize --copy --force","%{__glib_gettextize}", $0);
	$0 = fixedsub("intltoolize --copy --force", "%{__intltoolize}", $0);

	# atrpms
	$0 = fixedsub("%perl_configure", "%{__perl} Makefile.PL \\\n\tINSTALLDIRS=vendor", $0);
	$0 = fixedsub("%perl_makecheck", "%{?with_tests:%{__make} test}", $0);
}

##########
# %clean #
##########
/^%clean/, (/^%[a-z]+$/ && !/^%clean/ && !/^%((end)?if|else)/) {
	did_clean = 1
	use_macros()
}

############
# %install #
############
/^%install/, (/^%[a-z]+$/ && !/^%install/ && !/^%((end)?if|else)/) {

	preamble = 0

	if (/^[ \t]*rm([ \t]+-[rf]+)*[ \t]+\${?RPM_BUILD_ROOT}?/ && did_rmroot==0) {
		did_rmroot=1
		print "rm -rf $RPM_BUILD_ROOT"
		next
	}

	if (!/^(#?[ \t]*)$/ && !/^%install/ && did_rmroot==0) {
		print "rm -rf $RPM_BUILD_ROOT"
		did_rmroot=1
	}

	use_macros()

	# 'install -d' instead 'mkdir -p'
	if (/mkdir -p/)
		sub(/mkdir -p/, "install -d")

	# 'install' instead 'cp -p'
	if (/cp -p\b/)
		sub(/cp -p/, "install")

	# No '-u root' or '-g root' for 'install'
	if (/^install/ && /-[ug][ \t]*root/)
		gsub(/-[ug][ \t]*root /, "")

	if (/^install/ && /-m[ \t]*[0-9]+/)
		gsub(/-m[ \t]*[0-9]+ /, "")

	# No lines contain 'chown' or 'chgrp' if owner/group is 'root'
	if (($1 ~ /chown/ && $2 ~ /root\.root/) || ($1 ~ /chgrp/ && $2 ~ /root/))
		next

	# No lines contain 'chmod' if it sets the modes to '644'
	if ($1 ~ /chmod/ && $2 ~ /644/)
		next

	# foreign rpms
	$0 = fixedsub("%buildroot", "$RPM_BUILD_ROOT", $0)
	$0 = fixedsub("%{buildroot}", "$RPM_BUILD_ROOT", $0)

	# atrpms
	$0 = fixedsub("%perl_makeinstall", "%{__make} pure_install \\\n\tDESTDIR=$RPM_BUILD_ROOT", $0);
}

##########
# %files #
##########
/^%files/, (/^%[a-z \-]+$/ && !/^%files/ && !/^%((end)?if|else)/) {
	preamble = 0

	if ($0 ~ /^%files/)
		defattr = 1

	use_macros()
	use_files_macros()
}

##############
# %changelog #
##############
/^%changelog/, (/^%[a-z]+$/ && !/^%changelog/) {
	preamble = 0
	has_changelog = 1
	skip = 0
	# There should be some CVS keywords on the first line of %changelog.
	if (boc == 3) {
		if ($0 !~ _cvsmailfeedback)
			print "* %{date} " _cvsmailfeedback > changelog_file
		else
			skip = 1
		boc = 2
	}
	if (boc == 2 && !skip) {
		if (!/All persons listed below/) {
			printf "All persons listed below can be reached at " > changelog_file
			print "<cvs_login>" _cvsmaildomain "\n" > changelog_file
		} else
			skip = 1
		boc = 1
	}
	if (boc == 1 && !skip) {
		if (!/^$/) {
			if (!/\$.*Log:.*\$/)
				print "$" "Log:$" > changelog_file
			boc = 0
		}
	}
	# Define date macro.
	if (boc == 4) {
		if (date == 0) {
			printf "%%define date\t%%(echo `LC_ALL=\"C\"" > changelog_file
			print " date +\"%a %b %d %Y\"`)" > changelog_file
			date = 1
		}
		boc = 3
	}

	sub(/[ \t]+$/, "")
	if (!/^%[a-z]+$/ || /changelog/)
		print > changelog_file
	else
		print
	next
}

###########
# SCRIPTS #
###########
/^%pre/, (/^%[a-z]+$/ && !/^%pre/) {
	preamble = 0

	# %useradd and %groupadd may not be wrapped
	if (/%(useradd|groupadd).*\\$/) {
		a = $0; getline;
		sub(/^[\s\t]*/, "");
		$0 = substr(a, 1, length(a) - 1) $0;
	}
}

/^%post/, (/^%[a-z]+$/ && !/^%post/) {
	preamble = 0
}
/^%preun/, (/^%[a-z]+$/ && !/^%preun/) {
	preamble = 0
}
/^%postun/, (/^%[a-z]+$/ && !/^%postun/) {
	preamble = 0
}
/^%triggerin/, (/^%[a-z]+$/ && !/^%triggerin/) {
	preamble = 0
}
/^%triggerun/, (/^%[a-z]+$/ && !/^%triggerun/) {
	preamble = 0
}
/^%triggerpostun/, (/^%[a-z]+$/ && !/^%triggerpostun/) {
	preamble = 0
}
/^%pretrans/, (/^%[a-z]+$/ && !/^%pretrans/) {
	preamble = 0
}
/^%posttrans/, (/^%[a-z]+$/ && !/^%posttrans/) {
	preamble = 0
}

#############
# PREAMBLES #
#############
preamble == 1 {
	# There should not be a space after the name of field
	# and before the colon.
	sub(/[ \t]*:/, ":")

	if (/^%perl_module_wo_prefix/) {
		name = $2
		version = $3
		release = "0." fixedsub(".%{disttag}.at", "", $4)
	}

	field = tolower($1)
	fieldnlower = $1
	if (field ~ /group(\([^)]+\)):/)
		next
	if (field ~ /group:/) {
		format_preamble()
		sub(/^Utilities\//,"Applications/",$2)
		sub(/^Games/,"Applications/Games",$2)
		sub(/^X11\/Games/,"X11/Applications/Games",$2)
		sub(/^X11\/GNOME\/Development\/Libraries/,"X11/Development/Libraries",$2)
		sub(/^X11\/GNOME\/Applications/,"X11/Applications",$2)
		sub(/^X11\/GNOME/,"X11/Applications",$2)
		sub(/^X11\/Utilities/,"X11/Applications",$2)
		sub(/^X11\/Games\/Strategy/,"X11/Applications/Games/Strategy",$2)
		sub(/^Shells/,"Applications/Shells",$2)

		sub(/^[^ \t]*[ \t]*/,"")
		Grupa = $0

		print "Group:\t\t" Grupa
		if (Grupa ~ /^X11/ && x11 == 0)	# Is it X11 application?
			x11 = 1

		byl_plik_z_grupami = 0
		byl_opis_grupy = 0
		while ((getline linia_grup < groups_file) > 0) {
			byl_plik_z_grupami = 1
			if (linia_grup == Grupa) {
				byl_opis_grupy = 1
				break
			}
		}

		if (!byl_plik_z_grupami)
			print "######\t\t" groups_file ": no such file"
		else if (!byl_opis_grupy)
			print "######\t\t" "Unknown group!"

		close(groups_file)
		next
	}

	if (field ~ /prereq:/) {
		$1 = "Requires:"
		$(NF + 1) = " # FIXME add Requires(scriptlet) -adapter.awk"
	}

	# split (build)requires on commas
	if (field ~ /requires:/ && $0 ~ /,/) {
		l = substr($0, index($0, $2));
		n = split(l, p, / *, */);
		for (i in p) {
			printf("%s\t%s\n", $1, p[i]);
		}
		next;
	}

	if (field ~ /packager:|distribution:|docdir:|prefix:/)
		next

	if (field ~ /buildroot:/)
		$0 = $1 "%{tmpdir}/%{name}-%{version}-root-%(id -u -n)"

	# Use "License" instead of "Copyright" if it is (L)GPL or BSD
	if (field ~ /copyright:/ && $2 ~ /GPL|BSD/)
		$1 = "License:"

	if (field ~ /name:/) {
		name = $2
		name_seen = 1;
	}

	if (field ~ /version:/) {
		version = $2
		version_seen = 1;
	}

	if (field ~ /release:/) {
		release = $2
		release_seen = 1;
	}

	if (field ~ /serial:/)
		$1 = "Epoch:"

	# Use %{name} and %{version} in the filenames in "Source:"
	if (field ~ /^source/ || field ~ /patch/) {
		n = split($2, url, /\//)
		if (url[n] ~ /\.gz$/) {
			url[n+1] = ".gz" url[n+1]
			sub(/\.gz$/,"",url[n])
		}
		if (url[n] ~ /\.zip$/) {
			url[n+1] = ".zip" url[n+1]
			sub(/\.zip$/,"",url[n])
		}
		if (url[n] ~ /\.tar$/) {
			url[n+1] = ".tar" url[n+1]
			sub(/\.tar$/,"",url[n])
		}
		if (url[n] ~ /\.patch$/) {
			url[n+1] = ".patch" url[n+1]
			sub(/\.patch$/,"",url[n])
		}
		if (url[n] ~ /\.bz2$/) {
			url[n+1] = ".bz2" url[n+1]
			sub(/\.bz2$/,"",url[n])
		}
		if (url[n] ~ /\.logrotate$/) {
			url[n+1] = ".logrotate" url[n+1]
			sub(/\.logrotate$/,"",url[n])
		}
		if (url[n] ~ /\.pamd$/) {
			url[n+1] = ".pamd" url[n+1]
			sub(/\.pamd$/,"",url[n])
		}

		# allow %{name} just in last url component
		s = ""
		for (i = 1; i <= n; i++) {
			url[i] = fixedsub("%{name}", name, url[i])
			if (s) {
				s = s "/" url[i]
			} else {
				s = url[i]
			}
		}
		$2 = s url[n+1]

		filename = url[n]
		if (name) {
			url[n] = fixedsub(name, "%{name}", url[n])
		}
		if (field ~ /source/) {
			if (version) {
				url[n] = fixedsub(version, "%{version}", url[n])
			}
			if (_beta) {
				url[n] = fixedsub(_beta, "%{_beta}", url[n])
			}
			if (_rc) {
				url[n] = fixedsub(_rc, "%{_rc}", url[n])
			}
			if (_snap) {
				url[n] = fixedsub(_snap, "%{_snap}", url[n])
			}
		}
		$2 = fixedsub(filename, url[n], $2)

		# sourceforge urls
		sub("[?]use_mirror=.*$", "", $2);
		sub("[?]download$", "", $2);
		sub("^http://prdownloads\.sourceforge\.net/", "http://dl.sourceforge.net/", $2)

		sub("^http://.*\.dl\.sourceforge\.net/", "http://dl.sourceforge.net/", $2)
		sub("^http://dl\.sourceforge\.net/sourceforge/", "http://dl.sourceforge.net/", $2)
		sub("^http://dl\.sf\.net/", "http://dl.sourceforge.net/", $2)
	}


	if (field ~ /^source:/)
		$1 = "Source0:"

	if (field ~ /patch:/)
		$1 = "Patch0:"

	format_preamble()

	if ($1 ~ /%define/) {
		# Do not add %define of _prefix if it already is.
		if ($2 ~ /^_prefix/) {
			sub("^"prefix, $3, bindir)
			sub("^"prefix, $3, sbindir)
			sub("^"prefix, $3, libdir)
			sub("^"prefix, $3, datadir)
			sub("^"prefix, $3, includedir)
			prefix = $3
		}
		if ($2 ~ /_bindir/ && !/_sbindir/)
			bindir = $3
		if ($2 ~ /_sbindir/)
			sbindir = $3
		if ($2 ~ /_libdir/)
			libdir = $3
		if ($2 ~ /_sysconfdir/ && $3 !~ /^%\(/)
			sysconfdir = $3
		if ($2 ~ /_datadir/)
			datadir = $3
		if ($2 ~ /_includedir/)
			includedir = $3
		if ($2 ~ /_mandir/)
			mandir = $3
		if ($2 ~ /_infodir/)
			infodir = $3

		if ($2 ~ /_beta/)
			_beta = $3
		if ($2 ~ /_rc/)
			_rc = $3
		if ($2 ~ /_snap/)
			_snap = $3
	}

	if (field ~ /requires/) {
		# atrpms
		$0 = fixedsub("%{eversion}", "%{epoch}:%{version}-%{release}", $0);
	}
}

# main() ;-)
{
	preamble = 1

	sub(/[ \t]+$/, "")
	print

	if (name_seen == 0 && name) {
		print "Name:\t" name
		name_seen = 1
	}

	if (version_seen == 0 && version) {
		print "Version:\t" version
		version_seen = 1
	}

	if (release_seen == 0 && release) {
		print "Release:\t" release
		release_seen = 1
	}
}


END {
	if (do_not_touch_anything)
		exit 0

	close(changelog_file)
	while ((getline < changelog_file) > 0)
		print
	system("rm -f " changelog_file)



	if (did_clean == 0) {
		print ""
		print "%clean"
		print "rm -rf $RPM_BUILD_ROOT"
	}

	if (date == 0) {
		print ""
		print "%define date\t%(echo `LC_ALL=\"C\" date +\"%a %b %d %Y\"`)"
	}

	if (has_changelog == 0)
		print "%changelog"

	if (boc > 2)
		print "* %{date} PLD Team <feedback@pld-linux.org>"
	if (boc > 1) {
		printf "All persons listed below can be reached at "
		print "<cvs_login>@pld-linux.org\n"
	}
	if (boc > 0)
		print "$" "Log:$"
}

function fixedsub(s1,s2,t, ind) {
# substitutes fixed strings (not regexps)
	if (ind = index(t,s1))
		t = substr(t, 1, ind-1) s2 substr(t, ind+length(s1))
	return t
}

# There should be one or two tabs after the colon.
function format_preamble()
{
	sub(/:[ \t]*/, ":")
	if (match($0, /[A-Za-z0-9(),#_ \t]+[ \t]*:[ \t]*/) == 1) {
		if (RLENGTH < 8)
			sub(/:/, ":\t\t")
		else
			sub(/:/, ":\t")
	}
}

# Replace directly specified directories with macros
function use_macros()
{
	gsub(perl_sitearch, "%{perl_sitearch}")
	gsub(perl_archlib, "%{perl_archlib}")
	gsub(perl_privlib, "%{perl_privlib}")
	gsub(perl_vendorlib, "%{perl_vendorlib}")
	gsub(perl_vendorarch, "%{perl_vendorarch}")
	gsub(perl_sitelib, "%{perl_sitelib}")
	
	gsub(py_sitescriptdir, "%{py_sitescriptdir}")

	gsub(bindir, "%{_bindir}")
	gsub("%{prefix}/bin", "%{_bindir}")
	if(prefix"/bin" == bindir)
		gsub("%{_prefix}/bin", "%{_bindir}")

	for (c = 1; c <= NF; c++) {
		if ($c ~ sbindir "/fix-info-dir")
			continue;
		gsub(sbindir, "%{_sbindir}", $c)
	}

	gsub("%{prefix}/sbin", "%{_sbindir}")
	if (prefix"/sbin" == sbindir)
		gsub("%{_prefix}/sbin", "%{_sbindir}")

	for (c = 1; c <= NF; c++) {
		if ($c ~ sysconfdir "/{?cron.")
			continue;
		if ($c ~ sysconfdir "/{?crontab.d")
			continue;
		if ($c ~ sysconfdir "/{?logrotate.d")
			continue;
		if ($c ~ sysconfdir "/{?pam.d")
			continue;
		if ($c ~ sysconfdir "/{?profile.d")
			continue;
		if ($c ~ sysconfdir "/{?rc.d")
			continue;
		if ($c ~ sysconfdir "/{?security")
			continue;
		if ($c ~ sysconfdir "/{?skel")
			continue;
		if ($c ~ sysconfdir "/{?sysconfig")
			continue;
		if ($c ~ sysconfdir "/{?certs")
			continue;
		gsub(sysconfdir, "%{_sysconfdir}", $c)
	}

	for (c = 1; c <= NF; c++) {
		if ($c ~ datadir "/automake")
			continue;
		if ($c ~ datadir "/unsermake")
			continue;
		if ($c ~ datadir "/file/magic.mime")
			continue;
		gsub(datadir, "%{_datadir}", $c)
	}


	gsub("%{prefix}/share", "%{_datadir}")
	if (prefix"/share" == datadir)
		gsub("%{_prefix}/share", "%{_datadir}")

	gsub(includedir, "%{_includedir}")
	gsub("%{prefix}/include", "%{_includedir}")
	if (prefix"/include" == includedir)
		gsub("%{_prefix}/include", "%{_includedir}")

	gsub(mandir, "%{_mandir}")
	if ($0 !~ "%{_datadir}/manual")
		gsub("%{_datadir}/man", "%{_mandir}")
	gsub("%{_prefix}/share/man", "%{_mandir}")
	gsub("%{prefix}/share/man", "%{_mandir}")
	gsub("%{prefix}/man", "%{_mandir}")
	gsub("%{_prefix}/man", "%{_mandir}")

	gsub(infodir, "%{_infodir}")
	gsub("%{prefix}/info", "%{_infodir}")
	gsub("%{_prefix}/info", "%{_infodir}")

	if (prefix !~ "/X11R6") {
		gsub("%{_datadir}/aclocal", "%{_aclocaldir}")
	}

	gsub(examplesdir, "%{_examplesdir}")
	gsub("/usr/lib/pkgconfig", "%{_libdir}/pkgconfig")

	if (prefix != "/") {
		# leave --with-foo=/usr alone
		if ($0 !~ "--with.*=.*" prefix) {
			for (c = 1; c <= NF; c++) {
				if ($c ~ prefix "/sbin/fix-info-dir")
					continue;
				if ($c ~ prefix "/share/automake")
					continue;
				if ($c ~ prefix "/share/unsermake")
					continue;
				if ($c ~ prefix "/lib/sendmail")
					continue;
				gsub(prefix, "%{_prefix}", $c)
			}
		}
		gsub("%{prefix}", "%{_prefix}")
	}

	gsub("%{PACKAGE_VERSION}", "%{version}")
	gsub("%{PACKAGE_NAME}", "%{name}")

	gsub("^make$", "%{__make}")
	gsub("^make ", "%{__make} ")
	gsub("^gcc ", "%{__cc} ")

	# mandrake specs
	gsub("^%make$", "%{__make}")
	gsub("^%make ", "%{__make} ")
	gsub("^%makeinstall_std", "%{__make} install \\\n\tDESTDIR=$RPM_BUILD_ROOT")
	gsub("^%{makeinstall}", "%{__make} install \\\n\tDESTDIR=$RPM_BUILD_ROOT")
	gsub("^%{__rm} -rf %{buildroot}", "rm -rf $RPM_BUILD_ROOT")
	gsub("^%{__install}", "install")
	gsub("^%{__rm}", "rm")
	gsub("%optflags", "%{rpmcflags}")
	gsub("%{compat_perl_vendorarch}", "%{perl_vendorarch}")

	gsub("^%{__make} install DESTDIR=\$RPM_BUILD_ROOT", "%{__make} install \\\n\tDESTDIR=$RPM_BUILD_ROOT")
	gsub("^fix-info-dir$", "[ ! -x /usr/sbin/fix-info-dir ] || /usr/sbin/fix-info-dir -c %{_infodir} >/dev/null 2>\&1")
	$0 = fixedsub("%buildroot", "$RPM_BUILD_ROOT", $0)
	$0 = fixedsub("%{buildroot}", "$RPM_BUILD_ROOT", $0)
	gsub("%_bindir", "%{_bindir}")
	gsub("%_datadir", "%{_datadir}")
	gsub("%_iconsdir", "%{_iconsdir}")

	gsub("/usr/src/linux", "%{_kernelsrcdir}")
	gsub("%{_prefix}/src/linux", "%{_kernelsrcdir}")
}


# insertion sort of A[1..n]
# copied from mawk manual
function isort(A,n,		i,j,hold) {
	for (i = 2; i <= n; i++) {
		hold = A[j = i]
		while (A[j-1] > hold) {
			j-- ; A[j+1] = A[j]
		}
		A[j] = hold
	}
	# sentinel A[0] = "" will be created if needed
}


function use_files_macros(	i, n, t, a)
{
	gsub("^%{_sbindir}", "%attr(755,root,root) %{_sbindir}")
	gsub("^%{_bindir}", "%attr(755,root,root) %{_bindir}")

	# replace back
	gsub("%{_sysconfdir}/cron\.d", "/etc/cron.d")
	gsub("%{_sysconfdir}/crontab\.d", "/etc/cron.d")
	gsub("%{_sysconfdir}/logrotate\.d", "/etc/logrotate.d")
	gsub("%{_sysconfdir}/pam\.d", "/etc/pam.d")
	gsub("%{_sysconfdir}/profile\.d", "/etc/profile.d")
	gsub("%{_sysconfdir}/rc\.d", "/etc/rc.d")
	gsub("%{_sysconfdir}/security", "/etc/security")
	gsub("%{_sysconfdir}/skel", "/etc/skel")
	gsub("%{_sysconfdir}/sysconfig", "/etc/sysconfig")
	gsub("%{_sysconfdir}/certs", "/etc/certs")
	gsub("%{_sysconfdir}/init.d", "/etc/init.d")

	# /etc/init.d -> /etc/rc.d/init.d
	if (!/^\/etc\/init\.d$/) {
		 gsub("/etc/init.d", "/etc/rc.d/init.d")
	}

	if (/\/etc\/rc\.d\/init\.d\// && !/functions/) {
		if (!/%attr.*\/etc\/rc\.d\/init\.d/) {
			$0 = "%attr(754,root,root) " $0
		}
		if (/^%attr.*\/etc\/rc\.d\/init\.d/ && !/^%attr\(754 *,/) {
			gsub("^%attr\\(... *,", "%attr(754,");
		}
	}

	if (/lib.+\.so/ && !/^%attr.*/) {
		$0 = "%attr(755,root,root) " $0
	}

	# /etc/sysconfig files
	# %attr(640,root,root) %config(noreplace) %verify(not size mtime md5) /etc/sysconfig/*
	# attr not required, allow default 644 attr
	if (!/network-scripts/) {
		if (/\/etc\/sysconfig\// && /%config/ && !/%config\(noreplace\)/) {
			gsub("%config", "%config(noreplace)")
		}

		if (/\/etc\/sysconfig\// && !/%config\(noreplace\)/) {
			$NF = "%config(noreplace) " $NF
		}

		if (/\/etc\/sysconfig\// && /%attr\(755/) {
			gsub("^%attr\\(... *,", "%attr(640,");
		}

		if (/\/etc\/sysconfig\// && !/%verify/) {
			gsub("/etc/sysconfig", "%verify(not size mtime md5) /etc/sysconfig");
		}
	}


	# kill leading zeros
	if (/%attr\(0[1-9]/) {
		gsub("%attr\\(0", "%attr(")
	}

	# sort %verify attrs
	if (match($0, /%verify\(not([^)]+)\)/)) {
		t = substr($0, RSTART, RLENGTH)
		gsub(/^%verify\(not |\)$/, "", t)
		n = split(t, a, / /)
		isort(a, n)

		s = "%verify(not"
		for (i = 1 ; i <= n; i++) {
			s = s " " a[i]
		}
		s = s ")"

		gsub(/%verify\(not[^)]+\)/, s)
	}

	if (/%{_mandir}/) {
		gsub("\.gz$", "*")
	}

	# atrpms
	$0 = fixedsub("%{perl_man1dir}", "%{_mandir}/man1", $0);
	$0 = fixedsub("%{perl_man3dir}", "%{_mandir}/man3", $0);
	$0 = fixedsub("%{perl_bin}", "%{_bindir}", $0);
}

function fill(ch, n, i) {
	for (i = 0; i < n; i++)
		printf("%c", ch)
}

function format_flush(line, indent, newline, word, first_word) {
	first_word = 1
	if (format_indent == -1)
		newline = ""
	else
		newline = fill(" ", format_indent) "- "

	while (match(line, /[^\t ]+/)) {
		word = substr(line, RSTART, RLENGTH)
		if (length(newline) + length(word) + 1 > tw) {
			print newline

			if (format_indent == -1)
				newline = ""
			else
				newline = fill(" ", format_indent + 2)
			first_word = 1
		}

		if (first_word) {
			newline = newline word
			first_word = 0
		} else
			newline = newline " " word

		line = substr(line, RSTART + RLENGTH)
	}
	if (newline ~ /[^\t ]/) {
		print newline
	}
}

function cflags(var)
{
	if ($0 == var "=\"$RPM_OPT_FLAGS\"") {
		removed[var] = 1
		return 0
	}

	if (!/!\?debug/)
		sub("\$RPM_OPT_FLAGS", "%{rpmcflags}")
	return 1
}
