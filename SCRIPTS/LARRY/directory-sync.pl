#!/usr/bin/perl -w

#
# COPYRIGHT (c) 2013 DirecTV, L.L.C.  All Rights Reserved
#
# This software program and documentation are confidential and proprietary
# information of DirecTV L.L.C. ("Confidential Information"). You shall
# not disclose such Confidential Information and shall use it only in
# accordance with the terms of the license agreement you entered into with
# DirecTV.
#
# The software program and documentation are supplied "AS IS", without any
# accompanying services from DirecTV. DirecTV does not warrant that the
# operation of the program will be uninterrupted or error-free. The end-user
# understands that the program was developed for research purposes and is
# advised not to rely exclusively on the program for any reason.
#
# IN NO EVENT SHALL DIRECTV BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT,
# SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING, BUT NOT LIMITED TO,
# LOST PROFITS ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION,
# EVEN IF DIRECTV HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
# DIRECTV HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES,
# ENHANCEMENTS, OR MODIFICATIONS. DIRECTV MAKES NO REPRESENTATIONS OR
# WARRANTIES ABOUT THE SUITABILITY OF THE SOFTWARE, EITHER EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT. DIRECTV SHALL NOT
# BE LIABLE FOR ANY DAMAGES SUFFERED BY LICENSEE AS A RESULT OF USING,
# MODIFYING, OR DISTRIBUTING THIS SOFTWARE OR ITS DERIVATIVES.
#

#
# $Id: directory-sync.pl,v 1.8 2013/10/24 23:09:47 lslile Exp $
#

use strict;

use Symbol 'qualify_to_ref';
use Net::LDAP qw(LDAP_REFERRAL LDAP_OPERATIONS_ERROR);
use Net::LDAP::Control::Paged;
use Net::LDAP::LDIF;
use Getopt::Long qw(:config bundling noignore_case require_order);
use Digest::MD5;
use Fcntl;
use POSIX qw(:termios_h tmpnam strftime);
use URI;
use Mail::Sendmail;
use LWP;

use lib ("../../../libraries/trunk/perl/tools", "/opt/scripts/ldap/share/perl5/tools");

use ADTools;

# DEN Employee Search url
my $wpurl = 'http://whitepages.directv.com/search';

# AD to LDAP attribute hash organized by LDAP objectClass
my %acct_attr_hash = (
    "inetOrgPerson" => {
	"department" => "departmentNumber",
	"mail" => "mail",
	"manager" => "manager",
		},
    "organizationalPerson" => {
	"cn" => "cn",
	"givenName" => "givenName",
	"l" => "l",
	"physicalDeliveryOfficeName" => "physicalDeliveryOfficeName",
	"sn" => "sn",
	"telephoneNumber" => "telephoneNumber",
	"title" => "title",
		},
    "posixAccount" => {
	"cn" => "cn",
		},
    "mailRecipient" => {
	"mail" => "mailRoutingAddress",
		},
    "ntUser" => {
	"ntUserDomainID" => "sAMAccountName",
		},
    );

# DEN => AD attribute overrides, "supervisor" => manager is synthesized later
my %wp_attr_hash = (
    mail => "email",
    departmentnumber => "org",
    manager => "manager",
    #cn => "name",
    #employeenumber => "id",
    #physicaldeliveryofficename => "address",
    title => "title",
    #physicaldeliveryofficeName => "room",
    telephonenumber => "phone",
    );

# Mapping of AD OU to LDAP OU
my %ou_map = (
    "ou=regular users" => "ou=DirecTV",
    "ou=contractors" => "ou=DirecTV Contractor",
	    );

our ($opt_b, $opt_c, $opt_C, $opt_d, $opt_D,
     $opt_e, $opt_E, $opt_F, $opt_h, $opt_i,
     $opt_l, @opt_m, $opt_n, $opt_N, $opt_p,
     $opt_P, $opt_r, $opt_s, $opt_S, $opt_T, $opt_v,
     $opt_V, $opt_w, $opt_W, $opt_x, $opt_X,
     $opt_add, $opt_adD, $opt_adh, $opt_adb, $opt_adp,
     $opt_adw, $opt_adW);

# Logging and debug messages
sub debug_msg(@) { print @_ if $opt_d }
sub verbose(@) { print @_ if $opt_v }

