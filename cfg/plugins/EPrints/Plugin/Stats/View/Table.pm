package EPrints::Plugin::Stats::View::Table;

use EPrints::Plugin::Stats::View;
@ISA = ('EPrints::Plugin::Stats::View');

use strict;

# Stats::View::Table
#
# Draws an HTML table, usually to show the Top n Objects given a context, for instance:
#
# - Top EPrints globally,
# - Top EPrints given a set (Top EPrints in ECS)
# - Top Authors (== set) globally or in a set
# - Top Referrers (== value) globally or in a set
#
# Options:
# - show_count: show the counts or not
# - show_order: show the order (1,2,3,4...)
# - human_display: formats the number for humans (e.g. 1000 -> 1,000)
# - show_more: show the bottom paging options (10,25,50,all)

sub javascript_class
{
	return 'Table';
}

sub render_title
{
	my( $self, $context ) = @_;

	my $grouping = defined $context->{grouping} ? ":".$context->{grouping} : "";

	return $self->html_phrase( "title$grouping" );
}

sub get_data
{
	my( $self, $context ) = @_;
	my $session = $self->{session};

	# We need to know the Top <things> we're going to display...
	if( !EPrints::Utils::is_set( $self->options->{top} ) )
	{
		print "Stats::View::Table: missing option 'top'\n";
		return $session->make_doc_fragment;
	}

	# This bit of code tries to map what the user wants to view given the context
	my $local_context = $context->clone();
	my $options = $self->options;
	
	$options->{do_render} = ( defined $options->{export} ) ? 0 : 1;

	$options->{limit} ||= 10;
	delete $options->{limit} if( $options->{limit} eq 'all' );

	my $top = $self->options->{top};

	# Perhaps the user wants to see the top:
	# - eprints
	# - <set_name> eg top authors
	# - <value> eg top referrers / country...
	if( $top eq 'eprint' )
	{
		# we need to fetch eprint objects ie 'eprintid'
		$local_context->{grouping} = 'eprint';
		$options->{fields} = [ 'eprintid' ];
	}
	elsif( $top eq $local_context->{datatype} )
	{
		$local_context->{grouping} = 'value';
		$options->{fields} = [ 'value' ];
	}
	elsif( EPrints::Utils::is_set( $local_context->{set_name} ) )
	{
		$local_context->{grouping} = $top;
		$options->{fields} = [ 'set_value' ];
	}
	else
	{
		# perhaps it's a set then... let's assume so!
		$local_context->{set_name} = $top;
		delete $local_context->{grouping};
		$options->{fields} = [ 'set_value' ];
	}

	$self->{options} = $options;

	return $self->handler->data( $local_context )->select( %$options );
}

sub render_content_ajax
{
        my( $self, $context ) = @_;

	my $session = $self->{session};

	my $stats = $self->get_data( $context );

	unless( $stats->count )
	{
		return $session->html_phrase( 'lib/irstats2/error:no_data' );
	}

	my $options = $self->options;
	foreach( 'show_count', 'show_order', 'human_display', 'show_more' )
	{
		$options->{$_} = ( defined $options->{$_} && $options->{$_} eq '0' ) ? 0 : 1;
	}

	my $frag = $session->make_doc_fragment;
	my( $table, $tr, $td );

	$table = $frag->appendChild( $session->make_element( 'table', border => '0', cellpadding => '0', cellspacing => '0', class => 'irstats2_table' ) );

=pod
	$tr = $table->appendChild( $session->make_element( 'tr', class => 'irstats2_table_headings' ) );

	if( $options->{show_order} )
	{
		$td = $tr->appendChild( $session->make_element( 'td' ) );
	}

	$td = $tr->appendChild( $session->make_element( 'td' ) );
	$td->appendChild( $self->html_phrase( 'label:item' ) );

	if( $options->{show_count} )
	{
		$td = $tr->appendChild( $session->make_element( 'td' ) );
		$td->appendChild( $self->html_phrase( 'label:count' ) );
	}
=cut
	my $data = $stats->data;

	my $c = 0;
	my $reference = 0;
	my $ref_width = "100";
	foreach( @$data )
        {
		my $object = $_->{$options->{fields}->[0]};
                my $count = $_->{count};
		
		my $row_class = $c % 2 == 0 ? 'irstats2_table_row_even' : 'irstats2_table_row_odd';
		$tr = $table->appendChild( $session->make_element( 'tr', class => "$row_class" ) );

		if( $options->{show_order} )
		{
	                $td = $tr->appendChild( $session->make_element( 'td', class => 'irstats2_table_cell_order' ) );
        	        $td->appendChild( $session->make_text( ($c + 1)."." ) );	# $c starts at 0, we want the ordering to start at 1
		}

		$td = $tr->appendChild( $session->make_element( 'td', class => 'irstats2_table_cell_object' ) );
		$td->appendChild( $object );

		if( $options->{show_count} )
		{
			if( $c == 0 )
			{
				$reference = $count;
				$reference = 1 if( $reference == 0 );
			}

			my $cur_width = int( ($count / $reference)*$ref_width );
			$count = EPrints::Plugin::Stats::Utils::human_display( $count ) if( $options->{human_display} );

			$td = $tr->appendChild( $session->make_element( 'td', class => 'irstats2_table_cell_count' ) );
			my $ref_box = $td->appendChild( $session->make_element( 'div', class => 'irstats2_progress_wrapper', style => "width: $ref_width"."px" ) );
			my $ref_content = $ref_box->appendChild( $session->make_element( 'div', class => 'irstats2_progress', style => "width: $cur_width"."px" ) );
			my $span = $ref_content->appendChild( $session->make_element( 'span' ) );
			$span->appendChild( $session->make_text( $count ) );
		}

		$c++;	
	}

	# don't show the link if we've reached the max already...	
	if( $options->{show_more} )
	{
		my $table_options = $frag->appendChild( $session->make_element( 'div', class => 'irstats2_table_options ep_noprint' ) );

		foreach my $limit ( '10', '25', '50', 'all' )
		{
			$options->{limit} = $limit;
			$self->{options} = $options;

			my $json_context = $context->to_json();
			my $view_options = $self->options_to_json();

			my $link = $table_options->appendChild( $session->make_element( 'a', 
					href => '#',
					onclick => "new EPJS_Stats_Table( { 'context': $json_context, 'options': $view_options } );return false;"
			) );
			$link->appendChild( $session->make_text( $limit ) );
		}
	}

	return $frag;
}

1;

