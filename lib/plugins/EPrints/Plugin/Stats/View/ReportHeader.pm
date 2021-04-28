package EPrints::Plugin::Stats::View::ReportHeader;

use EPrints::Plugin::Stats::View;
@ISA = ('EPrints::Plugin::Stats::View');

use strict;

# Stats::View::ReportHeader
#
# The top section of a Report, showing the item(s) the users are looking at, as well as the dates and the options to filter/chose dates etc
#
# No options available for this plugin.

sub can_export { return 0; }

sub has_title
{
	return 0;
}

sub render_breadcrumbs
{
	my( $self ) = @_;

	# if set_value not set -> 'All items'
	# if set -> 'All items > <set_name>: <set_value>
	
	my $set = $self->context->set();

	my $session = $self->{session};
	my $bd = $session->make_doc_fragment;

	if( defined $set->{set_value} )
	{
		my $report = $self->context->{irs2report} || '';

		# TODO phrase up the breadcrumbs?
		# TODO would be nice to have a global method to retrieve the stats url:
		my $url = "/cgi/stats/report/$report";

		my $level1 = $bd->appendChild( $session->make_element( 'a', href => $url ) );
		$level1->appendChild( $self->handler->sets->render_set() );	# will render the 'main' set i.e. 'all items'

		$bd->appendChild( $session->make_text( " > " ) );

		$bd->appendChild( $self->handler->sets->render_set_name( $set->{set_name} ) );
		$bd->appendChild( $session->make_text( ": " ) );
		$bd->appendChild( $self->handler->sets->render_set( $set->{set_name}, $set->{set_value} ) );
	}
	else
	{
		$bd->appendChild( $self->handler->sets->render_set() ) ;
	}

	return $bd;
}

sub render_timeline
{
	my( $self ) = @_;
	
	my $session = $self->{session};
	my $tl = $session->make_doc_fragment;

	my $context = $self->context;

	my $tl_frame = $tl->appendChild( $session->make_element( 'div', class => 'irstats2_reportheader_timeline_frame' ) );

	if( !defined $context->{range} || $context->{range} ne '_ALL_' )
	{
		my $from = $context->get_property( 'from' );
		my $to = $context->get_property( 'to' );

		$tl_frame->appendChild( EPrints::Plugin::Stats::Utils::render_date( $session, { from => $from, to => $to } ) );
	}

	return $tl;
}