our $msgs_logged;
{
  my $logbuffer = '';
  sub clear_log_msg_buffer() { $logbuffer = ''; }
  sub log_msg_buffer(@)
  {
	my @msg = @_;
	print @msg if $opt_v;
	foreach (@msg)
	{
		$logbuffer = sprintf "%s%s", $logbuffer, $_;
	}
  }
  sub log_msg(*@)
  {
	my $fh = qualify_to_ref(shift, caller);
	my @msg = @_;
	print @msg if $opt_v;
	if (length $logbuffer)
	{
		print $fh $logbuffer;
		clear_log_msg_buffer;
	}
	print $fh @_;
	$msgs_logged = defined $msgs_logged ? $msgs_logged + 1 : 1;
  }
}

our (%connection_cache, %config, %maps, $uid, $home,
     $logfile, $signaled);

# Forcibly disable SASL Cyrus
our $Authen_SASL_Cyrus = 0;

our $maxlogfiles = 30;

GetOptions( 'b=s', 'c', 'C=s', 'd', 'D=s',
	    'e=s', 'E', 'F=s', 'h=s', 'i=s',
	    'l=s', 'n', 'N', 'p=i', 'P=i',
	    'r=s', 's=s', 'S:s', 'T=s', 'v', 'V',
	    'w=s', 'W', 'x', 'X=s',
	    'm=s' => \@opt_m,
	    'adD=s', 'add=s', 'adh=s', 'adb=s', 'adp=i',
	    'adw=s', 'adW',
	) or usage() and exit 0;


# Load the basic LDAP configuration
my %ldap_opt = get_ldap_config();

# AD LDAP configuration
my %ad_ldap_opt;

# Command line overrides for server, basedn and port
$ad_ldap_opt{'host'} = $opt_adh if (defined $opt_adh);
$ad_ldap_opt{'base'} = $opt_adb if (defined $opt_adb);
$ad_ldap_opt{'port'} = $opt_adp if ($opt_adp);

# Command line overrides for server, basedn and port
$ldap_opt{'host'} = $opt_h if (defined $opt_h);
$ldap_opt{'base'} = $opt_b if (defined $opt_b);
$ldap_opt{'port'} = $opt_p if ($opt_p);

# Copy back if not set
$opt_b = $ldap_opt{'base'} if ! defined $opt_b;

$opt_P = 3 if ! $opt_P;

# Set the default from address, if it wasn't given
$opt_F = "root"
	if (!$opt_F);

# Set the default from address, if it wasn't given
$opt_T = "root"
	if (!$opt_T);

# Set the default log file name, if it wasn't given
$opt_l = "/var/log/directory-sync/directory-sync-$opt_b-" .
    strftime("%G_%m_%d_%H%M%S", localtime($^T)) . ".ldif"
	if (!$opt_l);

debug_msg "Log file: $opt_l\n";

debug_msg "Log will be mailed to: ", join(", ", @opt_m), "\n"
	if @opt_m;

# Default port for LDAP is 389/tcp if nothing else
# was specified and name services are lacking the
# entry
$ldap_opt{'port'} = eval { getservbyname("ldap", "tcp") or "389" }
    if (! $ldap_opt{'port'});
$ad_ldap_opt{'port'} = eval { getservbyname("ldap", "tcp") or "389" }
    if (! $ad_ldap_opt{'port'});


# Do we have a valid server and basedn config?
die "Unable to find ldap server name.\n"
    if ! defined $ldap_opt{'host'};
die "Unable to find ldap search base dn.\n"
    if ! defined $ldap_opt{'base'};

# Load the users LDAP password from the command
# line or prompt for it if -w or -W respectively
$opt_w = get_password("Enter LDAP password") if $opt_W;

# Load the users AD password from the command
# line or prompt for it if --adw or --adW respectively
$opt_adw = get_password("Enter Active Directory password") if $opt_adW;

# Open the log file
sysopen(LH, $opt_l, O_TRUNC|O_WRONLY|O_CREAT) or
	die "Unable to open log file: $opt_l\n";
select((select(LH), $| = 1)[0]); # Set the log file to autoflush
END { log_rotate() if !$opt_d and $opt_l; }
END { mail_log() if defined $msgs_logged and !$opt_d and $opt_l; }

# Get an LWP browser
my $browser = LWP::UserAgent->new;

