package EPrints::Plugin::Stats::Handler;

our @ISA = qw/ EPrints::Plugin /;

use Date::Calc;
use strict;

my $INTERNAL_TABLE = 'irstats2_internal';
my $SET_TABLE_PREFIX = 'irstats2_sets';
my $GROUPING_TABLE_PREFIX = 'irstats2_groupings';
my $RENDERED_SET_TABLE = 'irstats2_cache_set_values';
my $DEBUG_SQL = 0;

# Stats::Handler
#
# The heart of the Stats package. This handles any communication with the Database.

# Caches the database handler from the EPrints Repository/Session object.
sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new( %params );
	
	$self->{noise} ||= $DEBUG_SQL;

	if( defined $self->{session} )
	{
		$self->{dbh} = $self->{session}->get_database;
	}	
	
	return $self;
}


#
# Internal table/values
#

# Creates the "internal" table, used to store "internal" values (e.g. current_accessid)
sub create_internal_tables
{
	my( $self ) = @_;
	
	my $dbh = $self->{dbh};
	return 0 unless( defined $dbh );

	my $rc = 1;	
	if( $dbh->has_table( $INTERNAL_TABLE ) )
	{
		$rc &= $dbh->drop_table( $INTERNAL_TABLE );
	}
	
	my $session = $self->{session};

	my @fields;

	push @fields, EPrints::MetaField->new(
				repository => $session->get_repository,
				name => "objectid",
				type => "text",
				maxlength => 255,
				sql_index => 0
	);

	push @fields, EPrints::MetaField->new(
				repository => $session->get_repository,
				name => "value",
				type => "text",
				maxlength => 255,
				sql_index => 0
	);

	$rc &= $self->_create_table( $INTERNAL_TABLE, 1, @fields );

	return $rc;
}

# Retrieves the stored value '$key'. The main use of this is for locking (see above) and also to keep track of the accessid when doing
# incremental updates of the stats (so to know where to restart from).
sub get_internal_value
{
	my( $self, $key ) = @_;
	
	my $dbh = $self->{dbh};
	return undef unless( defined $dbh && $dbh->has_table( $INTERNAL_TABLE ) );

	my $Q_value = $dbh->quote_identifier( 'value' );
	my $sql = "SELECT $Q_value FROM ".$dbh->quote_identifier( $INTERNAL_TABLE )." WHERE ".$dbh->quote_identifier("objectid")."=".$dbh->quote_value($key);
	my $sth = $dbh->prepare( $sql );
        $dbh->execute( $sth, $sql );
	my @r = $sth->fetchrow_array;
	return $r[0];
}

# sets the internal value '$key'
# $replace is an optional boolean which asks to replace the current value (if any), otherwise the current value will be +=
# Default behaviour is to replace the existing value
sub set_internal_value
{
	my( $self, $key, $newval, $replace, $insert ) = @_;
	
	$replace = 1 unless( defined $replace );
	$insert ||= 0;

	my $dbh = $self->{dbh};
	return undef unless( defined $dbh );

	my $curval = $self->get_internal_value( $key );
	if( defined $curval && !$insert )
	{
		$newval += $curval unless( defined $replace );
		return $dbh->_update( $INTERNAL_TABLE, ['objectid'], [$key], ['value'], [$newval] );
	}
	else
	{
                my @v;
                push @v, [$key, $newval];
                return $dbh->insert( $INTERNAL_TABLE, ['objectid', 'value'], @v );
	}

	return 0;
}

# Removes a previously stored internal value.
sub reset_internal_value
{
	my( $self, $key ) = @_;

	return 1 unless( defined $key );

	my $Q_tablename = $self->{dbh}->quote_identifier( $INTERNAL_TABLE );
	my $Q_key = $self->{dbh}->quote_identifier( "objectid" );
	my $Q_value = $self->{dbh}->quote_value( $key );

	return $self->{dbh}->do( "DELETE FROM $Q_tablename WHERE $Q_key = $Q_value" );
}



#
# Data management
#

# Create the data tables. Note how datestamp are represented as integer.
sub create_data_table
{
	my( $self, $datatype ) = @_;
	
	my $session = $self->{session};

	my $tablename = "irstats2_$datatype";

	$self->{dbh}->drop_table( $tablename ) if( $self->{dbh}->has_table( $tablename ) );
	
	$self->log( "Creating table '$tablename'" );

	my @fields;

	push @fields, EPrints::MetaField->new(
				repository => $session->get_repository,
				name => "uid",
				type => "int",
				sql_index => 0,
	);

	push @fields, EPrints::MetaField->new(
				repository => $session->get_repository,
				name => "eprintid",
				type => "int",
				sql_index => 1
	);

	# represented as follow: YYYYMMDD eg 20110201
	push @fields, EPrints::MetaField->new(
				repository => $session->get_repository,
				name => "datestamp",
				type => "int",
				sql_index => 1
	);
	
	push @fields, EPrints::MetaField->new(
				repository => $session->get_repository,
				name => "value",
				type => "text",
				maxlength => 255,
				sql_index => 1
	);
	
	push @fields, EPrints::MetaField->new(
				repository => $session->get_repository,
				name => "count",
				type => "int",
				sql_index => 0
	);

	return $self->_create_table( $tablename, 1, @fields );
}

# valid fields and which table they're associated with (data = the selected data table, set = the set table)
my $VALID_FIELDS = {

	'eprintid' => 'data',
	'datestamp' => 'data',
	'count' => 'data',
	'value' => 'data',

	'set_eprintid' => 'set',
	'set_value' => 'set',
	'grouping' => 'set',

};

