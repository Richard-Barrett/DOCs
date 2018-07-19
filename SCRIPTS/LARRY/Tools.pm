package Tools;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);# %EXPORT_TAGS);

$VERSION = 1.00;
@ISA	 = qw(Exporter);
@EXPORT	 = qw(
		LDAPRebind

		SimpleMenu
		PickList
		Prompt

		LDAPAddNetgroup
		LDAPDeleteNetgroup
		LDAPAddToNetgroup
		LDAPDeleteFromNetgroup

		LDAPAddPosixGroup
		LDAPDeletePosixGroup
		LDAPAddToPosixGroup
		LDAPDeleteFromPosixGroup

		LDAPAddSecurityGroup
		LDAPDeleteSecurityGroup
		LDAPAddToSecurityGroup
		LDAPDeleteFromSecurityGroup

		get_posix_group_name
		user_secondary_groups
		user_security_groups
		next_gidnumber
		next_uidnumber

		genSalt
		MD5Password
		SSHAPassword
		RandomPassword

		valid_mac
		canon_mac

		valid_ip
		ip_in_use

		get_my_serial_number
		pad_employeeNumber

		rcs_check_lock
		rcs_checkout
		rcs_checkin
	    );

@EXPORT_OK = qw();

#%EXPORT_TAGS = ( DEFAULT => [ qw() ],
#		    Both    => [ qw() ] );

use Carp;
use LDAPTools;
use Net::LDAP qw(LDAP_REFERRAL LDAP_OPERATIONS_ERROR);

use Data::Dumper;

sub get_posix_group_name($$);
sub user_secondary_groups($$);
sub user_security_groups($$);
sub ip_in_use($$);

# XXX NIS hash value width - NIS hash key width, ask me how I know...
my $max_nis_line_len = 1016;

# Minimum gidNumber
my $min_gidnumber = 2000;
my $min_uidnumber = 2000;

sub num { shift =~ /(\d+)/; $1 };

my $rebind;
my @rebind_args;

sub
LDAPRebind
{
	my ($func, @args) = @_;

	$rebind = $func;
	@rebind_args = @args;
}

