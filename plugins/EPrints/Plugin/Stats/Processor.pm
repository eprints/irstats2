package EPrints::Plugin::Stats::Processor;

our @ISA = qw/ EPrints::Plugin /;

use strict;

# Stats::Processor (Abstract class)
#
# This handles the processing of stats. Used in two cases: by the bin script that updates the stats daily and also when rendering data.
# 
# Properties:
# - $self->{provides} (ARRAYREF): which data this provides (for example 'eprint_downloads'). This s the same name as what is called 'datatype' in z_stats.pl.
# - $self->{cache}: used to cache the data when the stats updating is invoked. 

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );
	
        $self->{disable} = 0;
	
	# which stat sets does this provide?
	$self->{provides} = [];

	return $self;
}

sub process_dataset
{
	my( $self, $params ) = @_;

        my $session = $self->{'session'};
	my $handler = $params->{handler};

	if( !defined $params->{datasetid} )
	{
		$handler->log( "Error: missing parameter 'datasetid'" );
		return;
	}

	my $dataset = $session->dataset( $params->{datasetid} );
	
	if( !defined $dataset )
	{
		$handler->log( "Error: invalid dataset '$params->{datasetid}'" );
		return;
	}

	my $class = $dataset->dataobj_class();
	$class =~ s/EPrints::DataObj:://g;

	# e.g. 'current_eprintid' for the EPrints dataset
	my $ds_key = 'current_'.$dataset->key_field()->get_name;
	# my @plugins = @{$handler->get_stat_plugins( 'Processor::EPrint' ) || []};
	my @plugins = @{$handler->get_stat_plugins( "Processor::$class" ) || []};

	if( $params->{'create_tables'} || (exists $params->{incremental} && !$params->{incremental}) )
	{
		$_->create_tables( $handler ) for(@plugins);
	}
	else
	{
		# check if the table exists, still
		foreach my $plugin ( @plugins )
		{
			my $done = 0;
			foreach( @{$plugin->{provides} || [] } )
			{
				next if( $handler->{dbh}->has_table( "irstats2_$_" ) );
				last if( $done );
				$plugin->create_tables( $handler );
				$done = 1;
			}
		}
	}

	my @filters;
	foreach my $filterid (@{$params->{'filters'} || []})
	{
		my $filter = $session->plugin( "Stats::Filter::$filterid" );
		next unless( defined $filter );
		push @filters, $filter;
	}

#	my $current_eprintid = 0;
	my $current_record = 0;

	if( !exists $params->{incremental} || $params->{incremental} )
	{
	 	$current_record = $handler->get_internal_value( $ds_key ) || 0;
		#$handler->log( "EPrint: starting from eprintid = '$current_eprintid'" );
	}
		
	$handler->log( "$params->{datasetid}: starting from record $current_record" );

#	my $ds = $session->dataset( 'eprint' );
        my $searchexp = new EPrints::Search(
                session => $session,
                dataset => $dataset,
                allow_blank => 1 );

	if( $current_record > 0 )
	{
		$current_record++;
		$searchexp->add_field( $dataset->key_field(), "$current_record-" );
	}

	my $list = $searchexp->perform_search();

	unless( $list->count )
	{
		# $handler->set_internal_value( 'eprint_last_run', EPrints::Time::get_iso_timestamp() );
		return;
	}
	
	$handler->log( "$params->{datasetid}: ".$list->count." records to process." );

	my $info = { plugins => \@plugins, filters => \@filters };

	$list->map( sub {
		my( undef, undef, $record, undef ) = @_;

		foreach my $filter (@{$info->{filters}})
		{
			return unless( $filter->filter_record( $record ) );
		}

		foreach my $plugin (@{$info->{plugins}})
		{
			$plugin->process_record( $record );
		}

	}, $info );
	
	foreach my $plugin ( @plugins, @filters )
	{
		$plugin->commit_data($handler);
	}

	if( !exists $params->{incremental} || $params->{incremental} )
	{
		$handler->set_internal_value( $ds_key, $list->item( $list->count - 1 )->get_value( $dataset->key_field()->get_name ) );
	}

}

# Internal method - clears the cache to lower the memory footprint as stats are updated.
sub clear_cache { delete shift->{cache} };

# Tells which data (SQL) tables to create.
sub create_tables 
{
	my( $self, $handler ) = @_;
	my $rc = 1;
	foreach( @{ $self->{provides} || [] } )
	{
		$rc &&= $handler->create_data_table( "$_" );
	}
	return $rc;
}

# Should be subclassed - How to process a record.
# Note that "record" encompass different types:
# - Records from the Access dataset are HASH'es (see Processor::Access*)
# - Other records are usually EPrints::DataObj (e.g. EPrint objects, see Processor::EPrint*)
sub process_record { }

# Should be subclassed - What data to commit to the DB
sub commit_data 
{
        my( $self, $handler ) = @_;

	my $provides = $self->{provides};
	
	# 'provides' is an ARRAY REF but few Processor plugins provide more than one datatype (see Processor::Access::Downloads for an example)
	if( defined $provides && defined $provides->[0] )
	{
        	$handler->save_data_values( $provides->[0], $self->{cache} );
	}
}

# Common helper method
sub parse_datestamp
{
	my( $self, $session, $d ) = @_;

	if( defined( $d ) )
	{
		if( $d =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)$/ )
		{
			return { day => $3, month => $2, year => $1, epoch => EPrints::Time::datestring_to_timet( $session, "$1-$2-$3T$4:$5:$6Z" ) };
		}
		elsif( $d =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/ )
		{
			return { day => $3, month => $2, year => $1, epoch => EPrints::Time::datestring_to_timet( $session, "$1-$2-$3T00:00:00Z" ) };
		}
	}

	print STDERR "Stats::Processor: [error] failed to parse date '" . ( defined $d ? $d : "" ) . "'\n";

	return {day=>0,month=>0, year=>1900, epoch => 0};
}

sub conf { shift->{conf} || {} }

sub handler { shift->{handler} }

1;

