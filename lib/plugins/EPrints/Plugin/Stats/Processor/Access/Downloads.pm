package EPrints::Plugin::Stats::Processor::Access::Downloads;

our @ISA = qw/ EPrints::Plugin::Stats::Processor::Access /;

use strict;

# Processor::Access::Downloads
#
# Arguably the most important Processor plugin. This deals with the download counts (and summary pages hits).
#
# Provides 'eprint_downloads' and 'eprint_views'
# 

sub new
{
        my( $class, %params ) = @_;

	my $self = $class->SUPER::new( %params );

	$self->{provides} = [ "downloads", "views" ];
	$self->{disable} = 0;
	$self->{cache} = {};

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
	my ($self, $record,$is_download) = @_;

	my $epid = $record->{referent_id};
	return unless( defined $epid );
	
	my $date = $record->{datestamp}->{cache};

	if( $is_download )
	{
		$self->{cache_downloads}->{"$date"}->{$epid}->{downloads}++;
	}
	else
	{
		$self->{cache_views}->{"$date"}->{$epid}->{views}++;
	}

	return;
}

# use this to commit to db:
sub commit_data
{
	my( $self, $handler ) = @_;

	$handler->save_data_values( "downloads", $self->{cache_downloads} );
	$handler->save_data_values( "views", $self->{cache_views} );
}


1;

