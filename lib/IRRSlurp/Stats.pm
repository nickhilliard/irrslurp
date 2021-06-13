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

	$self->{log}->info('retrieving transfers', {rir => $self->{options}->{rirname}});
	$self->filemirror($self->get_transfers_filename(), 'transfers');

	$self->{log}->info('retrieving delegated', {rir => $self->{options}->{rirname}});
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

	my $pt = new Net::Patricia;
	my $transferblob = ${$self->slurp_json($self->{mirror}->{transfers}->{filename})};

	my $reccount = 0;
	my $cidrcount = 0;

        $self->{log}->info('started parsing transfer trie '.$self->{mirror}->{transfers}->{filename});

	foreach my $transfer (@{$transferblob->{transfers}}) {
		# not interested in mergers
		next if ($transfer->{type} eq "MERGER_ACQUISITION");

		# only ipv4 for the moment
		next unless ($transfer->{ip4nets});

		my @subnets;
		# LACNIC uses ISO8601 + milliseconds
		if ($self->{rir} eq 'lacnic' && $transfer->{transfer_date} =~ /(\d+-\d+-\d+T\d+:\d+:\d+)\.\d+(.*)/) {
			$transfer->{transfer_date} = $1.$2;
		}
		my $dt = DateTime::Format::ISO8601->parse_datetime($transfer->{transfer_date});
		my $epochtime = $dt->epoch;

		# lacnic put transfers sets into an array
		my $set = $self->{rir} eq 'lacnic' ? $transfer->{ip4nets}[0]->{transfer_set} : $transfer->{ip4nets}->{transfer_set};
		
		foreach my $transfernet (@{$set}) {

			$self->{log}->is_debug() && $self->{log}->debug("parsing: ", {start_address => $transfernet->{start_address}, end_address => $transfernet->{end_address}, timestamp => $epochtime});
			my $ip = new Net::IP ($transfernet->{start_address}." - ".$transfernet->{end_address});
			# this may be a non-contiguous range. If so, Net::IP::is_prefix will be set to 0
			if ($ip->{is_prefix}) {
				push (@subnets, $ip->prefix());
			} else {
				push (@subnets, $ip->find_prefixes());
			}
		}			

		$self->{log}->is_trace() && $self->{log}->trace("added to PT:", {subnets => \@subnets, timestamp => $epochtime});
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

	$self->{log}->info('ended parsing transfer trie '.$self->{mirror}->{transfers}->{filename}, { records => $reccount, cidrprefixes => $cidrcount});

	$self->{tries}->{transfers} = $pt;
}

sub createdelegatedtrie {
	my ($self) = @_;

	my $pt = new Net::Patricia;

	my $strp = DateTime::Format::Strptime->new(
		pattern		=> '%Y%m%d',
		time_zone	=> 'UTC',
	);

	my $reccount = 0;
	my $cidrcount = 0;

	$self->{log}->info('started parsing delegated trie '.$self->{mirror}->{delegated}->{filename});
	open (INPUT, $self->{mirror}->{delegated}->{filename});
	while (<INPUT>) {
		chomp;
		my @fields = split(/\|/);

		$self->{log}->is_trace() && $self->{log}->trace("parsing delegated file:", {fields => \@fields});

		next unless ($fields[0] eq $self->{rir});

		# only ipv4 for the moment
		next unless ($fields[2] eq 'ipv4');

		next if (defined($fields[5]) && $fields[5] eq 'summary');

		next unless ($fields[6] eq 'allocated'
			or $fields[6] eq 'assigned'
			or $fields[6] eq 'available'
			or $fields[6] eq 'reserved');

		my @subnets;
		my $timestamp = $fields[5] ? $fields[5] : '19800101';
		my $dt = $strp->parse_datetime($timestamp);
		my $epochtime = $dt->epoch;

		my $ip = new Net::IP ($fields[3]." + ".($fields[4] - 1));
		if ($ip->{is_prefix}) {
			push (@subnets, $ip->prefix());
		} else {
			push (@subnets, $ip->find_prefixes());
		}

		$self->{log}->is_trace() && $self->{log}->trace("added to PT:", {subnets => \@subnets, timestamp => $epochtime});
		foreach my $net (@subnets) {
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

	$self->{log}->info('ended parsing delegated trie '.$self->{mirror}->{delegated}->{filename}, { records => $reccount, cidrprefixes => $cidrcount});

	$self->{tries}->{delegated} = $pt;
}