sub render_filters
{
	my( $self ) = @_;

	my $session = $self->{session};
	my $frag = $session->make_doc_fragment;

## Filter Items button
	$frag->appendChild( $session->make_element( 'input',
			type => 'submit', 
                        class => 'irstats2_form_action_button',
                        value => $session->phrase( 'lib/irstats2/header:filter_items' ),
			id => 'irstats2_filters_button',
			onclick => "return EPJS_Stats_Action_Toggle( 'irstats2_filters_button', 'irstats2_filters', 'irstats2_form_action_button_selected' );",
        ) );

## Dates button
	$frag->appendChild( $session->make_element( 'input',
			type => 'submit', 
                        class => 'irstats2_form_action_button',
                        value => $session->phrase( 'lib/irstats2/header:dates' ),
			id => 'irstats2_dates_button',
			onclick => "return EPJS_Stats_Action_Toggle( 'irstats2_dates_button', 'irstats2_dates', 'irstats2_form_action_button_selected' );",
        ) );

## Available Reports button
	$frag->appendChild( $session->make_element( 'input', 
			type => 'submit',
                        class => 'irstats2_form_action_button',
                        value => $session->phrase( 'lib/irstats2/header:available_reports' ),
			id => 'irstats2_reports_button',
			onclick => "return EPJS_Stats_Action_Toggle( 'irstats2_reports_button', 'irstats2_reports', 'irstats2_form_action_button_selected' );",
        ) );
	
## Filter Items content
        my @sets = @{$self->handler->sets->get_sets_names()||[]};
	push @sets, 'eprintid';

        my $local_context = $self->handler->context->from_request( $session );
        my $report = $local_context->{report} || "";

	my $url = $self->context->current_url;

        my $div = $frag->appendChild( $session->make_element( 'div' ) );

	my $filters = $frag->appendChild( $session->make_element( 'div', id => 'irstats2_filters', class => 'irstats2_options_filters', style => 'display: none' ) );

        my $js_context = "{}";
        if( defined $local_context->{from} && $local_context->{to} )
        {
                $js_context = "{ 'from': '$local_context->{from}', 'to': '$local_context->{to}' }";
        }

        my $select = $filters->appendChild( $session->make_element( 'select',
                        name => 'set_name',
                        id => 'set_name',
                        onchange => "EPJS_Set_Finder( 'irstats2_filters_values', 'set_name', null, '$url', $js_context );",
        ) );
        foreach(@sets)
        {
                my $option = $select->appendChild( $session->make_element( 'option', value => "$_" ) );
                $option->appendChild( $self->handler->sets->render_set_name( $_ ) );
        }

        $filters->appendChild( $session->make_element( 'input', type => "text", name => "setdesc_q", id => "setdesc_q", size => '40', class => 'irstats2_setdesc_q' ) );

        $filters->appendChild( $session->make_element( 'div', id => 'irstats2_filters_values', class => 'irstats2_setdesc_values', style => 'display:none' ) );

        $filters->appendChild( $session->make_javascript( <<JS ) );
        EPJS_Set_Finder_Autocomplete( 'irstats2_filters_values', 'set_name', 'setdesc_q', '$url', $js_context );
        EPJS_Set_Finder( 'irstats2_filters_values', 'set_name', null, '$url', $js_context )
JS


## Dates content
        my( $min_date, $max_date ) = $self->handler->get_dataset_boundaries( 'access' );
        $min_date ||= '20000101';

        my @ranges = @{$self->options->{ranges}||[]};
        unless(scalar(@ranges))
        {
                my @years;
                
                my( $min_y, $max_y );
                if( $min_date =~ /^(\d{4})/ )
                {
                        $min_y = $1;
                }       
                if( $max_date =~ /^(\d{4})/ )
                {
                        $max_y = $1;
                }       
                
                if( defined $min_y && defined $max_y )
                {
                        push @years, $_ for( $min_y..$max_y );
                }       
                
                @ranges = ( '1m', '6m', '1y', '_ALL_', @years );
        }       
        
        $select = $session->make_element( 'select', name => 'range', style => 'margin-left:20px;' );
	foreach my $r (@ranges)
	{
		my $option = $session->make_element( 'option', value => "$r" );
		$select->appendChild( $option );
		$option->appendChild( EPrints::Plugin::Stats::Utils::render_date( $session, { range => $r } ) );
	}

	my $dates = $frag->appendChild( $session->make_element( 'div', id => 'irstats2_dates', class => 'irstats2_options_dates', style => 'display:none' ) );

        $dates->appendChild( $session->html_phrase( 'lib/irstats2/datepicker', ranges => $select ) );
 
        $dates->appendChild( $session->make_javascript( <<JS ) );
document.observe( "dom:loaded", function(){
	initDatePicker();
	datePickerController.getDatePicker( 'sd' ).setRangeLow( '$min_date' );
} );
JS

## Available Reports content
	
	my $reports_box = $frag->appendChild( $session->make_element( 'div', id => 'irstats2_reports', class => 'irstats2_options_reports', style => 'display:none' ) );

	my $conf = $session->config( 'irstats2', 'report' );

        # as to not display the current_report in the list of ... reports.
        my $current_report = $self->context->{ir2report};

	my $context = $self->context;

        my $reports = {};

	# first iteration: clean up and check reports apply to the current context
        foreach my $report ( keys %{$conf} )
        {
                next unless( $self->applies( $conf->{$report}, $context ) );
                next if( $report eq $current_report );

                my $category = $conf->{$report}->{category};
                next unless( defined $category );

                push @{$reports->{$category}}, $report;
        }

        $url = $session->get_uri;
        $url .= "/" unless( $url =~ /\/$/ );
        my $stats_url = $session->config( 'http_cgiurl' ).'/stats/report/';

        if( defined $context->{set_name} && defined $context->{set_value} )
        {
                $stats_url .= "$context->{set_name}/$context->{set_value}/";
        }

        my $blocks = 0;
        foreach( keys %$reports )
        {
                unless( defined $reports->{$_} && scalar( @{$reports->{$_}} ) )
                {
                        delete $reports->{$_};
                }
                $blocks++;
        }
        $blocks ||= 1;
        my $block_width = int( 100 / $blocks );
        $block_width = 25 if( $block_width > 25 );

        my $context_args = "?range=$context->{range}&from=$context->{from}&to=$context->{to}";

        my( $table, $tr, $td );
        $table = $reports_box->appendChild( $session->make_element( 'table', border => '0', cellpadding => '0', cellspacing => '0', class => 'irstats2_reports' ) );
        foreach my $category ( keys %$reports )
        {
                $tr = $table->appendChild( $session->make_element( 'tr' ) );

                # title
                $td = $tr->appendChild( $session->make_element( 'td', class => 'irstats2_reports_heading' ) );
                my $span = $td->appendChild( $session->make_element( 'span' ) );
                $span->appendChild( $session->html_phrase( "lib/irstats2:category:$category" ) );

                # content
                $td = $tr->appendChild( $session->make_element( 'td', class => 'irstats2_reports_content' ) );

                foreach my $report ( @{$reports->{$category}} )
                {
                        my $span = $td->appendChild( $session->make_element( 'span' ) );
                        # a bit hacky
                        my $href = ($report eq 'main') ? $stats_url : $stats_url.$report;
                        $href .= $context_args;
                        my $link = $span->appendChild( $session->make_element( 'a', class => 'irstats2_reportheader_link', href => $href ) );
                        $link->appendChild( $session->html_phrase( "lib/irstats2:report:$category:$report" ) );
                }
        }

	return $frag;
}