# Extracts stats data from the Database. Handles building up the SQL statement given all possible constraints (ORDER BY, what to SELECT, LIMIT etc.).
# This is used for "simple" cases where no Sets or Groupings are involved. Therefore there are no complex table JOIN here.
# Note that this can still call extract_set_data if the top eprints in a set are requested.
# This returns a HASH of (1) the selected fields (aka rows) and (2) the count (aka the number of downloads,deposits...)
sub extract_eprint_data
{
	my( $self, $context, $conf ) = @_;

	# Does the table exist?
	my $datatype = $context->{datatype};
	my $tablename = "irstats2_$datatype";
	return undef unless( $self->{dbh}->has_table( $tablename ) );

	my $Q_tablename = $self->{dbh}->quote_identifier( $tablename );

	# Dates are normalised by Stats::Context
	my $dates = $context->dates;
	my( $from, $to ) = ( $dates->{from}, $dates->{to} );

	# Datafilters provide extra filtering of rows.
	my $datafilter = $context->{datafilter};
		
	my $local_context = $context->clone();

	# the former option <type => "grouped">
	if( EPrints::Utils::is_set( $local_context->{grouping} ) &&  $local_context->{grouping} ne 'value' && $local_context->{grouping} ne 'eprint' )
	{
		return $self->extract_set_data( $local_context, $conf );
	}

	# Which fields (aka columns) to SELECT
	my $fields = $conf->{fields} || [];

	# Note: on Oracle, all selected columns (not including functions such as SUM) MUST be in the GROUP BY clause
	my @valid_fields;
	my @Q_valid_fields;		# DB quoted

	# Default settings
	my $order_by = undef;
	my $order = $conf->{order_by} || 'count';
	my $order_desc = ( defined $conf->{order_desc} && !$conf->{order_desc} ) ? 'ASC' : 'DESC';

	foreach my $field ( @$fields )
	{
		unless( $VALID_FIELDS->{$field} )
		{
			$self->log( "Warning: unknown field '$field' in Stats::Handler::extract_eprint_data", 1 );
			next;
		}
	
		# datafilter is to do with the 'value' column i.e. WHERE value = $datafilter	
		if( EPrints::Utils::is_set( $datafilter ) && $field eq 'value' )
		{
			# no need to select the datafilter value!! if we select something WHERE X=Y, there's no point to SELECT X (since we know it's always equal to Y)
			next;
		}
	
		push @valid_fields, $field;
		my $Q_field = $self->{dbh}->quote_identifier( "$field" );
		push @Q_valid_fields, $Q_field; 
		
		if( $order eq $field )
		{
			$order_by = "$Q_tablename.$Q_field";
		}
	}

	# SUM( count ) is always selected after the other fields:
	my $Q_count = $self->{dbh}->quote_identifier( "count" );
	push @Q_valid_fields, "SUM( $Q_count )";

	# SELECT [field1, field2, ...], SUM( count ) FROM tablename
	my $sql = "SELECT ".join(", ", @Q_valid_fields )." FROM $Q_tablename";;

	pop @Q_valid_fields;	# removes the SUM( count ), we'll re-use that array for the GROUP BY below and SUM( count ) doesn't need to be there

	# Building up the SQL conditions (WHERE...)
	my @conditions;	

	# time/datestamp conditions
	if( defined $from && defined $to )
	{
		my $Q_datestamp = $self->{dbh}->quote_identifier( 'datestamp' );
		my $Q_from = $self->{dbh}->quote_int( $from );

		if( $from < $to )
		{
			my $Q_to = $self->{dbh}->quote_int( $to );
			push @conditions, "$Q_datestamp >= $Q_from AND $Q_datestamp <= $Q_to";
		}
		elsif( "$from" eq "$to" )
		{
			push @conditions, "$Q_datestamp = $Q_from";
		}
	}

	# eprintid defined ?
	my $eprintid = $local_context->{set_value};
	if( EPrints::Utils::is_set( $eprintid ) )
	{
		# 'eprintid' is an integer so quote it as such
		push @conditions, $self->{dbh}->quote_identifier( 'eprintid' )." = ".$self->{dbh}->quote_int( $eprintid );
	}

	# extra filtering ? 
	if( EPrints::Utils::is_set( $datafilter ) )
	{
		push @conditions, $self->{dbh}->quote_identifier( 'value' )." = ".$self->{dbh}->quote_value( $datafilter );
	}

	my $show_archive_only = $self->{session}->config( 'irstats2', 'show_archive_only' ) || 0;
	if ($show_archive_only)
	{
		push @conditions, "eprintid in (select eprintid from eprint where eprint_status='archive')";
	}


	if( scalar( @conditions ) )
	{
		$sql .= " WHERE ".join( " AND ", @conditions );
	}

	if( scalar( @Q_valid_fields ) )
	{
		$sql .= " GROUP BY ".join( ", ", @Q_valid_fields );
	}

	# ORDER BY ? 
	if( EPrints::Utils::is_set( $order_by ) )
	{
		$sql .= " ORDER BY $order_by $order_desc";
	}
	else
	{
		$sql .= " ORDER BY SUM($Q_tablename.$Q_count) $order_desc";
	}

	# LIMIT, OFFSET 
	my $sth = $self->prepare_select( $sql, limit => $conf->{limit}, offset => $conf->{offset} );

	$self->log( "SQL IS '$sql'" ) if( $DEBUG_SQL );

	$self->{dbh}->execute( $sth, $sql );

	my @results;
	while( my @row = $sth->fetchrow_array )
	{
		# last row is always the SUM( count ) known as 'count' in the reply
		# 0 ... n-2 first rows are to do with the @fields
		my $c = 0;
		my $result = {};
		foreach( @valid_fields )
		{
			$result->{$_} = $row[$c++];
		}
		$result->{count} = $row[$c];
		push @results, $result;
	}

	return \@results;
}


