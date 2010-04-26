Summary:	Scripts for managing .spec files and building RPM packages
Summary(de.UTF-8):	Scripts fürs Bauen binärer RPM-Pakete
Summary(pl.UTF-8):	Skrypty pomocnicze do zarządznia plikami .spec i budowania RPM-ów
Summary(pt_BR.UTF-8):	Scripts e programas executáveis usados para construir pacotes
Summary(ru.UTF-8):	Скрипты и утилиты, необходимые для сборки пакетов
Summary(uk.UTF-8):	Скрипти та утиліти, необхідні для побудови пакетів
Name:		rpm-build-tools
Version:	4.4.39
Release:	1
License:	GPL
Group:		Applications/File
Group:		Base
Source0:	builder.sh
Source1:	adapter.awk
Source2:	adapter.sh
Source3:	pldnotify.awk
BuildRequires:	sed >= 4.0
Requires:	gawk >= 3.1.7
Requires:	grep
Requires:	less
Requires:	perl-base
Requires:	rpm-build
Requires:	rpm-build-macros >= 1.539
Requires:	sed >= 4.0
Requires:	util-linux
Requires:	wget
Suggests:	cvs-client
Suggests:	rpm-specdump >= 0.3
Suggests:	schedtool
BuildArch:	noarch
BuildRoot:	%{tmpdir}/%{name}-%{version}-root-%(id -u -n)

%define		_libdir	%{_prefix}/lib

%description
Scripts for managing .spec files and building RPM packages.

%description -l de.UTF-8
Scripts fürs Bauen RPM-Pakete.

%description -l pl.UTF-8
Skrypty pomocnicze do zarządzania plikami .spec i do budowania RPM-ów.

%description -l pt_BR.UTF-8
Este pacote contém scripts e programas executáveis que são usados para
construir pacotes usando o RPM.

%description -l ru.UTF-8
Различные вспомогательные скрипты и исполняемые программы, которые
используются для сборки RPM'ов.

%description -l uk.UTF-8
Різноманітні допоміжні скрипти та утиліти, які використовуються для
побудови RPM'ів.

%prep
%setup -qcT
cp -p %{SOURCE0} %{SOURCE1} %{SOURCE2} %{SOURCE3} .

%{__sed} -i -e 's,^adapter=.*/adapter.awk,adapter=%{_libdir}/adapter.awk,' adapter.sh

%{__sed} -i -e '/^VERSION=/s,\([^/]\+\)/.*",\1-RELEASE",' builder.sh adapter.sh
%{__sed} -i -e '/\tRCSID =/,/^\trev =/d;/\tVERSION = /s,\([^/]\+\)/.*,\1-RELEASE",' adapter.awk

%install
rm -rf $RPM_BUILD_ROOT
install -d $RPM_BUILD_ROOT{%{_bindir},%{_libdir}}
cp -a adapter.awk $RPM_BUILD_ROOT%{_libdir}/adapter.awk
install -p pldnotify.awk $RPM_BUILD_ROOT%{_bindir}
install -p builder.sh $RPM_BUILD_ROOT%{_bindir}/builder
install -p adapter.sh $RPM_BUILD_ROOT%{_bindir}/adapter

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(644,root,root,755)
%attr(755,root,root) %{_bindir}/builder
%attr(755,root,root) %{_bindir}/adapter
%attr(755,root,root) %{_bindir}/pldnotify.awk
%{_libdir}/adapter.awk
