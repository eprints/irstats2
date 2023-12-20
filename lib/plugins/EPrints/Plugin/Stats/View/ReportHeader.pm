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
		my $url = EPrints::Plugin::Stats::Utils::base_url( $session )."/$report";

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

	my $tl_frame = $tl->appendChild( $session->make_element( 'div', class => 'irstats2_reportheader_timeline_frame' , id=>"irstats2_reportheader_timeline_frame") );

	return $tl;
}

sub render_filters
{
	my( $self ) = @_;

	my $session = $self->{session};
	my $frag = $session->make_doc_fragment;

## Filter Items content
        my @sets = @{$self->handler->sets->get_sets_names()||[]};
        push @sets, 'eprintid';

        my $local_context = $self->handler->context->from_request( $session );
        my $report = $local_context->{irs2report} || "";

        my $url = $self->handler->context->current_url;
	$url .= "/" . $report if $report;

        my $filters = $frag->appendChild( $session->make_element( 'div', id => 'irstats2_filters', class => 'irstats2_options_filters' ) );

        my $js_context = "{}";
        if( defined $local_context->{from} && $local_context->{to} )
        {
                $js_context = "{ 'from': '$local_context->{from}', 'to': '$local_context->{to}' }";
        }

##seldiv -- block include a select dropdown and a text box.
        my $seldiv = $filters->appendChild( $session->make_element( 'div', class=>"irstats2_select_input" ) );
        my $select = $seldiv->appendChild( $session->make_element( 'select',
                        name => 'set_name',
                        id => 'set_name',
                        onchange => "EPJS_Set_Finder( 'irstats2_filters_values', 'set_name', null, '$url', $js_context );",
        ) );
        foreach(@sets)
        {
                my $option = $select->appendChild( $session->make_element( 'option', value => "$_" ) );
                $option->appendChild( $self->handler->sets->render_set_name( $_ ) );
        }
        $seldiv->appendChild($session->html_phrase( "lib/irstats2/restrict_by/label" ));
        $seldiv->appendChild( $session->make_element( 'input', type => "text", name => "setdesc_q", id => "setdesc_q", size => '40', class => 'irstats2_setdesc_q' ) );

        $filters->appendChild( $session->make_element( 'div', id => 'irstats2_filters_values', class => 'irstats2_setdesc_values', style => 'display:block' ) );

        $filters->appendChild( $session->make_javascript( <<JS ) );
        EPJS_Set_Finder_Autocomplete( 'irstats2_filters_values', 'set_name', 'setdesc_q', '$url', $js_context );
        EPJS_Set_Finder( 'irstats2_filters_values', 'set_name', null, '$url', $js_context )
JS

        $filters->appendChild( $self->{session}->make_javascript( undef,src => "/javascript/jquery.min.js" ) )  ;
        $filters->appendChild( $self->{session}->make_javascript( undef,src => "/javascript/daterangepicker.js"  )  );
        $filters->appendChild( $self->{session}->make_javascript( undef,src => "/javascript/jquery.query-object.js"  )  ); ## this is used for the date resolution field.
##work out years array to be put into the datepicker's js code:
        my( $min_date, $max_date ) = $self->handler->get_dataset_boundaries( 'access' );
            $min_date ||= '20000101';
        
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
                @years = ( $min_y..$max_y );
		@years = reverse @years;
        }

	if (scalar @years >5)
	{
		@years = splice @years,0,5; ## take the latest 5 years to put in the quick menu.
	}
        ##$code is the js code used to initialise daterange picker
        my $code;
        foreach (@years){
            my $from = $_."-01-01";
            my $to = $_."-12-31";
	    $code = $code."' $_': [moment('$from'),moment('$to')],";
        }               

##form for the date and date resolution
        my $datediv = $session->make_element( "div" );
        my $range = $session->make_element( "form" , "onsubmit"=>"return EPJS_drange_convert();", id=>"filter_year_selection");
        $datediv->appendChild($range);
        $filters->appendChild($datediv);
        $range->appendChild($session->make_element( 'input', id => 'drange',name=>"drange", type=>"text", size=>23 ));
        
       
        my $format = $session->config( 'irstats2', 'dateformat' );

        $filters->appendChild($session->make_javascript( <<JS ));
//define a global dateformat, so that the js code has access to: 
dateformat = "$format";


jQuery(document).ready(function() {


jQuery('input[name="drange"]').daterangepicker({
    locale:{format:"$format"},
    alwaysShowCalendars: true,
    ranges: {
       'Last 7 days': [moment().subtract(6, 'days'), moment()],
       'Last 30 days': [moment().subtract(29, 'days'), moment()],
       'Last month': [moment().subtract(1, 'month').startOf('month'), moment().subtract(1, 'month').endOf('month')],
       'The month before last': [moment().subtract(2, 'month').startOf('month'), moment().subtract(2, 'month').endOf('month')],
        $code
       'ALL': [moment('$min_date'), moment()], 
    }
});
});
//keep previous selected dates:
if (jQuery.query.keys.from)
{
    var from = moment(jQuery.query.keys.from.toString()).format('$format');
    var to = moment(jQuery.query.keys.to.toString()).format('$format');
    var drange =  from+ ' - '+to;
   // console.log(drange);
}
else{
    //use ALL:
    var drange =  moment('$min_date').format('$format')+ ' - '+moment().format('$format') ;
}
jQuery('input[name="drange"]').attr("value",drange);
jQuery('div[id="irstats2_reportheader_timeline_frame"]').text(drange);
jQuery.noConflict();
JS

