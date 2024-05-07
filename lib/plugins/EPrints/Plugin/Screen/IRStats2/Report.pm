package EPrints::Plugin::Screen::IRStats2::Report;

use EPrints::Plugin::Screen;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use JSON;
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
	$self->{cache_enabled} = defined $self->{session}->config( 'irstats2', 'cache_enabled' ) ? $self->{session}->config( 'irstats2', 'cache_enabled' ) : 1 ;
	$self->{cache_dir} = $self->{session}->config( 'irstats2', 'cache_dir' ) ;
	$self->{template} = $self->{session}->config( 'irstats2', 'template' ) if defined $self->{session}->config( 'irstats2', 'template' );
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

sub render_action_link
{
        my( $self, %opts ) = @_;

        my $link = $self->SUPER::render_action_link( %opts );
        $link->setAttribute( href => EPrints::Plugin::Stats::Utils::base_url( $self->{session} ) );
        return $link;
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

	my $report = $context->current_report;
	my $divrep=$self->{session}->make_element('h2', class=>'ep_tm_pagetitle report_title');
	$frag->appendChild($divrep);
	$divrep->appendChild($self->{session}->html_phrase( "lib/irstats2:report:$report" ));

	##load cache from file, if exist.
	my $cache_enabled = $self->{cache_enabled};
	foreach my $item ( @{$conf->{items} || []} )
	{
		my $using_cache = 0; # flag to indicate we are using cache
		my $loaded_from_cache = 0; # a flag to determine if the cache need to be write to disk.
		my $cachefile; 
		my $cache = {};
		my $pluginid = delete $item->{plugin};
		next unless( defined $pluginid );

		# check permissions
		if( exists $item->{priv} )
		{
			next if( !defined $session->current_user );
			next unless $session->current_user->allow( $item->{priv} );
		}

		my $options = delete $item->{options};
		$options ||= {};

		##jy2e08: url date_resolution overwrites the local config one.
		if (EPrints::Utils::is_set($options->{date_resolution}) && EPrints::Utils::is_set($self->{repository}->param('date_resolution')))
		{
			$options->{date_resolution} = 'month';
			$options->{date_resolution} = $self->{repository}->param('date_resolution') if $self->{repository}->param('date_resolution') =~ /^[a-zA-Z0-9_]+$/;
		}

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
		my $host = defined $session->config("host") ? $session->config("host") : $session->config("securehost");
		$cachefile = $self->{cache_dir}."/". md5_hex(  $host.$pluginid.$options->{metrics}.$local_context->{from}.$local_context->{to}.$local_context->{set_name}.$local_context->{set_value}.$local_context->{datatype}).".ir2";

		if( $cache_enabled  && not( -f "$cachefile.lock") )  ##if cache enabled and not locked and cache file exist
		{
			$using_cache = 1;
			if (-f $cachefile) ##Load from cache if cachefile exist.
			{
				local $/; #Enable 'slurp' mode
				open my $fh, "<$cachefile";
				my $json = <$fh>;
				close $fh;
				$cache = decode_json($json);
				$loaded_from_cache=1;
			}
			##otherwise, cache hash will not be filled, hence retrive from DB.
		}

		my $plugin = $session->plugin( "Stats::View::$pluginid", handler => $handler, options => $options, context => $local_context, cache=>$cache );
		next unless( defined $plugin );	# an error / warning would be nice...
		$frag->appendChild( $plugin->render );
		if( $using_cache && %$cache && (not $loaded_from_cache )) ## only save if we are using cache, %cache hash is not empty and not loaded from cache. $using_cache -> $cache_enabled && cachefile not locked.
		{
			#save $cache to file:
			my $json_cache = encode_json($cache);
			`touch $cachefile.lock`;
			open(OUT,">$cachefile");
			binmode(OUT, ":utf8");
			print OUT $json_cache;
			close OUT;
			`rm -f $cachefile.lock`;
		}
	}
	return $frag;	
}

1;
