#!/bin/sh
# creates .spec using pear makerpm command.
# requires tarball to exist in ../SOURCES.
#
set -e
spec="$1"
tarball=(rpm -q --qf '../SOURCES/%{name}-%{version}.tgz\n' --specfile "$spec" | head -n 1 | sed -e 's,php-pear-,,')
template=$(rpm -q --qf '%{name}-%{version}.spec\n' --specfile "$spec" | head -n 1)

if [ ! -f $tarball ]; then
	./builder -g $spec
fi
pear makerpm $tarball
ls -l $spec $template

# adjust template
# remove false sectons
sed -i -e '/^%if 0/,/%endif/d' $template
# and reversed true sections
sed -i -e '/^%if !1/,/%endif/d' $template
# kill consequtive blank lines
# http://info.ccone.at/INFO/Mail-Archives/procmail/Jul-2004/msg00132.html
sed -i -e '/./,$ !d;/^$/N;/\n$/D' $template

rpm=$(rpm -q --qf '../RPMS/%{name}-%{version}-%{release}.noarch.rpm\n' --specfile "$spec" | head -n 1)
if [ ! -f $rpm ]; then
	rpmbuild -bb $spec
fi

# prepare original spec
sed -i -e '
# simple changes
s/^%setup -q -c/%pear_package_setup/
/^BuildRequires:/s/rpm-php-pearprov >= 4.0.2-98/rpm-php-pearprov >= 4.4.2-11/g
/^%doc %{_pearname}-%{version}/d

# make new %install section
/^%install$/,/^%clean$/{
/^%\(install\|clean\)/p

/^rm -rf/{p
a\
install -d $RPM_BUILD_ROOT%{php_pear_dir}\
%pear_package_install\

}

d
}

' $spec

instdoc=$(grep '^%doc install' $template || :)
sed -i -e "
/%defattr(644,root,root,755)/a\
$instdoc
" $spec

doc=$(grep '^%doc docs/%{_pearname}/' $template || :)
if [ "$doc" ]; then
sed -i -e '/^%doc/a\
%doc docs/%{_pearname}/*
' $spec
fi

perl -pi -e '
	if (/^%{php_pear_dir}/ && !$done) {
		print "%{php_pear_dir}/.registry/*.reg\n";
		$done = 1;
	}
' $spec

if grep -q '^%files tests' $template; then
	sed -i -e '
/^%define.*date/{
i\
%files tests\
%defattr(644,root,root,755)\
%{php_pear_dir}/tests/*\

}

/^%prep/{
i\
%package tests\
Summary:	Tests for PEAR::%{_pearname}\
Summary(pl):	Testy dla PEAR::%{_pearname}\
Group:		Development\
Requires:	%{name} = %{epoch}:%{version}-%{release}\
AutoReq:	no\
\
%description tests\
Tests for PEAR::%{_pearname}.\
\
%description tests -l pl\
Testy dla PEAR::%{_pearname}.\

}
' $spec
fi

_noautoreq=$(grep '%define.*_noautoreq' $template || :)
if [ "$_noautoreq" ]; then
	sed -i -e "/^BuildRoot:/{
a\\
\\
# exclude optional dependencies\\
$_noautoreq
}
" $spec

	sed -i -e '/^%files/{
i\
%post\
if [ -f %{_docdir}/%{name}-%{version}/optional-packages.txt ]; then\
	cat %{_docdir}/%{name}-%{version}/optional-packages.txt\
fi\

}
' $spec

fi

vim -o $spec $template
