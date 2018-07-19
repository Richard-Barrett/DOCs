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

# $Id: LDAPTools.pm,v 1.6 2013/10/30 21:03:14 lslile Exp $

package LDAPTools;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);# %EXPORT_TAGS);

$VERSION = 1.00;
@ISA	 = qw(Exporter);
@EXPORT	 = qw($opt_b $opt_d $opt_D $opt_h $opt_n $opt_p
	      $opt_P $opt_v $opt_w $opt_W $opt_x $opt_X
	      %ldap_opt @ldap_opts
	      get_ldap_config ldap_open ldap_common_usage);
@EXPORT_OK = qw();
#%EXPORT_TAGS = ( DEFAULT => [ qw() ],
#		    Both    => [ qw() ] );

use Net::LDAP qw(LDAP_REFERRAL LDAP_OPERATIONS_ERROR);
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant qw(LDAP_CONTROL_PAGED);
use Net::LDAP::LDIF;
use POSIX qw(:termios_h strftime);

# LDAP related command line options
our ($opt_b, $opt_d, $opt_D, $opt_h, $opt_n, $opt_p,
     $opt_P, $opt_v, $opt_w, $opt_W, $opt_x, $opt_X);

our %ldap_opt;

our @ldap_opts = ( 'b=s', 'd', 'D=s', 'h=s', 'n',
    'p=i', 'P=i', 'v', 'w=s', 'W', 'x', 'X=s' );

sub
get_ldap_config
{
	# Location of the OpenLDAP config file
	my @conf = qw( /etc/openldap/ldap.conf ~/.ldaprc ./.ldaprc );
	my %opts;

	foreach my $file (@conf)
	{
		# Open the config file
		open (FILE, "<", glob $file) or next;

		# Parse out the values we are interested in
		# server, basedn and port
		while (<FILE>)
		{
			s/#.*//;
			$opts{lc $1} = $2 if (m/\b(\w+)\b\s+(.*)/);
		}

		# Close the file
		close FILE;
	}

	return %opts;
}

