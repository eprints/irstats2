# IRStats2 configuration file

$c->{irstats2} = {};

##dateformat on the report screen
$c->{irstats2}->{dateformat} = "DD/MM/YYYY";



##caching statistics
$c->{irstats2}->{cache_enabled} = 1;
$c->{irstats2}->{cache_dir} =  $EPrints::SystemSettings::conf->{base_path}."/tmp/stats";  ##irstats cache dir. The cache dir is cleared daily by processstats script.

if ($c->{irstats2}->{cache_enabled})
{
	`mkdir -p $c->{irstats2}->{cache_dir}`;
	if( !-d $c->{irstats2}->{cache_dir} )
	{
	      EPrints->abort( "IRStats2 failed to create cache directory '$c->{irstats2}->{cache_dir}'" );
	}
}

$c->{irstats2}->{cache_paths} = [
	"/stats/report",
	"/stats/report/requests"
];

$c->{plugins}{"Stats::Processor::Access::DocDownloads"}{params}{disable} = undef;

# The following utility routines can be used for inserting the charts into a summary page, eg
#
# my $util = $repository->get_conf( "irstats2", "util" );
# if( $util )
# {
#   $page->appendChild( &{$util->{render_summary_page_totals}}( $repository, $eprint ) );
#   $page->appendChild( &{$util->{render_summary_page_docs}}( $repository, $eprint ) );
# }

# render the stats summary chart if there is at least one public document
$c->{irstats2}->{util}->{render_summary_page_totals} = sub
{
  my ( $repository, $eprint ) = @_;

  my $count = 0;
  foreach my $doc ( $eprint->get_all_documents )
  {
    next unless $doc->is_public();
    $count++;
  }

  my $frag = $repository->xml()->create_document_fragment();
  if( $count )
  {
    $frag->appendChild(
      $repository->html_phrase(
        "lib/irstats2:embedded:summary_page:eprint:downloads",
        "eprintid" => $repository->make_text( $eprint->get_value( "eprintid" ) )
      )
    );
  }

  return $frag;
};

# render the stats chart for each public document, assuming there is more than 1
$c->{irstats2}->{util}->{render_summary_page_docs} = sub
{
  my ( $repository, $eprint ) = @_;

  my $count = 0;
  my $doc_stats = $repository->make_element( "div", class => "irstats2_summary_page_doc_stats_container" );
  foreach my $doc ( $eprint->get_all_documents )
  {
    next unless $doc->is_public();
    $count++;

    $doc_stats->appendChild(
      $repository->html_phrase(
        "lib/irstats2:embedded:summary_page:eprint:doc_downloads",
        "eprintid" => $repository->make_text( $doc->get_id ),
        "doc_name" => $repository->make_text( $doc->get_value( "main" ) ),
        "container_id_div" => $repository->make_element("div", id => "irstats2_summary_page_doc_downloads_".$doc->get_id, class => "irstats2_graph" ),
        "container_id" => $repository->make_text( "irstats2_summary_page_doc_downloads_" . $doc->get_id )
      )
    );
  }

  if( $count > 1 )
  {
    return $doc_stats;
  }
  else # 0 or 1 docs, dont need a doc level breakdown
  {
    return $repository->xml()->create_document_fragment()
  }
};

##################
# Data Processing
##################

# list of (EPrints) datasets to process:
$c->{irstats2}->{datasets} = {

	eprint => { incremental => 0 },
	
	access => { filters => [ 'Robots', 'Repeat' ] },

	history => { incremental => 1 },

#	user => { incremental => 0 },
};

##################
# Data Collection
##################

# This version of IRStats2 can maintain the access data as TSV files in
# $ARCHIVE_ROOT/var/access as well as / instead of the access table in the
# database.
#
# If you do not need data to be collected into the access table then the access
# table logger can be disabled by setting "access_table_logger_disabled" to 1.
#
# This version of IRStats2 only reads from the file log files and so disabling
# the file logger will prevent updates to the stats even if the table logger
# is still enabled.

