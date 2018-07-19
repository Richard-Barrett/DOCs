#!/usr/bin/perl -w
#
#  Copyright (c) 2004, 2005, Larry Lile <lile@users.sourceforge.net>
#  All rights reserved.
# 
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#  1. Redistributions of source code must retain the above copyright
#     notice unmodified, this list of conditions, and the following
#     disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
# 
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
#  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#  ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
#  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
#  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
#  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
#  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
#  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
#  OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#  SUCH DAMAGE.
# 
#  $Id: dshbak.pl,v 1.3 2005/07/20 00:12:24 lile Exp $
#

use strict;
use Getopt::Long qw(:config noignore_case);
use Digest::MD5 qw(md5_hex);

select((select(STDOUT), $| = 1)[0]);

our ($opt_c, $opt_h, $result, $sums);

sub dot(;$);
sub usage();
sub save($$);
sub display($@);

GetOptions('c', 'h') or exit usage;

exit !usage if $opt_h;

my $filtered = 0;

while (<STDIN>)
{
	my ($host, $output) = m/(.*?)\s*: (.*)/o;

	next
	    if ! defined $host or
		lc $host eq "fanout" or
		$host =~ m/working collective \(\d+\)/io;

	save $host, $output;
	$filtered++;
	($filtered % 1000) == 0 and print dot $filtered;
}
print dot if $filtered > 1000;

if ($opt_c)
{
	foreach (keys %$result)
	{
		my $key = $result->{$_}->{md5}->hexdigest;
		push @{$sums->{$key}->{hosts}}, $_;
	}
	foreach (keys %$sums)
	{
		my $host = @{$sums->{$_}->{hosts}}[0];
		display $sums->{$_}->{hosts}, @{$result->{$host}->{output}};
	}
}
else
{
	foreach (sort keys %$result)
	{
		display $_, @{$result->{$_}->{output}};
	}
}


sub usage()
{
	print "dshbak [-c]\n";
	return 1;
}

sub dot(;$)
{
	my $count = shift;
	return ($count ? "." : "\n");
}

sub save($$)
{
	my $host = shift;
	my $output = shift;

	return if ! $host;

	if ($output)
	{
		$result->{$host}->{md5} = Digest::MD5->new
		    if ! defined $result->{$host}->{md5};
		$result->{$host}->{count}++;
		push @{$result->{$host}->{output}}, $output;
		$result->{$host}->{md5}->add($output) if $opt_c;
	}
}

sub display($@)
{
	my $host = shift;
	my @output = @_;

	if (ref $host eq "ARRAY")
	{
		my $longest = 0;
		my $length = 0;
		my $hostline;
		foreach (@$host)
		{
			$longest = length $_ > $longest ? length $_ : $longest;
		}
		foreach (sort @$host)
		{
			if ($length + $longest > 78)
			{
				$hostline .= "\n";
				$length = 0;
			}
			my $add = $_ . " "x($longest - length $_) . "  ";
			$hostline .= $add;
			$length += length $add;
		}
		$host = $hostline;
	}

	print "HOSTS ", "-"x72, "\n$host\n", "-"x78, "\n",
	    join("\n", @output), "\n";
}
