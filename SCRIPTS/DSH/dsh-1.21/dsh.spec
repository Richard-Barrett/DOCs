%define ver	1.21
%define	RELEASE	1
%define rel	%{?CUSTOM_RELEASE} %{!?CUSTOM_RELEASE:%RELEASE}

Summary: Distributed Shell
Name: dsh
Version: %ver
Release: %rel
Copyright: BSD
Group: System Environment/Shells
Source: http://prdownloads.sourceforge.net/yadsh/dsh-%{ver}.tar.gz
BuildRoot: /var/tmp/dsh-%{PACKAGE_VERSION}-root
Packager: Larry Lile <lile@users.sourceforge.net>
Prefix: /usr

%description
Dsh is a parallel distributed shell.  It allows the user to
execute the same commands in parallel across many hosts at 
once using a variety of remote shells such as: rsh, kerberized
rsh and ssh.

%changelog

%prep
%setup

%build

%configure \
	--prefix=%prefix \
	--with-rsh=/usr/bin/rsh \
	--with-dshpath=/sbin:/usr/sbin:/bin:/usr/bin:/etc/usr/kerberos/sbin:/usr/kerberos/bin:/usr/local/bin:/usr/local/sys/bin
make

%install
rm -rf $RPM_BUILD_ROOT

make install DESTDIR=$RPM_BUILD_ROOT

%clean
[ -n "$RPM_BUILD_ROOT" -a "$RPM_BUILD_ROOT" != / ] && rm -rf $RPM_BUILD_ROOT

%files
%defattr(-, root, root)

%{prefix}/bin/*
%{prefix}/share/man/man1/*