# Extracts stats data from the Database, used for complex cases where Sets and/or Groupings are involved
# This needs to build up JOIN's between the appropriate Set/Grouping table and Data table.
#
# To select the top 10 "downloaded" Authors given a Division ('uos-fp'), the generated SQL looks like this:
#
#SELECT `irstats2_groupings_divisions`.`grouping_value`, SUM( `irstats2_eprint_downloads`.`count` ) FROM `irstats2_eprint_downloads` INNER JOIN `irstats2_groupings_divisions` ON `irstats2_eprint_downloads`.`eprintid`= `irstats2_groupings_divisions`.`set_eprintid` WHERE `irstats2_eprint_downloads`.`value` = 'downloads' AND `irstats2_groupings_divisions`.`grouping_name` = 'creators' AND `irstats2_groupings_divisions`.`set_value` = 'uos-fp' GROUP BY `irstats2_groupings_divisions`.`grouping_value` ORDER BY SUM(`irstats2_eprint_downloads`.`count`) DESC LIMIT 10;
sub extract_set_data
{
	my( $self, $context, $conf ) = @_;
	
	# more verbose error?
	return undef unless( defined $context->{set_name} );

	# table exists?
	my $datatype = $context->{datatype};
	my $data_tablename = "irstats2_$datatype";
	return undef unless( $self->{dbh}->has_table( $data_tablename ) );

	my $set_tablename = $SET_TABLE_PREFIX."_".$context->{set_name};
	return undef unless( $self->{dbh}->has_table( $set_tablename ) ); 

	my $Q_data_tablename = $self->{dbh}->quote_identifier( $data_tablename );
	my $Q_set_tablename = $self->{dbh}->quote_identifier( $set_tablename );

	my $type = $conf->{type} || '';
	my $datafilter = $context->{datafilter};

	# Scenario where no Groupings are used:
	if( !EPrints::Utils::is_set( $context->{grouping} ) || $context->{grouping} eq 'eprint' || $context->{grouping} eq 'value' )
	{
		# SUM( count ) requested... any other fields to select ? 
	
		my $fields = $conf->{fields} || [];

		my $select = "";

		# Note: on Oracle, all columns selected (not including functions such as SUM) MUST be in the GROUP BY clause
		my $group_by = "";

		my $order_by = undef;
		my $order = $conf->{order_by} || 'count';
		my $order_desc = ( defined $conf->{order_desc} && !$conf->{order_desc} ) ? 'ASC' : 'DESC';

		my @valid_fields;
		foreach my $field ( @$fields )
		{
			unless( $VALID_FIELDS->{$field} )
			{
				$self->log( "Warning: unknown field '$field' in Stats::Handler::extract_set_data", 1 );
				next;
			}

			# datafilter is to do with the 'value' column i.e. WHERE value = $datafilter	
			if( EPrints::Utils::is_set( $datafilter ) && $field eq 'value' )
			{
				# no need to select the datafilter value!! if we select something WHERE X=Y, there's no point to SELECT X (since we know it's always equal to Y)
				next;
			}
			
			my $Q_src_table = ($VALID_FIELDS->{$field} eq 'data') ? $Q_data_tablename : $Q_set_tablename; 
		
			push @valid_fields, $field;

			my $Q_field = $self->{dbh}->quote_identifier( "$field" );
	
			$select .= "$Q_src_table.$Q_field,";							#SUM(count) will always follow, so we can leave the trailing comma
			$group_by = length $group_by ? ", $Q_src_table.$Q_field" : "$Q_src_table.$Q_field";	# not true here

			if( $order eq $field )
			{
				$order_by = "$Q_src_table.$Q_field";
			}
		}

		my $Q_count = $self->{dbh}->quote_identifier( "count" );

		$select .= "SUM( $Q_data_tablename.$Q_count )";

		my $Q_eprintid = $self->{dbh}->quote_identifier( 'eprintid' );
		my $Q_set_eprintid = $self->{dbh}->quote_identifier( 'set_eprintid' );

		my $sql = "SELECT $select FROM $Q_data_tablename INNER JOIN $Q_set_tablename ON $Q_data_tablename.$Q_eprintid = $Q_set_tablename.$Q_set_eprintid";

		# then time to build up the conditions (WHERE ...):
		my @conditions;	

		my $from = $context->{from};
		my $to = $context->{to};

		# time/datestamp conditions
		if( defined $from && defined $to )
		{
			my $Q_datestamp = $self->{dbh}->quote_identifier( 'datestamp' );
			my $Q_from = $self->{dbh}->quote_int( $from );

			if( $from < $to )
			{
				my $Q_to = $self->{dbh}->quote_int( $to );
				push @conditions, "$Q_datestamp >= $Q_from AND $Q_datestamp <= $Q_to";
			}
			elsif( "$from" eq "$to" )
			{
				push @conditions, "$Q_datestamp = $Q_from";
			}
		}

		# set_value defined?
		if( EPrints::Utils::is_set( $context->{set_value} ) )
		{
			# 'eprintid' = int_value
			push @conditions, $Q_set_tablename.".".$self->{dbh}->quote_identifier( 'set_value' )." = ".$self->{dbh}->quote_value( $context->{set_value} );
		}

		# extra filtering ? 
		if( EPrints::Utils::is_set( $datafilter ) )
		{
			push @conditions, $Q_data_tablename.".".$self->{dbh}->quote_identifier( 'value' )." = ".$self->{dbh}->quote_value( $datafilter );
		}

		if( scalar( @conditions ) )
		{
			$sql .= " WHERE ".join( " AND ", @conditions );
		}
	
		if( length( $group_by ) )
		{
			$sql .= " GROUP BY $group_by";
		}

		# ORDER BY
		if( EPrints::Utils::is_set( $order_by ) )
		{
			$sql .= " ORDER BY $order_by $order_desc";
		}
		else
		{
			$sql .= " ORDER BY SUM($Q_data_tablename.$Q_count) $order_desc";
		}

		# LIMIT, OFFSET 
		my $sth = $self->prepare_select( $sql, limit => $conf->{limit}, offset => $conf->{offset} );
		
		$self->log( "SQL IS '$sql'" ) if( $DEBUG_SQL );

		$self->{dbh}->execute( $sth, $sql );

		my @results;


		while( my @row = $sth->fetchrow_array )
		{
			# last row is always the SUM( count ) known as 'count' in the reply
			# 0 ... n-2 first rows are to do with the @fields
			my $c = 0;
			my $result = {};
			foreach( @valid_fields )
			{
				$result->{$_} = $row[$c++];
			}
			$result->{count} = $row[$c];
			push @results, $result;
		}

		return \@results;
	}

	# Groupings are used below - for example: Top n {something, eg authors} over a set (eg a division)

	my $grouping = $context->{grouping};
	if( $grouping eq $context->{set_name} )
	{
		# in other words, you cannot select the Top Authors for an Author, or the Top Subjects for a Subject.
		$self->log( "Logic error: you cannot have the same set_name and grouping values!", 1 );
		return undef;
	}

	my $grouping_tablename = $GROUPING_TABLE_PREFIX."_".$context->{set_name};
	return undef unless( $self->{dbh}->has_table( $grouping_tablename ) );

	my $Q_grouping_tablename = $self->{dbh}->quote_identifier( $grouping_tablename );
	my $Q_grouping_value = $self->{dbh}->quote_identifier( 'grouping_value' );
	my $Q_count = $self->{dbh}->quote_identifier( "count" );
	my $Q_eprintid = $self->{dbh}->quote_identifier( 'eprintid' );
	my $Q_set_eprintid = $self->{dbh}->quote_identifier( 'set_eprintid' );

	my $order_desc = ( defined $conf->{order_desc} && !$conf->{order_desc} ) ? 'ASC' : 'DESC';

	my $sql = "SELECT $Q_grouping_tablename.$Q_grouping_value, SUM( $Q_data_tablename.$Q_count ) FROM $Q_data_tablename INNER JOIN $Q_grouping_tablename ON $Q_data_tablename.$Q_eprintid = $Q_grouping_tablename.$Q_set_eprintid";

	my @conditions;	

	# time/datestamp conditions
	if( defined $context->{from} && defined $context->{to} && $context->{from} < $context->{to} )
	{
		my $Q_datestamp = $self->{dbh}->quote_identifier( 'datestamp' );
		my $Q_from = $self->{dbh}->quote_int( $context->{from} );
		my $Q_to = $self->{dbh}->quote_int( $context->{to} );
		push @conditions, "$Q_data_tablename.$Q_datestamp >= $Q_from AND $Q_data_tablename.$Q_datestamp <= $Q_to";
	}

	# set_value defined? (should be)
	if( EPrints::Utils::is_set( $context->{set_value} ) )
	{
		push @conditions, $Q_grouping_tablename.".".$self->{dbh}->quote_identifier( 'set_value' )." = ".$self->{dbh}->quote_value( $context->{set_value} );
	}

	# extra filtering ? 
	if( EPrints::Utils::is_set( $datafilter ) )
	{
		push @conditions, $Q_data_tablename.".".$self->{dbh}->quote_identifier( 'value' )." = ".$self->{dbh}->quote_value( $datafilter );
	}

	my $Q_grouping_name = $self->{dbh}->quote_identifier( 'grouping_name' );
	push @conditions, $Q_grouping_tablename.".".$Q_grouping_name." = ".$self->{dbh}->quote_value( $grouping );

	if( scalar( @conditions ) )
	{
		$sql .= " WHERE ".join( " AND ", @conditions );
	}

	$sql .= " GROUP BY $Q_grouping_tablename.$Q_grouping_value ORDER BY SUM( $Q_data_tablename.$Q_count ) $order_desc";


	my $sth = $self->prepare_select( $sql, limit => $conf->{limit}, offset => $conf->{offset} );
	
	$self->log( "SQL IS '$sql'" ) if( $DEBUG_SQL );
	
	$self->{dbh}->execute( $sth, $sql );

	my @results;

	# TODO: remove hack!
	# sf2 - hack below: both value and set_value are assigned to $row[0] to allow proper rendering of the object that is returned
	while( my @row = $sth->fetchrow_array )
	{
		my $result = { value => $row[0], count => $row[1], set_value => $row[0] };
		push @results, $result;
	}

	return \@results;
}

