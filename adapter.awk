#!/usr/bin/gawk -f
#
# Adapter adapts .spec files for PLD Linux.
#
# Copyright (C) 1999-2010 PLD-Team <feedback@pld-linux.org>
# Authors:
# 	Michał Kuratczyk <kura@pld.org.pl>
# 	Sebastian Zagrodzki <s.zagrodzki@mimuw.edu.pl>
# 	Tomasz Kłoczko <kloczek@rudy.mif.pg.gda.pl>
# 	Artur Frysiak <wiget@pld-linux.org>
# 	Michal Kochanowicz <mkochano@pld.org.pl>
#	Jakub Bogusz <qboosh@pld-linux.org>
# 	Elan Ruusamäe <glen@pld-linux.org>
#
# See cvs log adapter{,.awk} for list of contributors
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# TODO
# - really long sourceX make preamble sorting totally fcked up (try snake.spec r1.1)
# - parse ../PLD-doc/BuildRequires.txt and setup proper BR epoches?
# - add "-nc" option to skip CVS interaction
# - sort Summary(XX)
# - sort Requires, BuildRequires
# - check if %description (lang=C) contains 8bit
# - desc wrapping is totally fucked up on global.spec,1.25, dosemu.spec,1.115-
# - it should change: /%source([0-9]+)/i to %{SOURCE\1}
# - extra quote on LDFLAGS line: https://bugs.launchpad.net/pld-linux/+bug/385836
# - %{with_foo:%attr()...} gets converted to %attr() %{with_foo:...} [vlc.spec]
# - 'R: foo ' (with traliling space) gets coverted to "R: foo\nR: " [vlc.spec @ 1.199 ]

BEGIN {
	RPM_SECTIONS = "package|build|changelog|clean|description|install|post|posttrans|postun|pre|prep|pretrans|preun|triggerin|triggerpostun|triggerun|verifyscript|check"
	SECTIONS = "^%(" RPM_SECTIONS ")"

	RCSID = "$Id$"
	rev = RCSID # TODO: parse from RCSID
	VERSION = "0.35/" rev

	PREAMBLE_TAGS = "(R|BR|Summary|Name|Version|Release|Epoch|License|Group|URL|BuildArch|BuildRoot|Obsoletes|Conflicts|Provides|ExclusiveArch|ExcludeArch|Pre[Rr]eq|(Build)?Requires|Suggests|Auto(Req|Prov))"

	usedigest = 0	# Enable to switch to rpm 4.4.6+ md5 digests

	preamble = 1	# Is it part of preamble? Default - yes
	boc = 4			# Beginning of %changelog
	bod = 0			# Beginning of %description
	tw = 70			# Descriptions width

	b_idx = 0		# index of BR/R arrays
	BR_count = 0	# number of additional BuildRequires

	# If variable removed, then 1 (for removing it from export)
	removed["LDFLAGS"] = 0
	removed["CFLAGS"] = 0
	removed["CXXFLAGS"] = 0

	# If 1, we are inside of comment block (started with /^#%/)
	comment_block = 0

	import_rpm_macros()

	packages_dir = topdir
	groups_file = packages_dir "/rpm.groups"

	system("cd "packages_dir"; [ -f rpm.groups ] || cvs up rpm.groups > /dev/null")
	system("[ -d ../PLD-doc ] && cd ../PLD-doc && ([ -f BuildRequires.txt ] || cvs up BuildRequires.txt >/dev/null)");

	# Temporary file for changelog section
	changelog_file = ENVIRON["HOME"] "/tmp/adapter.changelog"
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
	if (ENVIRON["SKIP_DEFATTR"] != 1) {
		if ($0 !~ /defattr/) {	# If no %defattr
			print "%defattr(644,root,root,755)"	# Add it
		} else {
			$0 = "%defattr(644,root,root,755)"	# Correct mistakes (if any)
		}
	}
	defattr = 0
}