$c->{access_table_logger_disabled} = 0;
$c->{access_file_logger_disabled} = 0;

$c->{access_logger_func} = sub {

	my( $repository, $epdata ) = @_;

	my $access_file_logger_disabled = $repository->config( "access_file_logger_disabled" );

	unless( defined( $access_file_logger_disabled ) && $access_file_logger_disabled )
	{
		my $logger = $repository->plugin( "Stats::Logger" );

		if( defined( $logger ) )
		{
			$logger->create_access( $epdata );
		}
	}
};


#######
# Sets
#######

# Defining new sets:
#
# A new set 'X' fills in the statement: "I want to be able to see downloads per X". For instance, for 'divisions': "I want to be able to see downloads per divisions" etc.
#
# A new grouping, withing a set, fills in the statement: "I want to be able to see Top Y per set". For instance for the set 'divisions' and the grouping 'authors': "I want to be able to see Top Authors per Divisions".
# This is why you don't have (by default) the grouping 'subjects' under 'divisions': "I want to see the Top Subjects per Divisions" (I don't find that stat particularly useful but you may).
#
$c->{irstats2}->{sets} = [
	{ 
		'field' => 'divisions', 
		'groupings' => [ 'authors', 'type' ]
	},
	{ 
		'field' => 'subjects', 
		'groupings' => [ 'authors', 'type' ]
	},
	{
		'name' => 'type',
		'field' => 'type',
		'groupings' => [ 'authors' ]
	},
#	# EdShare:
#	{
#		'field' => 'courses',
#	}
	# using creators_name and creators_id
	{
		'name' => 'authors', 
		'field' => 'creators',
		'groupings' => [ 'type' ], 

		'anon' => 1,	# don't show user's email address (the 'id' field)
		# for compound:
# if use_ids == 0 -> just use _name, same as having field => 'creators_name'
# if use_ids == 1 -> use _id as key for the set and _name for display - value will be ignored if _id is NOT set!

		'use_ids' => 1,
#		'id_field' => 'id',		# default value, optional. if the subfield is called 'email' then use 'email'
#		If your set returns too much data when no filter is applied, this forces at least n characters 
#		to be used for the filter before results are returned.
#		'minimum_filter_length' => 2, #integer
	},
#	# just using creators_name
#	{
#		'name' => 'authors', 
#		'field' => 'creators_name', 
#	},
#
#	{ 'field' => 'userid' },
];



###############
# Misc Options
###############

## the dataset to use when making individual eprint queries, i.e. do we show stats for any valid eprint id regardless of sub dataset, or do we revert to showing all repository stats for items not in the live archive. As these stats can be cached before an item is moved to the live archive and there is no generic use case of showing all repository stats if a chosen eprint is not yet in the archive, the default is 'eprint' rather than 'archive'.
$c->{irstats2}->{eprint_dataset} = "eprint";

# by default, anyone can view the stats. Comment out to enable only users with the special '+irstats2/view' role to view stats.
push @{$c->{public_roles}}, "+irstats2/view";
push @{$c->{public_roles}}, "+irstats2/export";

# The method below is called by the /cgi/stats/* scripts which handle the delivery of stats
$c->{irstats2}->{allow} = sub {
        my( $session, $priv ) = @_;

	return 0 unless( defined $priv );

# Un-comment the following block if you want to restrict access to stats (e.g. to restricted users) BUT you still want some stats graphs
# to display on the summary pages
#
#	if( $session->get_online )
#	{
#		# Allow any requests coming from a summary page
#       	my $referer = EPrints::Apache::AnApache::header_in(
#                                        $session->get_request,
#                                        'Referer' );
#		if( defined $referer )
#		{
#			my $hostname = defined $session->config( 'host' ) ? $session->config( 'host' ) : $session->config( 'securehost' );
#			return 0 unless defined $hostname;
#
#			return 1 if( $referer =~ /^https?:\/\/$hostname\/\d+\/?$/ );
#		}
#	}

        return 1 if( $session->allow_anybody( $priv ) );
        return 0 if( !defined $session->current_user );
        return $session->current_user->allow( $priv );
};


