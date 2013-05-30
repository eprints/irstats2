package EPrints::Plugin::Stats::View::KeyFigures;

use EPrints::Plugin::Stats::View;
our @ISA = ('EPrints::Plugin::Stats::View');

use strict;

# Stats::View::KeyFigures
#
# Shows an activity overview of the stats
# 

our $METRICS = {

	downloads => sub {
		$_[0]->set_property( 'datatype', 'downloads' );
		$_[0]->set_property( 'datafilter', undef );
		$_[0];
	},
	
	hits => sub {
		$_[0]->set_property( 'datatype', 'views' );
		$_[0]->set_property( 'datafilter', undef );
		$_[0];
	},

	deposits => sub {
		$_[0]->set_property( 'datatype', 'deposits' );
		$_[0]->set_property( 'datafilter', 'archive' );
		$_[0];
	},

	total_fulltext => sub {
		$_[0]->set_property( 'datatype', 'doc_access' );
		$_[0]->set_property( 'datafilter', 'full_text' );
		$_[0];
	},
	
	total_openaccess => sub {
		$_[0]->set_property( 'datatype', 'doc_access' );
		$_[0]->set_property( 'datafilter', 'open_access' );
		$_[0];
	},
	# lm = last month
	lm_downloads => sub {
		$_[0]->set_property( 'datatype', 'downloads' );
		$_[0]->set_property( 'datafilter', undef );
		$_[0]->dates( { from => undef, to => undef, range => '1m' } );
		$_[0];
	},
	lm_deposits => sub {
		$_[0]->set_property( 'datatype', 'deposits' );
		$_[0]->set_property( 'datafilter', 'archive' );
		$_[0]->dates( { from => undef, to => undef, range => '1m' } );
		$_[0];
	},

	ratio_fulltext => [ 'total_fulltext', 'deposits' ],

	ratio_openaccess => [ 'total_openaccess', 'deposits' ],
};

our $DEFAULT_METRICS = [
	'deposits.spark',
	'downloads.spark',
	'ratio_fulltext.progress',
	'ratio_openaccess.progress',
];

sub can_export { 0 }

sub apply_metric_context
{
	my( $self, $context, $metric ) = @_;

	my $local_context = $context->clone();

	return $local_context if( !defined $METRICS->{$metric} );

	my $f = $METRICS->{$metric};

	return $local_context if( ref( $f ) ne 'CODE' );

	eval { $local_context = &$f( $local_context, $metric ) };

	return $local_context;
}

sub get_metric
{
	my( $self, $context, $name ) = @_;
	
	return $self->{cache}->{$name} if( exists $self->{cache}->{$name} );

	$self->{cache}->{$name} = $self->handler->data( $context )->select( type => 'sum' )->sum_all();
	$self->{cache}->{$name} = 0 if( !defined $self->{cache}->{$name} );

	return $self->{cache}->{$name};
}

sub render_metric_with_spark
{
	my( $self, $context, $name ) = @_;

	my $frag = $self->{session}->make_doc_fragment;

	my $local_context = $self->apply_metric_context( $context, $name );

	my $count = $self->get_metric( $local_context, $name );

	my $js_context = $local_context->to_json();

       	$frag->appendChild( $self->{session}->make_element( "div", id => $name, class => "irstats2_googlespark" ) );
        $frag->appendChild( $self->{session}->make_javascript( <<DLSPARK ) );
document.observe("dom:loaded",function(){
	new EPJS_Stats_GoogleSpark( { 'context': $js_context, 'options': { 'container_id': '$name' } } );
});
DLSPARK
	
	my $div = $frag->appendChild( $self->{session}->make_element( 'span', class => 'irstats2_keyfigures_metric' ) );

	my $span = $div->appendChild( $self->{session}->make_element( 'span', class => 'irstats2_keyfigures_metric_figure' ) );
	$span->appendChild( $self->{session}->make_text( EPrints::Plugin::Stats::Utils::human_display( $count ) ) );

	$span = $div->appendChild( $self->{session}->make_element( 'span', class => 'irstats2_keyfigures_metric_text' ) );

	my $phraseid = (defined $count && "$count" ne "1") ? "metric:plural:$name" : "metric:singular:$name";

	$span->appendChild( $self->html_phrase( $phraseid ) );

	return $frag;
}

