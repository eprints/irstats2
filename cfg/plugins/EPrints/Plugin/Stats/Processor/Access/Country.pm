package EPrints::Plugin::Stats::Processor::Access::Country;

our @ISA = qw/ EPrints::Plugin::Stats::Processor::Access /;

use strict;

# Processor::Access::Country
#
# Processes the Country codes from Access records. Provides the 'eprint_countries' datatype
# Note that this requires Geo::IP or Geo::IP::PurePerl to work.
# 
# From: http://search.cpan.org/~borisz/Geo-IP-PurePerl-1.25/lib/Geo/IP/PurePerl.pm#SEE_ALSO
# Geo::IP - this now has the PurePerl code merged it, so it supports both XS and Pure Perl 
# implementations. The XS implementation is a wrapper around the GeoIP C API, which is much 
# faster than the Pure Perl API.
# I think this has been in place since ~Aug 2008

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

	#Test Geo::IP first - it's faster!
	my $geoPackage = "Geo::IP";

        if( !EPrints::Utils::require_if_exists( $geoPackage ) ){
        	# no Geo::IP, try Geo::IP::PurePerl 
                $geoPackage = "Geo::IP::PurePerl";
                unless( EPrints::Utils::require_if_exists( $geoPackage ) )
        	{
        	        $self->{advertise} = 0;
        	        $self->{disable} = 1;
        	        $self->{error} = "Failed to load required module for Processor::Access::Country. Country information will not be available.";
        	        return $self;
        	}
        }
	
        my $geoipDatFile = $self->{session}->config( "lib_path").'/geoip/GeoIP.dat';
        
	if( -e $geoipDatFile )
	{	
		# if possible, use the GeoIP data shipped with EPrints
		$self->{geoip} = $geoPackage->new( $geoipDatFile );
	}
	else
	{
		# otherwise use the global file
		$self->{geoip} = $geoPackage->new( 1 );
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
