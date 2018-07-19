# Copyright (c) 2003-2013, Larry Lile <lile@FreeBSD.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice unmodified, this list of conditions, and the following
#    disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

# $Id: ADTools.pm,v 1.1 2013/05/23 20:21:00 lslile Exp $

package ADTools;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);# %EXPORT_TAGS);

$VERSION = 1.00;
@ISA	 = qw(Exporter);
@EXPORT	 = qw(
		ad_open
		ad_connect
		defaultNamingContext

		ADS_UF_SCRIPT
		ADS_UF_ACCOUNTDISABLE
		ADS_UF_HOMEDIR_REQUIRED
		ADS_UF_LOCKOUT
		ADS_UF_PASSWD_NOTREQD
		ADS_UF_PASSWD_CANT_CHANGE
		ADS_UF_ENCRYPTED_TEXT_PASSWORD_ALLOWED
		ADS_UF_TEMP_DUPLICATE_ACCOUNT
		ADS_UF_NORMAL_ACCOUNT
		ADS_UF_INTERDOMAIN_TRUST_ACCOUNT
		ADS_UF_WORKSTATION_TRUST_ACCOUNT
		ADS_UF_SERVER_TRUST_ACCOUNT
		ADS_UF_DONT_EXPIRE_PASSWD
		ADS_UF_MNS_LOGON_ACCOUNT
		ADS_UF_SMARTCARD_REQUIRED
		ADS_UF_TRUSTED_FOR_DELEGATION
		ADS_UF_NOT_DELEGATED
		ADS_UF_USE_DES_KEY_ONLY
		ADS_UF_DONT_REQUIRE_PREAUTH
		ADS_UF_PASSWORD_EXPIRED
		ADS_UF_TRUSTED_TO_AUTHENTICATE_FOR_DELEGATION

	    );
@EXPORT_OK = qw();
#%EXPORT_TAGS = ( DEFAULT => [ qw() ],
#		    Both    => [ qw() ] );

use LDAPTools;
use Carp;
use Net::LDAP qw(LDAP_REFERRAL LDAP_OPERATIONS_ERROR);
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant qw(LDAP_CONTROL_PAGED);
use Net::LDAP::LDIF;
use POSIX qw(:termios_h strftime);
use Authen::Krb5;

# From ADSIEnumerations.pm
use constant ADS_UF_SCRIPT => 0x1;
use constant ADS_UF_ACCOUNTDISABLE => 0x2;
use constant ADS_UF_HOMEDIR_REQUIRED => 0x8;
use constant ADS_UF_LOCKOUT => 0x10;
use constant ADS_UF_PASSWD_NOTREQD => 0x20;
use constant ADS_UF_PASSWD_CANT_CHANGE => 0x40;
use constant ADS_UF_ENCRYPTED_TEXT_PASSWORD_ALLOWED => 0x80;
use constant ADS_UF_TEMP_DUPLICATE_ACCOUNT => 0x100;
use constant ADS_UF_NORMAL_ACCOUNT => 0x200;
use constant ADS_UF_INTERDOMAIN_TRUST_ACCOUNT => 0x800;
use constant ADS_UF_WORKSTATION_TRUST_ACCOUNT => 0x1000;
use constant ADS_UF_SERVER_TRUST_ACCOUNT => 0x2000;
use constant ADS_UF_DONT_EXPIRE_PASSWD => 0x10000;
use constant ADS_UF_MNS_LOGON_ACCOUNT => 0x20000;
use constant ADS_UF_SMARTCARD_REQUIRED => 0x40000;
use constant ADS_UF_TRUSTED_FOR_DELEGATION => 0x80000;
use constant ADS_UF_NOT_DELEGATED => 0x100000;
use constant ADS_UF_USE_DES_KEY_ONLY => 0x200000;
use constant ADS_UF_DONT_REQUIRE_PREAUTH => 0x400000;
use constant ADS_UF_PASSWORD_EXPIRED => 0x800000;
use constant ADS_UF_TRUSTED_TO_AUTHENTICATE_FOR_DELEGATION => 0x1000000;

