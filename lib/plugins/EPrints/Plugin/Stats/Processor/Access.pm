package EPrints::Plugin::Stats::Processor::Access;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;

# Processor::Access ("semi" abstract class)
#
# This handles records coming from the Access dataset. "Records" are not true EPrint Dataobj, instead they are pre-processed HASH'es. Since most
#  Processor::Access plugins need to do the same operations on the records (for example extract the dates), this is done only once and for all as to decrease
#  the amount of processing.
# 
# Note also that this class does NOT use the EPrints API to retrieve records (EPrints::List and EPrints::Search especially) because they cannot cope well with
#  large amount of data (Access tables may contains 10's of millions of records). So this class implements its own data retrieval techniques. Note that this
#  was especially a problem on Oracle.
#

# this will call all Processor::Access::* modules
sub process_dataset
{
	my( $self, $params ) = @_;

        my $session = $self->{'session'};
	my $handler = $params->{handler};

	my @plugins = @{$handler->get_stat_plugins( 'Processor::Access' ) || []};

	my @filters = ();
	foreach my $filterid (@{$params->{'filters'} || []})
	{
		my $filter = $session->plugin( "Stats::Filter::$filterid" ) or next;
		push @filters, $filter;
	}
	
	if( $params->{'create_tables'} || (exists $params->{incremental} && !$params->{incremental} ) )
	{
		$_->create_tables( $handler ) for(@plugins,@filters);
	}

	my $current_accessid = 0;
	
        my $access_max_sql = "SELECT MAX(accessid) FROM access;";
        my $access_max_sth = $handler->{dbh}->prepare( $access_max_sql );
        $handler->{dbh}->execute( $access_max_sth, $access_max_sql );
        my @access_max = $access_max_sth->fetchrow_array;

        unless( EPrints::Utils::is_set($access_max[0]) )
        {
                $handler->log( "Access: nothing to do" );
                return;
        }

	if( !exists $params->{incremental} || $params->{incremental} )
	{
	 	$current_accessid = $handler->get_internal_value( 'current_accessid' ) || 0;
		$handler->log( "Access: accessid to process: from $current_accessid to " . $access_max[0] );
	}

	# Locking the dataset (so that no other stats process can write to the DB at the same time)
	if( !$handler->lock_dataset( 'access' ) )
	{
		$handler->log( "Dataset 'access' is currently locked by another process.", 1 );
		return;
	}

	my $global_ref_time = time;
	my $global_records_parsed = 0;
	my $global_records_kept = 0;

	# the get_records() method handles incremental SQL processing (it doesn't retrieve ALL the records in one go)
	my $records_list = $self->get_records( $handler, undef, $current_accessid );

	$records_list->map( sub {

		my( undef, undef, $record, $info ) = @_;

		if( $global_records_parsed > 0 && $global_records_parsed % 100_000 == 0 )
		{
			$handler->log( "Access: processed $global_records_parsed records so far." );
		}		
		$global_records_parsed++;

		# filter out record?
		my $discard = 0;
		foreach my $filter (@filters)
		{
			if( $filter->filter_record( $record ) )
			{
				$discard = 1;
				last;
			}
		}
		if( $records_list->is_last() )
		{
			$handler->log( "Access: incremental commit to DB" );
			foreach my $plugin ( @plugins, @filters )
			{
				$plugin->commit_data( $handler );
				$plugin->clear_cache();
			}

		}
		return if( $discard );

		$global_records_kept++;
		
		foreach my $plugin (@plugins)
		{
			$plugin->process_record( $record, (defined $record->{referent_docid}?1:0) );
		}

	}, {} );

	# Because $record_list->is_last() is not reliable on the last run (see below: is_last()), we need to call commit_data again.
	foreach my $plugin ( @plugins, @filters )
	{
		$plugin->commit_data( $handler );
		$plugin->clear_cache();
	}

	my $last_record = $records_list->last();
	if( defined $last_record && (!exists $params->{incremental} || $params->{incremental} ) )
	{
		$handler->log( "Saving the state for dataset 'access'" );
		$handler->set_internal_value( 'current_accessid', $last_record->{accessid} );
	}

	# display stats (if verbose):
	my $total_time = ( time - $global_ref_time);
	$total_time = 1 if( $total_time < 1 );
	$global_records_parsed = 1 if( $global_records_parsed < 1 );
	$handler->log( "Access: it took $total_time secs to parse $global_records_parsed records ( average = ".sprintf( "%.2f", ($global_records_parsed / $total_time))." records/sec )" );
	
	$global_records_kept = 1 if( $global_records_kept < 1 );
	$handler->log( "Access: $global_records_kept records kept out of $global_records_parsed ( ratio = ".sprintf( "%.2f", 100*($global_records_kept/$global_records_parsed))."% )" );
	
	$handler->unlock_dataset( 'access' );
	
	return;
}

