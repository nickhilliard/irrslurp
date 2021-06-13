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

package IRRSlurp::Stats;

use parent 'IRRSlurp';

use strict;

use Data::Dumper;
use Net::IP;
use Net::Patricia;

use vars qw(@ISA @EXPORT_OK @EXPORT $VERSION $AUTOLOAD);

$VERSION = '0.01';

1;

sub new {
	my ($class, %options) = @_;

	my $self = $class->SUPER::new(%options);
	
	bless $self, $class;

	$self->refreshcache();

	$self->createtransfertrie();
	$self->createdelegatedtrie();

	return $self;
}

sub refreshcache {
        my ($self) = @_;

	$self->{log}->info('retrieving transfers, rir: '.$self->{options}->{rirname});
	$self->filemirror($self->get_transfers_filename(), 'transfers');

	$self->{log}->info('retrieving delegated, rir: '.$self->{options}->{rirname});
	$self->filemirror($self->get_delegated_filename(), 'delegated');
}

sub get_transfers_filename {
	my ($self) = @_;
	my $rir = $self->{rir};

	return $self->{rirdata}->{$rir}->{rootdir}."/stats/$rir/transfers/transfers_latest.json";
}

sub get_delegated_filename {
	my ($self) = @_;
	my $rir = $self->{rir};

	return $self->{rirdata}->{$rir}->{rootdir}."/stats/$rir/delegated-$rir-extended-latest";
}

sub createtransfertrie {
	my ($self) = @_;

	my ($pt, $prefixafi);
	if ($self->{options}->{protocol} == 6) {
		$pt = new Net::Patricia AF_INET6;
		$prefixafi = "ip6nets";
	} else {
		$pt = new Net::Patricia;
		$prefixafi = "ip4nets";
	}

	my $transferblob = ${$self->slurp_json($self->{mirror}->{transfers}->{filename})};

	my $reccount = 0;
	my $cidrcount = 0;

        $self->{log}->info('started parsing transfer trie for filename: '.$self->{mirror}->{transfers}->{filename});

	foreach my $transfer (@{$transferblob->{transfers}}) {
		# not interested in mergers
		next if ($transfer->{type} eq "MERGER_ACQUISITION");

		# only ipv4 for the moment
		next unless ($transfer->{$prefixafi});

		my @subnets;
		# LACNIC uses ISO8601 + 3-digit milliseconds, local TZ and no H:M separator in the specified TZ.
		# standard ISO8601 in UTC would have been really helpful here.
		if ($self->{rir} eq 'lacnic' && $transfer->{transfer_date} =~ /(\d+-\d+-\d+T\d+:\d+:\d+)\.\d+(.*)(\d{2})(\d{2})/) {
			$transfer->{transfer_date} = $1.$2.$3.":".$4;
		}
		my $dt = DateTime::Format::ISO8601->parse_datetime($transfer->{transfer_date});
		my $epochtime = $dt->epoch;

		# lacnic put transfers sets into an array
		my $set = $self->{rir} eq 'lacnic' ? $transfer->{$prefixafi}[0]->{transfer_set} : $transfer->{$prefixafi}->{transfer_set};
		
		foreach my $transfernet (@{$set}) {

			$self->{log}->is_debug() && $self->{log}->debug("parsing: start_address: $transfernet->{start_address}, end_address: $transfernet->{end_address}, timestamp: $epochtime");
			my $ip = new Net::IP ($transfernet->{start_address}." - ".$transfernet->{end_address});
			# this may be a non-contiguous range. If so, Net::IP::is_prefix will be set to 0
			if ($ip->{is_prefix}) {
				push (@subnets, $ip->prefix());
			} else {
				push (@subnets, $ip->find_prefixes());
			}
		}			

		$self->{log}->is_debug() && $self->{log}->debug("added to PT: subnets: ".join(",", @subnets).", timestamp: $epochtime");
		foreach my $net (@subnets) {
			my $userdata = {
				prefix		=> $net,
				timestamp	=> $epochtime,
			};
			$pt->add_string($net, $userdata);
		}
		$reccount++;
		$cidrcount += $#subnets + 1;
	}

	$self->{log}->info('ended parsing transfer trie for filename: '.$self->{mirror}->{transfers}->{filename}.", records: $reccount, cidrprefixes: $cidrcount");

	$self->{tries}->{transfers} = $pt;
}

sub createdelegatedtrie {
	my ($self) = @_;

	my ($pt, $prefixafi);
	if ($self->{options}->{protocol} == 6) {
		$pt = new Net::Patricia AF_INET6;
		$prefixafi = "ipv6";
	} else {
		$pt = new Net::Patricia;
		$prefixafi = "ipv4";
	}

	my $strp = DateTime::Format::Strptime->new(
		pattern		=> '%Y%m%d',
		time_zone	=> 'UTC',
	);

	my $reccount = 0;
	my $cidrcount = 0;

	$self->{log}->info('started parsing delegated trie for filename: '.$self->{mirror}->{delegated}->{filename});
	open (INPUT, $self->{mirror}->{delegated}->{filename});
	while (<INPUT>) {
		chomp;
		my @fields = split(/\|/);

		next unless ($fields[0] eq $self->{rir});

		next unless ($fields[2] eq $prefixafi);

		next if (defined($fields[5]) && $fields[5] eq 'summary');

		next unless ($fields[6] eq 'allocated'
			or $fields[6] eq 'assigned'
			or $fields[6] eq 'available'
			or $fields[6] eq 'reserved');

		$self->{log}->is_debug() && $self->{log}->debug("parsing delegated file: fields: ".join(",", @fields));

		my @subnets;
		my $timestamp = $fields[5] ? $fields[5] : '19800101';	 # randomly chosen early date from before there were allocations
		my $dt = $strp->parse_datetime($timestamp);
		my $epochtime = $dt->epoch;

		# ipv4 lists the number of IP addresses; ipv6 specifies the mask length
		my $ipspec;
		if ($self->{options}->{protocol} == 6) {
			$ipspec = $fields[3]."/".$fields[4];
		} else {
			$ipspec = $fields[3]." + ".($fields[4] - 1);
		}
		my $ip = new Net::IP ($ipspec);

		if ($ip->{is_prefix}) {
			my $prefix = $self->{options}->{protocol} == 6 ? $ip->short()."/".$ip->prefixlen() : $ip->prefix();
			push (@subnets, $prefix);
		} else {
			push (@subnets, $ip->find_prefixes());
		}

		foreach my $net (@subnets) {
			$self->{log}->is_debug() && $self->{log}->debug("added to PT: subnet: $net, timestamp: $epochtime, status: $fields[6]");
			my $userdata = {
				prefix		=> $net,
				timestamp	=> $epochtime,
				status		=> $fields[6],
			};
			$pt->add_string($net, $userdata);
		}
		$reccount++;
		$cidrcount += $#subnets + 1;
	}
	close (INPUT);

	$self->{log}->info("ended parsing delegated trie for filename: $self->{mirror}->{delegated}->{filename}, records: $reccount, cidrprefixes => $cidrcount");

	$self->{tries}->{delegated} = $pt;
}
