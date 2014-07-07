package EPrints::Plugin::Stats::View::Google::Graph;

use EPrints::Plugin::Stats::View;
@ISA = ('EPrints::Plugin::Stats::View');

use strict;

# Stats::View::Google::Graph
#
# Shows a graph (of downloads, deposits etc...)
#
# Options:
# - date_resolution: one of 'day', 'month' or 'year' - the granularity of the graph. Beware that choosing 'day' may pull lots of data
# - graph_type: one of 'area' of 'column' - 'area' is a line chart, 'column' a bar chart.

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new( %params );

	# default options		
	$self->options->{date_resolution} ||= 'day';
	$self->options->{graph_type} ||= 'area';

	return $self;
}

sub mimetype { 'application/json' }

# GoogleChart expects data like this:
# [ '1 Jan 2012', 1234 ] or [ 'Jan 2012', 1234] or [ '2012', 1234 ]
#
# in other words:
# [ string, int ]
#
# so we need to create the JSON, and render the dates properly

# and we need to fill in the missing gaps (days) here - if possible loop only once over the data

# data we get is ordered ASC so the first record is the first date we have data for - however if the user requested
# a specific FROM date then we can respect it and insert blank data beforehand
sub get_data
{
	my( $self ) = @_;

	# the FROM/TO dates might need to be normalised if the date resolution is "month" or "year" (cos it's better to start at the beginning of the month/year for those)
	my $from = $self->context->dates->{from};

	if( $self->options->{date_resolution} eq 'month' )
	{
		if( defined $from && $from =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			$from = $1.$2.'01';
			$self->context->dates( { from => $from } );
		}
	}
	elsif( $self->options->{date_resolution} eq 'year' )
	{
		if( $from =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			$from = $1.'0101';
			$self->context->dates( { from => $from } );
		}
	}

	# retrieves the data from the DB
	my $stats = $self->handler->data( $self->context )->select(
			fields => [ 'datestamp' ],
			order_by => 'datestamp',
			order_desc => 0,
	);

	# but we still need to group the data by day/month/year depending on options->{date_resolution}
	# and fill potential gaps in the data

	if( !defined $from && scalar( @{$stats->data} ) )
	{
		$from = $stats->{data}->[0]->{datestamp};
	}

	# this returns a continuous list of days/months/years - because there's no guarantee the data-points we retrieved from the DB are time-continuous (there
	# might be gaps)
	my $date_sections = EPrints::Plugin::Stats::Utils::get_dates( $from, $self->context->dates->{to}, $self->options->{date_resolution} );

	my $date_res = $self->options->{date_resolution};
	my $month_labels = EPrints::Plugin::Stats::Utils::get_month_labels( $self->{session} );
	
	# variables used to compute the average data points
	my $show_average = defined $self->options->{show_average} && $self->options->{show_average};
	my $avg_sum = 0;
	my $avg_n = 1;

	# if !$has_data then we can display a friendly message to our users rather than an empty graph
	my $has_data = 0;

	my @exports;

	# this builds in one pass: the data-points, the average data-points and the full-labels
	my $i = 0;
	foreach my $ds ( @$date_sections )
	{
		my $subtotal = 0;
		for( my $j=$i; $j < scalar(@{$stats->data}); $j++ )
		{
			my $datapoint = $stats->data->[$j] or last;

			if( defined $datapoint->{count} && $datapoint->{count} > 0 && !$has_data )
			{
				$has_data = 1;
			}

			if( $datapoint->{datestamp} =~ /^$ds/ )
			{
				$subtotal += $datapoint->{count} || 0;
				$i++;
			}
			else
			{
				# safety measure - not to be stuck on the 1st data point (though this probably means something is wrong in Utils::get_dates
				$i++ if( $i == 0 );

				last;
			}
		}
	
		my $desc;
		if( $date_res eq 'day' )
		{
			# 20120101 => 1 Jan 2012
			$ds =~ /^(\d{4})(\d{2})(\d{2})$/;
			$desc = "$3 ".$month_labels->[$2-1]." $1";
		}
		elsif( $date_res eq 'month' )
		{
			# 201201 => Jan 2012
			$ds =~ /^(\d{4})(\d{2})$/;
			$desc = $month_labels->[$2-1]." $1";
		}
		elsif( $date_res eq 'year' )
		{
			# 2012 => 2012
			$desc = $ds;
		}

		my $record = { count => $subtotal, datestamp => $ds, description => $desc };

		if( $show_average )
		{
			$avg_sum += $subtotal;
			$record->{average} = int( $avg_sum / $avg_n++ );
		}

		push @exports, $record;
	}
	
	# TODO needs new name:
	$stats->{data} = \@exports;

	# "has_data" in the sense that: has at least one non-zero data point
	$stats->{has_data} = $has_data;

	return $stats;
}

sub ajax
{
        my( $self ) = @_;

	my $stats = $self->get_data;

	# need to generate the JSON from @stats->data

	my $json_data_points = "";
	foreach (@{$stats->data} )
	{
		$json_data_points .= (length $json_data_points) ? ", [ \"$_->{description}\", $_->{count}" : "[ \"$_->{description}\", $_->{count}";

		if( exists $_->{average} )
		{
			$json_data_points .= ", $_->{average}";
		}

		$json_data_points .= "]",
	}
	
	my $graph_type = $self->options->{graph_type} || 'area';	# or 'column'

	print STDOUT "{ \"data\": [$json_data_points], \"type\": \"$graph_type\", \"show_average\": ".($self->options->{show_average}?'true':'false');

	if( exists $stats->{has_data} && !$stats->{has_data} )
	{
		my $msg = $self->phrase( 'no_data_point' );
		$msg =~ s/"/\\"/g;
		print STDOUT ", \"msg\": \"$msg\"";
	}

	print STDOUT "}";

	return;
}

sub export
{
        my( $self, $params ) = @_;

	my $stats = $self->get_data;
	
	$stats->export( $params );

	return;
}



sub render_title
{
	my( $self ) = @_;

	my $context = $self->context;

	my $datatype = defined $context->{datatype} ? $context->{datatype}: "no datatype?";

	my $datafilter = defined $context->{datafilter} ? ":".$context->{datafilter} : "";

	return $self->{session}->html_phrase( "lib/irstats2/type:$datatype$datafilter" );
}

sub javascript_class { return 'GoogleGraph'; }

1;