sub
SimpleMenu
{
	# SimpleMenu ( name, option => value )
	# name:		menu name
	# headers:	array of column headers
	# items:	array of arrays of menu items
	# left: 	left margin fill string
	# prompt:	prompt string
	# add:		show "add" option
	# delete:	show "delete" option
	# sort:		sort menu

	my @arg_keys = qw(headers items left prompt add delete quit sort byname);

	my $name = shift;

	my %args = @_;

	use Text::Tabs;

	my $this_function = (caller(0))[3];

	my @item = @{$args{'items'}} if defined $args{'items'};
	my @hdrs = @{$args{'headers'}} if defined $args{'headers'};

	my $left = "\t";
	$left = $args{'left'} if defined $args{'left'};

	my $add = $args{'add'};
	croak("Error: $this_function add => " )
	    if defined $add and ref $add ne "HASH";

	my $del = $args{'delete'};
	croak("Error: $this_function delete => ")
	    if defined $del and ref $del ne "HASH";

	my $quit = $args{'quit'};
	croak("Error: $this_function quit => ")
	    if defined $quit and $quit != 1 and ref $quit ne "HASH";

	my $sort = $args{'sort'};
	croak("Error: $this_function sort => ")
	    if defined $sort and ref $sort ne "" and ref $sort ne "CODE";

	my $byname = $args{'byname'};
	croak("Error: $this_function byname => ")
	    if defined $byname and ref $byname ne "";

	my @menu;		# Generated menu
	my $c_columns = 0;	# Total number of columns
	my @w_col;		# Max width of each column in the display
	my $extras;
	my %byname;

	# Prompt string
	my $prompt = "Enter selection [%s] => ";
	$prompt = $args{'prompt'} if defined $args{'prompt'};

	# Calculate the width of the header columns
	my $i = 0;
	foreach my $col (@hdrs)
	{
		$w_col[$i++] = (! defined $w_col[$i] or $w_col[$i] < length $col) ?
				    length $col : $w_col[$i];
		$c_columns++;
	}

	# Force column sizes for Add, Delete, Quit
	if (defined $add)
	{
		my $label = exists $add->{label} ? $add->{label} : "";
		$w_col[0] = 3 if !defined $w_col[0] or $w_col[0] < 3;
		$w_col[1] = length $label
		    if !defined $w_col[1] or $w_col[1] < length $label;
	}
	if (defined $del)
	{
		my $label = exists $add->{label} ? $add->{label} : "";
		$w_col[0] = 6 if !defined $w_col[0] or $w_col[0] < 6;
		$w_col[1] = length $label
		    if !defined $w_col[1] or $w_col[1] < length $label;
	}
	if (defined $quit)
	{
		my $label = exists $quit->{label} ? $quit->{label} : "";
		$w_col[0] = 4 if !defined $w_col[0] or $w_col[0] < 4;
		$w_col[1] = length $label
		    if !defined $w_col[1] or $w_col[1] < length $label;
	}

	foreach my $key (keys %args)
	{
		next if grep { /^$key$/i } @arg_keys;
		my $extra = $args{$key};
		my $label = exists $extra->{label} ? $extra->{label} : "";
		$w_col[0] = length $key if !defined $w_col[0] or $w_col[0] < length $key;
		$w_col[1] = length $label
		    if !defined $w_col[1] or $w_col[1] < length $label;
		$extras = 1;
	}

	# Build the menu list from the items given
	$i = 1;
	my @sorted = sort { &sort_array_elem_0 } @item;
	foreach my $entry ($sort ? @sorted : @item)
	{
		if (ref $entry eq "ARRAY")
		{
			# Copy multi column items
			push @menu, $entry;
			$c_columns = $c_columns < scalar @$entry ? scalar @$entry : $c_columns;
		} else {
			# Convert single column item to multi column
			push @menu, [ $entry ];
			$c_columns = 1 if $c_columns == 0;
		}

		$byname{lc $menu[$#menu][0]} = $i++ # Build name to index hash
		    if defined $byname;

		# Calculate the max width of the columns
		my $i = 0;
		foreach my $a (@{$menu[$#menu]})
		{
			my $b = $a;
			if (ref $a eq "ARRAY")
			{
				my $max = @$a[0];
				foreach my $c (@$a)
				{
					$max = $c if length $c > length $max;
				}
				$b = $max;
			}
			$w_col[$i++] = (! defined $w_col[$i] or $w_col[$i] < (! defined $b ? 0 : length $b)) ?
					    (! defined $a ? 0 : length $a) : $w_col[$i];
		}
	}

	my $t_left = expand $left;
	my $w_left = length $t_left;

	# Print the menu name centered above all columns
	if ($name)
	{
		my $tw_col = 0;
		foreach (@w_col)
		{
			$tw_col += $_;
		}
		printf "\n%s%*s%s\n\n", $left, ($w_left + $tw_col - length($name)) / 2, "", $name;
	}

	# Print the column headers
	if (@hdrs)
	{
		printf "%s%*s  ", $left, length(scalar(@menu)), "";
		my $j = 0;
		foreach my $col (@hdrs)
		{
			printf "%-*s ", $w_col[$j], $col;
		}
		print "\n\n";
	}

	# Display the numbered menu items
	$i = 0;
	foreach my $entry (@menu)
	{
		printf "%s%*d: ", $left, length(scalar(@menu)), $i + 1;
		my $j = 0;
		my @elem = @{$menu[$i]};
		foreach my $col (@elem)
		{
			if (ref $col eq "ARRAY")
			{
				foreach my $a (@$col)
				{
					printf "%-*s", 
					    $w_col[$j], $a;
					printf "\n%s%*s",
					    $left, 3 + length(scalar(@menu)) + $w_col[$j] , ""
						if $a ne @$col[$#$col];
				}
			}
			else
			{
				printf "%-*s ", $w_col[$j], $col;
			}
		}
		print "\n";
		$i++;
	}
	print "\n";

	# Called in a void context?
	return unless defined wantarray;

	# Are we just pointless?
	return
	    if scalar @menu == 0 and
	       !defined $add and
	       !defined $del and
	       !defined $quit and
	       !defined $extras;

	my %extras;
	foreach my $key (keys %args)
	{
		next if grep { /^$key$/i } @arg_keys;
		next if ! exists $args{$key}->{choice};
		my $extra = $args{$key};
		my $label = exists $extra->{label} ? $extra->{label} : "";
		$extras{$key} = substr($extra->{choice}, 0, 1);
		printf "%s%*s: ", $left, length(scalar(@menu)), substr($extra->{choice}, 0, 1);
		printf "%-*s ", $w_col[0], $key;
		printf "%-*s ", $w_col[1], $label
		    if defined $label ne "";
		print "\n";
	}
	print "\n" if defined $extras;

	if (defined $add)
	{
		my $label = exists $add->{label} ? $add->{label} : "";
		printf "%s%*s: ", $left, length(scalar(@menu)), substr($add->{choice}, 0, 1);
		printf "%-*s ", $w_col[0], "Add";
		printf "%-*s ", $w_col[1], $label
		    if defined $label ne "";
		print "\n";
	}
	if (defined $del)
	{
		my $label = exists $del->{label} ? $del->{label} : "";
		printf "%s%*s: ", $left, length(scalar(@menu)), substr($del->{choice}, 0, 1);
		printf "%-*s ", $w_col[0], "Delete";
		printf "%-*s ", $w_col[1], $label
		    if defined $label ne "";
		print "\n";
	}
	if (defined $quit)
	{
		my $label = exists $quit->{label} ? $quit->{label} : "";
		printf "%s%*s: ", $left, length(scalar(@menu)), substr($quit->{choice}, 0, 1);
		printf "%-*s ", $w_col[0], "Quit";
		printf "%-*s ", $w_col[1], $label
		    if defined $label ne "";
		print "\n";
	}
	print "\n" if defined $add or defined $del or defined $quit;

	my $summary = "";
	if ($prompt =~ /%s/)
	{
		$summary = sprintf "%s%d-%d", $summary, 1, scalar @menu
		    if scalar @menu > 0;

		$summary = sprintf "%s%s%s", $summary,
		    length $summary ? "|" : "",
		    defined $add ? substr($add->{choice}, 0, 1) : ""
			if defined $add;
		$summary = sprintf "%s%s%s", $summary,
		    length $summary ? "|" : "",
		    defined $del ? substr($del->{choice}, 0, 1) : ""
			if defined $del;
		$summary = sprintf "%s%s%s", $summary,
		    length $summary ? "|" : "",
		    defined $quit ? substr($quit->{choice}, 0, 1) : ""
			if defined $quit;
	}

	my $ans = Prompt($prompt,
		min => 1,
		max => scalar @menu,
		add => (defined $add ? $add : undef),
		del => (defined $del ? $del : undef),
		quit => (defined $quit ? $quit : undef),
		byname => (defined $byname ? \%byname : undef),
		%extras,
		);

	if (defined $ans and $ans =~ /^\d+$/ and $ans >= 1 and $ans <= scalar(@menu) + 1)
	{
		my @selected = @{$menu[$ans - 1]};
		return (wantarray ? @selected : $selected[0]);
	}

	return $ans;
}

sub
PickList
{
	my $name = shift;

	use POSIX;
	use Text::Tabs;

	my %args = @_;

	my $this_function = (caller(0))[3];

	use Term::ReadKey;
	my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();

	my $w_screen = $wchar;
	my $w_col = 0;

	my @list;
	my @item = @{$args{'items'}} if defined $args{'items'};

	my $left = "\t";
	$left = $args{'left'} if defined $args{'left'};

	my $numbered;
	$numbered = 1 if defined $args{'numbered'};

	my $add = $args{'add'};
	croak("Error: $this_function add => " )
	    if defined $add and ref $add ne "HASH";

	my $del = $args{'delete'};
	croak("Error: $this_function delete => ")
	    if defined $del and ref $del ne "HASH";

	my $quit = $args{'quit'};
	croak("Error: $this_function quit => ")
	    if defined $quit and $quit != 1 and ref $quit ne "HASH";

	# Prompt string
	my $prompt = "Enter selection [%s] => ";
	$prompt = $args{'prompt'} if defined $args{'prompt'};

	# Build the pick list from the items given
	foreach my $entry (sort @item)
	{
		push @list, $entry;
		$w_col = $w_col < length $entry ? length $entry : $w_col;
	}

	my $t_left = expand $left;
	my $w_left = length $t_left;

	my $w_num = defined $numbered ? length(scalar(@list) + 1) : 0;
	my $w_pad = $w_num ? 2 : 0;

	my $c_cols = floor(($w_screen - $w_left) / ($w_col + $w_num + $w_pad + 1));

	my $c_rows = ceil(scalar @item / $c_cols);

	# Print the menu name centered above all columns
	if ($name)
	{
		my $tw_col = $c_cols * $w_col;
		printf "\n%s%*s%s\n\n", $left, ($w_left + $tw_col - length($name)) / 2, "", $name;
	}

	for (my $i = 0; $i < $c_rows; $i++)
	{
		printf "%*s", length($left), $left;
		for (my $j = 0; $j < $c_cols; $j++)
		{
			if ($numbered)
			{
				printf "%*d: ", $w_num, $i + ($j * $c_rows) + 1
				    if defined $list[$i + ($j * $c_rows)];
			}
			printf "%-*s ", $w_col, $list[$i + ($j * $c_rows)]
			    if defined $list[$i + ($j * $c_rows)];
		}
		print "\n";
	}
	print "\n";

	#print "w_screen $w_screen w_left $w_left w_num $w_num w_col $w_col c_cols $c_cols c_rows $c_rows\n";
	my $ans = Prompt($prompt,
		min => (defined $numbered ? 1 : undef),
		max => (defined $numbered ? scalar @list + 1 : undef),
		add => (defined $add ? $add : undef),
		del => (defined $del ? $del : undef),
		quit => (defined $quit ? $quit : undef),
		items => [ @list ],
		);
}

sub
Prompt
{
	my $prompt = shift;
	my %args = @_;

	my %extras;

	my @arg_keys = qw(prompt add del min max quit items byname);

	my $this_function = (caller(0))[3];

	my $min;
	$min = $args{'min'} if defined $args{'min'};

	my $max;
	$max = $args{'max'} if defined $args{'max'};

	my $left = "\t";
	$left = $args{'left'} if defined $args{'left'};

	my $add = $args{'add'};
	    croak("Error: $this_function add => ")
		if defined $add and ref $add ne "HASH";

	my $del = $args{'del'};
	    croak("Error: $this_function del => ")
		if defined $del and ref $del ne "HASH";

	my $quit = $args{'quit'};
	    croak("Error: $this_function quit => ")
		if defined $quit and $quit != 1 and ref $quit ne "HASH";

	my $byname = $args{'byname'};
	    croak("Error: $this_function byname => ")
		if defined $byname and ref $byname ne "HASH";

	my $summary = "";
	if ($prompt =~ /%s/)
	{
		$summary = sprintf "%s%d-%d", $summary, $min, $max
		    if defined $min and defined $max and $max >= $min;

		foreach my $key (keys %args)
		{
			next if grep { /^$key$/i } @arg_keys;
			$summary = sprintf "%s%s%s", $summary,
			    (length $summary ? "|" : ""),
			    $args{$key};
			$extras{lc $args{$key}} = $key;
		}
	
		$summary = sprintf "%s%s%s", $summary,
		    length $summary ? "|" : "",
		    defined $add ? $add->{choice} : ""
			if defined $add;
		$summary = sprintf "%s%s%s", $summary,
		    length $summary ? "|" : "",
		    defined $del ? $del->{choice} : ""
			if defined $del;
		$summary = sprintf "%s%s%s", $summary,
		    length $summary ? "|" : "",
		    defined $quit ? $quit->{choice} : ""
			if defined $quit;
	}

	my $done;
	while (! $done)
	{
		printf "\n%s$prompt", $left, $summary;

		my $choice = <STDIN>;

		if (! defined $choice)
		{
			print "\n\n";
			return;
		}

		chomp($choice);
		$choice =~ s/^\s*|\s*$//g;

		if ($choice eq "")
		{
			return "";
		}

		if ($choice =~ /^\d+$/ and defined $min and defined $max)
		{
			if ($choice >= $min and $choice <= $max)
			{
				return $choice;
			}
			else
			{
				printf "\n%s%s is not a valid option\n\n", $left, $choice;
			}
		}
		elsif (defined $byname and exists($byname->{$choice}))
		{
			return $byname->{$choice};
		}
		elsif (defined $add and lc $choice eq lc $add->{choice})
		{
			if (defined $add->{callback})
			{
				return &{$add->{callback}}(@{$add->{args}});
			}
			else
			{
				return $add->{choice};
			}
		}
		elsif (defined $del and lc $choice eq lc $del->{choice})
		{
			if (defined $del->{callback})
			{
				return &{$del->{callback}}(@{$del->{args}});
			}
			else
			{
				return $del->{choice};
			}
		}
		elsif (defined $quit and lc $choice eq lc $quit->{choice})
		{
			if (defined $quit->{callback})
			{
				return &{$quit->{callback}}(@{$quit->{args}});
			}
			else
			{
				return $quit->{choice};
			}
		}
		elsif (exists $extras{lc $choice})
		{
			return $extras{lc $choice};
		}
		elsif (! %args)
		{
			return $choice;
		}
		else
		{
			printf "\n%s%s is not a valid option\n\n", $left, $choice;
		}
	}
}

sub
LDAPDeleteNetgroup
{
	my $ldap = shift;
	my $name = shift;

	my %args = @_;

	my $parent_function = (caller(1))[3];
	my $this_function = (caller(0))[3];

	my $parent;
	$parent = $args{'parent'} if defined $args{'parent'};

	my $sweep;
	$sweep = $args{'sweep'} if defined $args{'sweep'};

	#carp("$parent_function: $this_function(",
	#    $ldap, ",", $name,
	#    defined $parent ? ",parent=>$parent" : "",
	#    defined $sweep ? "sweep=>$sweep" : "",
	#     ")");

	my $group = $name;

	if (ref $group eq "")
	{
		# Find the netgroup to update
		my $filter = "(&(objectClass=nisNetgroup)(cn=$name))";

		my $result = $ldap->search(
					base   => $ldap_opt{'base'},
					filter => $filter,
					scope  => 'sub',
					);

		# Rebind LDAP and try again if REBIND has been set
		if (defined $rebind && $result->code && $result->code == 1)
		{
			my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
			return LDAPDeleteNetgroup($reldap, $name) if ! $reresult->code;
		}

		$result->code && croak("$this_function:(" . __LINE__ . ") LDAP query $filter error: ", $result->error);

		$result->count == 0 and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
		$result->count > 1  and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

		$group = $result->shift_entry;
	}
	elsif (ref $group ne "Net::LDAP::Entry")
	{
		croak("$this_function:(" . __LINE__ . ") name must be a Net::LDAP::Entry or netgroup name not ", ref $group);
	}

	$name = $group->get_value('cn');

	$group->delete;
	my $result = $group->update($ldap);
	$result = chase_referrals($result, $group)
	    if $result->code == LDAP_REFERRAL;

	croak("$this_function:(" . __LINE__ . ") Failed to delete netgroup $name")
		if $result->code;

	if ($parent)
	{
		if (ref $parent ne "Net::LDAP::Entry")
		{
			# Find the netgroup to update
			my $filter = "(&(objectClass=nisNetgroup)(cn=$parent))";

			my $result = $ldap->search(
						base   => $ldap_opt{'base'},
						filter => $filter,
						scope  => 'sub',
						);

			$result->code && die "LDAP query $filter error: ", $result->error;

			$result->count == 0 and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
			$result->count > 1  and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

			$parent = $result->shift_entry;
		}
		elsif (ref $parent ne "")
		{
			croak("$this_function:(" . __LINE__ . ") name must be a Net::LDAP::Entry or netgroup name");
		}

		my $p_name = $parent->get_value('cn');

		$parent->delete(memberNisNetgroup => [ $name ]);
		$result = $parent->update($ldap);
		$result = chase_referrals($result, $parent)
		    if $result->code == LDAP_REFERRAL;

		croak("$this_function:(" . __LINE__ . ") Failed to delete netgroup $name from $p_name")
			if $result->code;
	}

	return if ! defined $sweep;

	my $notyet = 0;
	if ($notyet and $parent)
	{
	        # Did we just empty this netgroup?
		if (! $parent->exists('nisNetgroupTriple') and
		    ! $parent->exists('memberNisNetgroup') )
		{
			LDAPDeleteNetgroup($ldap, $parent, sweep => 1);
		}
	}

	# Sweep the netgroup out of any other groups
	my $filter = "(&(objectClass=nisNetgroup)(memberNisNetgroup=$name))";

	$result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				);

	$result->code && die "LDAP query $filter error: ", $result->error;

	foreach my $entry ($result->entries)
	{
		my $p_name = $entry->get_value('cn');
		$entry->delete(memberNisNetgroup => [ $name ]);
		$result = $entry->update($ldap);
		$result = chase_referrals($result, $entry)
		    if $result->code == LDAP_REFERRAL;

		croak("$this_function:(" . __LINE__ . ") Failed to delete netgroup $name from $p_name")
			if $result->code;

		# Did we just empty this netgroup?
		if (! $entry->exists('nisNetgroupTriple') and
		    ! $entry->exists('memberNisNetgroup') )
		{
			LDAPDeleteNetgroup($ldap, $entry, sweep => 1);
		}
	}
}

sub
LDAPAddNetgroup
{
	my $ldap = shift;
	my $name = shift;

	my %args = @_;

	my $this_function = (caller(0))[3];

	my $description;
	$description = $args{'description'}
	    if defined $args{'description'};

	my $convert_to_nested;
	$convert_to_nested = $args{'convert_to_nested'}
	    if defined $args{'convert_to_nested'};

	my $parent;
	$parent = $args{'parent'} if defined $args{'parent'};

	my %attrs = (
			cn	    => $name,
			objectClass => [ qw(top nisNetgroup) ],
		    );

	$attrs{description} = $description
	    if defined $description and length $description;

	if (defined $convert_to_nested)
	{
		if (ref $convert_to_nested eq "Net::LDAP::Entry")
		{
			$attrs{'nisNetgroupTriple'} = [ $convert_to_nested->get_value('nisNetgroupTriple') ];
		}
		else
		{
			croak("$this_function:(" . __LINE__ . ") convert_to_nested not a Net::LDAP::Entry");
		}

	}

	croak("$this_function:(" . __LINE__ . ") parent not a Net::LDAP::Entry")
	    if defined $parent and ref $parent ne "Net::LDAP::Entry";

	my $new = Net::LDAP::Entry->new;
	$new->dn(sprintf "cn=%s,ou=netgroup,%s", $name, $ldap_opt{'base'});
	$new->add(%attrs);

	my $result = $new->update($ldap);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		$result = $new->update($reldap) if ! $reresult->code;
	}

	$result = chase_referrals($result, $new)
	    if $result->code == LDAP_REFERRAL;

	croak("$this_function:(" . __LINE__ . ") Failed to add netgroup $name ", $result->error) if $result->code;

	if (defined $convert_to_nested)
	{
		$convert_to_nested->delete('nisNetgroupTriple');
		$convert_to_nested->add(memberNisNetgroup => $name);

		my $result = $convert_to_nested->update($ldap);
		$result = chase_referrals($result, $convert_to_nested)
		    if $result->code == LDAP_REFERRAL;

		croak("$this_function:(" . __LINE__ . ") Failed to update netgroup ",
		    $convert_to_nested->get_value('cn'), " ", $result->error)
			if $result->code;
	}

	if (defined $parent)
	{
		if (grep { /$name/ } $parent->get_value('memberNisNetgroup'))
		{
			carp("$this_function:(" . __LINE__ . ") $name already a memeber of ", $parent->get_value('cn'));
			return $new;
		}
		$parent->add(memberNisNetgroup => $name);
		my $result = $parent->update($ldap);
		$result = chase_referrals($result, $parent)
		    if $result->code == LDAP_REFERRAL;

		croak("$this_function:(" . __LINE__ . ") Failed to add $name to netgroup ",
		    $parent->get_value('cn'), " ", $result->error)
			if $result->code;
	}

	return $new;
}

sub
LDAPDeleteFromNetgroup
{
	use LDAPTools;

	my $ldap = shift;
	my $name = shift;
	my $type = shift;
	my $del = shift;

	my $this_function = (caller(0))[3];

	croak("Error: $this_function: type must be triple, host, user or domain")
	    if $type ne "host" and $type ne "user" and
		$type ne "domain" and $type ne "triple";

	# Clear off any whitespace
	$del =~ s/^\s*|\s*$//g;

	# Create triple
	my $triple = $del;
	$triple = "($del,,)" if $type eq "host";
	$triple = "(,$del,)" if $type eq "user";
	$triple = "(,,$del)" if $type eq "domain";

	# Convert triple into a regex for sanity check
	my $re_triple = $triple;
	$re_triple =~ s/^(\()/\\s*(\\s*/;
	$re_triple =~ s/(\))$/\\s*)\\s*/;
	$re_triple =~ s/,/\\s*,\\s*/g;
	$re_triple =~ s/(\\s\*)+/\\s*/g;

	# Find the netgroup to update
	my $filter = "(&(objectClass=nisNetgroup)(cn=$name))";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return LDAPDeleteFromNetgroup($reldap, $name, $type, $del) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	$result->count == 0 and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
	$result->count > 1  and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

	my $entry = $result->shift_entry;
	my @members = $entry->get_value('nisNetgroupTriple');
	my @subgroups = $entry->get_value('memberNisNetgroup');

	# Sort through any nested netgroups, looking for the correct netgroup to update
	my $update;
	my @extract;
	foreach my $group (sort { num($a) <=> num($b) } @subgroups)
	{
		my $filter = "(&(objectClass=nisNetgroup)(cn=$group))";

		my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
					);

		$result->code && croak("$this_function:(" . __LINE__ . ") LDAP query $filter failed ", $result->error);

		if ($result->count == 0)
		{
			carp("$this_function:(" . __LINE__ . ") Netgroup $group included in $name but doesn't exist");
			next;
		}

		$result->count > 1  and croak("$this_function:(" . __LINE__ . ") multiple netgroups found named $group");

		my $entry = $result->shift_entry;

		# Check for duplicates
		if (my @foo = grep { /$re_triple/ } $entry->get_value('nisNetgroupTriple'))
		{
			carp("$this_function:(" . __LINE__ . ") $del in multipe nested netgroups $name and ",
			    $update->get_value("cn"), " ($group)") if defined $update;
			$update = $entry;
			@extract = @foo;
		}
	}

	# If this is a plain netgroup, check to see if we have enough room to add this triple
	if (!@subgroups)
	{
		# Check for duplicates
		if (my @foo = grep { /$re_triple/ } $entry->get_value('nisNetgroupTriple'))
		{
			$update = $entry;
			@extract = @foo;
		}
	}

	# If update didn't get defined, we failed to find the entry
	if (! defined $update)
	{
		croak("$this_function:(" . __LINE__ . ") Failed to determine netgroup to update for $del")
		    if ! defined $update;
	}

	croak("$this_function:(" . __LINE__ . ") Empty list of values to delete")
	    if ! @extract;

	$update->delete(nisNetgroupTriple => @extract);
	$result = $update->update($ldap);
	$result = chase_referrals($result, $update)
	    if $result->code == LDAP_REFERRAL;

	if ($result->code)
	{
		carp("$this_function:(" . __LINE__ . ") Failed to remove $del from $name: ", $result->error);
		return $result;
	}

	# Is the netgroup empty?
	if (! $update->exists('nisNetgroupTriple') and
	    ! $update->exists('memberNisNetgroup') and
	    lc $name ne lc $update->get_value("cn")
	    )
	{
		my ($parent, $sweep);

		if (lc $name ne lc $update->get_value("cn"))
		{
			$parent = $name;
			$sweep = 1;
		}

		#LDAPDeleteNetgroup($ldap, $update, parent => $name, sweep => 1);
		LDAPDeleteNetgroup($ldap, $update,
		    parent => (defined $parent ? $parent : undef),
		    sweep => (defined $sweep ? 1 : undef));
	}
}

sub
LDAPAddToNetgroup
{
	use LDAPTools;

	my $ldap = shift;
	my $name = shift;
	my $type = shift;
	my $add = shift;

	my $this_function = (caller(0))[3];

	croak("Error: $this_function: type must be triple, host, user or domain")
	    if $type ne "host" and $type ne "user" and
		$type ne "domain" and $type ne "triple";

	# Clear off any whitespace
	$add =~ s/^\s*|\s*$//g;

	if (lc $type eq "triple" and $add !~ /\(.*?,.*?,.*?\)/)
	{
		carp("$this_function:(" . __LINE__ . ") Request to add triple $add to netgroup isn't a triple");
		return;
	}
	elsif (lc $type eq "triple")
	{
		$add =~ /\s*\(\s*(.*?)\s*,\s*(.*?)\s*,\s*(.*?)\s*\)\s*/;
		my ($user, $host, $dom) = ($1, $2, $3);

		if ((! defined $host or $host eq "") and
		    (! defined $user or $user eq "") and
		    (! defined $dom or $dom eq ""))
		{
			carp("$this_function:(" . __LINE__ . ") Can't add empty triple $add to netgroup.");
			return;
		} 
	}

	# Create triple
	my $triple = $add;
	$triple = "($add,,)" if $type eq "host";
	$triple = "(,$add,)" if $type eq "user";
	$triple = "(,,$add)" if $type eq "domain";

	# Convert triple into a regex for sanity check
	my $re_triple = $triple;
	$re_triple =~ s/^(\()/\\s*(\\s*/;
	$re_triple =~ s/(\))$/\\s*)\\s*/;
	$re_triple =~ s/,/\\s*,\\s*/g;
	$re_triple =~ s/(\\s\*)+/\\s*/g;

	# Find the netgroup to update
	my $filter = "(&(objectClass=nisNetgroup)(cn=$name))";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return LDAPAddToNetgroup($reldap, $name, $type, $add) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	$result->count == 0 and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
	$result->count > 1  and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

	my $entry = $result->shift_entry;
	my @members = $entry->get_value('nisNetgroupTriple');
	my @subgroups = $entry->get_value('memberNisNetgroup');

	# Sort through any nested netgroups, looking for the correct netgroup to update
	# and verify that the new triple doesn't appear in any of them
	my $skip;
	my $next = 1;
	my $update;
	foreach my $group (sort { num($a) <=> num($b) } @subgroups)
	{
		my $filter = "(&(objectClass=nisNetgroup)(cn=$group))";

		my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
					);

		$result->code && croak("$this_function:(" . __LINE__ . ") LDAP query $filter failed ", $result->error);

		if ($result->count == 0)
		{
			carp("$this_function:(" . __LINE__ . ") Netgroup $group included in $name but doesn't exist");
			next;
		}

		$result->count > 1  and croak("$this_function:(" . __LINE__ . ") multiple netgroups found named $group");

		my $entry = $result->shift_entry;

		# Check for duplicates
		if (grep { /$re_triple/ } $entry->get_value('nisNetgroupTriple'))
		{
			carp("$this_function:(" . __LINE__ . ") $add is already in netgroup $name ($group)");
			$skip = 1;
			last;
		}

		# Check to see if we have room enough to add the triple to this entry
		my $len = length(join(" ", $entry->get_value('cn'), $entry->get_value('nisNetgroupTriple')));
		$update = $entry
		    if !defined $update and
			($len + length($triple) + 1) < $max_nis_line_len;

		# Looking for the next available integer,
		# stopping at the first gap
		if ($group =~ /(\d+)$/)
		{
			$next++ if $1 == $next;
		}
	}

	# If this is a plain netgroup, check to see if we have enough room to add this triple
	if (!@subgroups)
	{
		# Check for duplicates
		if (grep { /$re_triple/ } $entry->get_value('nisNetgroupTriple'))
		{
			carp("$this_function:(" . __LINE__ . ") $add is already in netgroup $name");
			$skip = 1;
		}

		my $len = length(join(" ", $entry->get_value('cn'), $entry->get_value('nisNetgroupTriple')));
		
		$update = $entry
		    if ! $skip and ! defined $update and
			($len + length($triple) + 1) < $max_nis_line_len;
	}

	# Skip is set for duplicates
	return if $skip;

	# If update didn't get defined, we need to add a new netgroup
	if (! defined $update)
	{
		# next, should be the next numbered group in the list
		my $newname = join('_', $name, $next);

		if (!@subgroups)
		{
			# If this was a regular netgroup, we need to convert it to nested
			$update = LDAPAddNetgroup($ldap, $newname, convert_to_nested => $entry);
		}
		else
		{
			# Add another nested group to the parent entry
			$update = LDAPAddNetgroup($ldap, $newname, parent => $entry);
		}
	}

	croak("$this_function:(" . __LINE__ . ") Failed to determine netgroup to update")
	    if ! defined $update;
	
	$update->add(nisNetgroupTriple => $triple);
	$result = $update->update($ldap);
	$result = chase_referrals($result, $update)
	    if $result->code == LDAP_REFERRAL;

	if ($result->code)
	{
		carp("$this_function:(" . __LINE__ . ") Failed to add $add to $name: ", $result->error);
	}
}

sub
LDAPAddPosixGroup
{
	my $ldap = shift;
	my $name = shift;

	my %args = @_;

	my $this_function = (caller(0))[3];

	my $description;
	$description = $args{'description'}
	    if defined $args{'description'};

	my $gidnumber = next_gidnumber($ldap);

	my %attrs = (
			cn	    => $name,
			gidNumber   => $gidnumber,
			objectClass => [ qw(top posixGroup) ],
		    );

	$attrs{description} = $description
	    if defined $description and length $description;

	my $new = Net::LDAP::Entry->new;
	$new->dn(sprintf "cn=%s,ou=group,%s", $name, $ldap_opt{'base'});
	$new->add(%attrs);

	my $result = $new->update($ldap);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		$result = $new->update($reldap) if ! $reresult->code;
	}

	$result = chase_referrals($result, $new)
	    if $result->code == LDAP_REFERRAL;

	croak("$this_function:(" . __LINE__ . ") Failed to add group $name ", $result->error)
	    if $result->code;

	return $new;
}

sub
LDAPDeletePosixGroup
{
	my $ldap = shift;
	my $name = shift;

	my %args = @_;

	my $this_function = (caller(0))[3];

	my $group = $name;

	if (ref $group eq "")
	{
		# Find the netgroup to update
		my $filter = "(&(objectClass=posixGroup)(cn=$name))";

		my $result = $ldap->search(
					base   => $ldap_opt{'base'},
					filter => $filter,
					scope  => 'sub',
					);

		# Rebind LDAP and try again if REBIND has been set
		if (defined $rebind && $result->code && $result->code == 1)
		{
			my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
			return LDAPDeletePosixGroup($reldap, $name) if ! $reresult->code;
		}

		$result->code && croak("$this_function:(" . __LINE__ . ") LDAP query $filter error: ", $result->error);

		$result->count == 0 and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
		$result->count > 1  and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

		$group = $result->shift_entry;
	}
	elsif (ref $group ne "Net::LDAP::Entry")
	{
		croak("$this_function:(" . __LINE__ . ") name must be a Net::LDAP::Entry or group name not ", ref $group);
	}

	$name = $group->get_value('cn');

	$group->delete;
	my $result = $group->update($ldap);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		$result = $group->update($reldap) if ! $reresult->code;
	}

	$result = chase_referrals($result, $group)
	    if $result->code == LDAP_REFERRAL;

	croak("$this_function:(" . __LINE__ . ") Failed to delete group $name")
		if $result->code;
}

