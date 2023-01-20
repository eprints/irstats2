package EPrints::Plugin::Stats::Processor::Access;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;
use Time::Local 'timegm_nocheck';
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError);

my $commit_period = 100_000;

sub process_access_record
{
	my( $record, $handler, $run_stats, $plugins, $filters ) = @_;

	if ($record =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z\t
	                   ([^\t]*)\t
	                   ([^\t]*)\t
	                   ([^\t]*)\t
	                   ([^\t]*)\t
	                   ([^\t]*)\t
	                   ([^\t]*)\n$/mx)
	{
		my $epoch = timegm_nocheck( $6, $5, $4, $3, $2 - 1, $1 - 1900 );

		my $data = {

			'datestamp' => {
				'hour' => $4,
				'epoch' => $epoch,
				'month' => $2,
				'day' => $3,
				'cache' => "$1$2$3",
				'year' => $1
			},

			'requester_id' => $7,
			'requester_user_agent' => $8,
			'referring_entity_id' => $9,
			'service_type_id' => $10,
			'referent_id' => $11,
			'referent_docid' => $12
		};

		if( $run_stats->{global_records_parsed} > 0 && $run_stats->{global_records_parsed} % 100_000 == 0 )
		{
			$handler->log( "Access: processed $run_stats->{global_records_parsed} records so far." );
		}

		$run_stats->{global_records_parsed}++;

		# filter out record?
		my $discard = 0;
		foreach my $filter (@$filters)
		{
			if( $filter->filter_record( $data ) )
			{
				$discard = 1;
				last;
			}
		}

		# Filter out records with no year set.
		if( !defined $data->{datestamp}->{year} )
		{
			$discard = 1;
		}

		if( !( $run_stats->{global_records_parsed} % $commit_period ) )
		{
			$handler->log( "Access: incremental commit to DB" );
			foreach my $plugin ( @$plugins, @$filters )
			{
				$plugin->commit_data( $handler );
				$plugin->clear_cache();
			}

		}
		return if( $discard );

		$run_stats->{global_records_kept}++;

		foreach my $plugin (@$plugins)
		{
			$plugin->process_record( $data, EPrints::Utils::is_set( $data->{referent_docid}) ? 1 : 0 );
		}
	}
}

sub process_existing_records
{
	my( $session, $handler, $run_stats, $plugins, $filters ) = @_;

	my $access_base_path = $session->config( 'archiveroot' ) . "/var/access";

	if( -e $access_base_path )
	{
		opendir my( $access_base_dh ), $access_base_path or die "Couldn't open dir '$access_base_path': $!";
		my @years = grep { /^\d{4}$/ } readdir $access_base_dh;
		closedir $access_base_dh;

		foreach my $year ( sort @years )
		{
			my $year_path = "$access_base_path/$year";

			opendir my( $year_dh ), "$year_path" or die "Couldn't open dir '$year_path': $!";
			my @days = grep { /^\d{4}-\d{2}-\d{2}\.log\.gz$/ } readdir $year_dh;
			closedir $year_dh;

			foreach my $day ( sort @days )
			{
				my $day_path = "$year_path/$day";

				$handler->log( "Processing file: $day_path" );

				if( my $gz = new IO::Uncompress::Gunzip( $day_path ))
				{
					while( my $line = <$gz> )
					{
						process_access_record( $line, $handler, $run_stats, $plugins, $filters );
					}

					$gz->close();
				}
				else
				{
					die "Couldn't open compressed file: $GzipError\n";
				}
			}
		}
	}
}

