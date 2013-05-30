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
	
	return $self;
}

sub process_record
{
	my ($self, $record, $is_download) = @_;
	
	my $epid = $record->{referent_id};
	return unless( defined $epid );

	my $ua = $record->{requester_user_agent};
	return unless( EPrints::Utils::is_set( $ua ) );

	foreach( keys %$BROWSERS_SIGNATURES )
	{
		if( $ua =~ $_ )
		{
			my $date = $record->{datestamp}->{cache};
			$self->{cache}->{"$date"}->{$epid}->{$BROWSERS_SIGNATURES->{$_}}++;
			last;
		}
	}
}

1;