function b_makekey(a, b,	s) {
	s = a "" b;
	# kill bcond
	gsub(/[#%]+{[!?]+[_a-zA-Z0-9]+:/, "", s);

	# kill commented out items
	gsub(/^#[ \t]*/, "", s);

	# force order
	gsub(/^Summary\(/, "11Summary(", s);
	gsub(/^Summary/, "10Summary", s);

	gsub(/^Name/, "2Name", s);
	gsub(/^Version/, "3Version", s);
	gsub(/^Release/, "4Release", s);
	gsub(/^Epoch/, "5Epoch", s);
	gsub(/^License/, "5License", s);
	gsub(/^Group/, "6Group", s);
	gsub(/^URL/, "7URL", s);

	gsub(/^BuildRequires/, "B1BuildRequires", s);
	gsub(/^BuildConflicts/, "B2BuildConflicts", s);

	gsub(/^Suggests/, "X1Suggests", s);
	gsub(/^Provides/, "X2Provides", s);
	gsub(/^Obsoletes/, "X3Obsoletes", s);
	gsub(/^Conflicts/, "X4Conflicts", s);
	gsub(/^BuildArch/, "X5BuildArch", s);
	gsub(/^ExclusiveArch/, "X6ExclusiveArch", s);
	gsub(/^ExcludeArch/, "X7ExcludeArch", s);
	gsub(/^BuildRoot/, "X9BuildRoot", s);

	gsub(/^AutoProv/, "Xx1AutoProv", s);
	gsub(/^AutoReq/, "Xx2AutoReq", s);

#	printf("%s -> %s\n", a""b, s);
	return s;
}

# Comments
/^#/ && (description == 0) {
	if (/This file does not like to be adapterized!/) {
		print			# print this message
		while (getline)		# print the rest of spec as it is
			print
		do_not_touch_anything = 1 # do not touch anything in END()
		exit(rc = 0)
	}

	# Generally, comments are printed without touching
	sub(/[ \t]+$/, "")

	if (/#[ \t]*Source.*md5/) {
		if (usedigest == 1) {
			sub(/^#[ \t]*Source/, "BuildRequires:\tdigest(%SOURCE", $0)
			sub(/-md5[ \t]*:[ \t]*/, ") = ", $0)
		}
		print $0
		next
	}
}

/^%define/ {
	# Remove defining _applnkdir (this macro has been included in rpm-3.0.4)
	if ($2 == "_applnkdir") {
		next
	}
	if ($2 == "date") {
		date = 1
		if (did_files == 0) {
			print "%files"
			print ""
			did_files = 1
		}
	}

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
	if ($2 ~ /_libdir/) {
		if ($3 ~ /^%\(/) {
			# TODO: should escape for latter checks like: ($c ~ sysconfdir "/{?cron.")
			libdir = "%%%%%%%%%%%%%%"
		} else {
			libdir = $3
		}
	}
	if ($2 ~ /_sysconfdir/) {
		if ($3 ~ /^%\(/) {
			# TODO: should escape for latter checks like: ($c ~ sysconfdir "/{?cron.")
			sysconfdir = "%%%%%%%%%%%%%%"
		} else {
			sysconfdir = $3
		}
	}
	if ($2 ~ /_datadir/) {
		if ($3 ~ /^%\(/) {
			# TODO: should escape for latter checks like: ($c ~ sysconfdir "/{?cron.")
			datadir = "%%%%%%%%%%%%%%"
		} else {
			datadir = $3
		}
	}
	if ($2 ~ /_includedir/)
		includedir = $3
	if ($2 ~ /_mandir/)
		mandir = $3
	if ($2 ~ /_infodir/)
		infodir = $3
	if ($2 ~ /_docdir/)
		docdir = $3

	# version related macros
	if ($2 ~ /^_beta$/)
		_beta = $3
	if ($2 ~ /^_rc$/)
		_rc = $3
	if ($2 ~ /^_pre$/)
		_pre = $3
	if ($2 ~ /^_snap$/)
		_snap = $3
	if ($2 ~ /^subver$/)
		subver = $3

	# these are used usually when adapterizing external spec
	if ($2 ~ /^name$/)
		name = $3
	if ($2 ~ /^version$/)
		version = $3
	if ($2 ~ /^release$/)
		release = $3

	if ($2 ~ /^mod_name$/)
		mod_name = $3

	sub(/[ \t]+$/, "");
	# do nothing further, otherwise adapter thinks we're at preamble
	print
	next
}

# Obsolete
/^%include.*\/usr\/lib\/rpm\/macros\.python$/ {
	next
}

################
# %description #
################
/^%description/, (!/^%description/ && $0 ~ SECTIONS) {
	preamble = 0

	if (/^%description/) {
		bod++
		format_line = ""
		format_indent = -1
	}

	# Format description
	if (ENVIRON["SKIP_DESC"] != 1 && description == 1 && !/^%[a-z]+/ && !/^%description/) {
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
/^%prep/, (!/^%prep/ && $0 ~ SECTIONS) {
	preamble = 0
	did_prep = 1

	use_macros()

	# Add '-q' to %setup
	if (/^%setup/ && !/-q/) {
		sub(/^%setup/, "%setup -q")
	}

	if (/^%setup/ && name != "setup") {
		$0 = fixedsub(name, "%{name}", $0);
		$0 = fixedsub(version, "%{version}", $0);
		if (_beta) {
			$0 = fixedsub(_beta, "%{_beta}", $0);
		}
		if (_rc) {
			$0 = fixedsub(_rc, "%{_rc}", $0);
		}
		if (_pre) {
			$0 = fixedsub(_pre, "%{_pre}", $0);
		}
		if (_snap) {
			$0 = fixedsub(_snap, "%{_snap}", $0);
		}
		if (subver) {
			$0 = fixedsub(subver, "%{subver}", $0);
		}
	}

	if (/^%setup/ && /-n %{name}-%{version}( |$)/) {
		$0 = fixedsub(" -n %{name}-%{version}", "", $0)
	}
	sub("^%patch ", "%patch0 ");

	# invalid in %prep
	sub("^rm -rf \$RPM_BUILD_ROOT.*", "");
}

##########
# %build #
##########
/^%build/, (!/^%build/ && $0 ~ SECTIONS) {
	preamble = 0

	if (did_prep == 0) {
		print "%prep"
		print ""
		did_prep = 1
	}

	use_macros()
	use_tabs()

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

	# quote CC
	if (/CC=%{__cc} /) {
		sub("CC=%{__cc}", "CC=\"%{__cc}\"")
	}
	
	# use PLD Linux macros
	$0 = fixedsub("glib-gettextize --copy --force","%{__glib_gettextize}", $0);
	$0 = fixedsub("intltoolize --copy --force", "%{__intltoolize}", $0);
	$0 = fixedsub("automake --add-missing --copy", "%{__automake}", $0);
	$0 = fixedsub("automake -a --foreign --copy", "%{__automake}", $0);
	$0 = fixedsub("automake -a -c --foreign", "%{__automake}", $0);
	$0 = fixedsub("automake -a -c", "%{__automake}", $0);
	$0 = fixedsub("libtoolize --force --automake --copy", "%{__libtoolize}", $0);
	$0 = fixedsub("libtoolize -c -f --automake", "%{__libtoolize}", $0);

	sub(/^aclocal$/, "%{__aclocal}");
	sub(/^autoheader$/, "%{__autoheader}");
	sub(/^autoconf$/, "%{__autoconf}");
	sub(/^automake$/, "%{__automake}");
	sub(/^libtoolize$/, "%{__libtoolize}");

	# atrpms
	$0 = fixedsub("%perl_configure", "%{__perl} Makefile.PL \\\n\tINSTALLDIRS=vendor", $0);
	$0 = fixedsub("%perl_makecheck", "%{?with_tests:%{__make} test}", $0);

	# alt linux
	$0 = fixedsub("%make_build", "%{__make}", $0);
}

##########
# %clean #
##########
/^%clean/, (!/^%clean/ && $0 ~ SECTIONS) {
	did_clean = 1

	use_macros()
}

############
# %install #
############
/^%install/, (!/^%install/ && $0 ~ SECTIONS) {

	preamble = 0

	# foreign rpms
	sub("^%{__rm} -rf %{buildroot}", "rm -rf $RPM_BUILD_ROOT")
	sub("%buildroot", "$RPM_BUILD_ROOT");
	sub("%{buildroot}", "$RPM_BUILD_ROOT");

	if (/^[ \t]*rm([ \t]+-[rf]+)*[ \t]+(\${?RPM_BUILD_ROOT}?|%{?buildroot}?)/ && did_rmroot==0) {
		did_rmroot=1
		print "rm -rf $RPM_BUILD_ROOT"
		next
	}

	if (!/^(#?[ \t]*)$/ && !/^%install/ && did_rmroot==0) {
		print "rm -rf $RPM_BUILD_ROOT"
		did_rmroot=1
	}

	if (tmpdir) {
		buildroot = tmpdir "/" name "-" version "-root-" ENVIRON["USER"]
		gsub(buildroot, "$RPM_BUILD_ROOT")
	}

	if (!/%{_lib}/) {
		sub("\$RPM_BUILD_ROOT/%", "$RPM_BUILD_ROOT%")
	}

	use_macros()

	# 'install -d' instead 'mkdir -p'
	if (/mkdir -p/)
		sub(/mkdir -p/, "install -d")

	# cp -a already implies cp -r
	sub(/^cp -ar/, "cp -a")

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

	# atrpms
	$0 = fixedsub("%perl_makeinstall", "%{__make} pure_install \\\n\tDESTDIR=$RPM_BUILD_ROOT", $0);

	# alt linux
	$0 = fixedsub("%make_install DESTDIR=$RPM_BUILD_ROOT install", "%{__make} install \\\n\tDESTDIR=$RPM_BUILD_ROOT", $0);
}

##########
# %files #
##########
/^%files/, (!/^%files/ && $0 ~ SECTIONS) {
	preamble = 0
	did_files = 1

	if ($0 ~ /^%files/)
		defattr = 1

	if (!use_files_macros()) {
		next
	}
}

##############
# %changelog #
##############
/^%changelog/, (!/^%changelog/ && $0 ~ SECTIONS) {
	preamble = 0
	has_changelog = 1
	skip = 0
	# There should be some CVS keywords on the first line of %changelog.
	if (boc == 3) {
		if ($0 !~ _cvsmailfeedback) {
			print "* %{date} " _cvsmailfeedback > changelog_file
		} else {
			skip = 1
		}
		boc = 2
	}
	if (boc == 2 && !skip) {
		if (!/All persons listed below/) {
			printf "All persons listed below can be reached at " > changelog_file
			print "<cvs_login>" _cvsmaildomain "\n" > changelog_file
		} else {
			skip = 1
		}
		boc = 1
	}
	if (boc == 1 && !skip) {
		if (!/^$/) {
			if (!/\$.*Log:.*\$/) {
				print "$" "Log:$" > changelog_file
			}
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

	sub(/[ \t]+$/, "");
	if (!/^%[a-z]+$/ || /changelog/) {
		# stop changelog if "real" changelog starts
		if (boc == 0 && /^\* /) {
			boc = -1
		}
		if (boc == -1) {
			next;
		}
		print > changelog_file
	} else {
		print
	}
	next
}

###########
# SCRIPTS #
###########
/^%pre/, (!/^%pre/ && $0 ~ SECTIONS) {
	preamble = 0

	if (gsub("/usr/sbin/useradd", "%useradd")) {
		sub(" 2> /dev/null \|\| :", "");
		sub(" >/dev/null 2>&1 \|\|:", "");
	}

	# %useradd and %groupadd may not be wrapped
	if (/%(useradd|groupadd).*\\$/) {
		a = $0; getline;
		sub(/^[\s\t]*/, "");
		$0 = substr(a, 1, length(a) - 1) $0;
	}
	use_script_macros()
}

/^%post/, (!/^%post/ && $0 ~ SECTIONS) {
	preamble = 0
	use_macros()
}
/^%preun/, (!/^%preun/ && $0 ~ SECTIONS) {
	preamble = 0
	use_macros()
}
/^%postun/, (!/^%postun/ && $0 ~ SECTIONS) {
	preamble = 0
	use_script_macros()
}
/^%triggerin/, (!/^%triggerin/ && $0 ~ SECTIONS) {
	preamble = 0
	use_script_macros()
}
/^%triggerun/, (!/^%triggerun/ && $0 ~ SECTIONS) {
	preamble = 0
	use_script_macros()
}
/^%triggerpostun/, (!/^%triggerpostun/ && $0 ~ SECTIONS) {
	preamble = 0
	use_script_macros()
}
/^%pretrans/, (!/^%pretrans/ && $0 ~ SECTIONS) {
	preamble = 0
	use_script_macros()
}
/^%posttrans/, (!/^%posttrans/ && $0 ~ SECTIONS) {
	preamble = 0
	use_script_macros()
}
/^%verifyscript/, (!/^%verifyscript/ && $0 ~ SECTIONS) {
	preamble = 0
	use_script_macros()
}
/^%check/, (!/^%check/ && $0 ~ SECTIONS) {
	preamble = 0
	use_script_macros()
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
	if (field ~ /summary:/ && !/etc\.$/ && !/Inc\.$/) {
		sub(/\.$/, "", $0);
	}
	if (field ~ /group(\([^)]+\)):/)
		next
	if (field ~ /group:/) {
		format_preamble()
		group = $0;
		sub(/^[^ \t]*[ \t]*/, "", group);
		group = replace_groupnames(group);
		$0 = "Group:\t\t" group

		if (group ~ /^X11/ && x11 == 0)	# Is it X11 application?
			x11 = 1

		byl_plik_z_groupmi = 0
		byl_opis_grupy = 0
		while ((getline linia_grup < groups_file) > 0) {
			byl_plik_z_groupmi = 1
			if (linia_grup == group) {
				byl_opis_grupy = 1
				break
			}
		}

		if (!byl_plik_z_groupmi)
			print "######\t\t" groups_file ": no such file"
		else if (!byl_opis_grupy)
			print "######\t\t" "Unknown group!"

		close(groups_file)
		did_groups = 1
	}

	if (field ~ /prereq:/) {
		sub(/Pre[Rr]eq:/, "Requires:", $1);
	}

	# split (build)requires, obsoletes on commas
	if (field ~ /(obsoletes|requires|provides|conflicts|suggests):/ && NF > 2) {
		value = substr($0, index($0, $2));
		$0 = format_requires($1, value);
	}

	# BR: tar (and others) is to common (rpm-build requires it)
	if (field ~ /^buildrequires:/) {
		l = substr($0, index($0, $2));
		if (l == "awk" ||
			l == "binutils" ||
			l == "bzip2" ||
			l == "cpio" ||
			l == "diffutils" ||
			l == "elfutils" ||
			l == "fileutils" ||
			l == "findutils" ||
			l == "glibc-devel" ||
			l == "grep" ||
			l == "gzip" ||
			l == "make" ||
			l == "patch" ||
			l == "sed" ||
			l == "sh-utils" ||
			l == "tar" ||
			l == "textutils") {
			next
		}

		replace_requires();
	}

	if (field ~ /^requires:/ || field ~ /^requires\(/) {
		replace_requires();
	}


	# obsolete/unwanted tags
	if (field ~ /vendor:|packager:|distribution:|docdir:|prefix:|icon:|author:|author-email:|metadata-version:/) {
		next
	}

	if (field ~ /buildroot:/) {
		$0 = $1 "%{tmpdir}/%{name}-%{version}-root-%(id -u -n)"
		did_build_root = 1
	}

	# Use "License" instead of "Copyright" if it is (L)GPL or BSD
	if (field ~ /copyright:/ && $2 ~ /GPL|BSD/) {
		$1 = "License:"
	}

	# ease updating from debian .dsc
	if (field ~ /homepage:/) {
		$1 = "URL:"
	}

	if (field ~ /license:/) {
		l = substr($0, index($0, $2));
		if (l == "Python Software Foundation License") {
			l = "PSF"
		}
		if (l == "Apache License 2.0" || l == "Apache 2.0" || l == "Apache License Version 2.0" || l == "Apache License, Version 2.0" || l == "Apache Software License v2") {
			l = "Apache v2.0"
		}
		if (l == "Apache Group License" || l == "Apache Software License" || l == "Apache License") {
			l = "Apache"
		}
		if (l == "Apache-style License" || l == "Apache-style Software License") {
			l = "Apache-like"
		}
		if (l == "Apache Software License 1.1" || l == "Apache 1.1") {
			l = "Apache v1.1"
		}
		if (l == "GPLv2") {
			l = "GPL v2"
		}
		if (l == "GPLv2+") {
			l = "GPL v2+"
		}
		if (l == "LGPLv2+") {
			l = "LGPL v2+"
		}
		if (l == "GPLv3") {
			l = "GPL v3"
		}
		if (l == "GPLv3+") {
			l = "GPL v3+"
		}
		if (l == "MPLv1.1") {
			l = "MPL v1.1"
		}
		$0 = "License:\t" l;
	}


	if (field ~ /name:/) {
		if ($2 == "%{name}" && name) {
			$2 = name
		}
		name = $2
		name_seen = 1;
	}

	if (field ~ /version:/) {
		if ($2 == "%{version}" && version) {
			$2 = version
		}
		version = $2
		version_seen = 1;
	}

	if (field ~ /release:/) {
		if ($2 == "%{release}" && release) {
			$2 = release
		}
		sub(/%atrelease /, "0.", $0)
		release = $2
		release_seen = 1;
	}


	if (field ~ /serial:/)
		$1 = "Epoch:"

	if (field ~ /home-page:/)
		$1 = "URL:"

	# proper caps
	if (field ~ /^url:$/)
		$1 = "URL:"

	if (field ~ /^patch/)
		$1 = "Patch" substr(field, 6);

	if (field ~ /^description:$/)
		$1 = "\n%description\n"

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

		# allow %{name} only in last url component
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
			if (_pre) {
				url[n] = fixedsub(_pre, "%{_pre}", url[n])
			}
			if (_snap) {
				url[n] = fixedsub(_snap, "%{_snap}", url[n])
			}
			if (subver) {
				url[n] = fixedsub(subver, "%{subver}", url[n])
			}
		}
		# assigning to $2 kills preamble formatting
		$2 = fixedsub(filename, url[n], $2)

		$2 = unify_url($2)
	}


	if (field ~ /^source:/)
		$1 = "Source0:"

	if (field ~ /^patch:/)
		$1 = "Patch0:"

	kill_preamble_macros();
	format_preamble()

	if (field ~ /requires/) {
		# atrpms
		$0 = fixedsub("%{eversion}", "%{epoch}:%{version}-%{release}", $0);
	}
}

/^%bcond_/ {
	# do nothing
	print
	next
}

# sort BR/R!
#
# NOTES:
# - mixing BR/R and anything else confuses this (all will be sorted together)
#	so don't do that.
# - comments leading the BR/R can not be associated,
#	so don't adapterize when the BR/R are mixed with comments
ENVIRON["SKIP_SORTBR"] != 1 && preamble == 1 && $0 ~ PREAMBLE_TAGS ":", $0 ~ PREAMBLE_TAGS ":"{
	if ($1 ~ /Pre[Rr]eq:/) {
		sub(/Pre[Rr]eq:/, "Requires:", $1);
	}
	if ($1 == "BR:" ) {
		$1 = "BuildRequires:"
	}
	if ($1 == "R:" ) {
		$1 = "Requires:"
	}
	format_preamble()
#	kill_preamble_macros(); # breaks tabbing

	b_idx++;
	l = substr($0, index($0, $2));
	b_ktmp = b_makekey($1, l);
	b_key[b_idx] = b_ktmp;
	b_val[b_ktmp] = $0;

	next;
}

preamble == 1 {
	if (b_idx > 0) {
		isort(b_key, b_idx);
		for (i = 1; i <= b_idx; i++) {
			v = b_val[b_key[i]];
			sub(/[ \t]+$/, "", v);
			print "" v;
		}
		b_idx = 0
	}
}

# main() ;-)
{
	preamble = 1

	sub(/[ \t]+$/, "")
	print

	if (name_seen == 0 && name) {
		print "Name:\t\t" name
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

	if (did_build_root == 0) {
#		print "BuildRoot:\t%{tmpdir}/%{name}-%{version}-root-%(id -u -n)"
		did_build_root = 1
	}
	if (did_groups == 0) {
#		print "Group:\t\tunknown"
		did_groups = 1
	}
}


END {
	if (do_not_touch_anything) {
		exit(rc)
	}

	# TODO: need to output these in proper place
	if (BR_count > 0) {
		for (i = 0; i <= BR_count; i++) {
			print BR[i];
		}
	}

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

	if (has_changelog == 0) {
		print "%changelog"
	}

	if (boc > 2) {
		print "* %{date} PLD Team <feedback@pld-linux.org>"
	}
	if (boc > 1) {
		printf "All persons listed below can be reached at "
		print "<cvs_login>@pld-linux.org\n"
	}
	if (boc > 0) {
		print "$" "Log:$"
	}
}

# substitutes fixed strings (not regexps)
function fixedsub(s1,s2,t, ind) {
	if (ind = index(t,s1))
		t = substr(t, 1, ind-1) s2 substr(t, ind+length(s1))
	return t
}

# replace s with s2 if it equals to s1
function replace(s, s1, s2) {
	if (s == s1) {
		return s2;
	} else {
		return s;
	}
}

# There should be one or two tabs after the colon.
function format_preamble()
{
	if (/^#/ || /^%bcond_with/) {
		return;
	}
	sub(/:[ \t]*/, ":")
	if (match($0, /[A-Za-z0-9(),#_ \t.-]+[ \t]*:[ \t]*/) == 1) {
		if (RLENGTH < 8) {
			sub(/:/, ":\t\t")
		} else {
			sub(/:/, ":\t")
		}
	}
}

# Replace directly specified directories with macros
function use_macros()
{
	# -m, --skip-macros, --no-macros -- skip macros subst
	if (ENVIRON["SKIP_MACROS"]) {
		return
	}

	# leave inline sed lines alone
	if (/(%{__sed}|sed) -i -e/) {
		return;
	}

	sub("%{_defaultdocdir}", "%{_docdir}");
	sub("%{_bindir}/perl", "%{__perl}");
	sub("%{_bindir}/python", "%{__python}");

	gsub(infodir, "%{_infodir}")

	gsub(perl_sitearch, "%{perl_sitearch}")
	gsub(perl_archlib, "%{perl_archlib}")
	gsub(perl_privlib, "%{perl_privlib}")
	gsub(perl_vendorlib, "%{perl_vendorlib}")
	gsub(perl_vendorarch, "%{perl_vendorarch}")
	gsub(perl_sitelib, "%{perl_sitelib}")
	
	gsub(py_sitescriptdir, "%{py_sitescriptdir}")
	gsub(py_sitedir, "%{py_sitedir}")
	gsub(py_scriptdir, "%{py_scriptdir}")
	gsub("%{_libdir}/python2.4/site-packages", "%{py_sitedir}")

	gsub(ruby_archdir, "%{ruby_archdir}")
	gsub(ruby_ridir, "%{ruby_ridir}")
	gsub(ruby_rubylibdir, "%{ruby_rubylibdir}")
	gsub(ruby_sitearchdir, "%{ruby_sitearchdir}")
	gsub(ruby_sitelibdir, "%{ruby_sitelibdir}")
	gsub(ruby_rdocdir, "%{ruby_rdocdir}")

	gsub("%{_datadir}/applications", "%{_desktopdir}")
	gsub("%{_datadir}/pixmaps", "%{_pixmapsdir}")
	gsub("%{_datadir}/java", "%{_javadir}")

	gsub("%{_libdir}/pkgconfig", "%{_pkgconfigdir}")
	gsub(pkgconfigdir, "%{_pkgconfigdir}")

	gsub(libdir, "%{_libdir}")
	gsub(javadir, "%{_javadir}")

	gsub(bindir, "%{_bindir}")
	gsub("%{prefix}/bin", "%{_bindir}")
	if (prefix"/bin" == bindir)
		gsub("%{_prefix}/bin", "%{_bindir}")

	for (c = 1; c <= NF; c++) {
		if ($c ~ sbindir "/fix-info-dir")
			continue;
		if ($c ~ sbindir "/webapp")
			continue;
		if ($c ~ sbindir "/ldconfig")
			continue;
		if ($c ~ sbindir "/chsh")
			continue;
		if ($c ~ sbindir "/usermod")
			continue;
		if ($c ~ sbindir "/chkconfig")
			continue;
		if ($c ~ sbindir "/installzope(product|3package)")
			continue;
		gsub(sbindir, "%{_sbindir}", $c)
	}

	gsub("%{prefix}/sbin", "%{_sbindir}")
	if (prefix"/sbin" == sbindir) {
		gsub("%{_prefix}/sbin", "%{_sbindir}")
	}

	for (c = 1; c <= NF; c++) {
		if ($c ~ sysconfdir "/{?cron.")
			continue;
		if ($c ~ sysconfdir "/{?crontab.d")
			continue;
		if ($c ~ sysconfdir "/{?env.d")
			continue;
		if ($c ~ sysconfdir "/{?modprobe.(d|conf)")
			continue;
		if ($c ~ sysconfdir "/{?udev")
			continue;
		if ($c ~ sysconfdir "/{?hotplug")
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
		if ($c ~ sysconfdir "/{?shrc.d")
			continue;
		if ($c ~ sysconfdir "/{?certs")
			continue;
		if ($c ~ sysconfdir "/{?X11")
			continue;
		if ($c ~ sysconfdir "/{?ld.so.conf.d")
			continue;
		if ($c ~ sysconfdir "/{?rpm")
			continue;
		if ($c ~ sysconfdir "/{?bash_completion.d")
			continue;
		if ($c ~ sysconfdir "/{?samba")
			continue;
		if ($c ~ sysconfdir "/shells")
			continue;
		if ($c ~ sysconfdir "/ppp")
			continue;
		if ($c ~ sysconfdir "/dbus-1")
			continue;
		if ($c ~ sysconfdir "/tmpwatch")
			continue;
		if ($c ~ sysconfdir "/acpi")
			continue;
		if ($c ~ sysconfdir "/apm")
			continue;
		gsub(sysconfdir, "%{_sysconfdir}", $c)
	}

	gsub(docdir, "%{_docdir}")

	gsub(kdedocdir, "%{_kdedocdir}")

	gsub(gtkdocdir, "%{_gtkdocdir}")
	gsub("%{_docdir}/gtk-doc/html", "%{_gtkdocdir}")

	gsub(php_pear_dir, "%{php_pear_dir}")
	gsub(php_data_dir, "%{php_data_dir}")

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

	# CFLAGS="-I/usr/include/ncurses is usually correct.
	if (!/-I\/usr\/include/) {
		gsub(includedir, "%{_includedir}")
	}

	gsub("%{prefix}/include", "%{_includedir}")
	if (prefix"/include" == includedir) {
		gsub("%{_prefix}/include", "%{_includedir}")
	}

	gsub(mandir, "%{_mandir}")
	if ($0 !~ "%{_datadir}/manual") {
		gsub("%{_datadir}/man", "%{_mandir}")
	}
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

	if (prefix != "/") {
		# leave --with-foo=/usr alone
		if ($0 !~ "--with.*=.*" prefix) {
			for (c = 1; c <= NF; c++) {
				if ($c ~ prefix "/sbin/fix-info-dir")
					continue;
				if ($c ~ prefix "/sbin/webapp")
					continue;
				if ($c ~ prefix "/sbin/chsh")
					continue;
				if ($c ~ prefix "/sbin/usermod")
					continue;
				if ($c ~ prefix "/sbin/installzope(product|3package)")
					continue;
				if ($c ~ prefix "/share/automake")
					continue;
				if ($c ~ prefix "/share/unsermake")
					continue;
				if ($c ~ prefix "/lib/sendmail")
					continue;
				if ($c ~ prefix "/lib/pkgconfig")
					continue;

				# CFLAGS="-I/usr..." is usually correct.
				if (/-I\/usr/)
					continue;
				# same for LDFLAGS="-L/usr..."
				if (/-L\/usr/)
					continue;

				gsub(prefix, "%{_prefix}", $c)
			}
		}
		gsub("%{prefix}", "%{_prefix}")
	}

	# replace back
	gsub("%{_includedir}/ncurses", "/usr/include/ncurses")
	gsub("%{_includedir}/freetype", "/usr/include/freetype")

	gsub("%{PACKAGE_VERSION}", "%{version}")
	gsub("%{PACKAGE_NAME}", "%{name}")

	gsub("^make$", "%{__make}")
	gsub("^make ", "%{__make} ")
	gsub("^gcc ", "%{__cc} ")
	gsub("^rm --interactive=never ", "%{__rm} ")

	# fedora
	gsub("%{ruby_sitearch}", "%{ruby_sitearchdir}")
	gsub("%{python_sitearch}", "%{py_sitedir}")
	gsub("%{python_sitelib}", "%{py_sitescriptdir}")

	# alt linux
	gsub("%_man1dir", "%{_mandir}/man1")

	# mandrake specs
	gsub("^%make$", "%{__make}")
	gsub("^%make ", "%{__make} ")
	gsub("^%makeinstall_std", "%{__make} install \\\n\tDESTDIR=$RPM_BUILD_ROOT")
	gsub("^%{makeinstall}", "%{__make} install \\\n\tDESTDIR=$RPM_BUILD_ROOT")
	gsub("^%makeinstall", "%{__make} install \\\n\tDESTDIR=$RPM_BUILD_ROOT")
	gsub("^%{__rm} -rf %{buildroot}", "rm -rf $RPM_BUILD_ROOT")
	gsub("^%{__install}", "install")
	gsub("%optflags", "%{rpmcflags}")
	gsub("%{compat_perl_vendorarch}", "%{perl_vendorarch}")

	gsub("^%{__make} install DESTDIR=\$RPM_BUILD_ROOT", "%{__make} install \\\n\tDESTDIR=$RPM_BUILD_ROOT")
	gsub("^fix-info-dir$", "[ ! -x /usr/sbin/fix-info-dir ] || /usr/sbin/fix-info-dir -c %{_infodir} >/dev/null 2>\\&1")
	$0 = fixedsub("%buildroot", "$RPM_BUILD_ROOT", $0)
	$0 = fixedsub("%{buildroot}", "$RPM_BUILD_ROOT", $0)
	$0 = fixedsub("CXXFLAGS=%{rpmcflags} %configure", "CXXFLAGS=%{rpmcflags}\n%configure", $0);
	$0 = fixedsub("%__install", "install", $0);

	# split configure line to multiple lines
	if (/%configure / && !/\\$/) {
		$0 = format_configure($0);
	}

	gsub("%_bindir", "%{_bindir}")
	gsub("%_datadir", "%{_datadir}")
	gsub("%_iconsdir", "%{_iconsdir}")
	gsub("%_sbindir", "%{_sbindir}")
	gsub("%_mandir", "%{_mandir}")
	gsub("%name", "%{name}")
	gsub(/%__rm/, "rm");
	gsub(/%__mkdir_p/, "install -d");
	gsub(/%__cp/, "cp");
	gsub(/%__ln_s/, "ln -s");
	gsub(/%__sed/, "%{__sed}");
	gsub(/%__cat/, "cat");
	gsub(/%__chmod/, "chmod");

	gsub("/usr/src/linux", "%{_kernelsrcdir}")
	gsub("%{_prefix}/src/linux", "%{_kernelsrcdir}")

	if (/^ant / || /^%{ant}/) {
		sub(/^ant/, "%ant")
		sub(/^%{ant}/, "%ant")
		add_br("BuildRequires:  jpackage-utils");
		add_br("BuildRequires:  rpmbuild(macros) >= 1.300");
	}

	$0 = fixedsub("%(%{__cc} -dumpversion)", "%{cc_version}", $0);
	$0 = fixedsub("%(%{__cxx} -dumpversion)", "%{cxx_version}", $0);
}

function format_configure(line,		n, a, s) {
	n = split(line, a, / /);
	s = a[1] " \\\n";
	for (i = 2; i <= n; i++) {
		s = s "\t" a[i] " \\\n"
	}
	return s
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


function use_files_macros(	i, n, t, a, l)
{
	use_macros()

	# skip comments
	if (/^#/) {
		return 1;
	}

	sub("^%doc %{_mandir}", "%{_mandir}")

	gsub("^%{_sbindir}", "%attr(755,root,root) %{_sbindir}")
	gsub("^%{_bindir}", "%attr(755,root,root) %{_bindir}")

	# uid/gid nobody is not valid in %files
	if (/%attr([^)]*nobody[^)]*)/ && !/FIXME/) {
		$0 = $0 " # FIXME nobody user/group can't own files! -adapter.awk"
	}

	# s[gu]id programs with globs are evil
	if (/%attr\([246]...,.*\*/ && !/FIXME/) {
		$0 = $0 " # FIXME no globs for suid/sgid files"
	}

	# replace back
	gsub("%{_sysconfdir}/cron\.d", "/etc/cron.d")
	gsub("%{_sysconfdir}/crontab\.d", "/etc/crontab.d")
	gsub("%{_sysconfdir}/logrotate\.d", "/etc/logrotate.d")
	gsub("%{_sysconfdir}/pam\.d", "/etc/pam.d")
	gsub("%{_sysconfdir}/profile\.d", "/etc/profile.d")
	gsub("%{_sysconfdir}/rc\.d", "/etc/rc.d")
	gsub("%{_sysconfdir}/security", "/etc/security")
	gsub("%{_sysconfdir}/skel", "/etc/skel")
	gsub("%{_sysconfdir}/sysconfig", "/etc/sysconfig")
	gsub("%{_sysconfdir}/certs", "/etc/certs")
	gsub("%{_sysconfdir}/init.d", "/etc/init.d")
	gsub("%{_sysconfdir}/dbus-1", "/etc/dbus-1")
	gsub("%{_sysconfdir}/pki", "/etc/pki")
	gsub("%{_sysconfdir}/tmpwatch", "/etc/tmpwatch")

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

	if (/lib.+\.so/ && !/\.so$/ && !/^%attr.*/ && !/%exclude/) {
		$0 = "%attr(755,root,root) " $0
	}

	if (/%{perl_vendorarch}.*\.so$/ && !/^%attr.*/) {
		$0 = "%attr(755,root,root) " $0
	}

	# remove attrs from man pages
	if (/%{_mandir}/ && /^%attr/) {
		sub("^%attr\\(.*\\) *", "");
	}

	# /etc/sysconfig files
	# %attr(640,root,root) %config(noreplace) %verify(not size mtime md5) /etc/sysconfig/*
	# attr not required, allow default 644 attr
	if (!/network-scripts/ && !/%dir/ && !/\.d$/ && !/functions/ && !/\/etc\/sysconfig\/wmstyle/) {
		if (/\/etc\/sysconfig\// && /%config/ && !/%config\(noreplace/) {
			gsub("%config", "%config(noreplace)")
		}

		if (/\/etc\/sysconfig\// && !/%config\(noreplace/) {
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

	# kill leading whitespace
	gsub(/^ +/, "");

	# kill default attrs
	gsub(/%dir %attr\(755,root,root\)/, "%dir");
	gsub(/%attr\(755,root,root\) %dir/, "%dir");
	if (!/%dir/) {
		gsub(/%attr\(644,root,root\) /, "");
	}

	# sort %verify attrs
	if (match($0, /%verify\(not([^)]+)\)/)) {
		t = substr($0, RSTART, RLENGTH)
		# kill commas: %verify(not,md5,size,mtime)
		gsub(/,/, " ", t);

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

	# locale dir and no %lang -> bad
	if (/%{_datadir}\/locale\/.*\// && !/%(dir|lang)/) {
		$(NF + 1) = "# FIXME consider using %find_lang"
	}

	# python egg-infos
	if (match($0, "^%{py_site(script)?dir}/.+-py"py_ver".egg-info$")) {
		# tests:
		#%{py_sitedir}/*-py2.4.egg-info
		#%{py_sitescriptdir}/GnuPGInterface-%{version}-py2.4.egg-info
		#%{py_sitescriptdir}/python_mpd-%{version}-py2.4.egg-info
		#%{py_sitescriptdir}/mechanize-0.1.6b-py2.4.egg-info

		l = index($0, "/");
		t = substr($0, 0, l);
		s = substr($0, l + 1, RLENGTH - l - length("-py"py_ver".egg-info"));
		if (match(s, "[^-]+$")) {
#printf("s[%s]; start[%d]; length[%d]\n", s, RSTART, RLENGTH);
			if (RSTART > 1) {
				s = substr(s, 0, RSTART - 1);
			}
#printf("s2[%s]\n", s);
			print "%if \"%{py_ver}\" > \"2.4\""
#print t "/.+.egg-info"
			gsub(t "/.+.egg-info", t "/" s "-*.egg-info");
			print
			print "%endif"
			return 0;
		}
	}

	# atrpms
	$0 = fixedsub("%{perl_man1dir}", "%{_mandir}/man1", $0);
	$0 = fixedsub("%{perl_man3dir}", "%{_mandir}/man3", $0);
	$0 = fixedsub("%{perl_bin}", "%{_bindir}", $0);

	gsub(libdir "/pkgconfig", "%{_pkgconfigdir}");
	gsub("%{_libdir}/pkgconfig", "%{_pkgconfigdir}");
	gsub("%{_prefix}/lib/pkgconfig", "%{_pkgconfigdir}");

	gsub("%{_datadir}/applications", "%{_desktopdir}");
	gsub("%{_datadir}/icons", "%{_iconsdir}");
	gsub("%{_datadir}/pixmaps", "%{_pixmapsdir}");
	gsub("%{_datadir}/pear", "%{php_pear_dir}");
	gsub("%{_datadir}/php", "%{php_data_dir}");

	return 1
}

function use_script_macros()
{
	if (gsub("/sbin/service", "%service")) {
		sub(" >/dev/null 2>&1 \|\|:", "");
		sub(" 2> /dev/null \|\| :", "");
	}
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

function unify_url(url)
{

	# sourceforge urls
	# Docs about sourceforge mirror system: http://sourceforge.net/apps/trac/sourceforge/wiki/Mirrors
	sub("^http://prdownloads\.sourceforge\.net/", "http://downloads.sourceforge.net/", url)
	sub("^http://download\.sf\.net/", "http://downloads.sourceforge.net/", url)
	sub("^http://download\.sourceforge\.net/", "http://downloads.sourceforge.net/", url)
	sub("^http://dl\.sourceforge\.net/", "http://downloads.sourceforge.net/", url)
	sub("^http://.*\.dl\.sourceforge\.net/", "http://downloads.sourceforge.net/", url)
	sub("^http://dl\.sf\.net/", "http://downloads.sourceforge.net/", url)
	sub("^http://downloads\.sourceforge\.net/sourceforge/", "http://downloads.sourceforge.net/", url)
	# new style urls, strip "files/" between and prepend dl.
	if (match(url, "^http://sourceforge.net/projects/[^/]+/files/")) {
		url = substr(url, 1, RLENGTH - length("files/")) substr(url, RSTART + RLENGTH);
		sub("^http://sourceforge.net/projects/", "http://downloads.sourceforge.net/project/", url);
	}
	if (url ~ /sourceforge.net/) {
		sub("[?&]big_mirror=.*$", "", url);
		sub("[?&]modtime=.*$", "", url);
		sub("[?]use_mirror=.*$", "", url);
		sub("[?]download$", "", url);
		sub("/download$", "", url);
	}

	sub("^ftp://ftp\.gnome\.org/", "http://ftp.gnome.org/", url)
	sub("^http://ftp\.gnome\.org/pub/gnome/", "http://ftp.gnome.org/pub/GNOME/", url)

	# apache urls
	sub("^http://apache.zone-h.org/", "http://www.apache.org/dist/", url)

	# gnu.org
	sub("^ftp://ftp\.gnu\.org/", "http://ftp.gnu.org/", url)
	sub("^http://ftp\.gnu\.org/pub/gnu/", "http://ftp.gnu.org/gnu/", url)

	# debian.org
	sub("^ftp://ftp\.[^.]+\.debian\.org/", "ftp://ftp.debian.org/", url)
	sub("^http://ftp\.[^.]+\.debian\.org/", "ftp://ftp.debian.org/", url)
	sub("^ftp://ftp\.debian\.org/pub/debian/", "ftp://ftp.debian.org/debian/", url)

	return url
}

function demacroize(str)
{
	if (mod_name) {
		sub("%{mod_name}", mod_name, str);
	}
	if (name) {
		sub("%{name}", name, str);
	}
	if (version) {
		sub("%{version}", version, str);
	}
	if (_beta) {
		sub("%{_beta}", _beta, str);
	}
	if (_rc) {
		sub("%{_rc}", _rc, str);
	}
	if (_pre) {
		sub("%{_pre}", _pre, str);
	}
	if (_snap) {
		sub("%{_snap}", _snap, str);
	}
	if (subver) {
		sub("%{subver}", subver, str);
	}
	return str;
}

function kill_preamble_macros()
{
	if ($1 ~ /^Obsoletes:/) {
		# NB! assigning $2 a value breaks tabbing
		$2 = demacroize($2);
	}
	if ($1 ~ /^URL:/) {
		# NB! assigning $2 a value breaks tabbing
		$2 = demacroize($2);
		$2 = unify_url($2)
	}
}

function get_epoch(pkg, ver,	epoch)
{
	return
# should parse the BR lines more adequately:
#	freetype = 2.0.0 -> correct
#	freetype = 2.1.9 -> with epoch 1, as epoch 1 was added in 2.1.7

	shell = "grep -o '^" pkg ":[^:]\+' ../PLD-doc/BuildRequires.txt | awk '{print $NF}'";
	shell | getline epoch;
	return epoch;
}

function format_requires(tag, value,	n, p, i, deps, ndeps) {
	# skip any formatting for commented out items or some weird macros
	if (/^#/ || /%\(/) {
		return tag "\t" value
	}
	n = split(value, p, / *,? */);
	for (i = 1; i <= n; i++) {
		if (p[i+1] ~ /[<=>]/) {
			# add epoch if the version doesn't have it but BuildRequires.txt has
			if (p[i] ~ /^[a-z]/ && p[i+2] !~ /^[0-9]+:/) {
				epoch = get_epoch(p[i], p[i+2])
				if (epoch) {
					p[i+2] = epoch ":" p[i+2];
				}
			}
			deps[ndeps++] = p[i] " " p[i+1] " " p[i+2];
			i += 2;
		} else {
			deps[ndeps++] = p[i];
		}
	}
	s = ""
	for (i in deps) {
		s = s sprintf("%s\t%s\n", tag, deps[i]);
	}
	return substr(s, 1, length(s)-1);
}

function use_tabs()
{
	# reverse vim: ts=4 sw=4 et
	gsub(/    /, "\t");
}

function add_br(br)
{
	BR[BR_count++] = br
}


# Load rpm macros
# you should update the list also in adapter when making changes here
function import_rpm_macros() {
	# File with rpm groups
	topdir = ENVIRON["_topdir"]

	if (!topdir) {
		print "adapter.awk should not not be invoked directly, but via adapter script" > "/dev/stderr"
		do_not_touch_anything = 1
		exit(rc = 1);
	}

	if (!ENVIRON["ADAPTER_REVISION"] || ENVIRON["ADAPTER_REVISION"] < 1.44) {
		print "adapter shell script is outdated, please cvs up it" > "/dev/stderr"
		do_not_touch_anything = 1
		exit(rc = 1);
	}

	# get cvsaddress for changelog section
	# using rpm macros as too lazy to add ~/.adapterrc parsing support.
	_cvsmaildomain = ENVIRON["_cvsmaildomain"]
	_cvsmailfeedback = ENVIRON["_cvsmailfeedback"]

	prefix = ENVIRON["_prefix"]
	bindir = ENVIRON["_bindir"]
	sbindir = ENVIRON["_sbindir"]
	libdir = ENVIRON["_libdir"]
	sysconfdir = ENVIRON["_sysconfdir"]
	datadir = ENVIRON["_datadir"]
	includedir = ENVIRON["_includedir"]
	mandir = ENVIRON["_mandir"]
	infodir = ENVIRON["_infodir"]
	examplesdir = ENVIRON["_examplesdir"]
	docdir = ENVIRON["_defaultdocdir"]
	kdedocdir = ENVIRON["_kdedocdir"]
	gtkdocdir = ENVIRON["_gtkdocdir"]
	desktopdir = ENVIRON["_desktopdir"]
	pixmapsdir = ENVIRON["_pixmapsdir"]
	javadir = ENVIRON["_javadir"]
	pkgconfigdir = ENVIRON["_pkgconfigdir"]

	perl_sitearch = ENVIRON["perl_sitearch"]
	perl_archlib = ENVIRON["perl_archlib"]
	perl_privlib = ENVIRON["perl_privlib"]
	perl_vendorlib = ENVIRON["perl_vendorlib"]
	perl_vendorarch = ENVIRON["perl_vendorarch"]
	perl_sitelib = ENVIRON["perl_sitelib"]

	py_sitescriptdir = ENVIRON["py_sitescriptdir"]
	py_sitedir = ENVIRON["py_sitedir"]
	py_scriptdir = ENVIRON["py_scriptdir"]
	py_ver = ENVIRON["py_ver"]

	ruby_archdir = ENVIRON["ruby_archdir"]
	ruby_ridir = ENVIRON["ruby_ridir"]
	ruby_rubylibdir = ENVIRON["ruby_rubylibdir"]
	ruby_sitearchdir = ENVIRON["ruby_sitearchdir"]
	ruby_sitelibdir = ENVIRON["ruby_sitelibdir"]
	ruby_rdocdir = ENVIRON["ruby_rdocdir"]

	php_pear_dir = ENVIRON["php_pear_dir"]
	php_data_dir = ENVIRON["php_data_dir"]
	tmpdir = ENVIRON["tmpdir"]
}


# php virtual deps as discussed in devel-en
function replace_php_virtual_deps() {
	pkg = $2
#	if (pkg == "php-program") {
#		$0 = $1 "\t/usr/bin/php"
#		return
#	}

#	if (pkg ~ /^php-[a-z]/ && pkg !~ /^php-(pear|common|cli|devel|fcgi|cgi|dirs|program|pecl-)/) {
#		sub(/^php-/, "php(", pkg);
#		sub(/$/, ") # verify this correctness -- it may be wanted to use specific not virtual dep", pkg);
#		$2 = pkg
#	}

	if (pkg ~/^php$/) {
		$2 = "webserver(php)";
		if ($4 ~ /^[0-9]:/) {
			$4 = substr($4, 3);
		}
	}

	if (pkg ~/^php4$/) {
		$2 = "webserver(php)";
		if ($4 ~ /^[0-9]:/) {
			$4 = substr($4, 3);
		}
	}
}

function replace_requires() {

	sub(/^freetype2-devel$/, "freetype-devel", $2);

	# use virtual, not package name
	sub(/^rpm-build-macros$/, "rpmbuild(macros)", $2);

	# bad package.xml, see http://pear.php.net/bugs/bug.php?id=17779
	sub(/^php-php-gtk/, "php-gtk2", $2);

	# jpackages
	sub(/^antlr3$/, "java-antlr3", $2);
	sub(/^avalon-framework$/, "java-avalon-framework", $2);
	sub(/^avalon-logkit$/, "java-avalon-logkit", $2);
	sub(/^axis$/, "java-axis", $2);
	sub(/^bsf$/, "java-bsf", $2);
	sub(/^gnu-regexp$/, "java-gnu-regexp", $2);
	sub(/^gnu.regexp$/, "java-gnu-regexp", $2);
	sub(/^hamcrest$/, "java-hamcrest", $2);
	sub(/^jaas$/, "java(jaas)", $2);
	sub(/^jaf$/, "java(jaf)", $2);
	sub(/^jakarta-ant$/, "ant", $2);
	sub(/^jakarta-commons-httpclient$/, "java-commons-httpclient", $2);
	sub(/^jakarta-log4j$/, "java-log4j", $2);
	sub(/^jakarta-oro$/, "java-oro", $2);
	sub(/^jakarta-servletapi$/, "java(servlet)", $2);
	sub(/^java-devel$/, "jdk", $2);
	sub(/^java\(JSP\)$/, "java(jsp)", $2);
	sub(/^java\(JavaServerFaces\)$/, "java(javaserverfaces)", $2);
	sub(/^java\(Portlet\)$/, "java(portlet)", $2);
	sub(/^java\(Servlet\)$/, "java(servlet)", $2);
	sub(/^javamail$/, "java(javamail)", $2);
	sub(/^jaxp$/, "java(jaxp)", $2);
	sub(/^jaxp_parser_impl$/, "java(jaxp_parser_impl)", $2);
	sub(/^jaxp_transform_impl$/, "java(jaxp_transform_impl)", $2);
	sub(/^jce$/, "java(jce)", $2);
	sub(/^jcommon$/, "java-jcommon", $2);
	sub(/^jdbc-stdext$/, "java(jdbc-stdext)", $2);
	sub(/^jdepend$/, "java-jdepend", $2);
	sub(/^jfreechart$/, "java-jfreechart", $2);
	sub(/^jmx$/, "java(jmx)", $2);
	sub(/^jndi$/, "java(jndi)", $2);
	sub(/^jsch$/, "java-jsch", $2);
	sub(/^jsse$/, "java(jsse)", $2);
	sub(/^jta$/, "java(jta)", $2);
	sub(/^junit$/, "java-junit", $2);
	sub(/^ldapjdk$/, "ldapsdk", $2);
	sub(/^log4j$/, "java-log4j", $2);
	sub(/^logging-log4j$/, "java-log4j", $2);
	sub(/^oro$/, "java-oro", $2);
	sub(/^rhino$/, "java-rhino", $2);
	sub(/^saxon-scripts$/, "saxon", $2);
	sub(/^servlet$/, "java(servlet)", $2);
	sub(/^uddi4j$/, "java-uddi4j", $2);
	sub(/^wsdl4j$/, "java-wsdl4j", $2);
	sub(/^xalan-j$/, "java-xalan", $2);
	sub(/^xalan-j2$/, "java-xalan", $2);
	sub(/^xerces-j$/, "java-xerces", $2);
	sub(/^xerces-j2$/, "java-xerces", $2);
	sub(/^xml-commons-apis$/, "java-xml-commons-apis", $2);
	sub(/^xml-commons-resolver$/, "java-xml-commons-resolver", $2);

	# fedora / redhat
	sub(/^Django$/, "python-django", $2);
	sub(/^GitPython$/, "python-git", $2);
	sub(/^chkconfig$/, "/sbin/chkconfig", $2);
	sub(/^db4-devel$/, "db-devel", $2);
	sub(/^dbus-python$/, "python-dbus", $2);
	sub(/^file-devel$/, "libmagic-devel", $2);
	sub(/^fuse-devel$/, "libfuse-devel", $2);
	sub(/^gamin-python$/, "python-gamin", $2);
	sub(/^gcc-c\+\+$/, "libstdc++-devel", $2);
	sub(/^gnome-python2-extras$/, "python-gnome-extras", $2);
	sub(/^gnome-python2-gtkspell$/, "python-gnome-extras-gtkspell", $2);
	sub(/^gtk2$/, "gtk+2", $2);
	sub(/^gtk2-devel$/, "gtk+2-devel", $2);
	sub(/^initscripts$/, "rc-scripts", $2);
	sub(/^iscsi-initiator-utils$/, "open-iscsi", $2);
	sub(/^libXft-devel$/, "xorg-lib-libXft-devel", $2);
	sub(/^libXrandr-devel$/, "xorg-lib-libXrandr-devel", $2);
	sub(/^mod_wsgi$/, "apache-mod_wsgi", $2);
	sub(/^notify-python$/, "python-pynotify", $2);
	sub(/^pyOpenSSL$/, "python-pyOpenSSL", $2);
	sub(/^pygobject2$/, "python-pygobject", $2);
	sub(/^pygtk2$/, "python-pygtk", $2);
	sub(/^pygtk2-devel$/, "python-pygtk-devel", $2);
	sub(/^python-enchant$/, "python-pyenchant", $2);
	sub(/^python-imaging$/, "python-PIL", $2);
	sub(/^python-imaging-tk$/, "python-PIL-tk", $2);
	sub(/^python-pygtk$/, "python-pygtk-gtk", $2);
	sub(/^python2-devel$/, "python-devel", $2);
	sub(/^qt4-devel$/, "qt4-build", $2);
	sub(/^qtlockedfile-devel$/, "QtLockedFile-devel", $2);
	sub(/^tftp-server$/, "tftpdaemon", $2);
	sub(/^tkinter$/, "python-tkinter", $2);
	sub(/^xapian-bindings-python$/, "python-xapian", $2);

	# debian / ubuntu
	sub(/^blkid-dev$/, "libblkid-devel", $2);
	sub(/^ext2fs-dev$/, "e2fsprogs-devel", $2);
	sub(/^libao-dev$/, "libao-devel", $2);
	sub(/^libboost-filesystem[0-9.]+-dev$/, "boost-devel", $2);
	sub(/^libboost-program-options[0-9.]+-dev$/, "boost-devel", $2);
	sub(/^libboost-regex[0-9.]+-dev$/, "boost-devel", $2);
	sub(/^libboost-thread[0-9.]+-dev$/, "boost-devel", $2);
	sub(/^libcurl4-openssl-dev$/, "curl-devel", $2);
	sub(/^libdnet-dev$/, "libdnet-devel", $2);
	sub(/^libesd0-dev$/, "esound-devel", $2);
	sub(/^libfishsound1-dev$/, "libfishsound-devel", $2);
	sub(/^libgconf2-dev$/, "GConf2-devel", $2);
	sub(/^libgl1-mesa-dev$/, "OpenGL-devel", $2);
	sub(/^libgl1-mesa-dri$/, "OpenGL", $2);
	sub(/^libglib2.0-dev$/, "glib2-devel", $2);
	sub(/^libglu1-mesa-dev$/, "OpenGL-GLU-devel", $2);
	sub(/^libgtk2.0-dev$/, "gtk+2-devel", $2);
	sub(/^libhunspell-dev$/, "hunspell-devel", $2);
	sub(/^libmcrypt-dev$/, "libmcrypt-devel", $2);
	sub(/^libmhash-dev$/, "mhash-devel", $2);
	sub(/^liboggz1-dev$/, "libggz-devel", $2);
	sub(/^libpango1.0-dev$/, "pango-devel", $2);
	sub(/^libqt4-dev$/, "qt4-build", $2);
	sub(/^libshout3-dev$/, "libshout-devel", $2);
	sub(/^libslp-dev$/, "openslp-devel", $2);
	sub(/^libsndfile1-dev$/, "libsndfile-devel", $2);
	sub(/^libspeex-dev$/, "speex-devel", $2);
	sub(/^libssl-dev$/, "openssl-devel", $2);
	sub(/^libvorbis-dev$/, "libvorbis-devel", $2);
	sub(/^libxslt1-dev$/, "libxslt-devel", $2);
	sub(/^libxss-dev$/, "xorg-lib-libXScrnSaver-devel", $2);
	sub(/^mesa-common-dev$/, "OpenGL-devel", $2);

	replace_php_virtual_deps()
}

function replace_groupnames(group) {
	group = replace(group, "Amusements/Games", "Applications/Games");
	group = replace(group, "Amusements/Games/Strategy/Real Time", "X11/Applications/Games/Strategy");
	group = replace(group, "Application/Multimedia", "Applications/Multimedia");
	group = replace(group, "Application/System", "Applications/System");
	group = replace(group, "Applications/Compilers", "Development/Languages");
	group = replace(group, "Applications/Daemons", "Daemons");
	group = replace(group, "Applications/Internet", "Applications/Networking");
	group = replace(group, "Applications/Internet/Peer to Peer", "Applications/Networking");
	group = replace(group, "Applications/Productivity", "X11/Applications");
	group = replace(group, "Database", "Applications/Databases");
	group = replace(group, "Development/C", "Development/Libraries");
	group = replace(group, "Development/Code Generators", "Development");
	group = replace(group, "Development/Docs", "Documentation");
	group = replace(group, "Development/Documentation", "Documentation");
	group = replace(group, "Development/Java", "Development/Languages/Java");
	group = replace(group, "Development/Languages/Other", "Development/Languages");;
	group = replace(group, "Development/Languages/Ruby", "Development/Languages");
	group = replace(group, "Development/Libraries/C and C++", "Development/Libraries");
	group = replace(group, "Development/Libraries/Java", "Development/Languages/Java");
	group = replace(group, "Development/Libraries/Python", "Development/Languages/Python");
	group = replace(group, "Development/Libraries/TCL", "Development/Languages/Tcl");;
	group = replace(group, "Development/Other", "Development");
	group = replace(group, "Development/Python", "Development/Languages/Python");
	group = replace(group, "Development/Testing", "Development");
	group = replace(group, "Emulators", "Applications/Emulators");
	group = replace(group, "File tools", "Applications/File");
	group = replace(group, "Games", "Applications/Games");
	group = replace(group, "Library/Development", "Development/Libraries");
	group = replace(group, "Networking/Deamons", "Networking/Daemons");
	group = replace(group, "Productivity/Databases/Servers", "Applications/Databases");
	group = replace(group, "Productivity/Networking/Web/Servers", "Networking/Daemons/HTTP");;
	group = replace(group, "Shells", "Applications/Shells");
	group = replace(group, "System Environment/Base", "Base");
	group = replace(group, "System Environment/Daemons", "Daemons");
	group = replace(group, "System Environment/Kernel", "Base/Kernel");
	group = replace(group, "System Environment/Libraries", "Libraries");
	group = replace(group, "System Tools", "Applications/System");
	group = replace(group, "System", "Base");
	group = replace(group, "System/Base", "Base");
	group = replace(group, "System/Kernel and hardware", "Base/Kernel");
	group = replace(group, "System/Libraries", "Libraries");
	group = replace(group, "System/Servers", "Daemons");
	group = replace(group, "Text Processing/Markup/HTML", "Applications/Text");
	group = replace(group, "Text Processing/Markup/XML", "Applications/Text");
	group = replace(group, "User Interface/Desktops", "X11/Applications");
	group = replace(group, "Utilities/System", "Applications/System");
	group = replace(group, "Web/Database", "Applications/WWW");
	group = replace(group, "X11/GNOME", "X11/Applications");
	group = replace(group, "X11/GNOME/Applications", "X11/Applications");
	group = replace(group, "X11/GNOME/Development/Libraries", "X11/Development/Libraries");
	group = replace(group, "X11/Games", "X11/Applications/Games");
	group = replace(group, "X11/Games/Strategy", "X11/Applications/Games/Strategy");
	group = replace(group, "X11/Library", "X11/Libraries");
	group = replace(group, "X11/Utilities", "X11/Applications");
	group = replace(group, "X11/XFree86", "X11");
	group = replace(group, "X11/Xserver", "X11/Servers");
	group = replace(group, "Applications/Web", "Applications/WWW");

	return group;
}

# vim:ts=4:sw=4