# Inserts a group of records into the database. This inserts multiple rows
# using one INSERT statement for performance. In practice, this needs to be
# batched so that a single INSERT statement does not exceed database limits.

sub save_data_values_aux
{
	my( $self, $tablename, $columns, $rows ) = @_;

	my $sql = "INSERT INTO ".$self->{dbh}->quote_identifier( $tablename );
	$sql .= " (".join(",", map { $self->{dbh}->quote_identifier($_) } @$columns).")";
	$sql .= " VALUES ";

	my $row_template = "(".join(",", map { '?' } @$columns)."),";

	foreach my $row (@$rows)
	{
		$sql .= $row_template;
	}

	$sql =~ s/,$//;

	my $sth = $self->{dbh}->prepare($sql);

	my $i = 1;

	$self->{dbh}->begin;

	foreach my $row (@$rows)
	{
		my( $counter, $epid, $date, $value, $count ) = @$row;

		$sth->bind_param( $i++, $counter );
		$sth->bind_param( $i++, $epid );
		$sth->bind_param( $i++, $date );
		$sth->bind_param( $i++, $value );
		$sth->bind_param( $i++, $count );
	}

	my $rc = $sth->execute();

	$self->{dbh}->commit;

	return $rc;
}

# Saves processed data to the correct table
# called by Processor::{class}::{type}->commit_data()
sub save_data_values
{
	my( $self, $datatype, $data ) = @_;

	my $batch_limit = 1000;

	my $tablename = "irstats2_$datatype";
	$data ||= {};

	my $counter = $self->get_next_counter( $tablename ) || 0;

	my $columns = [ 'uid', 'eprintid', 'datestamp', 'value', 'count' ];

	my $rc = 1;

	# Batch values into groups.

	my @rows;

	foreach my $date ( keys %{$data} )
	{
		foreach my $epid ( keys %{$data->{$date}} )
		{
			foreach my $value ( keys %{$data->{$date}->{$epid}} )
			{
				push @rows, [ $counter++, $epid, $date, $value, $data->{$date}->{$epid}->{$value} ];

				# If we have a full batch of rows to save, then save them.

				if( scalar( @rows ) > $batch_limit )
				{
					$rc &&= $self->save_data_values_aux( $tablename, $columns, \@rows );
					@rows = ();
				}
			}
		}
	}

	# If there is a partial batch left over at the end then save it.

	if( scalar( @rows ) > 0 )
	{
		$rc &&= $self->save_data_values_aux( $tablename, $columns, \@rows );
	}

	return $rc;
}


