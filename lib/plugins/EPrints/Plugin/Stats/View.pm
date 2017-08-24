package EPrints::Plugin::Stats::View;

use EPrints::Plugin;
@ISA = ('EPrints::Plugin');

use strict;

# Stats::View (Abstract class)
#
# Plugins used on Reports. Views may be versatile and are not necessary aware of the data they're rendering (downloads? deposits?...) . But they know how to render it (e.g. a Graph, a Table...)
# 
# They can also optionally do the data retrieval via ajax (see View::render_content_ajax).
# 
# 'options' refers to the options set in the local configuration for that View (see z_stats.pl, $c->{irstats2}->{report}). For example you may want to limit a Table to display the top
#  10 elements. This is done as an option.
#
# 'context' refers to the Context of the query. For example, is a set selected? Is a special date range selected?
#

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new( %params );

	my $view_id = $self->get_id;
	$view_id =~ s/Stats::View::(.*)$/$1/;
	$self->options->{view} = $view_id;

	# if set to 1, this will add the CSS class "ep_noprint" to the containers, effectively hidding the View when people try to print the page
	$self->{hide_from_print} = 0;

	return $self;	
}

sub mimetype { 'text/html' }

# Called by the Javascript layer via AJAX (see irstats2.js). This method simply calls View::render_content_ajax and prints the result to the page.
sub ajax
{
        my( $self ) = @_;

	my $frag = $self->render_content_ajax();

	binmode( STDOUT, ":utf8" );

	print STDOUT EPrints::XML::to_string( $frag ) if( defined $frag );

	return;
}

# Helper methods
sub options { 
	my( $self ) = @_;

	if( !defined $self->{options} )
	{
		$self->{options} = {};
	}
	
	return $self->{options};
}
sub handler { shift->{handler} }
sub context { shift->{context} }


# Which Javascript class to use (View plugins using AJAX should sub-class this). Javascript classes are defined in irstats2.js.
sub javascript_class { 'View' }

# The main data retrieval method. Usually called by View::render_content, View::render_content_ajax or View::export (the methods that require the data)
sub get_data
{
	my( $self, $params ) = @_;

	return $self->handler->data( $self->context );
}


# Helper method returning the container ID (HTML attribute) if specified. If not, it will generate a unique ID.
# This is important for Ajax callback, to know where to insert the data to.
sub container
{
	my( $self ) = @_;

	if( !defined $self->options->{container_id} )
	{
		$self->options->{container_id} = $self->generate_container_id();
	}

	return $self->options->{container_id};
}

sub generate_container_id { "irstats2_container_".int(rand()*100000) }

sub has_title { return 1 }

# Renders the title of the View, if any.
sub render_title { shift->html_phrase( 'title' ) }

# By default render_content will create the AJAX callback (so the *real* rendering is then done by View::render_content_ajax). 
# But this can be over-riden if you'd rather render the data directly on the page (without going via AJAX). View::KeyFigures provides a good example.
sub render_content
{
        my( $self ) = @_;

        my $session = $self->{session};

        my $frag = $session->make_doc_fragment;

	my $id = $self->container;

	my $js_class = $self->javascript_class();
	my $css_class = 'irstats2_'.lc( $js_class );

	my $json_context = $self->context->to_json();
	my $view_options = $self->options_to_json();

        $frag->appendChild( $session->make_element( "div", id => "$id", class => $css_class ) );

	# note: when called from a Browse View, the DOM is already loaded thus the dom:loaded Event will never fire. That's why we first test that the dom's already loaded below.
        $frag->appendChild( $session->make_javascript( <<CODE ) );
	if( document.loaded )
	  new EPJS_Stats_$js_class( { 'context': $json_context, 'options': $view_options } );
	else
		document.observe("dom:loaded",function(){
			  new EPJS_Stats_$js_class( { 'context': $json_context, 'options': $view_options } );
		});
CODE

        return $frag;
}

# Method called to render the data (graph etc) when using the AJAX callback.
sub render_content_ajax
{
	my( $self ) = @_;

	$self->{session}->log( 'EPrints::Plugin::Stats::View::render_content_ajax must be sub-classed' );

	return $self->{session}->make_doc_fragment;
}

