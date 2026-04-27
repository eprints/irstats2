package EPrints::Plugin::Stats::Processor::Access::Browsers;

our @ISA = qw/ EPrints::Plugin::Stats::Processor::Access /;

use strict;

# Processor::Access::Browsers
#
# Processes the User agents from Access records. Provides the 'eprint_browsers' datatype
# 

our $BROWSERS_SIGNATURES = {
	'; AOL' => 'AOL',
	'Chrome\/' => 'Google Chrome',
	'Elinks\/' => 'Elinks',
	'Firefox\/' => 'Firefox',
	'; MSIE ' => 'Microsoft Internet Explorer',
	'Netscape\/' => 'Netscape',
	'Navigator\/' => 'Netscape',
	'Safari\/' => 'Apple Safari',
	'; Android ' => 'Android',
	'\(BlackBerry;' => 'BlackBerry',
	'Opera\/' => 'Opera',
	'; Opera Mobi\/' => 'Opera Mobile',
};

our $BROWSERS_SIGNATURES_ORDER = [
	'; AOL',
	'Chrome\/',
	'Elinks\/',
	'Firefox\/',
	'; MSIE ',
	'Netscape\/',
	'Navigator\/',
        'Safari\/',
        '; Android ',
        '\(BlackBerry;',
        'Opera\/',
        '; Opera Mobi\/',
];

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );
        $self->{provides} = [ "browsers" ];
	$self->{disable} = 0;
	$self->{cache} = {};

	# still used?!
        $self->{conf} = {
                fields => [ 'value' ],
                render => 'string',
        };

	if ( EPrints::Utils::require_if_exists( 'HTTP::BrowserDetect' ) )
	{
		$self->{conf}->{browser_cache} = {};
	}
	else
	{
		if ( $self->{session}->config( 'irstats2', 'browsers_signatures' ) )
		{
			$BROWSERS_SIGNATURES = $self->{session}->config( 'irstats2', 'browsers_signatures' );
		}
		if ( $self->{session}->config( 'irstats2', 'browsers_signatures_order' ) )
		{
			$BROWSERS_SIGNATURES_ORDER = $self->{session}->config( 'irstats2', 'browsers_signatures_order' );
		}
	}

	return $self;
}

sub process_record
{
	my ($self, $record, $is_download) = @_;
	
	my $epid = $record->{referent_id};
	return unless( defined $epid );

	my $ua = $record->{requester_user_agent};
	return unless( EPrints::Utils::is_set( $ua ) );

	my $date = $record->{datestamp}->{cache};


	if ( defined $self->{conf}->{browser_cache} )
	{
		my $browser;
		if ( $self->{conf}->{browser_cache}->{$ua} )
		{
			$browser = $self->{conf}->{browser_cache}->{$ua};
		}
		else
		{
			my $browser_detect = HTTP::BrowserDetect->new( $ua );
			$browser = $browser_detect->browser_string || 'Other';
			$self->{conf}->{browser_cache}->{$ua} = $browser;
		}
		$self->{cache}->{"$date"}->{$epid}->{$browser}++;
	}
	else
	{
		my $found = 0;
		foreach( @$BROWSERS_SIGNATURES_ORDER )
		{
			if( $ua =~ $_ )
			{
				$self->{cache}->{"$date"}->{$epid}->{$BROWSERS_SIGNATURES->{$_}}++;
				$found = 1;
				last;
			}
		}

		if (not $found)
		{
			$self->{cache}->{"$date"}->{$epid}->{Other}++;
		}
	}
}

1;