#
# Sets tables/values
#

# Selects the distinct set_value and rendered_set_value given a set_name
# optional $like is the SQL LIKE value
# This is used by /cgi/set_finder and View::ReportHeader
sub get_all_rendered_set_values
{
	my( $self, $set_name, $like ) = @_;

	return [] unless( defined $set_name && $self->{dbh}->has_table( $RENDERED_SET_TABLE ) );

	my $Q_table = $self->{dbh}->quote_identifier( "$RENDERED_SET_TABLE" );
	my $Q_set_value = $self->{dbh}->quote_identifier( 'set_value' );
	my $Q_rendered_set_value = $self->{dbh}->quote_identifier( 'rendered_set_value' );

	my $Q_field_set_name = $self->{dbh}->quote_identifier( 'set_name' );
	my $Q_set_name = $self->{dbh}->quote_value( $set_name );

	my $sql = "SELECT $Q_set_value, $Q_rendered_set_value FROM $Q_table WHERE $Q_field_set_name = $Q_set_name";

	if( EPrints::Utils::is_set( $like ) )
	{
		$sql .= " AND $Q_rendered_set_value".$self->{dbh}->sql_LIKE.$self->{dbh}->quote_value( '%'.EPrints::Database::prep_like_value( $like ).'%' );
	}

	$sql .= " ORDER BY $Q_rendered_set_value";

	if( $self->{dbh}->get_server_version =~ /MySQL/ )
	{
		# this allows proper order'ing of values
		$sql .= " COLLATE utf8_unicode_ci";
	}
	my $sth = $self->prepare_select( $sql );
			
	$self->log( "SQL IS '$sql'" ) if( $DEBUG_SQL );

	$self->{dbh}->execute( $sth, $sql );

	my @values;
	while( my @r = $sth->fetchrow_array )
	{
		push @values, { set_value => $r[0], rendered_set_value => $r[1] };
	}

	return \@values;
}

# Selects a rendered set value from the DB - Used by Sets
sub get_rendered_set_value
{
	my( $self, $set_name, $set_value ) = @_;
	
	return [] unless( defined $set_name && defined $set_value && $self->{dbh}->has_table( $RENDERED_SET_TABLE ) );

	my $Q_table = $self->{dbh}->quote_identifier( "$RENDERED_SET_TABLE" );
	my $Q_rendered_set_value = $self->{dbh}->quote_identifier( 'rendered_set_value' );

	my $Q_field_set_name = $self->{dbh}->quote_identifier( 'set_name' );
	my $Q_set_name = $self->{dbh}->quote_value( $set_name );

	my $Q_field_set_value = $self->{dbh}->quote_identifier( 'set_value' );
	my $Q_set_value = $self->{dbh}->quote_value( $set_value );

	my $sql = "SELECT $Q_rendered_set_value FROM $Q_table WHERE $Q_field_set_name = $Q_set_name AND $Q_field_set_value = $Q_set_value";

	my $sth = $self->prepare_select( $sql );
			
	$self->log( "SQL IS '$sql'" ) if( $DEBUG_SQL );

	$self->{dbh}->execute( $sth, $sql );

	my @r = $sth->fetchrow_array;

	return $r[0];
}

# Inserts a new Set value
sub insert_set_value
{
	my( $self, $set_name, $set_value, $eprintid ) = @_;

	return $self->{dbh}->insert( $SET_TABLE_PREFIX."_$set_name", [ 'set_value', 'set_eprintid' ], ([$set_value, $eprintid ]) );
}

# Inserts a new Grouping value (similar to Sets)
sub insert_grouping_value
{
	my( $self, $set_name, $set_value, $eprintid, $grouping_name, $grouping_value ) = @_;

	return $self->{dbh}->insert( $GROUPING_TABLE_PREFIX."_$set_name", [ 'set_value', 'set_eprintid', 'grouping_name', 'grouping_value' ], ([$set_value, $eprintid, $grouping_name, $grouping_value ]) );
}

