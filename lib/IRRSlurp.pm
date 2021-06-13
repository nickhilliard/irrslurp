package IRRSlurp;

use strict;

use Data::Dumper;
use LWP::UserAgent;
use JSON;
use Log::Any;
use DateTime::Format::ISO8601;

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

	my $self;
	
	$self->{log} = Log::Any->get_logger();
	use Log::Any::Adapter ('Stderr', log_level => 'info' );

	$self->{log}->info("instantiating ".__PACKAGE__." using parameters:", {progname => $0, pid => $$, perl_version => $], %options});
	
	$self->{options} = \%options;
	$self->{rirdata} = $rirdata;
	$self->{rir} = $self->{options}->{rirname};
	$self->{options}->{cachedir} = '/tmp/cache';

	if (!defined ($rirdata->{$self->{rir}})) {
		$self->{log}->error('rir not defined', {rir => $self->{options}->{rirname}});
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

	$self->{log}->info('mirroring', {url => $url, output => $filename});
	my $res = $ua->mirror($url, $filename);

	if ($res->is_success) {
		$self->{mirror}->{$type}->{lastmodified} = $res->last_modified;
	} else {
		if ($res->code == 304) {	# not modified
			$self->{mirror}->{$type}->{lastmodified} = (stat ($filename))[9];
		} else {
			$self->{log}->info('mirror process failed');
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

	open (my $fh, "<:encoding(UTF-8)", $filename) || die("Can't open \$filename\": $!\n");
	local $/ = undef;
	my $json_input = <$fh>;
	close ($fh);
	
	my $json = JSON->new;

	my $decoded = $json->decode($json_input);

	return (\$decoded);
}
