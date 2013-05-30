package EPrints::Plugin::Stats::View::Google::Spark;

use EPrints::Plugin::Stats::View;
@ISA = ('EPrints::Plugin::Stats::View');

use strict;

# Stats::View::Google::Spark
#
# Display a spark line (a miniature graph) - Always shows the last 6 months.
#
# No options available for this plugin.

sub mimetype { 'application/json' }
	
sub get_data
{
	my( $self, $context ) = @_;

	my $local_context = $context->clone();
	$local_context->dates( { range => '6m', from => undef, to => undef } );

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

	my $find_first = 0;	
	foreach my $stat ( @{$stats->data} )
	{
		my ($string, $count) = ( $stat->{datestamp}, $stat->{count} );
	
		# discard all the NULL values at the beginning:
		next if( "$count" eq '0' && !$find_first );
		$find_first = 1;

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
	
	foreach my $date ( @order_data )
	{
		my $desc;
		# 20120101 => 1 Jan 2012
		$date =~ /^(\d{4})(\d{2})(\d{2})$/;
		$desc = "$3 ".$month_labels->[$2-1]." $1";

		push @full_labels, "[ \"$desc\", ".$google_data->{$date}." ]";
	}

	my $jsdata = join(",",@full_labels);
	print STDOUT "{ \"data\": [$jsdata] }";

	return;
}

sub render_title
{
	my( $self, $context ) = @_;

	my $datatype = defined $context->{datatype} ? $context->{datatype}: "no datatype?";

	my $datafilter = defined $context->{datafilter} ? ":".$context->{datafilter} : "";

	return $self->{session}->html_phrase( "lib/irstats2/type:$datatype$datafilter" );
}

sub javascript_class { return 'GoogleSpark'; }

1;