# LDAP related command line options
#our ($opt_b, $opt_d, $opt_D, $opt_h, $opt_n, $opt_p,
#     $opt_P, $opt_v, $opt_w, $opt_W, $opt_x, $opt_X);

our %ldap_opt;

#our @ldap_opts = ( 'b=s', 'd', 'D=s', 'h=s', 'n',
#    'p=i', 'P=i', 'v', 'w=s', 'W', 'x', 'X=s' );

our $samaccountname;

sub
ad_open
{
	my $samaccountname = shift;
	my $password = shift;

	my $this_function = (caller(0))[3];

	# XXX Maybe it should just be 00 + $samaccountname, not sure
	$samaccountname = sprintf("%s%s",
	    substr("000000", 0, 7 - length($samaccountname)), $samaccountname)
		if defined $samaccountname and length $samaccountname < 6;

	my $context = Authen::Krb5::init_context();
	confess("Failed to initialize kerberos ", Authen::Krb5::error(), "\n")
	    if ! defined $context;

	my $realm = Authen::Krb5::get_default_realm();
	confess("Unable to determine default realm ", Authen::Krb5::error(), "\n")
	    if ! defined $realm;

	my $servp = Authen::Krb5::parse_name("krbtgt/$realm");
	confess("Unable to determine parse tgt request for $realm ", Authen::Krb5::error(), "\n")
	    if ! defined $servp;

	my $cc = Authen::Krb5::cc_default();
	confess("Unable to acquire default credentials cache ", Authen::Krb5::error(), "\n")
	    if ! defined $cc;

	my $valid;
	my $initialize;
	my $cursor = $cc->start_seq_get();
	if ($cursor)
	{
		while (my $cred = $cc->next_cred($cursor))
		{
			if (! defined $samaccountname and $cred->server =~ /^krbtgt/)
			{
				$samaccountname = $cred->client;
				$samaccountname =~ s/\@.*//;
			}
			next if $cred->server !~ /^krbtgt/;
			$valid = 1 if $cred->endtime > time();
			last if $valid;
		}
		$cc->end_seq_get($cursor);
	} else {
		#$cc->initialize($userp);
		$initialize = 1;
	}

	if ($> == 0 && $< != 0)
	{
		my $cc_file = Authen::Krb5::cc_default_name();
		$cc_file =~ s/^FILE://g;
		chown $>, $cc_file;
	}

	if (! defined $samaccountname)
	{
		print "Account name for realm $realm: ";
		chomp($samaccountname = <STDIN>);
	}

	my $userp = Authen::Krb5::parse_name($samaccountname);
	confess("Failed to parse principal $samaccountname ", Authen::Krb5::error(), "\n")
	    if ! defined $userp;

	$cc->initialize($userp) if defined $initialize;

	if (!$valid)
	{
		# XXX Try this with the cached LDAP password
		my $tgt = Authen::Krb5::get_in_tkt_with_password($userp, $servp, $password, $cc)
		    if defined $password;

		if (! defined $tgt)
		{
			my $ad_pw = get_password(
			    "Active Directory password for $samaccountname\@$realm"
				);
			$tgt = Authen::Krb5::get_in_tkt_with_password($userp, $servp, $ad_pw, $cc);	
		}

		confess("Failed to get tgt for $samaccountname\@$realm ", Authen::Krb5::error(), "\n")
		    if ! defined $tgt;
	}

	use Net::DNS;

	my @server;
	my $res = Net::DNS::Resolver->new;
	my $query = $res->query("_ldap._tcp." . $realm, "SRV");
	if ($query)
	{
		foreach my $rr ( grep { $_ ->type eq 'SRV' }
		    sort { $a->priority <=> $b->priority }
			$query->answer )
		{
			my $scheme = $rr->port == 636 ? 'ldaps://' : 'ldap://';
			push @server, $scheme . $rr->target . ':' . $rr->port;
		}
	}

	use URI;

	# Build a connection to the ldap server
	my ($ad, $result);
	foreach my $server (@server)
	{
		my $uri = URI->new($server);
		$server = $uri->host;
		my $port = defined $uri->port ? $uri->port : '389';

		warn "\nAttempting to contact $server\n" if $opt_d;

		($ad, $result) = ad_connect($server, $port);
		warn $@ and next if ! $ad;

		if ($result and $result->code)
		{
			warn "Failed to bind $server: ", $result->error, "\n";
			next;
		}
		elsif ($result)
		{
			last;
		}
	}
	die "\n" if ! $ad or ! $result;

	return wantarray ? ($ad, $result) : $ad;


}