# Specify a default time range if none are specified (by default, all the stats are returned).
#$c->{irstats2}->{default_range} = '1y';

# Local Domains for Referrers
# STRING => REGEX_PATTERN
# For example:
# $c->{irstats2}->{local_domains} = { "ECS Intranet" => "\\.ecs\\.soton\\.ac\\.uk", "University Intranet" => "\\.soton\\.ac\\.uk" };

#IPs additional to http://www.eprints.org/resource/bad_robots/robots_ip.txt to not include in stats
#$c->{irstats2}->{robots_ip} = [ ];

#UAs additional to http://www.eprints.org/resource/bad_robots/robots_ua.txt to not include in stats
#$c->{irstats2}->{robots_ua} = [ ];


# time-out for the so-called "double-click" filtering - default to 3600 secs = 1 hour
# Default setting - 3600 secs = 1 hour
# Current setting - 3600 * 24 = 24 hours
$c->{plugins}->{"Stats::Filter::Repeat"}->{params}->{timeout} = 3600 * 24;

# Prevents EPrints 3.2 from breaking. 
# Trigger is not implemented in earlier EPrints versions.
# '16' is from EPrints::Const::EP_TRIGGER_DYNAMIC_TEMPLATE
$EPrints::Plugin::Stats::EP_TRIGGER_DYNAMIC_TEMPLATE ||= 16;

