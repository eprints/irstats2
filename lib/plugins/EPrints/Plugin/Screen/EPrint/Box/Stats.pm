package EPrints::Plugin::Screen::EPrint::Box::Stats;

our @ISA = ( 'EPrints::Plugin::Screen::EPrint::Box' );

use strict;

sub can_be_viewed
{
        my( $self ) = @_;

        return 0 if $self->{session}->get_secure;
        return $self->has_value;
}

sub has_value
{
        my( $self ) = @_;

        my $eprint = $self->{processor}->{eprint};
        my @docs = $eprint->get_all_documents;

        return (scalar @docs > 0);
}

sub render
{
        my( $self ) = @_;

        return $self->{session}->html_phrase( 'lib/irstats2:embedded:summary_page:eprint:downloads',
                        eprintid => $self->{session}->make_text( $self->{processor}->{eprint}->get_id )
        );
}

sub render_collapsed { 0 }

1;