sub
LDAPAddToPosixGroup
{
	use LDAPTools;

	my $ldap = shift;
	my $name = shift;
	my $add = shift;

	my $this_function = (caller(0))[3];

	# Clear off any whitespace
	$add =~ s/^\s*|\s*$//g;

	# Find the group to update
	my $filter = "(&(objectClass=posixGroup)(cn=$name))";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return LDAPAddToPosixGroup($reldap, $name, $add) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	$result->count == 0 and
	    croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
	$result->count > 1 and
	    croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

	my $entry = $result->shift_entry;
	my @members = $entry->get_value('memberUid');

	# Check for duplicates
	if (grep { /\s*add\s*$/i } $entry->get_value('memberUid'))
	{
		carp("$this_function:(" . __LINE__ . ") $add is already in group $name");
		return;
	}

	my $len = length(
			join(":", $entry->get_value('cn'), "x", $entry->get_value('gidNumber'),
			join(",", $entry->get_value('memberUid'), $add))
			);

	carp("$this_function: Group $name exceeds the recommended line length $add/$max_nis_line_len")
	    if $len > $max_nis_line_len;

	$entry->add(memberUid => $add);
	$result = $entry->update($ldap);
	$result = chase_referrals($result, $entry)
	    if $result->code == LDAP_REFERRAL;

	if ($result->code)
	{
		carp("$this_function:(" . __LINE__ . ") Failed to add $add to $name: ", $result->error);
	}
}

