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

	$self->{provides} = [ "cache_downloads", "cache_views" ];

	$self->{disable} = 0;

	return $self;
}

sub clear_cache
{
	my( $self ) = @_;

	delete $self->{cache_downloads};
	delete $self->{cache_views};
}

sub process_record
{
	my ($self, $eprint ) = @_;

	my $epid = $eprint->get_id;
	return unless( defined $epid );
	
	foreach my $type ( "downloads", "views" )
	{
		my $ctx = $self->{handler}->context( { datatype => $type, set_name => 'eprint', set_value => $epid, cache => 0 } );

		my $count = $self->{handler}->data( $ctx )->select->sum_all;

		# "0" is a place-holder for the datestamp which is not used in the downloads_cache table (that's the point)
		$self->{"cache_$type"}->{"0"}->{$epid}->{"type"} = $count;
	}
}

# use this to commit to db:
sub commit_data
{
	my( $self, $handler ) = @_;

	$handler->save_data_values( "cache_downloads", $self->{cache_downloads} );
	$handler->save_data_values( "cache_views", $self->{cache_views} );
}

1;