# Trigger to load the Google Charts library from the template(s)
$c->add_trigger( $EPrints::Plugin::Stats::EP_TRIGGER_DYNAMIC_TEMPLATE, sub
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


# Hide the link to the reports by default:
$c->{plugins}->{"Screen::IRStats2::Report"}->{appears}->{key_tools} = undef;

##########
# Reports
##########


#
#	Reports definition
#
# Structure:
# $c->{irstats2}->{report} = {
#
#	$report_name => {
#		items => [
#		{
#			plugin => '$View_plugin_name',
#
#			# then pass extra optional arguments:
#			show_title => 0 or 1,
#			title_phrase => 'title_phrase_id',
#			custom_css => 'border:0px;font:12px;',
#
#			# then other arguments are Plugin-specific:
#
#			# for any data-related View plugin:
#			datatype => '$some_data_type',
#			datafilter => '$some_data_filter'
#			grouping => '$some_grouping'
#
#			# for Timeline:
#			ranges => [ '1m', '6m', '1y' ],		# Ranges to show in the <select>
#
#			# for SetsLookup:
#			sets => [ 'authors' ],			# the Sets handled by the Lookup feature
#		},
#		{ 
#			plugin => '$Another_View_plugin'
#			# ETC...
#		}
#		],
#		category => '$some_category',			# (optional) used by ReportHeader to gather Reports together. If not set, 
#								# it won't display that report in ReportHeader
#	},
#	$other_report_name => { ETC }
# }

$c->{irstats2}->{report} = {
	# the main Report page	
	main => {
		items => [ 
			{ plugin => 'ReportHeader' },
			{
				plugin => 'Google::Graph',
				datatype => 'downloads',
				options => {
					date_resolution => 'month',
					graph_type => 'column',
					show_average => 0
				},
			},
			{
				plugin => 'KeyFigures',
			},
			{
				plugin => 'Grid',
				options => { 
					items => [
						{
							plugin => 'Table',
							datatype => 'downloads',
							options => {
								limit => 5,
								top => 'eprint',
								title_phrase => 'top_downloads',
								#citestyle => 'default', # defaults to brief
							},
						},
						{
							plugin => 'Table',
							datatype => 'downloads',
							options => {
								limit => 5,
								top => 'authors',
								title_phrase => 'top_authors',
							}
						},
					]
				},
			},
		],
		category => 'general',
	},
	
	eprint => {
		items => [ 
		{ plugin => 'ReportHeader' },
		{ plugin => 'Google::Graph', 
			datatype => 'downloads',
			options => {
				date_resolution => 'month',
				graph_type => 'column',
			},
		 },
		{ plugin => 'KeyFigures',
			options => {
				metrics => [ 'downloads.spark', 'hits.spark' ],
		}
	
		 },
		]
	},

	authors => {
		items => [ 
			{ plugin => 'ReportHeader' },
			{
				plugin => 'Google::Graph', 
				datatype => 'downloads',
				options => {
					date_resolution => 'month',
					graph_type => 'column',
				},
			},
			{
				plugin => 'KeyFigures',
				options => {
					metrics => [ 'downloads.spark', 'hits.spark' ],
				}
			},
			{
				plugin => 'Table',
				datatype => 'downloads',
				options => {
					limit => 10,
					top => 'eprint',
					title_phrase => 'top_downloads',
					#citestyle => 'default', # defaults to brief
				},
			},
		]
	},

	# Other custom Reports	
	most_popular_eprints => {
		items => [
			{ plugin => 'ReportHeader' },
			{
				plugin => 'Table',
				datatype => 'downloads',
				options => {
					limit => 10,
					top => 'eprint',
					title_phrase => 'top_downloads',
					#citestyle => 'default', # defaults to brief
				},
			},
		],

		# can't show the most popular eprints if we're looking at an eprint
		appears => { set_name => [ '!eprint' ] },
		# appears => { set_name => [ '*' ] },
		# appears => { set_name => [ 'authors', 'divisions' ] },
		category => 'most_popular'
	},

	most_popular_authors => {
		items => [
			{ plugin => 'ReportHeader' },
			{
				plugin => 'Table',
				datatype => 'downloads',
				options => {
					top => 'authors',
					title_phrase => 'top_authors',
				}
			},
			{ plugin => 'KeyFigures', },
		],
		appears => { set_name => [ '!eprint', '!authors' ] },
		category => 'most_popular',
	},

#	most_popular_divisions => {
#		items => [
#			{ plugin => 'ReportHeader' },
#			{
#				plugin => 'Table',
#				datatype => 'downloads',
#				options => {
#					top => 'divisions',
#					title_phrase => 'title_phrase_id'
#				}
#			},
#		],
#		appears => { set_name => [ '!eprint', '!divisions' ] },
#		category => 'most_popular',
#	},

	deposits => {
		items => [
			{ plugin => 'ReportHeader' },
			{
				plugin => 'Google::Graph',
				datatype => 'deposits',
				datafilter => 'archive',
				options => {
					date_resolution => 'month',
					graph_type => 'column',
					show_average => 0
				}
			},
			{
				plugin => 'Grid',
				options => {
					items => [
						{
							plugin => 'Google::PieChart',
							datatype => 'deposits',
							datafilter => 'archive',
							options => {
								top => 'type',
								title_phrase => 'item_types'
							}
						},
						{
							plugin => 'Table',
							datatype => 'doc_format',
							options => {
								title_phrase => 'file_format',
								top => 'doc_format',
							}
						},
					]
				}
			},
		],
		category => 'advanced'
	},

	requests => {
		items => [
			{ plugin => 'ReportHeader' },
			{
				plugin => 'Google::GeoChart',
				datatype => 'countries',
				options => {
					title_phrase => 'download_countries',
				}
			},
			# if you'd rather see a table of countries, use this:
			#{
			#	plugin => 'Table',
			#	datatype => 'countries',
			#	options => { top => 'countries', title_phrase => 'download_countries' },
			#},
			{
				plugin => 'Grid',
				options => {
					items => [
						{
							plugin => 'Table',
							datatype => 'referrer',
							options => {
								title_phrase => 'top_referrers',
								top => 'referrer',
							}
						},
						{
							plugin => 'Table',
							datatype => 'browsers',
							options => {
								title_phrase => 'browsers',
								top => 'browsers',
							}
						},
					]	
				}
			},    # end of Grid
		],
		category => 'advanced',
	},

	compare_years => {
		items => [ 
			{ plugin => 'ReportHeader' },
			{ plugin => 'Compare' }, 
		],
		category => 'general',
	},

	summary_page => {
		items => [ 
			{ 
				plugin => 'Google::Graph',
				datatype => 'downloads',
				range => '1y',
				options => {
					date_resolution => 'month',
					graph_type => 'column',
					title_phrase => 'lib/irstats2:embedded:summary_page:eprint:downloads:year',
				}
			},
		],
	},
};

# Bazaar config

$c->{plugins}{"Stats::Context"}{params}{disable} = 0;
$c->{plugins}{"Stats::Data"}{params}{disable} = 0;
$c->{plugins}{"Stats::Export"}{params}{disable} = 0;
$c->{plugins}{"Stats::Handler"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor"}{params}{disable} = 0;
$c->{plugins}{"Stats::Sets"}{params}{disable} = 0;
$c->{plugins}{"Stats::Utils"}{params}{disable} = 0;
$c->{plugins}{"Stats::View"}{params}{disable} = 0;

$c->{plugins}{"Stats::Export::CSV"}{params}{disable} = 0;
$c->{plugins}{"Stats::Export::JSON"}{params}{disable} = 0;
$c->{plugins}{"Stats::Export::XML"}{params}{disable} = 0;

$c->{plugins}{"Stats::Filter::Robots"}{params}{disable} = 0;
$c->{plugins}{"Stats::Filter::Repeat"}{params}{disable} = 0;

$c->{plugins}{"Stats::Processor::Access"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor::Access::Browsers"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor::Access::Country"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor::Access::Downloads"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor::Access::Referrer"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor::Access::SearchTerms"}{params}{disable} = 0;

$c->{plugins}{"Stats::Processor::EPrint"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor::EPrint::Deposits"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor::EPrint::DocumentAccess"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor::EPrint::DocumentFormat"}{params}{disable} = 0;

$c->{plugins}{"Stats::Processor::History"}{params}{disable} = 0;
$c->{plugins}{"Stats::Processor::History::Actions"}{params}{disable} = 0;

$c->{plugins}{"Stats::View::Compare"}{params}{disable} = 0;
$c->{plugins}{"Stats::View::Counter"}{params}{disable} = 0;
$c->{plugins}{"Stats::View::Google::GeoChart"}{params}{disable} = 0;
$c->{plugins}{"Stats::View::Google::Graph"}{params}{disable} = 0;
$c->{plugins}{"Stats::View::Google::PieChart"}{params}{disable} = 0;
$c->{plugins}{"Stats::View::Google::Spark"}{params}{disable} = 0;
$c->{plugins}{"Stats::View::Grid"}{params}{disable} = 0;
$c->{plugins}{"Stats::View::KeyFigures"}{params}{disable} = 0;
$c->{plugins}{"Stats::View::ReportHeader"}{params}{disable} = 0;
$c->{plugins}{"Stats::View::Table"}{params}{disable} = 0;

$c->{plugins}{"Screen::IRStats2::Report"}{params}{disable} = 0;

# Display download stats for an eprint on it's summary page?
# Confusingly, set this to 0 to make them appear, or 1 to not show them.

$c->{plugins}{"Screen::EPrint::Box::Stats"}{params}{disable} = 1;

# Where on the summary page should they appear?
# Valid options are 'summary_left', 'summary_right', 'summary_bottom', 'summary_top'.
# The default is 'summary_bottom' - the following 2 lines demonstrate how to move it
# somewhere else

#$c->{plugins}{"Screen::EPrint::Box::Stats"}{appears}{summary_bottom} = undef;
#$c->{plugins}{"Screen::EPrint::Box::Stats"}{appears}{summary_right} = 1000;
