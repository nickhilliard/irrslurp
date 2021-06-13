require 5.002;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME	    	=> 'IRRSlurp',
	VERSION_FROM    => 'lib/IRRSlurp.pm',

	PREREQ_PM       => {
		LWP::UserAgent => 0,
		JSON => 0,
		Log::Any => 0,
		DateTime::Format::ISO8601 => 0,
		Net::IP => 0,
		Net::Patricia => 0,
	},

	'dist'	  => {
		'COMPRESS' => 'gzip -9f',
		'SUFFIX' => 'gz'
	},
);
