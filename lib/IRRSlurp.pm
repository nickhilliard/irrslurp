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

package IRRSlurp;

use strict;

use Data::Dumper;

use LWP::UserAgent;
use JSON;
use Log::Dispatch;
use DateTime::Format::ISO8601;
use File::Basename;
use POSIX qw(strftime);

use vars qw(@ISA @EXPORT_OK @EXPORT $VERSION $AUTOLOAD);

$VERSION = '0.01';

our $rirdata = {
	'afrinic' => {
		'rootdir' => 'https://ftp.afrinic.net',
	},
	'apnic' => {
		'rootdir' => 'https://ftp.apnic.net/public/apnic',
	},
	'arin' => {
		'rootdir' => 'https://ftp.arin.net/pub',
		'nonauth' => 'https://ftp.arin.net/pub/rr/arin-nonauth.db.gz',
	},
	'lacnic' => {
		'rootdir' => 'https://ftp.lacnic.net/pub',
	},
	'ripencc' => {
		'rootdir' => 'https://ftp.ripe.net/pub',
		'nonauth' => 'https://ftp.ripe.net/ripe/dbase/ripe-nonauth.db.gz',
	},
};

1;

sub new {
	my ($class, %options) = @_;
	my @tags = qw (debug cachedir rirname protocol);

	my $self;

	$self->{options}->{cachedir} = 'irrcache';
	$self->{options}->{debug} = 'warning';
	foreach my $tag (@tags) {
		$self->{options}->{$tag} = $options{$tag} if (defined $options{$tag});
	}

	my $log_callback = sub {
		my %p = @_;

		my $tz = strftime("%z", localtime(time()));
		$tz =~ s/(\d{2})(\d{2})/$1:$2/;

		my $msg = ""
			.strftime("%Y-%m-%dT%H:%M:%S", localtime(time())).$tz
			." [".basename($0)."] "
			.uc($p{level}).": "
			.$p{message};
		return $msg;
	};

	$self->{log} = my $log = Log::Dispatch->new(
		outputs => [
			[ 'Screen', min_level => $self->{options}->{debug}, newline => 1 ],
		],
		callbacks => $log_callback,
	);
	$self->{log}->info("instantiating ".__PACKAGE__." using parameters: progname: $0, pid: $$, perl_version: $]");
	
	$self->{rirdata} = $rirdata;
	$self->{rir} = $self->{options}->{rirname};

	if (!defined ($rirdata->{$self->{rir}})) {
		$self->{log}->error("unknown/undefined rir: $self->{options}->{rirname}");
		return undef;
	}

	bless $self, $class;

	return $self;
}

sub filemirror {
	my ($self, $url, $type) = @_;
	
        my ($suffix, $filename);

        if ($url =~ /\/([^\/]+)$/) {
        	$suffix = $1;
	} else {
		$suffix = $url;
	}

	$filename = $self->{options}->{cachedir}."/".$self->{rir}."-".$suffix;

	$self->{mirror}->{$type}->{filename} = $filename;
	$self->{mirror}->{$type}->{url} = $url;

        -d $self->{options}->{cachedir} || $self->make_cache_dir();

	my $ua  = LWP::UserAgent->new( timeout => 30 );

	$self->{log}->info("mirroring url: $url, output: $filename");
	my $res = $ua->mirror($url, $filename);

	if ($res->is_success) {
		$self->{mirror}->{$type}->{lastmodified} = $res->last_modified;
	} else {
		if ($res->code == 304) {	# not modified
			$self->{mirror}->{$type}->{lastmodified} = (stat ($filename))[9];
		} else {
			$self->{log}->warning('mirror process failed');
			die $res->status_line;
		}
	}

	$self->{log}->info('mirror was successful');
	return 1;
}

sub make_cache_dir {
	my ($self) = @_;

	if (! -d $self->{options}->{cachedir}) {
		use File::Path qw(make_path);
		return (make_path($self->{options}->{cachedir}));
	}

	return 1;
}
        
sub slurp_json {
        my ($self, $filename) = @_;

	open (my $fh, "<:encoding(UTF-8)", $filename) || ($self->{log}->warning("Can't open \$filename\": $!") && die );
	local $/ = undef;
	my $json_input = <$fh>;
	close ($fh);
	
	my $json = JSON->new;

	my $decoded = $json->decode($json_input);

	return (\$decoded);
}
