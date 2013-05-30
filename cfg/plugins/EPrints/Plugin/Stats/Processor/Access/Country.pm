package EPrints::Plugin::Stats::Processor::Access::Country;

our @ISA = qw/ EPrints::Plugin::Stats::Processor::Access /;

use strict;

# Processor::Access::Country
#
# Processes the Country codes from Access records. Provides the 'eprint_countries' datatype
# Note that this requires Geo::IP to work.
# 

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

        unless( EPrints::Utils::require_if_exists( "Geo::IP::PurePerl" ) )
        {
                $self->{advertise} = 0;
                $self->{disable} = 1;
                $self->{error} = "Failed to load required module for Processor::Access::Country. Country information will not be available.";
                return $self;
        }

	if( -e '/opt/eprints3/lib/geoip/GeoIP.dat' )
	{	
		# if possible, use the GeoIP data shipped with EPrints
		$self->{geoip} = Geo::IP::PurePerl->new( '/opt/eprints3/lib/geoip/GeoIP.dat' );
	}
	else
	{
		# otherwise use the global file
		$self->{geoip} = Geo::IP::PurePerl->new( 1 );
	}

	unless( defined $self->{geoip} )
	{
                $self->{advertise} = 0;
                $self->{disable} = 1;
                $self->{error} = "Failed to load required module for Processor::Access::Country. Country information will not be available.";
                return $self;
	}

        $self->{disable} = 0;
        $self->{provides} = [ "countries" ];

	$self->{conf} = {
                fields => [ 'value' ],
                render => 'phrase',
                render_phrase_prefix => 'irstats2_objects:country_code:',
        };

	return $self;
}

sub process_record
{
	my ($self, $record, $is_download) = @_;

	return unless( $is_download );
	
        my $ip = $record->{requester_id};
        return unless( defined $ip );

	my $code = $self->{geoip}->country_code_by_addr( $ip );

	if( defined $code && length $code )
	{
		my $epid = $record->{referent_id};
		return unless( defined $epid );

		my $date = $record->{datestamp}->{cache};
		$self->{cache}->{"$date"}->{$epid}->{$code}++;	
	}
}


1;
