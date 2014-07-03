package EPrints::Plugin::Stats::Processor::EPrint::CacheDownloads;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;

# Processor::EPrint::CacheDownloads
#
# Keep a cache table of cumulative downloads for each eprint 
#
# This is used internally anytime a date filter is not used in a report and makes the response times *much* faster
#

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

	$self->{provides} = [ "cache_downloads" ];

	$self->{disable} = 0;

	return $self;
}

sub process_record
{
	my ($self, $eprint ) = @_;

	my $epid = $eprint->get_id;
	return unless( defined $epid );
	
	my $ctx = $self->{handler}->context( { datatype => "downloads", set_name => 'eprint', set_value => $epid } );

	my $count = $self->{handler}->data( $ctx )->select->sum_all;

	my $datestamp = "0";

	# "0" is a place-holder for the datestamp which is not used in the downloads_cache table (that's the point)
	$self->{cache}->{"0"}->{$epid}->{"downloads"} = $count;
}


1;