sub
ad_connect
{
	my $server  = shift;
	my $port    = shift;

	my $fqdn;
	my $result;
	my $ldap;

	my $uid;

	my @pwent = getpwuid($<) or
	    die "Go away, you don't exist.\n";
	$uid = $pwent[0];

	# Get our fqdn, we will need it if we authenticate
	if (!(($fqdn) = gethostbyname($server)))
	{
		$@ = "Unable to resolve host name $server\n";
		return undef;
	}

	warn "Starting SASL/GSSAPI authentication\n" if $opt_d;
	# SASL/GSSAPI authentication to LDAP
	if (!($ldap = new Net::LDAP(
				$server,
				port	=> $port,
				version	=> $opt_P,
				)))
	{
		$@ = "Unable to init for $server: $@\n";
		return;
	}

	my $authzid = $opt_X;
	$authzid = "dn:$opt_D" if $opt_D and ! $opt_X;

	my $bind_dn = $opt_D;
	$bind_dn = "uid=$uid" if ! $opt_D;

	use Authen::SASL;
	my $sasl = Authen::SASL->new(
			'GSSAPI',
			'service'=> 'ldap',
			'fqdn'	=> $fqdn,
			'user'	=> ($authzid ? $authzid : ''),
			);

	warn "Binding to LDAP $bind_dn\n" if $opt_d;
	warn "SASL authzid: $authzid\n" if $opt_d and $authzid;
	$result = $ldap->bind($bind_dn, sasl => $sasl);

	return ($ldap, $result);
}

sub
defaultNamingContext
{
	my $ldap = shift;

	my $this_function = (caller(0))[3];

	croak("$this_function(\$ldap) no Net::LDAP object provided")
	    if ! defined $ldap or ref $ldap ne "Net::LDAP";

	my $result = $ldap->search(
	    base => "", scope => "base", filter => "(objectClass=*)",
	    attrs => [ 'defaultNamingContext' ]);

	confess("LDAP error querying defaultNamingContext ", $result->error, "\n")
	    if $result->code;

	confess("Unexpected result for rootDSE\n")
	    if $result->count != 1;


	my $rootDSE = $result->shift_entry;

	return $rootDSE->get_value('defaultNamingContext')
	    if $rootDSE->exists('defaultNamingContext');
}

sub
get_password
{
	my $prompt = shift;
	my $r;
	my $term = POSIX::Termios->new;
	my $echo = (ECHO | ECHOK);
	my $stdin = fileno(STDIN);
	my $oterm;

	# Reading a password from stdin, we should go
	# into noecho mode to keep people from reading
	# over our shoulders
	$term->getattr($stdin);
	$oterm = $term->getlflag;

	print "$prompt: ";
	# Set no echo mode
	$term->setlflag($oterm & ~$echo);
	$term->setattr($stdin, TCSANOW);
	# Read the passwd
	chomp($r = <STDIN>);
	# Restore the terminal settings
	$term->setlflag($oterm);
	$term->setattr($stdin, TCSANOW);
	# Push down a line since the <cr> didn't echo
	print "\n";

	return $r;
}

1;
