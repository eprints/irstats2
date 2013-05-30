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

sub mimetype { 'application/json' }
	
sub get_data
{
	my( $self, $context ) = @_;

	my $local_context = $context->clone();
	my $options = $self->options;

	my $date_res = $options->{date_resolution} || 'day';

	if( $date_res eq 'month' )
	{
		my( $from, $to ) = EPrints::Plugin::Stats::Utils::normalise_dates( $self->handler, $local_context );

		if( $from =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			$from = $1.$2.'01';
			$local_context->dates( { range => undef, from => $from, to => $to } );	
		}
	}
	elsif( $date_res eq 'year' )
	{
		my( $from, $to ) = EPrints::Plugin::Stats::Utils::normalise_dates( $self->handler, $local_context );
		if( $from =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			$from = $1.'0101';
			$local_context->dates( { range => undef, from => $from, to => $to } );	
		}
	}

	return $self->handler->data( $local_context )->select(
			fields => [ 'datestamp' ],
			order_by => 'datestamp',
			order_desc => 1,
	);
}

sub ajax
{
        my( $self, $context ) = @_;

	my $stats = $self->get_data( $context );

	# GoogleChart expects data like this:
	# [ '1 Jan 2012', 1234 ] or [ 'Jan 2012', 1234] or [ '2012', 1234 ]
	#
	# in other words:
	# [ string, int ]
	#
	# so we need to create the JSON, and render the dates properly

	my $google_data = {};
	my @order_data;
	my $date_res = $self->options->{date_resolution} || 'day';

	my $find_first = 0;	
	foreach my $stat ( @{$stats->data} )
	{
		my ($string, $count) = ( $stat->{datestamp}, $stat->{count} );
	
		# discard all the NULL values at the beginning:
		next if( "$count" eq '0' && !$find_first );
		$find_first = 1;

		if( $date_res eq 'month' )
		{	
			$string =~ s/\d{2}$//g;
		}
		elsif( $date_res eq 'year' )
		{
			$string =~ s/\d{4}$//g;
		}
		if( exists $google_data->{$string} )
		{
			$google_data->{$string} += $count;
		}
		else
		{
			$google_data->{$string} = $count;
			push @order_data, $string;
		}
	}

	my @full_labels;
	my $month_labels = EPrints::Plugin::Stats::Utils::get_month_labels( $self->{session} );

	my $show_average = defined $self->options->{show_average} && $self->options->{show_average};
	my $sum = 0;
	my $n = 1;
	foreach my $date ( @order_data )
	{
		my $desc;
		if( $date_res eq 'day' )
		{
			# 20120101 => 1 Jan 2012
			$date =~ /^(\d{4})(\d{2})(\d{2})$/;
			$desc = "$3 ".$month_labels->[$2-1]." $1";
		}
		elsif( $date_res eq 'month' )
		{
			# 201201 => Jan 2012
			$date =~ /^(\d{4})(\d{2})$/;
			$desc = $month_labels->[$2-1]." $1";
		}
		elsif( $date_res eq 'year' )
		{
			# 2012 => 2012
			$desc = $date;
		}

		if( $show_average )
		{
			$sum += $google_data->{$date};
			my $avg = int( $sum / $n++ );
			push @full_labels, "[ \"$desc\", ".$google_data->{$date}.", $avg ]";
		}
		else
		{
			push @full_labels, "[ \"$desc\", ".$google_data->{$date}." ]";
		}
	}

	my $jsdata = join(",",@full_labels);

	my $graph_type = $self->options->{graph_type} || 'area';	# or 'column'
	
	print STDOUT "{ \"data\": [$jsdata], \"type\": \"$graph_type\", \"show_average\": ".($show_average?'true':'false')." }";

	return;
}

sub render_title
{
	my( $self, $context ) = @_;

	my $datatype = defined $context->{datatype} ? $context->{datatype}: "no datatype?";

	my $datafilter = defined $context->{datafilter} ? ":".$context->{datafilter} : "";

	return $self->{session}->html_phrase( "lib/irstats2/type:$datatype$datafilter" );
}

sub javascript_class { return 'GoogleGraph'; }

1;