#####resolution block 
        my $res_block = $session->make_element( 'span', style => 'margin-left:20px;margin-right:20px;', id=>"date_resolution_container" );
        $res_block->appendChild($session->html_phrase( "lib/irstats2/date_resolution/label" ));
#        my $select = $session->make_element( 'select', name => 'range', style => 'margin-left:20px;' );
#        my $dates = $frag->appendChild( $session->make_element( 'div', id => 'irstats2_dates', class => 'irstats2_options_dates' ) );

        my $selected_res = $session->param('date_resolution') || "month";
#        my $res_select = $session->make_element( 'radio', id => 'select_date_resolution', name=>"date_resolution", style => 'margin-left:20px;' );
        foreach my $res ('day','month','year')
        {
            my $res_option;
            my $label = $session->make_element( 'label', id=>"date_resolution");
            if ($res eq $selected_res)
            {
                $res_option = $session->make_element( 'input', type=>"radio", name=>"date_resolution", value => "$res", checked=>1);
            }
            else{
                $res_option = $session->make_element( 'input', type=>"radio", name=>"date_resolution",  value => "$res");
            }
            $res_block->appendChild( $label );
            $label->appendChild($res_option);
            $label->appendChild($session->html_phrase( "lib/irstats2/date_resolution/$res" ));
        }
    $range->appendChild($res_block);
    ###end of resolution block

##submit button:
    my $rangesubmit = $session->make_element( 'input','type'=>"submit", 'value'=>$session->html_phrase( "lib/irstats2/date_resolution/submit" )->toString() );
    $range->appendChild($rangesubmit);








## Available Reports content
	
    my $conf = $session->config( 'irstats2', 'report' );

        # as to not display the current_report in the list of ... reports.
    my $current_report = $self->context->{irs2report};

    my $context = $self->context;

    my $reports = {};

	# first iteration: clean up and check reports apply to the current context
        foreach my $report ( sort(keys %{$conf}) )
        {
            #        next unless( $self->applies( $conf->{$report}, $context ) );

                ##filter out 
                next if( $report eq $current_report );

                ##filter out report that do not have category defined.
                my $category = $conf->{$report}->{category};
                next unless( defined $category );

                push @{$reports->{$category}}, $report;
        }

        my $stats_url = EPrints::Plugin::Stats::Utils::base_url( $session ).'/';

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

        my $context_args = "?from=$context->{from}&to=$context->{to}"  if ($context->{from} &&  $context->{to});

        my( $tr, $td );

        $tr = $filters->appendChild( $session->make_element( 'div', class => 'irstats2_reports' ) );
        $td = $tr->appendChild( $session->make_element( 'div', class => 'irstats2_reports_content' ) );
        $tr->appendChild( $session->make_element( 'div', id => 'irstats2_clear' ) );
        foreach my $category ( keys %$reports )
        {
                # content

                foreach my $report ( @{$reports->{$category}} )
                {
                        my $span = $td->appendChild( $session->make_element( 'span', class=>'irstats2_reports_span', style=>"padding-right:15px;" ) );

                        if ($self->applies( $conf->{$report}, $context ))
                        {
                                # if the main report, don't add the additional parameters.
                                my $href = ($report eq 'main') ? $stats_url : $stats_url.$report;
                                $href .= $context_args;
                                my $link = $span->appendChild( $session->make_element( 'a', class => 'irstats2_reportheader_link', href => $href ) );
                                $link->appendChild( $session->html_phrase( "lib/irstats2:report:$category:$report" ) );
                        }
                        else
                        {
                                my $link_dis = $span->appendChild( $session->make_element( 'span', class => 'irstats2_reportheader_disabled_link' ) );
                                $link_dis->appendChild( $session->html_phrase( "lib/irstats2:report:$category:$report" ) );
                        }

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

        my $content = $frag->appendChild( $session->make_element( 'div', class => 'irstats2_reportheader' ) );
	
        my $title = $session->make_element( "div", class => 'irstats2_view_title_filter' );
        $title->appendChild( $session->make_text( "Filters" ) );
        $frag->appendChild( $title );

        my $trigger = $session->make_element( 'a',
                href => '#',
                class => 'irstats2_filter_bar_toggle ep_noprint',
                onclick => "return EPJS_Stats_Export_Toggle( this, 'irstats2_filters' );"
        );
        $trigger->appendChild( $session->make_element( 'img', border => '0', src => '/style/images/multi_up.png', title => 'Filter options' ) );
        $title->appendChild($trigger);

        my $breadcrumbs = $content->appendChild( $session->make_element( 'span', class => 'irstats2_reportheader_breadcrumbs' ) );
        $breadcrumbs->appendChild( $self->render_breadcrumbs );

        my $timeline = $content->appendChild( $session->make_element( 'span', class => 'irstats2_reportheader_timeline' ) );
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

	my $local_context = $self->handler->context->from_request( $session );
	my $report = $local_context->{irs2report} || "";

	my $url = EPrints::Plugin::Stats::Utils::base_url( $session ).'/'.$report;

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

	$frag->appendChild( $session->make_element( 'div', id => $container_id, class => 'irstats2_setdesc_values', style => 'display:block' ) );

	$div->appendChild( $session->make_javascript( <<JS ) );
	EPJS_Set_Finder_Autocomplete( '$container_id', 'set_name', 'setdesc_q', '$url', $js_context );
	EPJS_Set_Finder( '$container_id', 'set_name', null, '$url', $js_context )
JS

	return $frag;
}

1;
