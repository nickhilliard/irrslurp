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