# Inserts a rendered set value (this is a cache)
sub insert_rendered_set_value
{
	my( $self, $set_name, $set_value, $rendered_value ) = @_;

	return $self->{dbh}->insert( $RENDERED_SET_TABLE, [ 'set_name', 'set_value', 'rendered_set_value' ], ([ $set_name, $set_value, $rendered_value ]) );
}

# Will remove any set/grouping tables
# Note this is done via a SQL LIKE - this is to ensure that all Sets/Groupings tables are removed, even the ones which are not defined in the local conf.
sub delete_sets_tables
{
        my( $self ) = @_;

        foreach my $table_prefix ( $SET_TABLE_PREFIX, $GROUPING_TABLE_PREFIX )
        {
                # sf2 / should use $self->{dbh}->sql_LIKE (but doesn't work on 3.2)
                my $sql = "SHOW TABLES LIKE ".$self->{dbh}->quote_value( $table_prefix."_%" );

                my $sth = $self->prepare_select( $sql );

                $self->{dbh}->execute( $sth, $sql );

                my @values;
                while( my @r = $sth->fetchrow_array )
                {
			next if( $r[0] !~ /^$table_prefix/ );	# may seem redundant but I'll sleep better with this extra test
                        $self->{dbh}->do( "DROP TABLE ".$self->{dbh}->quote_identifier( $r[0] ) );
                        $self->log( "Removed table '$r[0]'" );
                }
        }

	if( $self->{dbh}->has_table( $RENDERED_SET_TABLE ) )
	{
	        $self->{dbh}->do( "DROP TABLE ".$self->{dbh}->quote_identifier( $RENDERED_SET_TABLE ) );
        	$self->log( "Removed table '$RENDERED_SET_TABLE'" );
	}
}

# Creates the Sets/Groupings/Cache (rendered values) tables
sub create_sets_tables
{
	my( $self, $sets ) = @_;
	
	my $session = $self->{session};
	
	my $sets_plugin = $self->sets;

	$self->delete_sets_tables( $sets );

	my $rc = 1;
	my @fields;
	foreach my $set_name (@$sets)
	{
		@fields = ();

		# set table
		push @fields, EPrints::MetaField->new(
					repository => $session->get_repository,
					name => "set_value",
					type => "text",
					maxlength => 255,
					sql_index => 1
		);
		
		push @fields, EPrints::MetaField->new(
					repository => $session->get_repository,
					name => "set_eprintid",
					type => "int",
					sql_index => 1
		);
		
		$rc &= $self->_create_table( $SET_TABLE_PREFIX."_$set_name", 2, @fields );

		@fields = ();
		
		# groupings table
		
		push @fields, EPrints::MetaField->new(
					repository => $session->get_repository,
					name => "set_value",
					type => "text",
					maxlength => 255,
					sql_index => 1
		);
		
		push @fields, EPrints::MetaField->new(
					repository => $session->get_repository,
					name => "set_eprintid",
					type => "int",
					sql_index => 1
		);
		
		push @fields, EPrints::MetaField->new(
					repository => $session->get_repository,
					name => "grouping_name",
					type => "text",
					maxlength => 25,
					sql_index => 1
		);
		
		push @fields, EPrints::MetaField->new(
					repository => $session->get_repository,
					name => "grouping_value",
					type => "text",
					maxlength => 255,
					sql_index => 1
		);

		$rc &= $self->_create_table( $GROUPING_TABLE_PREFIX."_$set_name", 0, @fields );
	}

	# $RENDERED_SET_TABLE
	@fields = ();

	push @fields, EPrints::MetaField->new(
			repository => $session->get_repository,
			name => "set_name",
			type => "text",
			maxlength => 255,
			sql_index => 0
	);
	
	push @fields, EPrints::MetaField->new(
			repository => $session->get_repository,
			name => "set_value",
			type => "text",
			maxlength => 255,
			sql_index => 0
	);

	push @fields, EPrints::MetaField->new(
			repository => $session->get_repository,
			name => "rendered_set_value",
			type => "longtext",
			sql_index => 0
	);
		
	$rc &= $self->_create_table( $RENDERED_SET_TABLE, 0, @fields );

	return $rc;
}

sub valid_set_value
{
        my( $self, $set_name, $set_value ) = @_;

        return 0 unless( defined $set_name && defined $set_value );

        # TODO can do better than that?
        if( $set_name eq 'eprint' )
        {
            my $eprint_ds = $self->{session}->config( 'irstats2', 'eprint_dataset' ) || "archive";
            return (defined $self->{session}->dataset( $eprint_ds )->dataobj( $set_value ) ) ? 1 : 0;
        }

        my $set_tablename = $SET_TABLE_PREFIX."_".$set_name;
        return 0 unless( $self->{dbh}->has_table( $set_tablename ) );

        my $Q_set_table = $self->{dbh}->quote_identifier( $set_tablename );
        my $Q_set_value_field = $self->{dbh}->quote_identifier( 'set_value' );
        my $Q_set_value = $self->{dbh}->quote_value( $set_value );

        my $sql = "SELECT 1 FROM $Q_set_table WHERE $Q_set_value_field = $Q_set_value";
        my $sth = $self->prepare_select( $sql, limit => 1 );

        $self->log( "SQL IS '$sql'" ) if( $DEBUG_SQL );

        $self->{dbh}->execute( $sth, $sql );

        my @r = $sth->fetchrow_array;

        return ( @r && scalar( @r ) > 0 ) ? 1 : 0;
}


#
# Plugins
#