sub
ldap_open
{
	use URI;

	my %args = @_;

	my $progressive = $args{progressive};

	# Load the basic LDAP configuration
	%ldap_opt = get_ldap_config();

	# Command line overrides for server, basedn and port
	$ldap_opt{'host'} = $opt_h if (defined $opt_h);
	$ldap_opt{'base'} = $opt_b if (defined $opt_b);
	$ldap_opt{'port'} = $opt_p if ($opt_p);

	$opt_P = 3 if ! $opt_P;

	# Default port for LDAP is 389/tcp if nothing else
	# was specified and name services are lacking the
	# entry
	$ldap_opt{'port'} = eval { getservbyname("ldap", "tcp") or "389" }
	    if (! $ldap_opt{'port'});

	# Do we have a valid server and basedn config?
	die "Unable to find ldap server name.\n"
	    if ! defined $ldap_opt{'host'} and ! defined $ldap_opt{'uri'};
	die "Unable to find ldap search base dn.\n"
	    if ! defined $ldap_opt{'base'};

	# Load the users LDAP password from the command
	# line or prompt for it if -w or -W respectively
	$opt_w = get_password("Enter LDAP password") if $opt_W;

	my @server;

	@server = split(/\s+/, $ldap_opt{'uri'}) if $ldap_opt{'uri'};

	if (defined $ldap_opt{'host'})
	{
		foreach my $host (split(/\s+/, $ldap_opt{'host'}))
		{
			if ($host =~ /^ldap:\/\//i)
			{
				push @server, "ldap://$host";
			}
			else
			{
				push @server, "ldap://$host";
			}
		}
	}

	# Build a connection to the ldap server
	my ($ldap, $result);
	foreach my $server (@server)
	{
		my $uri = URI->new($server);
		$server = $uri->host;
		my $port = defined $uri->port ? $uri->port : $ldap_opt{'port'};

		#($server, my $port) = split(/:/, $server, 2);
		#$port = $ldap_opt{'port'} if ! $port;

		warn "\nAttempting to contact $server\n" if $opt_d;

		if ($progressive)
		{
			($ldap, $result) = ldap_connect_progressive($server, $port);
		} else {
			($ldap, $result) = ldap_connect($server, $port);
		}
		warn $@ and next if ! $ldap;

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
	die "\n" if ! $ldap or ! $result;

	return ($ldap, $result);
}

sub
ldap_connect
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

	if (! $opt_x)
	{
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
	}
	else
	{
		warn "Starting simple authentication\n" if $opt_d;
		# Simple authentication to LDAP
		if (!($ldap = new Net::LDAP(
					$server,
					port	=> $port,
					version	=> $opt_P,
					)))
		{
	 		$@ = "Unable to init for $server: $@\n";
			return;
		}

		if ($opt_D)
		{
			# with a specific bind_dn
			warn "Binding to LDAP dn: $opt_D\n" if $opt_d;
			if ($opt_w or $opt_W)
			{
				# and password
				$result = $ldap->bind($opt_D,
				    password => $opt_w);
			}
			else
			{
				$result = $ldap->bind($opt_D);
			}
		}
		else
		{
			# Anonymous
			warn "Binding to LDAP anonymously\n" if $opt_d;
			$result = $ldap->bind;
		}
	}
	return ($ldap, $result);
}

sub
ldap_connect_progressive
{
	use Storable;

	my $server  = shift;
	my $port    = shift;

	my $fqdn;
	my $result;
	my $ldap;

	my @pwent = getpwuid($<) or
	    die "Go away, you don't exist.\n";
	my $uid = $pwent[0];
	my $uidNumber = $pwent[2];
	my $gidNumber = $pwent[3];
        my $home = $pwent[7];

	# Get our fqdn, we will need it if we authenticate
	if (!(($fqdn) = gethostbyname($server)))
	{
		$@ = "Unable to resolve host name $server\n";
		return undef;
	}

	my $now = time;
	my $cache = "/tmp/ldapcc_$uidNumber";
	my %cred;
	if (my (@stat) = stat $cache)
	{
		if ($now < $stat[9] + (5 * 60))
		{
			my $rcache = retrieve($cache)
			    or die "Unable to read cache $cache\n";
			%cred = %$rcache;
		} 
	} else {
		warn "No cache file $cache.\n" if $opt_d;
	}

	$opt_D = $cred{'binddn'} if ! defined $opt_D;
	$opt_w = $cred{'passwd'} if ! defined $opt_w;

	# Create connection to LDAP server
	if (!($ldap = new Net::LDAP(
				$server,
				port	=> $port,
				version	=> $opt_P,
				)))
	{
			$@ = "Unable to init for $server: $@\n";
		return;
	}

	if ( ! defined $opt_D )
	{
		# Make an anonymous bind
		warn "Initial LDAP anonymous bind\n" if $opt_d;
		$result = $ldap->bind;

		if ( ! $result->code )
		{
			$result = $ldap->search(
				base	=> $ldap_opt{'base'},
				filter	=> "(&(objectClass=posixAccount)(uid=$uid))",
				scope	=> 'sub',
					);

			if (! $result->code and $result->count == 1)
			{
				my $entry = $result->shift_entry;
				$opt_D = $entry->dn;
				warn "BindDN determined to be $opt_D.\n"
				    if $opt_d;
			} 
		}
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

	# Return bound connection if SASL bind succeeded.
	return ($ldap, $result) if ! $result->code;

	warn "Starting simple authentication\n" if $opt_d;

	if ( ! defined $opt_w )
	{
		# Load the users LDAP password from the command
		# line or prompt for it if -w or -W respectively
		$opt_w = get_password("Enter LDAP password");
	}

	if ($opt_D)
	{
		# with a specific bind_dn
		warn "Binding to LDAP dn: $opt_D\n" if $opt_d;
		if ($opt_w or $opt_W)
		{
			# and password
			$result = $ldap->bind($opt_D,
			    password => $opt_w);
		}
	}
	else
	{
		# Anonymous
		warn "Binding to LDAP anonymously\n" if $opt_d;
		$result = $ldap->bind;
	}

	if ( ! $result->code )
	{
		$cred{'binddn'} = $opt_D;
		$cred{'passwd'} = $opt_w;
		store \%cred, $cache
		    or warn "Unable to store credentail cache $cache.\n";
		chmod 0600, $cache;
		chown $uidNumber, $gidNumber, $cache;
	}

	return ($ldap, $result);
}

sub
ldap_entry
{
	my $entry = shift;

	my @rc;

	push @rc, "dn: ".$entry->dn."\n";
	push @rc, "changetype: add\n";
	foreach my $attr (sort $entry->attributes)
	{
		push @rc, "attr: $attr\n";
		foreach ($entry->get_value($attr))
		{
			push @rc, "$attr: ", ($_ ? $_ : ""), "\n";
		}
	}

	@rc;
}

sub
ldap_mods
{
	my $entry = shift;
	my $changes = shift;

	my @rc;

	return if !$changes or !$entry;

	push @rc, "dn: " . $entry->dn . "\n";
	push @rc, "changetype: modify\n";
	foreach my $attr (keys %$changes)
	{
		push @rc, "replace: $attr\n";
		foreach (@{$changes->{$attr}})
		{
			push @rc, "$attr: $_\n";
		}
		push @rc, "# $attr: " . join("\n# $attr: ", $entry->get_value($attr)) . "\n";
		push @rc, "-\n";
	}

	@rc;
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

sub
ldap_common_usage
{
	print "
 LDAP options:
  -b basedn	      base dn for searches
  -D binddn	      bind DN
  -h host             LDAP server (implies -N)
  -p port	      port on LDAP server
  -P 2|3	      procotol version (default: 3)
  -v                  run in verbose mode
  -w password         bind password (for simple authentication)
  -W                  prompt for bind password
  -x                  use simple authentication (default: SASL/GSSAPI)
  -X authzid          SASL authorization identity (\"dn:<dn>\" or \"u:<user>\")
";
}

1;
