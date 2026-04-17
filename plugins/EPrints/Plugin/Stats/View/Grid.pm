package EPrints::Plugin::Stats::View::Grid;

use EPrints::Plugin::Stats::View;
@ISA = ('EPrints::Plugin::Stats::View');

use strict;

# Stats::View::Grid
#
# Allows to draw 2 View plugins on the same row. This doesn't display any stats.
#
# Options:
# - items: an ARRAYREF of View plugins (defined the same way as for $c->{stats}->{report}->{$reportname}
#

sub can_export { return 0; }

sub has_title
{
	return 0;
}

sub render
{
	my( $self ) = @_;

	my $options = $self->options;
	my $session = $self->{session};

	return $self->{session}->make_doc_fragment unless( scalar( @{$options->{items}} ) > 0 );

	my( $table, $tr, $td );
	$table = $session->make_element( 'table', width => '100%', border => '0', cellpadding => '0', cellspacing => '0', class => 'irstats2_view_Grid' );
	$tr = $table->appendChild( $session->make_element( 'tr' ) );

	my $handler = $self->handler;

	my $cell_width = int( 100 / scalar( @{$options->{items}} ) );

	my $done_any = 0;
        foreach my $item ( @{$options->{items} || []} )
        {
                my $pluginid = delete $item->{plugin};
                next unless( defined $pluginid );

                my $options = delete $item->{options};
                $options ||= {};

                my $local_context = $self->context->clone();

                # local context
                my $done_any = 0;
                foreach( keys %$item )
                {
                        $local_context->{$_} = $item->{$_};
                        $done_any = 1;
                }
                $local_context->parse_context() if( $done_any );

                my $plugin = $session->plugin( "Stats::View::$pluginid", 
			handler => $handler, 
			options => $options, 
			context => $local_context 
		);
                next unless( defined $plugin ); # an error / warning would be nice...

		$td = $tr->appendChild( $session->make_element( 'td', 'valign' => 'top', width => $cell_width."%" ) );
		$td->appendChild( $plugin->render );
        }

	return $table;
}

1;