# Instanciates and caches all EPrints::Plugin::Stats::* plugins
sub get_stat_plugins
{
	my( $self, $classname ) = @_;

	return () unless( defined $classname );

	my @plugins;
        foreach my $id ( $self->{session}->plugin_list( type => "Stats" ) )
	{
		next unless( $id =~ /^Stats::$classname/ );
		my $p = $self->{session}->plugin( "$id", handler => $self );
		push @plugins, $p if( !$p->{disable} );
	}

	# return ($a->{priority} || 1000) <=> ($b->{priority} || 1000) ?
	my @sortedplugins = sort { 
		my $cmpa = $a->{priority};
		$cmpa = 1000 unless(defined $cmpa);
		my $cmpb = $b->{priority};
		$cmpb = 1000 unless(defined $cmpb); 
		return $cmpa <=> $cmpb; 
	} @plugins;

	return \@sortedplugins;
}


# Builds a map (a hash) between a list of stats datasets (eg 'eprint_downloads') and the Plugin that
# provides/handles that stat dataset (Processor/Access/Downloads.pm)
# Used by Handler::get_processor
sub _load_processors
{
	my( $self ) = @_;

	return if( $self->{processors_map_loaded} );

	my $processors = $self->get_stat_plugins( "Processor" );
	my $filters = $self->get_stat_plugins( "Filter" );

	foreach my $proc ( @$processors, @$filters )
	{
		next unless( defined $proc && !$proc->{disable} && defined $proc->{provides} );
		foreach my $p ( @{ $proc->{provides} || [] } )
		{
			$self->{processors_map}->{$p} = $proc->get_id;
			$self->{processors_map_loaded} = 1;
		}
	}

	return;
}

sub get_processor
{
	my( $self, $datatype ) = @_;
	$self->_load_processors;
	my $pluginid =  $self->{processors_map}->{"$datatype"};
	unless( defined $pluginid )
	{
		$self->log( "Stats::Handler: requested processor '$datatype' does not exist.", 1 );
		return;
	}
	return $self->{session}->plugin( $pluginid );
}

# Caches the Sets plugin
sub sets
{
	my( $self ) = @_;

	unless( defined $self->{sets_handler} )
	{
		$self->{sets_handler} = $self->{session}->plugin( 'Stats::Sets', handler => $self );
	}
	
	return $self->{sets_handler};
}


#
# Utility methods
#

# Creates a new Context object.
sub context
{
	my( $self, $context ) = @_;
	return EPrints::Plugin::Stats::Context->new( %$context, handler => $self, session => $self->{session} );
}

# Creates a new Data object.
sub data
{
	my( $self, $context ) = @_;
	return EPrints::Plugin::Stats::Data->new( handler => $self, context => $context, session => $self->{session} );
}


# Returns the number of rows in a given dataset
# $dataset is the EPrints dataset object (EPrints::DataSet)
sub get_dataset_size
{
	my( $self, $dataset ) = @_;

	my $key_field = $dataset->key_field();

	return undef unless( defined $key_field );

	$key_field = $key_field->get_name;

	my $Q_table = $self->{dbh}->quote_identifier( $dataset->base_id() );
	my $Q_key_field = $self->{dbh}->quote_identifier( $dataset->base_id(), $key_field );

	my $sql = "SELECT COUNT( $Q_key_field ) FROM $Q_table";
        my $sth = $self->{dbh}->prepare( $sql );
        $self->{dbh}->execute( $sth, $sql );
        my @r = $sth->fetchrow_array;
        return undef unless( scalar( @r ) );

	return $r[0];
}

# Returns the date boundaries of a given dataset (oldest/newest record) by using the 'datestamp' field
# $dataset is the EPrints dataset object (EPrints::DataSet)
sub get_dataset_boundaries
{
	my( $self, $datasetid ) = @_;
	
	my $dataset = $self->{session}->dataset( $datasetid );
	return undef unless( defined $dataset && $dataset->has_field( 'datestamp' ) );

	my $key_field = $dataset->key_field();
	return undef unless( defined $key_field );

	$key_field = $key_field->get_name;

	my $Q_table = $self->{dbh}->quote_identifier( $dataset->base_id() );
	my $Q_key_field = $self->{dbh}->quote_identifier( $dataset->base_id(), $key_field );

	my $Q_datestamp_year = $self->{dbh}->quote_identifier( 'datestamp_year' );
	my $Q_datestamp_month = $self->{dbh}->quote_identifier( 'datestamp_month' );
	my $Q_datestamp_day = $self->{dbh}->quote_identifier( 'datestamp_day' );

	my( $sql, $sth, $min_date, $max_date, $year, $month, $day );

	my @dates_fields = ( $Q_datestamp_year, $Q_datestamp_month, $Q_datestamp_day );
	my @dates_values = ();

	foreach my $op ( "MIN", "MAX" )
	{
		# this will iteratively select: min(year), min(month) and min(day) (then max(year), ...).
		for( my $i = 0; $i < 3; $i++ )
		{
			my @conditions;
			my $field = $dates_fields[$i];
		
			for( my $j = 0; $j < $i; $j++ )
			{
				push @conditions, "$dates_fields[$j] = ".$self->{dbh}->quote_value( $dates_values[$j] );
			}

			# first iteration: SELECT MIN( ... ), 2nd: SELECT MAX( ... )
			$sql = "SELECT $op( $field ) FROM $Q_table";

			if( scalar(@conditions) )
			{
				$sql .= " WHERE ".join( " AND ", @conditions );
			}

			$sth = $self->{dbh}->prepare( $sql );
			$self->{dbh}->execute( $sth, $sql );
			my @r = $sth->fetchrow_array;
			$dates_values[$i] = $r[0] || '0';
		}

		if( $op eq 'MIN' )
		{
			$min_date = sprintf("%04d",$dates_values[0]).sprintf("%02d", $dates_values[1]).sprintf("%02d", $dates_values[2]);
		}
		else
		{
			$max_date = sprintf("%04d",$dates_values[0]).sprintf("%02d", $dates_values[1]).sprintf("%02d", $dates_values[2]);
		}
	}

	return( $min_date, $max_date );
}

