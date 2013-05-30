package EPrints::Plugin::Stats::View::Counter;

our @ISA = qw/ EPrints::Plugin::Stats::View /;

use strict;

# Stats::View::Counter
#
# Simply display a counter
# 
# Options:
# - human_display: formats the number for humans (e.g. 1000 -> 1,000)

sub javascript_class
{
	return 'Counter';
}

sub render_content_ajax
{
	my( $self, $context ) = @_;

	my $count = $self->handler->data( $context )->select()->sum_all();

        my $human_display = $self->options->{human_display} || 1;
        $human_display = 1 unless( defined $human_display && $human_display eq '0' );
	$count = EPrints::Plugin::Stats::Utils::human_display( $count ) if( $human_display );

	my $span = $self->{session}->make_element( 'span', class => 'irstats2_counter_value' );
	$span->appendChild( $self->{session}->make_text( $count ) );
	return $span;
}

1;