sub
LDAPDeleteFromPosixGroup
{
	use LDAPTools;

	my $ldap = shift;
	my $name = shift;
	my $del = shift;

	my $this_function = (caller(0))[3];

	# Clear off any whitespace
	$del =~ s/^\s*|\s*$//g;

	# Find the group to update
	my $filter = "(&(objectClass=posixGroup)(cn=$name))";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return LDAPDeleteFromPosixGroup($reldap, $name, $del) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	$result->count == 0 and
	    croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
	$result->count > 1 and
	    croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

	my $entry = $result->shift_entry;
	my @members = $entry->get_value('memberUid');

	# Check for duplicates
	if (! grep { /^\s*$del\s*$/ } $entry->get_value('memberUid'))
	{
		carp("$this_function:(" . __LINE__ . ") $del not found in $name");
	}

	$entry->delete(memberUid => [ $del ]);
	$result = $entry->update($ldap);
	$result = chase_referrals($result, $entry)
	    if $result->code == LDAP_REFERRAL;

	if ($result->code)
	{
		carp("$this_function:(" . __LINE__ . ") Failed to remove $del from $name: ", $result->error);
		return $result;
	}
}

sub
sort_array_elem_0
{
	my $one;
	my $two;

	if (ref $a eq "ARRAY")
	{
		my @tmp = @{$a};
		$one = $tmp[0];
	} else {
		$one = $a;
	}

	if (ref $b eq "ARRAY")
	{
		my @tmp = @{$b};
		$two = $tmp[0];
	} else {
		$two = $b;
	}

	$one cmp $two;
}

