#!/bin/sh
# creates .spec using pear makerpm command.
# requires tarball to exist in ../SOURCES.
#
set -e
spec="$1"
tarball=$(rpm -q --qf '../SOURCES/%{name}-%{version}.tgz' --specfile "$spec" | sed -e 's,php-pear-,,')
template=$(rpm -q --qf '%{name}-%{version}.spec' --specfile "$spec")

pear makerpm $tarball
ls -l $template

# adjust template
# remove false sectons
sed -i -e '/^%if 0/,/%endif/d' $template
# and reversed true sections
sed -i -e '/^%if !1/,/%endif/d' $template
# kill consequtive blank lines
# http://info.ccone.at/INFO/Mail-Archives/procmail/Jul-2004/msg00132.html
sed -i -e '/./,$ !d;/^$/N;/\n$/D' $template

#rpmbuild -bb $spec

# prepare original spec
sed -i -e '
# simple changes
s/^%setup -q -c/%pear_package_setup/
/^BuildRequires:/s/rpm-php-pearprov >= 4.0.2-98/rpm-php-pearprov >= 4.4.2-11/g
s#^%doc %{_pearname}-%{version}#%doc docs/%{_pearname}#g

# make new %install section
/^%install$/,/^%clean$/{
/^%\(install\|clean\)/p

/^rm -rf/{p
a\
%pear_package_install\

}

d
}

' $spec

doc=$(grep '^%doc install' $template)
sed -i -e "
/%defattr(644,root,root,755)/a\
$doc
" $spec

vim -o $spec $template
exit 1