# The main rendering method, called by Screen::IRStats2::Report
sub render
{
	my( $self ) = @_;

	my $session = $self->{session};
	my $frag = $session->make_doc_fragment;
	my $options = $self->options;

	# just re-use $self->options->{view}
	my $class_id = $self->get_id;
	$class_id =~ s/^Stats::View:://g;
	$class_id =~ s/::/_/g;

	my $classes = "irstats2_view irstats2_view_$class_id";

	if( $self->{hide_from_print} )
	{
		$classes .= " ep_noprint";
	}
	
	my $container = $session->make_element( 'div', align=>'center',class => "$classes" );
	$frag->appendChild( $container );

	my $title;
	if( $self->has_title() )
	{
		unless( defined $options->{show_title} && !$options->{show_title} )
		{
			$title = $session->make_element( "div", class => 'irstats2_view_title' );

			# note that this option has been deprecated because it doesn't support internationalisation
			if( defined $options->{title} )
			{
				$title->appendChild( $session->make_text( $options->{title} ) );
			}
			elsif( defined $options->{title_phrase} )
			{
				$title->appendChild( $session->html_phrase( "lib/irstats2:view:".$options->{title_phrase} ) );
			}
			else
			{
				$title->appendChild( $self->render_title() );
			}
			$container->appendChild( $title );
		}
	}
	
	if( $self->can_export() && defined $title )
	{
		$container->appendChild( $self->render_export_bar( $title ) );
	}

	my $content = $session->make_element( "div", class => 'irstats2_view_content' );
	$container->appendChild( $content );

	my $custom_css = $options->{custom_css};
	$content->setAttribute( 'style', $custom_css ) if( defined $custom_css );

	$content->appendChild( $self->render_content() );
	
	return $frag;
}

# Tells whether to render the Export bar or not. Certain plugins cannot export.
sub can_export { 1 }


# Renders the Export bar for the View plugins that need it.
sub render_export_bar
{
	my( $self, $target ) = @_;
	
	my $session = $self->{session};

	my @plugins = @{$self->export_plugins() || [] };
	return $session->make_doc_fragment unless( scalar( @plugins ) );

	my $export = $session->make_element( 'div', class => 'irstats2_export_bar ep_noprint' );

	my $content_id = $self->generate_container_id;

	my $trigger = $session->make_element( 'a',
			href => '#',
			class => 'irstats2_export_bar_toggle ep_noprint',
			onclick => "return EPJS_Stats_Export_Toggle( this, '$content_id' );"
	);
	
	$trigger->appendChild( $session->make_element( 'img', border => '0', src => '/style/images/multi_down.png', title => 'Export options' ) );
	$target->appendChild( $trigger );

	my $content = $export->appendChild( $session->make_element( 'div',
			class => 'irstats2_export_content',
			style => 'display: none;',
			id => $content_id
	) );

	my $options = $self->options;
	my $local_options = EPrints::Utils::clone( $options );
	delete $local_options->{export};

	my $select = $session->make_element( 'select', name => 'export' );
	foreach my $plugin (@plugins)
	{
		my $id = $plugin->get_id;
		next if( $id eq 'Stats::Export' );
		$id =~ s/^Stats::Export::(.*)$/$1/;

		my $option = $select->appendChild( $session->make_element( 'option', value => "$id" ) );
		$option->appendChild( $session->make_text( "$id" ) );
	}

	$content->appendChild( $session->html_phrase( 'irstats2/view/export_section', 
			params => $self->context->render_hidden_bits( $local_options ),
			options => $select
	) );

	return $export;
}


# This will actually export the data. No rendering (View::render etc.) is done in this case.
sub export
{
        my( $self, $params ) = @_;

        my $data = $self->get_data( $params );

        $data->export( $params );
}

sub export_plugins
{
	my( $self ) = @_;

	return $self->handler->get_stat_plugins( 'Export' );
}

# Transforms the configuration options into JSON. Used for AJAX callbacks.
sub options_to_json
{
	my( $self ) = @_;

	my @json;
	foreach( keys %{ $self->options || {} } )
	{
		my $value = $self->options->{$_};
		next unless( defined $value );
		if( ref( $value ) eq 'ARRAY' )
		{
			$value = join( ";", @$value );
		}
		$value =~ s/'/\\'/g;
		push @json, "'$_': '$value'";
	}

	return "{ ".join(", ",@json)." }";
}


1;