sub process_new_records
{
	my( $session, $handler, $run_stats, $plugins, $filters ) = @_;

	my $access_base_path = $session->config( 'archiveroot' ) . "/var/access";
	my $input_path = $access_base_path . "/current";

	my @now = localtime();
	my $today = sprintf("%04d-%02d-%02d", $now[5] + 1900, $now[4] + 1, $now[3]);

	if (-e $input_path)
	{
		opendir my($input_dh), $input_path or die "Couldn't open dir '$input_path': $!";
		my @input_days = grep { /^\d{4}-\d{2}-\d{2}\.log$/ } readdir $input_dh;
		closedir $input_dh;

		# Go through each day file (ARCHIVE/var/access/current/YYYY-MM-DD.log).
		foreach my $input_filename (sort @input_days)
		{
			my( $year, $month, $day ) = ( $input_filename =~ /^(\d{4})-(\d{2})-(\d{2}).log$/);

			# Skip the current day and leave it for the next run.
			if( "$year-$month-$day" ne $today )
			{
				my $output_path = "$access_base_path/$year";
				my $output_filename = "$output_path/$year-$month-$day.log.gz";

				mkdir( $output_path ) unless -e $output_path;

				my $full_input_filename = "$input_path/$input_filename";

				$handler->log( "Processing: $input_filename (Total so far: " . $run_stats->{global_records_parsed} . ")" );

				my %existing_lines;
				my @entries;
				my @new_entries;

				# Read the existing day file if it exists. If for some reason we end up
				# processing entries that are already present in the access log then
				# don't add them again.

				if( -e $output_filename )
				{
					if( my $gz = new IO::Uncompress::Gunzip( $output_filename ))
					{
						while( my $line = <$gz> )
						{
							$existing_lines{$line} = 1;
							push @entries, $line;
						}
	
						$gz->close();
					}
					else
					{
						die "Couldn't open compressed file: $GzipError\n";
					}
				}

				# Collect entries that aren't already in the day file and add them.

				if( open( my $fh, '<:encoding(UTF-8)', $full_input_filename ))
				{
					while( my $line = <$fh> )
					{
						next if( $existing_lines{$line} );

						push @new_entries, $line;

						$existing_lines{$line} = 1;
					}
				}
				else
				{
					die "Couldn't open $full_input_filename.";
				}

				# Write the entries (sorted).

				push @entries, @new_entries;

				if( my $gz = new IO::Compress::Gzip( $output_filename ))
				{
					foreach my $entry (sort @entries)
					{
						print $gz $entry;
					}

					$gz->close();
				}
				else
				{
					die "Couldn't open compressed file: $GzipError\n";
				}

				my $new_entries_length = scalar @new_entries;

				foreach my $new_entry (@new_entries)
				{
					process_access_record( $new_entry, $handler, $run_stats, $plugins, $filters );
				}

				# Delete the current file.

				unlink $full_input_filename;
			}
		}
	}
}

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

	# Locking the dataset (so that no other stats process can write to the DB at the same time)
	if( !$handler->lock_dataset( 'access' ) )
	{
		$handler->log( "Dataset 'access' is currently locked by another process.", 1 );
		return;
	}

	my %run_stats = (
		global_ref_time => time,
		global_records_parsed => 0,
		global_records_kept => 0
	);

	if( $params->{'create_tables'} )
	{
		process_existing_records( $session, $handler, \%run_stats, \@plugins, \@filters );
	}

	process_new_records( $session, $handler, \%run_stats, \@plugins, \@filters );

	# Because $record_list->is_last() is not reliable on the last run (see below: is_last()), we need to call commit_data again.
	foreach my $plugin ( @plugins, @filters )
	{
		$plugin->commit_data( $handler );
		$plugin->clear_cache();
	}

	# display stats (if verbose):
	my $total_time = ( time - $run_stats{global_ref_time} );
	$total_time = 1 if( $total_time < 1 );
	$run_stats{global_records_parsed} = 1 if( $run_stats{global_records_parsed} < 1 );
	$handler->log( "Access: it took $total_time secs to parse $run_stats{global_records_parsed} records ( average = ".sprintf( "%.2f", ($run_stats{global_records_parsed} / $total_time))." records/sec )" );

	$run_stats{global_records_kept} = 1 if( $run_stats{global_records_kept} < 1 );
	$handler->log( "Access: $run_stats{global_records_kept} records kept out of $run_stats{global_records_parsed} ( ratio = ".sprintf( "%.2f", 100*($run_stats{global_records_kept}/$run_stats{global_records_parsed}))."% )" );

	$handler->unlock_dataset( 'access' );

	return;
}

1;