sub
get_posix_group_name($$)
{
	my $ldap = shift;
	my $group = shift;

	my $this_function = (caller(0))[3];

	croak("$this_function(Net::LDAP, \"gid\") Net::LDAP object not valid")
	    if ! defined $ldap or ref $ldap ne "Net::LDAP";

	croak("$this_function(Net::LDAP, \"gid\" | Net::LDAP::Entry) gid is not a scalar or Net::LDAP::Entry")
	    if ! defined $group or (ref $group ne "Net::LDAP::Entry" and ref $group ne "");

	if (ref $group ne "Net::LDAP::Entry")
	{
		my $filter = "(&(objectClass=posixGroup)(gidNumber=$group))";

		my $result = $ldap->search(
					base   => $ldap_opt{'base'},
					filter => $filter,
					scope  => 'sub',
					attrs  => [ qw(cn) ],
					);

		# Rebind LDAP and try again if REBIND has been set
		if (defined $rebind && $result->code && $result->code == 1)
		{
			my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
			return get_posix_group_name($reldap, $group) if ! $reresult->code;
		}

		$result->code && die "LDAP query $filter error: ", $result->error, " (", $result->code, ")";

		return $group if $result->count == 0;
		$result->count > 1 and
		    croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

		$group = $result->shift_entry;
	}

	return $group->get_value('cn');

}