sub applies
{
        my( $self, $report, $context ) = @_;

        # $report->{appears} => undef (report appears nowhere)
        # $report->{appears} => {} 
        return 0 if( exists $report->{appears} && ( !$report->{appears} || !EPrints::Utils::is_set( $report->{appears} ) ) );

        my $appears = $report->{appears};
        return 1 if( !defined $appears );

        return 0 if( exists $appears->{set_name} && ( !$appears->{set_name} || !EPrints::Utils::is_set( $appears->{set_name} ) ) );

        my $valid_sets = $appears->{set_name};
        $valid_sets = [$valid_sets] unless( ref($valid_sets) eq 'ARRAY' );
        my $set_name = $context->{set_name} || 'repository';

        foreach my $vset (@$valid_sets)
        {
                return 1 if( $vset eq '*' || $vset eq $set_name );

                if( $vset =~ /^\!(.*)$/ )
                {
                        return 0 if( $1 eq $set_name );
                }
        }

        return 1;
}

sub render_content
{
	my( $self ) = @_;

	my $session = $self->{session};

	my $frag = $session->make_doc_fragment;

	my $content = $frag->appendChild( $session->make_element( 'table', class => 'irstats2_reportheader' ) );
	my $content_tr = $content->appendChild( $session->make_element( 'tr' ) );

	my $breadcrumbs = $content_tr->appendChild( $session->make_element( 'td', class => 'irstats2_reportheader_breadcrumbs' ) );
	$breadcrumbs->appendChild( $self->render_breadcrumbs );
	
	my $timeline = $content_tr->appendChild( $session->make_element( 'td', class => 'irstats2_reportheader_timeline' ) );
	$timeline->appendChild( $self->render_timeline );
	
	my $options = $frag->appendChild( $session->make_element( 'div', class => 'irstats2_reportheader_options' ) );
	$options->appendChild( $self->render_filters );

	return $frag;
}

# This renders the set lookups
sub render_content_ajax
{
	my( $self ) = @_;

	my @sets = @{$self->handler->sets->get_sets_names()||[]};

	my $session = $self->{session};
	my $frag = $session->make_doc_fragment;

	my $container_id = $self->generate_container_id;

	my $local_context = $self->handler->context->from_request( $self->{session} );
	my $report = $local_context->{irs2report} || "";

	my $url = "/cgi/stats/report/$report";

=pod
# All items in the repository
	my $all_link = $session->make_element( 'a', href => "$url" );
	$all_link->appendChild( $session->html_phrase( 'lib/irstats2/sets:repository' ) );
	$frag->appendChild( $all_link );

	$frag->appendChild( $session->make_element( 'hr' ) );

# Searching by eprint id
	$frag->appendChild( $self->html_phrase( 'eprintid' ) );
	$frag->appendChild( $session->make_element( 'input', 
			type => 'text',
			name => 'setdesc_eprintid',
			id => 'setdesc_eprintid',
			size => '10',
	) );
	
	$frag->appendChild( $session->make_element( 'input',
			onclick => "var epid = \$( 'setdesc_eprintid' ).value; if( epid == null ) return false; window.location.href = '/cgi/stats/report/eprint/'+epid+'/$report'; return false",
			class => 'irstats2_setdesc_link ep_form_action_button',
			value => $self->phrase( 'view' ),
	) );

	$frag->appendChild( $session->make_element( 'hr' ) );
=cut

# Searching for a set value
	my $div = $frag->appendChild( $session->make_element( 'div' ) );
	
	my $js_context = "{}";
	if( defined $local_context->{from} && $local_context->{to} )
	{
		$js_context = "{ 'from': '$local_context->{from}', 'to': '$local_context->{to}' }";
	}

	my $select = $div->appendChild( $session->make_element( 'select', 
			name => 'set_name', 
			id => 'set_name',
			onchange => "EPJS_Set_Finder( '$container_id', 'set_name', null, '$url', $js_context );",
	) );
	foreach(@sets)
	{
		my $option = $select->appendChild( $session->make_element( 'option', value => "$_" ) );
		$option->appendChild( $self->handler->sets->render_set_name( $_ ) );
	}


	$div->appendChild( $session->make_element( 'input', type => "text", name => "setdesc_q", id => "setdesc_q", size => '40', class => 'irstats2_setdesc_q' ) );

	$frag->appendChild( $session->make_element( 'div', id => $container_id, class => 'irstats2_setdesc_values', style => 'display:none' ) );

	$div->appendChild( $session->make_javascript( <<JS ) );
	EPJS_Set_Finder_Autocomplete( '$container_id', 'set_name', 'setdesc_q', '$url', $js_context );
	EPJS_Set_Finder( '$container_id', 'set_name', null, '$url', $js_context )
JS

	return $frag;
}

1;