sub compute_metric
{
	my( $self, $context, $name ) = @_;

	return $self->{cache}->{$name} if( exists $self->{cache}->{$name} );

	my $metric = $METRICS->{$name};
	
	if( ref( $metric ) eq 'CODE' )
	{
		my $local_context = $self->apply_metric_context( $context, $name );
		return $self->get_metric( $local_context, $name );
	}
	elsif( ref( $metric ) eq 'ARRAY' )
	{
	 	# will return the ratio ( metric1 / metric2 ) * 100
		my( $metric1, $metric2 ) = @$metric;
		my $value1 = $self->compute_metric( $context, $metric1 );
		my $value2 = $self->compute_metric( $context, $metric2 );

		my $ratio = ( defined $value1 && defined $value2 && $value1 > 0 && $value2 > 0 ) ? sprintf( "%.0f", ($value1 / $value2)*100 ): '0';
		return $ratio;
	}

	return 0;
}

sub render_metric_with_progress
{
	my( $self, $context, $name ) = @_;

	my $value = $self->compute_metric( $context, $name );

	my $table = $self->{session}->make_element( 'table', class => 'irstats2_keyfigures_progress' );
	my $tr = $table->appendChild( $self->{session}->make_element( 'tr' ) );
	my $td = $tr->appendChild( $self->{session}->make_element( 'td', width => '50%' ) );

	my $ref_width = '110';

	my $div = $td->appendChild( $self->{session}->make_element( 'div', class => 'irstats2_progress_wrapper', style => 'width:'.$ref_width.'px;' ) );
	my $progress = $div->appendChild( $self->{session}->make_element( 'div', class => 'irstats2_progress' ) );

	my $width = $value;
	# value between 0 and 100
	$width = 0 if( $width < 0 );
	$width = 100 if( $width > 100 );
	$width = int( $width*$ref_width / 100 );

	$progress->setAttribute( 'style', 'width:'.int($width).'px;' );

	$td = $tr->appendChild( $self->{session}->make_element( 'td', width => '50%' ) );

	my $span = $td->appendChild( $self->{session}->make_element( 'span', class => 'irstats2_keyfigures_metric' ) );
	
	my $figure = $span->appendChild( $self->{session}->make_element( 'span', class => 'irstats2_keyfigures_metric_figure' ) );
	$figure->appendChild( $self->{session}->make_text( $value.'%' ) );

	my $text = $span->appendChild( $self->{session}->make_element( 'span', class => 'irstats2_keyfigures_metric_text' ) );
	$text->appendChild( $self->html_phrase( "metric:$name" ) );

	return $table;
}

# This plugin doesn't have an AJAX callback - everything is rendered as the plugin is called
sub render_content
{
	my( $self, $context, $params ) = @_;

	my $session = $self->{session};

	my $frag = $session->make_element( 'div', class => 'irstats2_keyfigures' );

	my $metrics = $self->options->{metrics};

	if( !EPrints::Utils::is_set( $metrics ) || ref( $metrics ) ne 'ARRAY' )
	{
		$metrics = $DEFAULT_METRICS;
	}

	my $c = 0;
	foreach my $metric (@$metrics)
	{
		my ($name, $type) = split( /\./, $metric );
		next unless( defined $name );
		$type = 'spark' if( !defined $type || !( $type eq 'spark' || $type eq 'progress' ) );

		my $section = $frag->appendChild( $session->make_element( 'div', class => 'irstats2_keyfigures_section' ) );

		if( $type eq 'spark' )
		{
			$section->appendChild( $self->render_metric_with_spark( $context, $name ) );
		}
		elsif( $type eq 'progress' )
		{
			$section->appendChild( $self->render_metric_with_progress( $context, $name ) );
		}

		if( ( $c % 2 == 1 ) && $c > 0 )
		{
			$frag->appendChild( $session->make_element( 'div', class => 'irstats2_ruler' ) );
		}
		$c++;
	}

	$frag->appendChild( $session->make_element( 'div', class => 'irstats2_ruler' ) );

	return $frag;
}


1;
