package EPrints::Plugin::Stats::Export;

use EPrints::Plugin;
@ISA = ( 'EPrints::Plugin' );

use strict;

# Stats::Export (Abstract class)
#
# Plugins handling the export of data.
#

# Certain plugins (XML, JSON) gives some contextual information about the data being exported
sub get_export_context
{
        my( $self, $stats ) = @_;

        my $export_context = {};

        my $repo = $self->{session}->phrase( 'archive_name' ) || 'Repository';
        my $base_url = $self->{session}->config( 'base_url' );

        $export_context->{origin} = { name => $repo, url => $base_url };

        my $context = $stats->context;

        if( defined $context )
        {
                my $dates = $context->dates();

                $export_context->{timescale} = { format => 'YYYYMMDD', from => $dates->{from}, to => $dates->{to} };

                my $handler = $context->handler;
                my $set_plugin = $handler->sets;
                my $set = $context->set();
                if( defined $set )
                {
                        my $desc = EPrints::Utils::tree_to_utf8( $set_plugin->render_set( $set->{set_name}, $set->{set_value} ) );
                        $export_context->{set} = { name => $set->{set_name}, value => $set->{set_value}, description => $desc };
                }
        }

        return $export_context;
}

# to sub-class:
sub mimetype { 'text/html' }
sub export {}

1;

