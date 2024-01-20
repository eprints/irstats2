# Trigger to load the Google Charts library from the template(s)
$c->add_trigger( EPrints::Const::EP_TRIGGER_DYNAMIC_TEMPLATE, sub
{
		my( %args ) = @_;

		my( $repo, $pins ) = @args{qw/ repository pins/};

	# Only include Google Charts APIs if needed on current page.
	my $stats_path = '^' . $repo->config( "rel_cgipath" ) . "/stats/";
	my $abstract_path = '^' . $repo->config( "rel_path" ) . '/[0-9]+/?$';
	my $abstract_long_path = '^' . $repo->config( "rel_path" ) . '/id/eprint/[0-9]+/?';
	my $for_stats = 0;
	# IRStats2 pages
	if ( $repo->get_request->uri =~ m!$stats_path! )
	{
		$for_stats = 1;
	}
	# Abstract pages if IRStats2 box plugin enabled
	elsif ( $repo->config( 'plugins', 'Screen::EPrint::Box::Stats', 'params', 'disable' ) == '0' && ( $repo->get_request->uri =~ m!$abstract_path! || $repo->get_request->uri =~ m!$abstract_long_path! ) )
	{
		$for_stats = 1;
	}
	return EP_TRIGGER_OK unless $for_stats;

		my $head = $repo->make_doc_fragment;

		$head->appendChild( $repo->make_javascript( undef,
				src => "https://www.google.com/jsapi"
		) );

		$head->appendChild( $repo->make_javascript( 'google.charts.load("current", {packages:["corechart", "geochart"]});' ) );

		if( defined $pins->{'utf-8.head'} )
		{
				$pins->{'utf-8.head'} .= $repo->xhtml->to_xhtml( $head );
		}

		if( defined $pins->{head} )
		{
				$head->appendChild( $pins->{head} );
				$pins->{head} = $head;
		}
		else
		{
				$pins->{head} = $head;
		}

		return EP_TRIGGER_OK;
} );
