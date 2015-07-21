package EPrints::Plugin::Screen::EPrint::Box::Stats;

our @ISA = ( 'EPrints::Plugin::Screen::EPrint::Box' );

use strict;

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new(%params);

	$self->{appears} = [
		{
			place => "summary_bottom",
			position => 1000,
		},
	];

	return $self;
}

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
        my( $self, $eprint, $report ) = @_;

	$eprint = $self->{processor}->{eprint} unless defined $eprint;

	$report = $self->param( 'report' ) || 'summary_page' unless $report;

	my $repo = $self->{repository};

	my $handler = $repo->plugin( 'Stats::Handler' );

	my $context = $handler->context( {
		irs2report => $report,
		set_name => 'eprint',
		set_value => $eprint->id,
		datatype => 'downloads',
	} );

	my $conf = EPrints::Utils::clone( $repo->config( qw( irstats2 report ), $report ) );

	my $frag = $repo->make_doc_fragment;

	foreach my $item ( @{$conf->{items} || []} )
	{
		my $pluginid = delete $item->{plugin};
		next unless( defined $pluginid );

		next if $pluginid eq "ReportHeader";

		my $options = delete $item->{options};
		$options ||= {};

		# each View plugin needs its own copy of the context (if a View plugin changed one parameter of the context, this would propagate across all View plugins)	
		my $local_context = $context->clone();

		# local context
		my $done_any = 0;
		foreach( keys %$item )
		{
			$local_context->{$_} = $item->{$_};
			$done_any = 1;
		}
		$local_context->parse_context() if( $done_any );

		my $plugin = $repo->plugin( "Stats::View::$pluginid", handler => $handler, options => $options, context => $local_context );
		next unless( defined $plugin );	# an error / warning would be nice...
		
		$frag->appendChild( $plugin->render );
	}

	return $frag;
}

sub render_collapsed { 0 }

1;

