Summary:	Scripts for managing .spec files and building RPM packages
Summary(de.UTF-8):	Scripts fürs Bauen binärer RPM-Pakete
Summary(pl.UTF-8):	Skrypty pomocnicze do zarządznia plikami .spec i budowania RPM-ów
Summary(pt_BR.UTF-8):	Scripts e programas executáveis usados para construir pacotes
Summary(ru.UTF-8):	Скрипты и утилиты, необходимые для сборки пакетов
Summary(uk.UTF-8):	Скрипти та утиліти, необхідні для побудови пакетів
Group:		Applications/File
Requires:	rpm-build
Name:		rpm-build-tools
Version:	4.4.9
Release:	11
License:	GPL
Group:		Base
Source0:	builder
Source1:	adapter.awk
Source2:	adapter
Source3:	pldnotify.awk
Requires:	less
Requires:	wget
Suggests:	cvs
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
sed -e 's,^adapter=.*/adapter.awk,adapter=%{_libdir}/adapter.awk,' %{SOURCE2} > adapter

%install
rm -rf $RPM_BUILD_ROOT
install -d $RPM_BUILD_ROOT{%{_bindir},%{_libdir}}
install %{SOURCE0} $RPM_BUILD_ROOT%{_bindir}/builder
install adapter $RPM_BUILD_ROOT%{_bindir}/adapter
cp -a %{SOURCE1} $RPM_BUILD_ROOT%{_libdir}/adapter.awk
install %{SOURCE3} $RPM_BUILD_ROOT%{_bindir}/pldnotify.awk

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(644,root,root,755)
%attr(755,root,root) %{_bindir}/builder
%attr(755,root,root) %{_bindir}/adapter
%attr(755,root,root) %{_bindir}/pldnotify.awk
%{_libdir}/adapter.awk
