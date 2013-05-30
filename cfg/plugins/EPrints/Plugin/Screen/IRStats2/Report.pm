package EPrints::Plugin::Screen::IRStats2::Report;

use EPrints::Plugin::Screen;
@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

# Screen::IRStats2::Report
#
# The screen handling the generation of reports. The main function is to get the context of the query and to pass on the context
#  to the appropriate View plugins

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new(%params);

        $self->{appears} = [
                {
                        place => "key_tools",
                        position => 5000,
                }
        ];

	return $self;
}

sub can_be_viewed
{
	my( $self ) = @_;

	my $session = $self->{session};

	if( defined $session && $session->can_call( 'irstats2', 'allow' ) )
	{
		return $session->call( ['irstats2', 'allow'], $session, 'irstats2/view' );
	} 

	return 0;
}

sub from
{
	my( $self ) = @_;

	$self->SUPER::from;

	my $processor = $self->{processor};
	$processor->{stats}->{handler} = $self->{session}->plugin( 'Stats::Handler' );

	$processor->{context} = $processor->{stats}->{handler}->context()->from_request( $self->{session} );

	my $report = $processor->{context}->current_report;
	my $conf = $self->{session}->config( 'irstats2', 'report', $report );

	$processor->{stats}->{conf} = EPrints::Utils::clone( $conf );
}

sub render_title
{
	my( $self ) = @_;

	my $processor = $self->{processor};

	if( !defined $self->{processor}->{stats}->{handler} )
	{
		$self->from;
	}

	my $handler = $self->{processor}->{stats}->{handler} || $self->{session}->plugin( 'Stats::Handler' );

	my $report = $processor->{context}->current_report;
	return $self->{session}->html_phrase( "lib/irstats2:report:$report" );
}

sub render
{
	my( $self ) = @_;

	my $session = $self->{session};
	my $frag = $session->make_doc_fragment;

	my $handler = $self->{processor}->{stats}->{handler};

	my $conf = $self->{processor}->{stats}->{conf};
	unless( defined $conf )
	{
		# no conf means that this report is not valid.
		return $session->render_message( 'error', $self->html_phrase( "invalid_report" ) );
	}

	my $context = $self->{processor}->{context};

	if( !$context->has_valid_set() )
	{
		return $self->html_phrase( 'invalid_set_value' );
	}

	foreach my $item ( @{$conf->{items} || []} )
	{
		my $pluginid = delete $item->{plugin};
		next unless( defined $pluginid );

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

		my $plugin = $session->plugin( "Stats::View::$pluginid", handler => $handler, options => $options );
		next unless( defined $plugin );	# an error / warning would be nice...
		
		$frag->appendChild( $plugin->render( $local_context ) );
	}

	return $frag;	
}

1;
