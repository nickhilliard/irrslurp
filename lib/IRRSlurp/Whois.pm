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

package IRRSlurp::Whois;

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

	$self->createwhoishash();

	return $self;
}

sub refreshcache {
        my ($self) = @_;

	$self->{log}->info('retrieving transfers', {rir => $self->{options}->{rirname}});
	$self->filemirror($self->get_whois_nonauth_filename(), 'whois_nonauth');
}

sub get_whois_nonauth_filename {
	my ($self) = @_;
	my $rir = $self->{rir};

	return $self->{rirdata}->{$rir}->{'nonauth'};
}

sub createwhoishash {
	my ($self) = @_;
	
	my $hash;

	$self->{log}->info('started parsing whois hash '.$self->{mirror}->{whois_nonauth}->{filename});

	local $/ = "";

	open (INPUT, "gunzip<".$self->{mirror}->{whois_nonauth}->{filename}."|");
	while (<INPUT>) {
		next unless (/route:\s+(\S+)/);
		my $prefix = $1;

		my $timestamp = 0;
		if (/last-modified:\s+(\S+)/) {
			my $dt = DateTime::Format::ISO8601->parse_datetime($1);
			$timestamp = $dt->epoch;
		}

		my $origin;
		if (/origin:\s+(\S+)/) {
			$origin = uc($1);
		}

		my $key = $prefix.$origin;

		$hash->{$key} = {
			timestamp => $timestamp,
		};

		$self->{log}->is_trace() && $self->{log}->trace("added to hash:", {key => $key, hash => $hash->{$key}});
	}
	close (INPUT);

	$self->{log}->info('ended parsing whois hash '.$self->{mirror}->{whois_nonauth}->{filename});

	$self->{hash}->{whois_nonauth} = $hash;
}
