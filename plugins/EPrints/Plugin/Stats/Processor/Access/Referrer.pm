package EPrints::Plugin::Stats::Processor::Access::Referrer;

our @ISA = qw/ EPrints::Plugin::Stats::Processor::Access /;

use strict;

# Processor::Access::Referrer
#
# Processes the Referrer from Access records. Provides the 'eprint_referrer' datatype
# 
# Note that it is possible to define local domains e.g. your local Uni intranet.
#

sub new
{
	my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );
	$self->{provides} = [ "referrer" ];
	$self->{disable} = 0;
	$self->{cache} = {};

	if( defined $self->{session} )
	{
		$self->{host} = $self->{session}->config( "host" );
		$self->{host} = $self->{session}->config( "securehost" ) unless EPrints::Utils::is_set( $self->{host} );
		$self->{domains} = $self->{session}->config( "irstats2", "local_domains" );
	}

	$self->{domains} ||= {};

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
	
	my $ref = $record->{referring_entity_id};
	return unless( EPrints::Utils::is_set( $ref ) );

	# and unescaping the %XX characters:
	$ref =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	my $referrer = $self->get_referrer( $ref );

	return unless( defined $referrer );

	my $date = $record->{datestamp}->{cache};
	
	$self->{cache}->{"$date"}->{$epid}->{$referrer}++;
}

sub get_referrer
{
	my( $self, $ref ) = @_;

	my( $protocol, $hostname, $uri ) = EPrints::Plugin::Stats::Utils::parse_url( $ref );

	unless( defined $hostname )
	{
		return undef;
	}

	# Internal hit
	if( $hostname eq 'localhost' )
	{
		return 'Internal (Abstract page)';	# if( $uri =~ /^\/\d+$/ );
	}
		
	# Internal hit via OAI
	if( $protocol eq 'info:oai' )
	{
		return 'Internal (OAI-PMH)';
	}

	if( defined $self->{host} && $hostname eq $self->{host} )
	{
		return 'Internal (Abstract page)' if( $uri =~ /^\/\d+$/ );

		return 'Internal (Search)' if( $uri =~ m#^/cgi/search/# );

		return 'Internal (Browse view)' if( $uri =~ m#^/view/# );
	
		return 'Internal (Latest Additions)' if( $uri =~ m#^/cgi/latest# );

		return 'Internal (MePrints Profile Page)' if( $uri =~ m#^/profile/# );

		return 'Internal';
	}

	return 'Google' if( $hostname =~ /google\./ );

	return 'Yahoo' if( $hostname =~ /yahoo\./ );

	return 'MSN/Bing' if( $hostname =~ /(msn|bing)\./ );

	return 'Facebook' if( $hostname =~ /facebook\./ );

	# could have some local definitions

	while( my($k,$v) = each %{$self->{domains}} )
	{
		return $k if( $hostname =~ /$v/ );
	}

	# unknown
	return $hostname;
}

1;
