# Trigger to load the Google Charts library from the template(s)
$c->add_trigger( EPrints::Const::EP_TRIGGER_DYNAMIC_TEMPLATE, sub
{
		my( %args ) = @_;

		my( $repo, $pins ) = @args{qw/ repository pins/};

	return EP_TRIGGER_OK unless defined $repo->get_request;

	# Only include Google Charts APIs if needed on current page.
	my $stats_path = '^' . $repo->config( "rel_cgipath" ) . "/stats/";
	my $abstract_path = '^' . $repo->config( "rel_path" ) . '/[0-9]+/?$';
	my $abstract_long_path = '^' . $repo->config( "rel_path" ) . '/id/eprint/[0-9]+/?';
	my $for_stats = 0;
	my $box_disabled = $repo->config( 'plugins', 'Screen::EPrint::Box::Stats', 'params', 'disable' ) || 0;
	# IRStats2 pages
	if ( defined $repo->get_request && $repo->get_request->uri =~ m!^$stats_path! )
	{
		$for_stats = 1;
	}
	# Abstract pages if IRStats2 box plugin enabled
	elsif ( !$box_disabled && EPrints::Utils::is_set( $repo->config( 'plugins', 'Screen::EPrint::Box::Stats', 'appears' ) ) && defined $repo->get_request && ( $repo->get_request->uri =~ m!^$abstract_path! || $repo->get_request->uri =~ m!^$abstract_long_path! ) )
	{
		$for_stats = 1;
	}
	elsif ( $repo->config( "irstats2", "abstract_embed" ) && defined $repo->get_request && ( $repo->get_request->uri =~ m!^$abstract_path! || $repo->get_request->uri =~ m!^$abstract_long_path! ) )
	{
		$for_stats = 1;
	}
	elsif( $repo->config( "irstats2", "extra_paths" ) && defined $repo->get_request )
	{
		my $request_uri = $repo->get_request->uri;
		foreach my $extra_path ( @{$repo->config( "irstats2", "extra_paths" ) } )
		{
			if ( $request_uri =~ m!^$extra_path! )
			{
				$for_stats = 1;
			}
		}
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
}, id => 'include_google_charts_jsapi' );