sub
LDAPAddSecurityGroup
{
        my $ldap = shift;
        my $name = shift;

        my %args = @_;

        my $this_function = (caller(0))[3];

        my $description;
        $description = $args{'description'}
            if defined $args{'description'};

        my %attrs = (
                        cn          => $name,
                        objectClass => [ qw(top groupofuniquenames) ],
                    );

        $attrs{description} = $description
            if defined $description and length $description;

        my $new = Net::LDAP::Entry->new;
        $new->dn(sprintf "cn=%s,ou=Groups,%s", $name, $ldap_opt{'base'});
        $new->add(%attrs);

        my $result = $new->update($ldap);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		$result = $new->update($reldap) if ! $reresult->code;
	}

        $result = chase_referrals($result, $new)
            if $result->code == LDAP_REFERRAL;

        croak("$this_function:(" . __LINE__ . ") Failed to add group $name ", $result->error)
            if $result->code;

        return $new;
}

sub
LDAPDeleteSecurityGroup
{
	my $ldap = shift;
	my $name = shift;

	my %args = @_;

	my $this_function = (caller(0))[3];

	my $group = $name;

	if (ref $group eq "")
	{
		# Find the netgroup to update
		my $filter = "(&(objectClass=groupofuniquenames)(cn=$name))";

		my $result = $ldap->search(
					base   => $ldap_opt{'base'},
					filter => $filter,
					scope  => 'sub',
					);

		# Rebind LDAP and try again if REBIND has been set
		if (defined $rebind && $result->code && $result->code == 1)
		{
			my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
			return LDAPDeleteSecurityGroup($reldap, $name) if ! $reresult->code;
		}

		$result->code && croak("$this_function:(" . __LINE__ . ") LDAP query $filter error: ", $result->error);

		$result->count == 0 and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
		$result->count > 1  and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

		$group = $result->shift_entry;
	}
	elsif (ref $group ne "Net::LDAP::Entry")
	{
		croak("$this_function:(" . __LINE__ . ") name must be a Net::LDAP::Entry or group name not ", ref $group);
	}

	$name = $group->get_value('cn');

	$group->delete;
	my $result = $group->update($ldap);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		$result = $group->update($reldap) if ! $reresult->code;
	}

	$result = chase_referrals($result, $group)
	    if $result->code == LDAP_REFERRAL;

	croak("$this_function:(" . __LINE__ . ") Failed to delete group $name")
		if $result->code;
}