# This method generates the SQL to retrieve the current Access records and returns them wrapped into a StatsRecordList object (see below)
# Note that we cannot use the EPrints Search (too slow for the potential amount of records)
# Note that we cannot return ALL the records in one go in an array(-ref) (use far too much memory)
sub get_records
{
	my( $self, $handler, $block, $from_accessid ) = @_;

	my @fields = (qw{
accessid
datestamp_year
datestamp_month
datestamp_day
datestamp_hour
datestamp_minute
datestamp_second
requester_id
requester_user_agent
referring_entity_id
service_type_id
referent_id
referent_docid
});

	my( $date_year, $date_month ) = (undef,undef);

	my $Q_fields = {};
	my @Q_fields = ();

	foreach( @fields )
	{
		$Q_fields->{$_} = $handler->{dbh}->quote_identifier( $_ );
		push @Q_fields, $Q_fields->{$_};
	}

	my $Q_table = $handler->{dbh}->quote_identifier( 'access' );

	my $sql = "SELECT ".join(",",@Q_fields)." FROM $Q_table";

	my @conditions;
	if( defined $date_year && defined $date_month )
	{
		my $Q_year = $handler->{dbh}->quote_value( $date_year );
		my $Q_month = $handler->{dbh}->quote_value( $date_month );

		push @conditions, $Q_fields->{'datestamp_year'}."=$Q_year";
		push @conditions, $Q_fields->{'datestamp_month'}."=$Q_month";
	}

	if( defined $from_accessid && "$from_accessid" ne "0" )
	{
		my $Q_access = $handler->{dbh}->quote_identifier( 'accessid' );
		my $Q_accessid = $handler->{dbh}->quote_value( $from_accessid );
		push @conditions, "$Q_access > $Q_accessid";
	}

	if( scalar(@conditions) )
	{
		$sql .= " WHERE ".join( " AND ", @conditions );
	}
	
	my $list = StatsRecordList->new( dbh => $handler->{dbh}, rawsql => $sql );
	return $list;
}

# This "internal" package is a replacement for EPrints::List for larger datasets.

package StatsRecordList;

use strict;
use Time::Local 'timegm_nocheck';

sub new
{
	my( $class, %opts ) = @_;

	my $self = bless \%opts, $class;

	$self->{idx} = 0;
	$self->{offset} = 0;
	$self->{limit} ||= 100_000;	# 100,000 records in one go maximum!
	$self->{records} = [];

	$self->init_query();

	return $self;
}

sub init_query
{
	my( $self ) = @_;

	my $sql = $self->{rawsql};

	my %o;
	$o{limit} = $self->{limit};
	$o{offset} = $self->{offset};

        my $sth = $self->{dbh}->prepare_select( $sql, %o );	#limit => $self->{limit}, offset => $self->{offset} );

        $self->{dbh}->execute( $sth, $sql );

	$self->{sth} = $sth;
}

# not reliable if the number of rows returned by the SQL statement is != to $self->{limit} (i.e. there are less rows than the LIMIT).
# note than on DBI there are no reliable ways to count the number of SELECT'ed rows rather than fetching them all and keeping a count.
sub is_last
{
	my( $self ) = @_;

	return ( $self->{idx} == $self->{limit} - 1 ) ? 1:0;
}

sub map
{
	my( $self, $fn, $info ) = @_;

	my $record;
        while ( $record = $self->next )
        {
		&{$fn}( undef, undef, $record, $info );
	}

	return;
}

sub next
{
	my( $self ) = @_;

	if( $self->{idx} >= $self->{limit} - 1 )
	{
		$self->{offset} += $self->{limit};
		$self->{idx} = 0;
		$self->init_query;
	}

	$self->{idx}++;
	my $row = $self->{sth}->fetchrow_arrayref;

	return $self->transform( $row );
}

sub transform
{
	my( $self, $row ) = @_;

	return undef unless( defined $row && scalar( @$row ) );

	my $h = {
		accessid => $row->[0],
		requester_id => $row->[7],
		requester_user_agent => $row->[8],
		referring_entity_id => $row->[9],
		service_type_id => $row->[10],
		referent_id => $row->[11],
		referent_docid => $row->[12],
	};

	my $hour = sprintf( "%02d", $row->[4] );	
	my $day = sprintf( "%02d", $row->[3]);
	my $month = sprintf( "%02d", $row->[2]);
	my $year = $row->[1];

	$h->{datestamp} = {
		hour => $hour, day => $day, month => $month, year => $year,
		cache => "$year$month$day",
		epoch => timegm_nocheck $row->[6]||0,$row->[5]||0,$row->[4],$row->[3],$row->[2]-1,$row->[1]-1900,
	};

	$self->{last_record} = $h;

	return $h;
}

sub last
{
	my( $self ) = @_;

	return $self->{last_record};
}

1;
