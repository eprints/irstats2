# IRStats2 configuration file

$c->{irstats2} = {};

##################
# Data Processing
##################

# list of (EPrints) datasets to process:
$c->{irstats2}->{datasets} = {

	eprint => { incremental => 0 },
	
	access => { filters => [ 'Robots', 'Repeat'] },

	history => { incremental => 1 },

#	user => { incremental => 0 },
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
		'groupings' => [ 'authors' ]
	},
	{ 
		'field' => 'subjects', 
		'groupings' => [ 'authors' ]
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
#			my $hostname = $session->config( 'host' ) or return 0;
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

# time-out for the so-called "double-click" filtering - default to 3600 secs = 1 hour
$c->{plugins}->{"Stats::Filter::Repeat"}->{params}->{timeout} = 3600 * 24;

# prevents EPrints 3.2 from breaking (because that trigger isn't implemented in that versin of EPrints)
# the value '16' comes from EPrints::Const::EP_TRIGGER_DYNAMIC_TEMPLATE
$EPrints::Plugin::Stats::EP_TRIGGER_DYNAMIC_TEMPLATE ||= 16;

# Trigger to load the Google Charts library from the template(s)
$c->add_trigger( $EPrints::Plugin::Stats::EP_TRIGGER_DYNAMIC_TEMPLATE, sub
{
        my( %args ) = @_;

        my( $repo, $pins ) = @args{qw/ repository pins/};

        my $protocol = $repo->get_secure ? 'https':'http';

        my $head = $repo->make_doc_fragment;

        $head->appendChild( $repo->make_javascript( undef,
                src => "$protocol://www.google.com/jsapi"
        ) );

        $head->appendChild( $repo->make_javascript( 'google.load("visualization", "1", {packages:["corechart", "geochart"]});' ) );

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
#			title => 'My Custom Title',
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
				show_average => 1
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
			] },
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
#
#		items => [
#		{ plugin => 'ReportHeader' },
#		{
#			plugin => 'Table',
#			datatype => 'downloads',
#			options => {
#				top => 'divisions',
#				title => 'Top Schools'
#			}
#		},
#		],
#		appears => { set_name => [ '!eprint', '!divisions' ] },
#
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
				show_average => 1
			}
		},
		{
			plugin => 'Grid', options => { items => [

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

		] } },
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
		#	options => { top => 'countries', title => 'Countries' },
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
		} },    # end of Grid

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
		{ plugin => 'Google::Graph', datatype => 'downloads', range => '1y', options => { date_resolution => 'month', graph_type => 'column', title => 'Downloads per month over past year' } },
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
#MM 04/05/2017 - New filter for IP addresses
$c->{plugins}{"Stats::Filter::LocalIP"}{params}{disable} = 0;


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

# Display download stats for an EPrints on it's summary page?
# Confusingly, set this to '0' to make them appear, or 1 to not show them
$c->{plugins}{"Screen::EPrint::Box::Stats"}{params}{disable} = 1;
# Where on the summary page should they appear?
# Valid options are 'summary_left', 'summary_right', 'summary_bottom', 'summary_top'.
# The default is 'summary_bottom' - the following 2 lines demonstrate how to move it
# somewhere else
#$c->{plugins}{"Screen::EPrint::Box::Stats"}{appears}{summary_bottom} = undef;
#$c->{plugins}{"Screen::EPrint::Box::Stats"}{appears}{summary_right} = 1000;