sub
LDAPAddToSecurityGroup
{
	use LDAPTools;

	my $ldap = shift;
	my $name = shift;
	my $add = shift;

	my $this_function = (caller(0))[3];

	# Clear off any whitespace
	#$add =~ s/^\s*|\s*$//g;

	# Find the group to update
	my $filter = "(&(objectClass=groupofuniquenames)(cn=$name))";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return LDAPAddToSecurityGroup($reldap, $name, $add) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	$result->count == 0 and
	    croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
	$result->count > 1 and
	    croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

	my $entry = $result->shift_entry;
	my @members = $entry->get_value('uniqueMember');

	# Check for duplicates
	if (grep { /\s*add\s*$/i } $entry->get_value('uniqueMember'))
	{
		carp("$this_function:(" . __LINE__ . ") $add is already in group $name");
		return;
	}

	my $len = length( join(":", "uniqueMember", $entry->get_value('uniqueMember')));

	carp("$this_function: Group $name exceeds the recommended line length $add/$max_nis_line_len")
	    if $len > $max_nis_line_len;

	$entry->add(uniqueMember => $add);
	$result = $entry->update($ldap);
	$result = chase_referrals($result, $entry)
	    if $result->code == LDAP_REFERRAL;

	if ($result->code)
	{
		carp("$this_function:(" . __LINE__ . ") Failed to add $add to $name: ", $result->error);
	}
}

sub
LDAPDeleteFromSecurityGroup
{
	use LDAPTools;

	my $ldap = shift;
	my $name = shift;
	my $del = shift;

	my $this_function = (caller(0))[3];

	# Clear off any whitespace
	$del =~ s/^\s*|\s*$//g;

	# Find the group to update
	my $filter = "(&(objectClass=groupofuniquenames)(cn=$name))";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return LDAPDeleteFromSecurityGroup($reldap, $name, $del) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	$result->count == 0 and
	    croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
	$result->count > 1 and
	    croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

	my $entry = $result->shift_entry;
	my @members = $entry->get_value('uniqueMember');

	# Check for duplicates
	if (! grep { /^\s*$del\s*$/ } $entry->get_value('uniqueMember'))
	{
		carp("$this_function:(" . __LINE__ . ") $del not found in $name");
	}

	$entry->delete(uniqueMember => [ $del ]);
	$result = $entry->update($ldap);
	$result = chase_referrals($result, $entry)
	    if $result->code == LDAP_REFERRAL;

	if ($result->code)
	{
		carp("$this_function:(" . __LINE__ . ") Failed to remove $del from $name: ", $result->error);
		return $result;
	}
}

sub
user_secondary_groups($$)
{
	my $ldap = shift;
	my $user = shift;

	my $this_function = (caller(0))[3];

	croak("$this_function(Net::LDAP, \"uid\") Net::LDAP object not valid")
	    if ! defined $ldap or ref $ldap ne "Net::LDAP";

	croak("$this_function(Net::LDAP, \"uid\" | Net::LDAP::Entry) uid is not a scalar or Net::LDAP::Entry")
	    if ! defined $user or (ref $user ne "Net::LDAP::Entry" and ref $user ne "");

	my $uid = $user;
	$uid = $user->get_value('uid') if ref $user eq "Net::LDAP::Entry";
	
	my $filter = "(&(objectClass=posixGroup)(memberUid=$uid))";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				attrs  => [ qw(cn) ],
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return user_secondary_groups($reldap, $user) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	# Sort all the gidNumbers into an array
	my @groups = map { $_->get_value('cn') }
			sort { $a->get_value('cn') cmp $b->get_value('cn') }
				$result->entries;

	return @groups;
}

sub
user_security_groups($$)
{
	my $ldap = shift;
	my $user = shift;

	my $this_function = (caller(0))[3];

	croak("$this_function(Net::LDAP, \"uid\") Net::LDAP object not valid")
	    if ! defined $ldap or ref $ldap ne "Net::LDAP";

	croak("$this_function(Net::LDAP, \"uid\" | Net::LDAP::Entry) uid is not a scalar or Net::LDAP::Entry")
	    if ! defined $user or (ref $user ne "Net::LDAP::Entry" and ref $user ne "");

	if (ref $user ne "Net::LDAP::Entry")
	{
		# Find the netgroup to update
		my $filter = "(&(objectClass=posixAccount)(uid=$user))";

		my $result = $ldap->search(
					base   => $ldap_opt{'base'},
					filter => $filter,
					scope  => 'sub',
					);

		# Rebind LDAP and try again if REBIND has been set
		if (defined $rebind && $result->code && $result->code == 1)
		{
			my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
			return user_security_groups($reldap, $user) if ! $reresult->code;
		}

		$result->code && die "LDAP query $filter error: ", $result->error;

		#$result->count == 0 and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned no results");
		return if $result->count == 0;
		$result->count > 1  and croak("$this_function:(" . __LINE__ . ") LDAP query $filter returned multiple results");

		$user = $result->shift_entry;
	}
	
	my $dn = $user->dn;

	my $filter = "(&(objectClass=groupOfUniqueNames)(uniqueMember=$dn))";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				attrs  => [ qw(cn) ],
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return user_security_groups($reldap, $user) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	# Sort all the groups into an array
	my @groups = map { $_->get_value('cn') }
			sort { $a->get_value('cn') cmp $b->get_value('cn') }
				$result->entries;

	return @groups;
}