# Locks a (stats) table for writting. This prevents having two 'process_stats' processes running at the same time.
sub lock_dataset
{
	my( $self, $dataset_id ) = @_;

	my $lock_id = $dataset_id.".lock";

	return 0 if( defined $self->get_internal_value( $lock_id ) );
	
	my $rc = 0;
	eval {
		$rc = $self->set_internal_value( $lock_id, '1', 0, 1 );
	};

	return 0 if( $@ || !$rc );

	return 1;
}

# Unlocks a (stats) table for writing.
sub unlock_dataset
{
	my( $self, $dataset_id ) = @_;
	
	my $lock_id = $dataset_id.".lock";

	return 1 unless( defined $self->get_internal_value( $lock_id ) );

	my $rc = 0;
	eval {
		$rc = $self->reset_internal_value( $lock_id );
	};

	return 0 if( $@ || !$rc );

	return 1;
}

# Data tables used counters as primary key as no other rows combination can ensure uniqueness.
sub get_next_counter
{
	my( $self, $tablename ) = @_;

	return 0 unless( defined $tablename );

	my $Q_uid = $self->{dbh}->quote_identifier( 'uid' );
	my $Q_tablename = $self->{dbh}->quote_identifier( $tablename );

	my $sql = "SELECT MAX($Q_uid) FROM $Q_tablename;";
	my $sth = $self->prepare_select( $sql );
	$self->{dbh}->execute( $sth, $sql );

	my @r = $sth->fetchrow_array;

	return ( @r && scalar( @r ) > 0 && defined $r[0] ) ? ($r[0]+1) : 0;
}

# API changed in 3.3.9 - this takes care of either version
sub _create_table
{
	my( $self, $tablename, $setkey, @fields ) = @_;

	my $version = EPrints->VERSION();

	if( !EPrints::Utils::is_set( $version ) )
	{
		# EPrints->VERSION() was added in the 3.3 branch so if VERSION() doesn't exist, assume an older version of EPrints
		$version = v3.2.0;
	}

	if( $version gt v3.3.8 )
	{
		return $self->{dbh}->create_table( $tablename, $setkey, @fields );
	}

	# pre-3.3.9 API
	return $self->{dbh}->create_table( $tablename, undef, $setkey, @fields );
}

# See https://github.com/eprints/irstats2/issues/1 to see why it's not re-using the EPrints' prepare_select function
sub prepare_select
{
        my( $self, $sql, %options ) = @_;

        if( defined $options{limit} && length($options{limit}) )
        {
                if( defined $options{offset} && length($options{offset}) )
                {
                        $sql .= sprintf(" LIMIT %d OFFSET %d",
                                $options{limit},
                                $options{offset} );
                }
                else
                {
                        $sql .= sprintf(" LIMIT %d", $options{limit} );
                }
        }

        return $self->{dbh}->prepare( $sql );
}


# Called by bin/ script when processing stats
sub process_dataset
{
	my( $self, $dataset_id, $conf ) = @_;

	my $session = $self->{session};

	my $ds = $session->dataset( "$dataset_id" );

	unless( defined $ds )
	{
		$self->log( "Stats::Handler: dataset '$dataset_id' does not exist", 1 );
		return;
	}


#### CODE BELOW IS REDUNDANT WITH Processor::process_dataset:

	my $class = $ds->get_object_class();
	$class =~ /DataObj::(.*)$/;
	my $processors_class = "Stats::Processor::$1";

	my $processor_id;
	if( defined $session->get_plugin_factory->get_plugin_class( $processors_class ) )
	{
		$processor_id = $processors_class;
	}
	else
	{
		$processor_id = 'Stats::Processor';
	}


	# instantiate and ask (politely) to process the dataset
	my $processor = $session->plugin( "$processor_id", handler => $self );
	unless( defined $processor )
	{
		$self->log( "Failed to load '$processor_id'", 1 );
		return;
	}

	# TODO not needed anymore
	$conf->{handler} = $self;

	$self->log( "About to process dataset '$dataset_id'" );
	
	$processor->process_dataset( $conf );

	return;
}

# Turns on/off the debugging. All SQL queries will be shown in the logs if debug is on.
sub debug
{
	my( $self, $debug ) = @_;

	$self->{noise} = EPrints::Utils::is_set( $debug ) ? 1:0;
}


# Write info to the Apache logs when debug is switched on
sub log
{
	my( $self, $msg, $always_show ) = @_;

	return if( !$self->{noise} && !$always_show );

	$self->{session}->log( $msg );
}

# will remove any SQL tables starting in 'irstats2_%'
sub uninstall
{
	my( $self ) = @_;

	# sf2 / should use $self->{dbh}->sql_LIKE (but doesn't work on 3.2)
	my $sql = "SHOW TABLES LIKE ".$self->{dbh}->quote_value( "irstats2_%" );

        my $sth = $self->prepare_select( $sql );

        $self->{dbh}->execute( $sth, $sql );

        my @values;
        while( my @r = $sth->fetchrow_array )
        {
		$self->{dbh}->do( "DROP TABLE ".$self->{dbh}->quote_identifier( $r[0] ) );
		$self->log( "Removed table '$r[0]'" );
        }

	$self->log( "IRStats2 uninstalled." );
}

1;
