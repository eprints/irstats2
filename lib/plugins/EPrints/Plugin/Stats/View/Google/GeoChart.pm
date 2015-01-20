package EPrints::Plugin::Stats::View::Google::GeoChart;

use EPrints::Plugin::Stats::View;
@ISA = ('EPrints::Plugin::Stats::View');

use strict;

# Stats::View::Google::GeoChart
#
# Shows an interactive map of download locations
#
# No options available for this plugin.

sub mimetype { 'application/json' }

sub get_data
{
	my( $self ) = @_;

	return $self->handler->data( $self->context )->select( fields => [ 'value' ], do_render => 0 );
}

sub ajax
{
	my( $self ) = @_;

	my $stats = $self->get_data;
	
	my @data;
        foreach(@{$stats->data})
        {
		my $value = $_->{value};
		my $count = $_->{count};
		push @data, "[\"$value\", $count]";
        }

	my $jsdata = join(",",@data);

	print STDOUT "{ \"data\": [$jsdata] }";

	return;
}


sub render_title
{
	my( $self ) = @_;

	my $context = $self->context;

	my $datatype = defined $context->{datatype} ? $context->{datatype}: "no datatype?";
	return $self->{session}->make_text( $datatype );
	
	return $self->html_phrase( 'title' );
}

sub javascript_class { return 'GoogleGeoChart'; }

1;

