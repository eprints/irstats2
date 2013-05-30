package EPrints::Plugin::Stats::View::Compare;

use EPrints::Plugin::Stats::View;
@ISA = ('EPrints::Plugin::Stats::View');

use strict;

# Stats::View::Compare (Experimental, will be improved)
#
# Shows the download graphs for each years.
#
# Potential improvement: being able to select what the users want to compare
#
# No options available for this plugin

sub has_title
{
	return 0;
}

sub render_content
{
	my( $self, $context ) = @_;

	my $session = $self->{session};

	my $frag = $session->make_doc_fragment;

	my $div = $frag->appendChild( $session->make_element( 'div', class => 'irstats2_compare' ) );

        my( $min_date, $max_date ) = $self->handler->get_dataset_boundaries( 'access' );
        $min_date ||= '20000101';

	my @years;

	my( $min_y, $max_y );
	if( $min_date =~ /^(\d{4})/ )
	{
		$min_y = $1;
	}
	if( $max_date =~ /^(\d{4})/ )
	{
		$max_y = $1;
	}

	if( defined $min_y && defined $max_y )
	{
		push @years, $_ for( $min_y..$max_y );
	}

	foreach my $year (@years)
	{
		my $box = $session->make_element( 'div', style => 'background-color: #666;color:#CCC;padding: 5px; font-size: 14px;' );
		$frag->appendChild( $box );

		$box->appendChild( $session->make_text( "$year" ) );

		$frag->appendChild( $self->render_sub_plugins( $context, $year  ) );
	}

	return $frag;

}

sub render_sub_plugins
{
	my( $self, $context, $year ) = @_;

	# to have the same yAxis scale, we'd need to know the max value over the entire dataset
	my $plugin = $self->{session}->plugin( "Stats::View::Google::Graph", handler => $self->handler, options => { date_resolution => 'month', graph_type => 'column' } );

	my $local_context = $context->clone();
	$local_context->{datatype} = 'downloads';
	$local_context->dates( { from => undef, to => undef, range => "$year" } );

	return $plugin->render( $local_context );
}

sub can_export { 0 }

1;
