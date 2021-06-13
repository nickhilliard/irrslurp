#!/usr/bin/perl -w
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Copyright (c) 2021 Nick Hilliard. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
#  * Neither the name of the copyright holders nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

use Data::Dumper;

use IRRSlurp::Stats;
use IRRSlurp::Whois;
use JSON;

my $ripewhois = new IRRSlurp::Whois (rirname => 'ripencc');
my $hash = \$ripewhois->{hash}->{whois_nonauth};

my $invalids;

foreach my $rirname (qw (arin lacnic afrinic apnic)) {
	my $stats = new IRRSlurp::Stats (rirname => $rirname);

	$ripewhois->{log}->debug ("searching $rirname for invalid NONAUTH objects");

	foreach my $trietype (qw (transfers delegated)) {
		my $pt = $stats->{tries}->{$trietype};

		foreach my $route (keys %{$$hash}) {
			my ($prefix, $asn);

			next unless ($route =~ /(\S+\/[0-9]+)AS([0-9]+)/);
			$prefix = $1; $asn = $2;

			my $data = $pt->match_string($prefix);
			next unless (defined($data));

			my $reregtime = $data->{timestamp};
			my $nonauthtime = $$hash->{$route}->{timestamp};

			# bogons are entries where:
			# 1. the resource registration time is later than the last-modified time in ripe-whois
			# 2. the RIR delegated status is 'reserved' or 'available'

			next unless (
				($reregtime > $nonauthtime)
				|| ( $trietype eq 'delegated' && defined ($data->{status}) && ($data->{status} eq 'reserved' || $data->{status} eq 'available') )
			);

			my $tracedata = {
				route => $route,
				nonauth => {
					timestamp => $nonauthtime,
				},
				auth => {
					prefix => $data->{prefix},
					timestamp => $reregtime,
					source => $stats->{rir},
					type => $trietype,
				},
			};
			if (defined ($data->{status})) {
				$tracedata->{auth}->{status} = $data->{status};
			}

			push @{$invalids->{$route}}, $tracedata;

			$ripewhois->{log}->is_debug() && $ripewhois->{log}->debug ("matched nonauthprefix: $route", { tracedata => $tracedata});
		}
	}
}

my $json = JSON->new->allow_nonref;
print $json->pretty->encode($invalids)."\n";
