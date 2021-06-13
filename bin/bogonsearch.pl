#!/usr/bin/perl -w

use Data::Dumper;

use IRRSlurp::Stats;
use IRRSlurp::Whois;
use Net::Patricia;
use JSON;

my $ripewhois = new IRRSlurp::Whois (rirname => 'ripencc');
my $hash = \$ripewhois->{hash}->{whois_nonauth};


my $rirname = 'lacnic';
my $stats = new IRRSlurp::Stats (rirname => $rirname);

my $pt = $stats->{tries}->{transfers};

my $invalids;

foreach my $route (keys %{$$hash}) {
	my ($prefix, $asn);

	next unless ($route =~ /(\S+\/[0-9]+)AS([0-9]+)/);
	$prefix = $1; $asn = $2;

	my $data = $pt->match_string($prefix);
	next unless (defined($data));

	my $transfertime = $data->{timestamp};
	my $nonauthtime = $$hash->{$route}->{timestamp};
	next unless ($transfertime > $nonauthtime);

	my $tracedata = {
		route => $route,
		nonauth => {
			timestamp => $nonauthtime,
		},
		auth => {
			prefix => $data->{prefix},
			timestamp => $transfertime,
			source => $stats->{rir},
			type => 'transfers',
		},
	};
	push @{$invalids->{$route}}, $tracedata;

	$ripewhois->{log}->debug ("matched nonauthprefix: $route", { tracedata => $tracedata});
}

my $json = JSON->new->allow_nonref;
print $json->pretty->encode($invalids)."\n";