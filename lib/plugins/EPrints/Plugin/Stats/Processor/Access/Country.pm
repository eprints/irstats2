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
	return $self if( !$self->{session} );

	# if possible, use the GeoIP data file shipped with EPrints
	my $dat_file = $self->{session}->config( "lib_path" ) . '/geoip/GeoIP.dat';
	
	# alternatively use the global one
	$dat_file = 1 if( !-e $dat_file );	

	#Test Geo::IP first - it's faster!
	#If dat_file is not the global one and Geo::IP is available, then we need to call open($dat_file) not new($dat_file)
	foreach my $pkg ( 'GeoIP2::Database::Reader', 'Geo::IP', 'Geo::IP::PurePerl' )
	{
		if( EPrints::Utils::require_if_exists( $pkg ) )
		{
			if( $pkg =~ /GeoIP2/ && -e "/usr/share/GeoIP/GeoLite2-Country.mmdb" )
            {
				$dat_file = "/usr/share/GeoIP/GeoLite2-Country.mmdb";
				$self->{geoip} = GeoIP2::Database::Reader->new( file  => $dat_file, locales => [ 'en' ] );
			}
			elsif( $pkg !~ /PurePerl/ )
			{
				$self->{geoip} = $pkg->new( $dat_file ) if $dat_file eq '1';
				$self->{geoip} = $pkg->open( $dat_file ) if $dat_file ne '1';
			}
			else
			{
				$self->{geoip} = $pkg->new( $dat_file );
			}
			last if( defined $self->{geoip} );
		}
	}

	if( !defined $self->{geoip} )
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

	my $code;
	if ( ref $self->{geoip} eq "GeoIP2::Database::Reader" )
	{
		eval
		{
			$code = $self->{geoip}->country( ip => $ip )->country()->iso_code();
		};
	}
	else
	{
		$code = $self->{geoip}->country_code_by_addr( $ip );
	}

	if( defined $code && length $code )
	{
		my $epid = $record->{referent_id};
		return unless( defined $epid );

		my $date = $record->{datestamp}->{cache};
		$self->{cache}->{"$date"}->{$epid}->{$code}++;	
	}
}


1;