# Build a connection to the ldap server
my ($ldap, $result);
foreach my $server (split(/\s+/, $ldap_opt{'host'}))
{
	($server, my $port) = split(/:/, $server, 2);
	$port = $ldap_opt{'port'} if ! $port;

	debug_msg "\nAttempting to contact $server\n";

	($ldap, $result) = ldap_connect($server, $port);
	debug $@ and next if ! $ldap;

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

# Connect to AD
my ($ad_ldap, $ad_result) = ad_open($opt_adD, $opt_adw);

# Query LDAP for accounts with employee numbers
my $filter = '(&(objectClass=posixAccount)(employeeNumber=*))';
#$filter = '(&(objectClass=posixAccount)(employeeNumber=455339))';
#$filter = '(&(objectClass=posixAccount)(uid=brice))';

debug_msg "Querying ", $ldap_opt{'base'}, " for $filter\n";

$result = $ldap->search(
	base   => $ldap_opt{'base'},
	filter => $filter,
	scope  => 'sub',
	);

$result->code && die "LDAP query failed: ", $result->error;

# Walk the LDAP result set, sorted to make debugging easier
foreach my $entry ($result->sorted('cn', 'sn', 'givenName', 'uid'))
{
	my $who =  $entry->exists('employeeNumber') ?
		"employee number " . $entry->get_value('employeeNumber') :
		"user id " . $entry->get_value('uid');

	debug_msg "Working on $who ", "(", $entry->dn, ")\n";

	my $empno = $entry->get_value("employeeNumber");

	if (! defined $empno)
	{
		debug_msg "No employee number, can't sync with AD\n\n";
		next;
	}

	my $ad_entry;

	# Query AD for this employee number
	my $filter = "(&(objectClass=user)(objectClass=person)" .
		     "(employeeID=$empno))";

	debug_msg "Query AD ", $ad_ldap_opt{'base'}, "?$filter\n";
	$result = $ad_ldap->search(
				base   => $ad_ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				);

	$result->code && die "AD query $filter failed: ", $result->error;

	if ($result->count == 0)
	{
		# Can't do anything if we didn't find them
		debug_msg "No account found for $who\n\n";
		next;
	}
	elsif ($result->count > 1)
	{
		# See if we can match
		foreach my $tmp ($result->entries)
		{
			if ($tmp->get_value('sAMAccountName') =~ /^0{0,2}$empno$/i)
			{
				debug_msg "Found multiple accounts for $who, ",
				    "matched sAMAccountName ",
				    $tmp->get_value('sAMAccountName'), "\n";
				$ad_entry = $tmp;
				last;
			}
		}
		if (! defined $ad_entry)
		{
			# This is bad, but we should move on
			debug_msg "Found multiple accounts for $who\n\n";
			next;
		}
	}

	clear_log_msg_buffer;
	# Matched, go to work
	my $update;
	$ad_entry = $result->shift_entry if ! defined $ad_entry;
	
	log_msg_buffer "# Employee Number: $who\n",
		    "# LDAP: ", $entry->dn, "\n",
		    "# AD  : ", $ad_entry->dn, "\n";

	my $uac = $ad_entry->get_value('userAccountControl');
	log_msg_buffer "# AD account disabled!\n"
	    if $uac & ADS_UF_ACCOUNTDISABLE;
	log_msg_buffer "# AD password expired!\n"
	    if $uac & ADS_UF_PASSWORD_EXPIRED;
	#log_msg_buffer "# AD account not flagged\n"
	#    if $uac & ADS_UF_NORMAL_ACCOUNT;

	# Determine our Org Unit from the DN
	my @ldap_comp = split(/\s*(?<!\\),\s*/, lc $entry->dn);
	my $ldap_ou = $ldap_comp[1];

	# Determine our AD Org Unit from the DN
	my @ad_comp = split(/\s*(?<!\\),\s*/, lc $ad_entry->dn);
	my $ad_ou;
	foreach (@ad_comp)
	{
		undef $ad_ou if $_ !~ /^ou\s*=/;
		last if $_ =~ /ou\s*=\s*users/i;
		$ad_ou = $_;
	}
	$ad_ou =~ s/\s*=\s*/=/ if defined $ad_ou;
	
	debug_msg "AD   ou: $ad_ou\n" if defined $ad_ou;
	debug_msg "LDAP ou: $ldap_ou\n" if defined $ldap_ou;
	debug_msg "Mapped : ", $ou_map{$ad_ou}, "\n"
	    if defined $ad_ou and defined $ldap_ou and
		exists $ou_map {$ad_ou};

	# Query the DEN for this employee number
	my $url = URI->new($wpurl);
	$url->query_form( search => $empno);
	debug_msg "WP query $url\n";
	my $response; # = $browser->get($url);

	# Extract the plain text data from the HTML
	my %wp;
	if (defined $response and $response->content =~ m{<textarea.*?>(.*?)</textarea>}is)
	{
		# Build a key => value hash from the data
		foreach my $line (split(/\s*\n\s*/, $1))
		{
			next if $line =~ /^\s*$/;
			my ($key, $val) = split(/\s*:\s*/, $line);
			next if ! defined $key or
				! defined $val or
				$val =~ /^\s*$/;
			$wp{lc $key} = $val;
		}
	}

	# Debug info...
	foreach my $key (sort keys %wp)
	{
		debug_msg "den - $key:", $wp{$key}, "\n";
	}

	# Extract the supervisor's employee number
	my $supervisor = $wp{'supervisor'} if exists $wp{'supervisor'};
	if (defined $supervisor and
	    $response->content =~
		m{$supervisor.*?<a.*?href=.*?search=(.*?)\'}is)
	{
		# Synthesize the manager dn attribute from
		# the supervisors employee number
		$wp{'manager'} = manager_dn( empno => $1 );
	}

	# Move the Employee to the correct OU based on the OU
	# mapping table, if they aren't already correctly located
	if (defined $ad_ou and exists $ou_map{lc $ad_ou} and 
	    lc $ou_map{lc $ad_ou} ne $ldap_ou)
	{
		my $superior = join(",", $ou_map{lc $ad_ou},
				    "ou=People", $ldap_opt{'base'});
		$entry->changetype("moddn");
		$entry->add(newsuperior => $superior);
		$entry->add(newrdn => $ldap_comp[0]);
		$entry->add(deleteoldrdn => 0);

		debug_msg "Mod dn new superior: $superior\n";
		log_msg LH, "# AD ", $ad_entry->dn, " moving to ",
			    $ou_map{lc $ad_ou}, " in LDAP\n",
			    $entry->ldif(change => 1);
				
		# Skip the actual mod dn if they called for chicken mode
		if (!$opt_n)
		{
			my $result = $entry->update($ldap);
			$result = chase_referrals($result, $entry)
				if $result->code == LDAP_REFERRAL;
			log_msg LH, "# Failed to moddn entry: ",
				    $result->error, "\n" if $result->code;
		}
		log_msg LH, "\n";
	}

	# Begin working the AD => LDAP attribute map
	foreach my $class (keys %acct_attr_hash)
	{
		# Extract the attributes for this objectClass
		my %class_attr_hash = %{$acct_attr_hash{$class}};

		debug_msg "$class - (none)\n" if ! %class_attr_hash;
		
		my $check_oc;

		# Lack of GECOS annoys me
		if (lc $class eq 'posixaccount' and !$entry->exists('gecos'))
		{
			log_msg LH, "# Empty GECOS field, initializing\n";
			my $gecos = join(" ", $ad_entry->get_value('givenName'),
					$ad_entry->get_value('sn'));
			$entry->replace(gecos => $gecos);
			$check_oc = 1;
			$update = 1;
		}

		if (lc $class eq 'ntuser' and !$entry->exists('ntUserDomainID'))
		{
			$entry->replace(ntUserDomainID => "LA\\" . $ad_entry->get_value('sAMAccountName'));
			$check_oc = 1;
			$update = 1;
		}

		# Convert AD proxyAddresses to mailAlternateAddresses
		if (lc $class eq 'mailrecipient')
		{
			my @alts = map { /^smtp:(.*)?\@/i ? $1 : () } 
				    $ad_entry->get_value('proxyAddresses');

			my $uid = $entry->get_value('uid');
			push @alts, $uid
			    if ! grep { /^$uid$/i } @alts;

			@alts = map { lc } @alts;

			debug_msg "$class - [proxyAddresses]: ",
			    (@alts ? join(", ", @alts) : "(none)"), "\n";

			my @add;
			foreach my $a (@alts)
			{
				push @add, $a
				    if ! grep { /^$a$/i } $entry->get_value('mailAlternateAddress');
			}

			if (0 and
		    join("|", sort @alts) ne
		    join("|", sort $entry->get_value('mailAlternateAddress'))
			    )
			{
				$entry->replace(
				    mailAlternateAddress => [ @alts ]
						);
				$check_oc = 1;
				$update = 1;
			}
			if (@add)
			{
				$entry->add(
				    mailAlternateAddress => [ @add ]
					);
				$check_oc = 1;
				$update = 1;
			}
		}

		# For each objectClass, iterate the attributes
		foreach my $source (keys %class_attr_hash)
		{
			my $target = $class_attr_hash{$source};
			my $target_value = $ad_entry->get_value($source);

			# XXX Offsite mail-routing hack
			if (lc $target eq "mailroutingaddress" and
			    $entry->exists($target) and
			    $entry->get_value($target) !~ /\@directv.com/i)
			{
				debug_msg "$class - $target: skipping routes offsite ",
				    $entry->get_value($target), "\n";
				next; # Skip the DEN override as well.
			}

			# The manager attribute must be converted to a DN
			# so go find the manager in LDAP and retrieve the DN
			if (lc $target eq "manager" and
			    $ad_entry->exists('manager'))
			{
				my $filter = "(&(objectClass=user)" .
					     "(objectClass=person)" .
					     "(employeeID=$empno))";

				debug_msg "Query AD ", $ad_ldap_opt{'base'}, "?$filter\n";
				my $result = $ad_ldap->search(
						base   => $ad_ldap_opt{'base'},
						filter => $filter,
						scope  => 'sub',
						attrs  => qw(employeeID),
							);

				if (!$result->code and $result->count == 1)
				{
					my $manager_empno =
				    		$result->shift_entry->
						    get_value('employeeID');
					$target_value =
				    manager_dn(empno => $manager_empno);
				}

			}

			# Override AD values based on DEN data as defined
			# in the DEN attribute map
			if (exists $wp_attr_hash{lc $target} and
			    defined $wp{$wp_attr_hash{lc $target}} and
			    (!defined $target_value or 
			      $target_value ne $wp{$wp_attr_hash{lc $target}})
				)
			{
				debug_msg "$target overridden by den: ",
				    (defined $target_value ?
					$target_value : 
					"(unset)"),
				    " => ",
				    $wp{$wp_attr_hash{lc $target}}, "\n";

				$target_value = $wp{$wp_attr_hash{lc $target}};
			}

			debug_msg "$class - $source: ", (defined $target_value ?
							$target_value :
							"No Value"), "\n";

			if (defined $target_value)
			{
				if (! $entry->exists($target) or 
				    $target_value ne $entry->get_value($target))
				{
					verbose "-$target: ",
					    ($entry->exists($target) ?
					    $entry->get_value($target) : ""),
					    "\n";
					verbose "+$source: ", ($target_value ?
					    $target_value : ""), "\n";

					$entry->replace(
					    $target => $target_value
							);
					$check_oc = 1;
					$update = 1;
				}
			}
		}
		# Verify the required objectClass for this attribute
		if ($check_oc and
		    ! grep { /^$class$/i } $entry->get_value('objectClass'))
		{
			$entry->add( objectClass => $class );
			$update = 1;
		}
	}

	# $update will be set if changes need to be committed
	log_msg LH, $entry->ldif(change => 1), "\n" if $update;

	# Skip updates if they called for chicken mode
	if ($update and !$opt_n)
	{
		my $result = $entry->update($ldap);
		$result = chase_referrals($result, $entry)
			if $result->code == LDAP_REFERRAL;
		log_msg LH, "# Failed to add entry: ", $result->error, "\n"
			if $result->code;
	}
}

# Find a user record by employee number and return the object DN
sub
manager_dn
{
	my %args = (@_);

	# Called wrong
	die if ! exists $args{'empno'};

	my $filter = sprintf '(&(objectClass=inetOrgPerson)' .
			    '(employeeNumber=%s))', $args{'empno'};

	debug_msg "Query LDAP ", $ldap_opt{'base'}, "?$filter\n";
	my $result = $ldap->search(
		    base   => $ldap_opt{'base'},
		    filter => $filter,
		    scope  => 'sub',
		);

	$result->code && die "LDAP query failed: ", $result->error;

	return $result->shift_entry->dn if $result->count == 1;
	
	return;
}

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

	if ($Authen_SASL_Cyrus and ! $opt_x)
	{
		debug_msg "Starting SASL/GSSAPI authentication\n";
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

		debug_msg "Binding to LDAP $bind_dn\n";
		debug_msg "SASL authzid: $authzid\n" if $authzid;
		$result = $ldap->bind($bind_dn, sasl => $sasl);
	}
	else
	{
		debug_msg "Starting simple authentication\n";
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
			debug_msg "Binding to LDAP dn: $opt_D\n";
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
			debug_msg "Binding to LDAP anonymously\n";
			$result = $ldap->bind;
		}
	}
	return ($ldap, $result);
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
mail_log
{
	my $domain = '@' . `dnsdomainname`;

	my $to = $opt_T;
	$to .= '@' . $domain if $to !~ /\@/;

	my $from = $opt_F;
	$from .= '@' . $domain if $from !~ /\@/;

	my $cc = join(", ", @opt_m);
	my $subject = "AD Update " . ($opt_n ? "[ Testing ] " : "") .
		      $ldap_opt{'host'} . " dn: " . $opt_b . ": " .
		      strftime("%m-%d-%G %H:%M", localtime($^T));

	unless (open(LH, "<$opt_l"))
	{
		warn "Unable to open log file $opt_l to e-mail update\n";
		return;
	}

	my $message = join('', <LH>) . "# Log file: $opt_l\n\n";
	close LH;


	my %mail = (
			CC	=> $cc,
			From	=> $from,
			Subject	=> $subject,
			Message	=> $message,
			smtp	=> "smtp$domain",
		);

	$mail{'To'} = $to;

	sendmail(%mail) or warn "\n***" . $Mail::Sendmail::error . "\n\n";
}

sub log_rotate
{
	use File::Basename;

	my $logdir = dirname($opt_l);
	my @logfiles;

	return if $maxlogfiles == 0 or ! $logdir;

	verbose "Rotating log files in $logdir\n";

	if (! -d "$logdir" ) {
		verbose "Unable to rotate log files, $logdir does not exist.\n\n";
		return;
	}

	if (! opendir LOGDIR, "$logdir" ) {
		verbose "Unable to open log directory $logdir.\n\n";
		return;
	}

	foreach (grep { /prm-sync-ad-.*ldif$/ && -f "$logdir/$_" } readdir LOGDIR ) {
		push @logfiles, [ stat("$logdir/$_"), "$logdir/$_" ];
	}
	close LOGDIR;

	@logfiles = sort { $$b[9] <=> $$a[9] } @logfiles;

	delete @logfiles[0 .. ($maxlogfiles - 1)];

	foreach (@logfiles) {
		my $logfile = $$_[$#$_];
		verbose "Removing logfile $logfile.\n"
		    if $logfile;
		verbose "Unable to delete $logfile.\n"
		    if $logfile and ((unlink $logfile) != 1);
	}
}

sub get_password
{
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

	print "Enter LDAP Password: ";
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

sub usage
{
	print "
Usage: directory-sync [switches] map|filter [arguments] [attr [...]]
  -l                  Log file
  -m address          mail log file to this address, may be repeated
  -n		      show what would be done but don't make changes
  -N		      do not chase update referrals
  -T address	      LHS for To address in mail (default prm-updates)
  -F address	      LHS for From address in mail (default prm-updates)
  -v                  run in verbose mode

 Active Directory options:
  --adb basedn        base dn for searches
  --adD binddn        bind DN
  --adh host          AD Server
  --adp port          port on AD server
  --adw password      bind password (SASL/GSSAPI)
  --adW               prompt for bind password

 LDAP options:
  -b basedn	      base dn for searches
  -D binddn	      bind DN
  -h host             LDAP server (implies -N)
  -p port	      port on LDAP server
  -P 2|3	      procotol version (default: 3)
  -w password         bind password (for simple authentication)
  -W                  prompt for bind password
  -x                  use simple authentication (default: SASL/GSSAPI)
  -X authzid          SASL authorization identity (\"dn:<dn>\" or \"u:<user>\")

";
}