sub
next_gidnumber
{
	my $ldap = shift;

	my $filter = "(objectClass=posixGroup)";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				attrs  => [ qw(cn gidNumber) ],
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return next_gidnumber($reldap) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	# Sort all the gidNumbers into an array
	my @gids = map { $_->get_value('gidNumber') }
			sort { $a->get_value('gidNumber') <=> $b->get_value('gidNumber') }
				$result->entries;

	# This will return the current largest gidnumber + 1
	return $gids[$#gids] + 1;

	# This will find the next available gid > $min_gidnumber
#	my $new = $min_gidnumber;
#	foreach my $gid (@gids)
#	{
#		next if $gid < $new;
#
#		if ($new == $gid)
#		{
#			$new++;
#		} else {
#			return $new;
#		}
#	}
#	return undef;
}

sub
next_uidnumber
{
	my $ldap = shift;

	my $filter = "(objectClass=posixAccount)";

	my $result = $ldap->search(
				base   => $ldap_opt{'base'},
				filter => $filter,
				scope  => 'sub',
				attrs  => [ qw(cn uidNumber) ],
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return next_uidnumber($reldap) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter error: ", $result->error;

	# Sort all the uidNumbers into an array
	# XXX We have 2 fliers when it comes to uidNumbers, they are excluded in the map
	my @uids = map { ( $_->get_value('uidNumber') == 99999  ||
			   $_->get_value('uidNumber') == 999999 ||
			   $_->get_value('uidNumber') == 1845518684 ?
				() : $_->get_value('uidNumber') ) }
			sort { $a->get_value('uidNumber') <=> $b->get_value('uidNumber') }
				$result->entries;

	# This will return the current largest uidnumber + 1
	return $uids[$#uids] + 1;
}

sub
ip_in_use($$)
{
	my $ldap = shift;
	my $ip = shift;

	my $this_function = (caller(0))[3];

	croak("$this_function(Net::LDAP, \"ip\") Net::LDAP object not valid")
	    if ! defined $ldap or ref $ldap ne "Net::LDAP";

	return if ! defined $ip;

	my $filter = sprintf "(&(objectClass=ipHost)(ipHostNumber=$ip))";

	my $result = $ldap->search(
				base	=> $ldap_opt{'base'},
				filter	=> $filter,
				scope	=> 'sub',
				);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return ip_in_use($reldap, $ip) if ! $reresult->code;
	}

	$result->code and die "LDAP search $filter failed: ", $result->error;

	return if $result->count == 0;

	return $result->shift_entry;
}

sub
valid_ip($)
{
	my $ip = shift;

	if ($ip =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/)
	{
		return 1
			if $1 >= 1 and $1 <= 255 and
			   $2 >= 1 and $2 <= 255 and
			   $3 >= 1 and $3 <= 255 and
			   $4 >= 1 and $4 <= 255;
	}
	return;
}

sub
valid_mac($)
{
	my $mac = shift;

	return 1 if $mac =~ m/^(([a-fA-F0-9]){1,2}:){5}([a-fA-F0-9]{1,2}){1}$/;
	return 1 if $mac =~ m/^(([a-fA-F0-9]){1,2}-){5}([a-fA-F0-9]{1,2}){1}$/;
	return 1 if $mac =~ m/^[a-fA-F0-9]{12}$/;
	return;
}

sub
canon_mac($)
{
	my $mac = shift;

	my @byte;
	if ($mac =~ /:/) {
		@byte = split(/:/, $mac);
	} elsif ($mac =~ /-/) {
		@byte = split(/-/, $mac);
	} else {
		@byte = ( $mac =~ m/.{2}/g );
	}

	#croak("Failed to parse $mac as a mac address\n") if @byte != 6;
	return if @byte != 6;

	@byte = map { $_ = hex $_ } @byte;
	map { return if $_ > 255 } @byte;

	return sprintf("%0.2x:%0.2x:%0.2x:%0.2x:%0.2x:%0.2x", @byte);
}

sub
get_my_serial_number
{
	my $ldap = shift;

	my @pwent = getpwuid($<) or
	    die "Go away, you don't exist.\n";
	my $uid = $pwent[0];

	my $filter = "(&(objectClass=posixAccount)(uid=$uid))";

	my $result = $ldap->search(
			base   => $ldap_opt{'base'},
			filter => $filter,
			scope  => 'sub',
			);

	# Rebind LDAP and try again if REBIND has been set
	if (defined $rebind && $result->code && $result->code == 1)
	{
		my ($reldap, $reresult) = &$rebind($ldap, @rebind_args);
		return get_my_serial_number($reldap) if ! $reresult->code;
	}

	$result->code && die "LDAP query $filter failed!: ", $result->error;

	if ($result->count == 1)
	{
		return $result->shift_entry->get_value('employeeNumber');
	}
}

sub
pad_employeeNumber($)
{
	my $empno = shift;
	return if ! defined $empno;

	# XXX Maybe it should just be 00 + $empno, not sure
	return sprintf("%s%s",
	    substr("000000", 0, 7 - length($empno)), $empno)
		if length $empno < 6;
	return $empno;
}

sub
RandomPassword(;$)
{
	my $length = shift;

	$length = 8 if ! defined $length;

	my $this_function = (caller(0))[3];

	croak("$this_function password length $length should be at least 8")
	    if $length < 8;

	my @char = ( '!', '%', '&', '+'..'.', '@', ':', 2..9, 'a'..'k', 'm'..'z', 'A'..'H', 'J'..'N', 'P'..'Z');

	my $pw = "";

	for (my $i = 0; $i < $length; $i++)
	{
		$pw .= $char[rand($#char)];
	}
	return $pw;

}

sub
MD5Password($)
{
	my $clear = shift;

	my $this_function = (caller(0))[3];

	croak("$this_function no clear text passed")
	    if ! defined $clear;

	my $salt = genSalt(8);

	return "{crypt}" . (crypt $clear, '$1$'.$salt.'$');

}

sub
SSHAPassword($)
{
	my $clear = shift;

	my $this_function = (caller(0))[3];

	croak("$this_function no clear text passed")
	    if ! defined $clear;

	use Digest::SHA1;
	use MIME::Base64;

	my $salt = genSalt(8);

	my $ctx = Digest::SHA1->new;
	$ctx->add($clear);
	$ctx->add($salt);

	return '{SSHA}' . encode_base64($ctx->digest . $salt, '');
}

sub
genSalt(;$)
{
	my $length = shift;

	$length = 2 if ! defined $length;

	my $this_function = (caller(0))[3];

	croak("$this_function salt length $length should be between 2 and 16")
	    if $length < 2 or $length > 16;

	my @char = ( 0..9, 'a'..'z', 'A'..'Z');

	my $salt = "";

	for (my $i = 0; $i < $length; $i++)
	{
		my $offset = ($i == 0 ? 1 : 0);
		$salt .= $char[rand($#char - $offset) + $offset];
	}
	return $salt;
}

sub
rcs_check_lock
{
	my $file = shift;

	return if ! defined $file;

	my $this_function = (caller(0))[3];

	my @log = `rlog -L -hlR $file`;
	my $rc = $? >> 8;

	my %name;
	my $last_key;
	foreach my $line (@log)
	{
		chomp($line);
		next if $line =~ /^\s*$/;
		my ($key, $value) = split(/\s*:\s*/, $line, 2);
		if ($key =~ /^\s+/)
		{
			croak "subkey $key but no previous key defined"
			    if ! defined $last_key;
			$key =~ s/^\s+//;
			$name{$last_key}{$key} = $value;
		}
		else
		{
			$last_key = $key;
			$name{$key}{value} = $value;
		}
	}

	my $real = (getpwuid($<))[0];
	my $effective = (getpwuid($>))[0];

	foreach my $locker (keys %{$name{locks}})
	{
		next if $locker eq "value";
		return $locker if $locker ne $real and $locker ne $effective;
		return 0 if $locker eq $real or $locker eq $effective;
	}
	return undef;
}

sub
rcs_checkout
{
	my $file = shift;

	return if ! defined $file;

	my $this_function = (caller(0))[3];

	# XXX RCS is stupid, it checks $< not $> with access
	my $save = $<;
	$< = $> if $< != $>;

	my @log = `co -q -l $file 2>&1`;
	my $rc = $? >> 8;

	$< = $save if $< != $save; # XXX

	print Dumper(\@log, \$rc) if $rc ne 0;
	return $rc if $rc ne 0;
}

sub
rcs_checkin
{
	my $file = shift;
	my $comment = shift;

	return if ! defined $file;

	my $this_function = (caller(0))[3];

	$comment = "$this_function - no comment provided" if ! defined $comment;

	# XXX RCS is stupid, it checks $< not $> with access
	my $save = $<;
	$< = $> if $< != $>;

	my @log = `ci -q -m\"$comment\" -u $file 2>&1`;
	my $rc = $? >> 8;

	$< = $save if $< != $save; # XXX

	print Dumper(\@log, \$rc) if $rc ne 0;
	return $rc if $rc ne 0;
}

1;
