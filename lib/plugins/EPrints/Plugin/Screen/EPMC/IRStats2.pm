package EPrints::Plugin::Screen::EPMC::IRStats2;

use EPrints::Plugin::Screen::EPMC;

@ISA = ( 'EPrints::Plugin::Screen::EPMC' );

use strict;

sub new
{
      my( $class, %params ) = @_;

      my $self = $class->SUPER::new( %params );

      $self->{actions} = [qw( enable disable )];
      $self->{disable} = 0; # always enabled, even in lib/plugins

      $self->{package_name} = "irstats2";

      return $self;
}



sub render_messages
{
    my( $self ) = @_;

    my $repo = $self->{repository};
    my $xml = $repo->xml;

    my $frag = $xml->create_document_fragment;
    my @missing;
    my $datecalc = EPrints::Utils::require_if_exists('Date::Calc');
    my $geoip = EPrints::Utils::require_if_exists( 'Geo::IP' );
    push @missing, "Date::Calc" unless defined $datecalc;
    push @missing, "Geo::IP" unless defined $geoip;
    if( scalar @missing >0  )
    {
        $frag->appendChild(
            $repo->render_message(
                'error', $self->html_phrase( 'error:no_plugins',packages => $repo->xml->create_text_node( join(", ",@missing) ))
            ) );
        return $frag;
    }


    return $frag;
}



1;

