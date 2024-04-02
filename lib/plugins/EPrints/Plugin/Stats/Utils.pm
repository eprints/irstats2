package EPrints::Plugin::Stats::Utils;

our @ISA = qw/ EPrints::Plugin /;

use strict;
use Date::Calc;

# Stats::Utils
#
# Provides a few useful methods for the Stats package, mostly around the handling of dates.

# return the url to the main stats report page
sub base_url
{
	my( $session ) = @_;
	
	return $session->config( 'perl_url' ).'/stats/report';
}

############################
#
# Validate parameters from Apache request meet expected patterns/values.
# Returns 'true' if the value is sensible for the parameter e.g.
#  - 'limit' is numeric or "all"
#  - 'container_id
# 
# This is used by cgi scripts e.g. cgi/stats/get
#
# These validations are additional to 'context' parameter handling which
# is dealt with in EPrints::Plugins::Stats::Context.
#
#  Expected non-context params:
#  - base_url
#  - date_resolution
#  - container_id
#  - export
#  - graph_type
#  - limit
#  - q (set_finder)
#  - referer (possibly deprecated - browse-view stats?)
#  - show_average
#  - title_phrase
#  - top
#  - view
#
# Note: the cgi script is still responsible for reading params
#
############################

sub validate_non_context_param
{
	my( $session, $k, $v ) = @_;

	if( $k eq 'limit' )
	{
		return $v =~ /^\d+|all$/;
	}
	elsif( $k eq 'date_resolution' )
	{
		return $v =~ /^day|month|year$/;
	}
	elsif( $k eq 'graph_type' )
	{
		return $v =~ /^area|column$/;
	}
	elsif( $k eq 'cumulative' )
	{
		return $v =~ /^true|false$/;
	}
	elsif( $k eq 'show_average' )
	{
		return $v =~ /^true|false$/;
	}
	elsif( $k eq 'title' )
	{
		return $v;
	}
	elsif( $k eq 'title_phrase' )
	{
		return $session->get_lang->has_phrase( $v );
	}
	elsif( $k eq 'q' )
	{
		#anything sensible for a set-lookup query?
		# https://perldoc.perl.org/perlrecharclass#Bracketed-Character-Classes
		return $v =~ /^[[:print:]]+$/;
	}
	elsif( $k =~ /^export|top|view|container_id$/ )
	{
		return $v =~ /^[\w\.\-\:]+$/; #NB \w includes underscore, digit
	}
	elsif( $k =~ 'base_url' )
	{
		my $base_url = base_url( $session );
		return $v =~ m!^$base_url/?\w+$!;
	}
	elsif( $k =~ 'referer' )
	{
		# this appear not to be used. Log param usage as it is unexpected.
		$session->log( "IRStats2 (Utils validate_non_context_params): unexpected use of URL parameter: $k (value: $v)." );
	}

	# an unexpected URL parameter. Get rid!
	$session->log( "IRStats2 (Utils validate_non_context_params): unexpected URL parameter: $k (value: $v) has been ignored." );

	# NB No default return value
	return;
}




############################
#
# Dates formatting methods
#
############################

# 
# On the interface / JS, it's possible to combine the following way of representing a date:
#
# with a range: $daterange->{range} = '12m' # the last 12 months
# with explicit from/to dates: $daterange->{from} = '20110101', $daterange->{to} = '20110701' # from 1st Jan 2011 to 1st July 2011
#
# it is also possible to combine the two styles
#
# However when used for fetching data from the Database, only the form YYYYMMDD is valid, because this is how they are representated in the DB (they're effectively stored as INT values,
# as they are quicker to select/filter than strings). See Handler.pm for more details.
#



# returns an array of dates, given a range, as used on the Graph plotter
# this is to force having all the dates defined for a given range (even so there's no data)
# date_resolution = one of 'day' [default], 'month' or 'year' > expresses the grouping
# to = optional, default to YESTERDAY
sub get_dates
{
	my( $from, $to, $date_resolution ) = @_;

	return [] unless( defined $from );

	if( !defined $to )
	{
		my( $to_y, $to_m, $to_d ) = Date::Calc::Add_Delta_YMD( Date::Calc::Today(), 0, 0, -1 );
		$to = $to_y * 10000 + $to_m * 100 + $to_d;
	}

	# safety
	return [] if( $from > $to );


# depending on date_resolution:
# - 'day': returns stacks of valid days: 01-01-2001, 02-01-2001 etc
# - 'month': return stacks of valid months: 01-2001, 02-2001 etc
# - 'year': return stacks of valid years: 2001, 2002 etc
#
# note that only grouping per 'day' is tricky (we then need to use Date::Calc to make sure of leap years etc)
# 

	my @sections;

	if( $date_resolution eq 'year' )
	{
		$from = substr( $from, 0 , 4);
		$to = substr( $to, 0, 4);
		my $start = $from;
		for( $from .. $to )
		{
			push @sections, $start++;
		}
	}
	elsif( $date_resolution eq 'month' )
	{
		$from =~ /^(\d{4})(\d{2})/;
		my( $from_y, $from_m ) = ( $1, $2 );
		
		$to =~ /^(\d{4})(\d{2})/;
		my( $to_y, $to_m ) = ( $1, $2 );
		for( my $y = $from_y; $y <= $to_y; $y++ )
		{
			for( my $m = ($y == $from_y ? $from_m : 1); $m <= ( $y == $to_y ? $to_m : 12 ); $m++ )
			{
				push @sections, sprintf( "%04d%02d", $y, $m );
			}
		}
	}
	elsif( $date_resolution eq 'day' )
	{
		$from =~ /^(\d{4})(\d{2})(\d{2})$/;

		my( $cur_y, $cur_m, $cur_d ) = ( $1, $2, $3 );

		# something went wrong... better not carry on into the while(1) loop :-)
		return [] if( !defined $cur_y || !defined $cur_m || !defined $cur_d );

		my $fdate = $from;

		while( $fdate <= $to )
		{
			push @sections, $fdate;

			my( $y, $m, $d ) = Date::Calc::Add_Delta_YMD( $cur_y, $cur_m, $cur_d, 0, 0, 1 );

			$fdate = $y*10000 + $m*100 + $d;

			( $cur_y, $cur_m, $cur_d ) = ( $y, $m, $d );
		}
	}

	return \@sections;
       
}

# turns a range string (eg '1m') into a [ year, month, day ] (eg [0,-1,0] as used by Date::Calc)
sub range_to_offset
{
	my( $range ) = @_;

	if( defined $range && $range ne '_ALL_' && $range =~ /^(\d+)([dmy])$/ )
	{
		return [0,0,(-1*$1)] if( $2 eq 'd' );
		return [0,(-1*$1),0] if( $2 eq 'm' );
		if( $2 eq 'y' )
		{
			# let's max this up to -20y (no point in requesting stats data before the invention of the web!)
			my $y = $1 > 20 ? 20 : $1;
			return [(-1*$y),0,0] 
		}
	}

	print STDERR "Stats::Utils::range_to_offset: unknown range '$range'\n";
	
	return [0,0,0];

}


# given a context object, returns 
sub normalise_dates
{
	my( $context ) = @_;

	my( $range, $from, $to ) = @{$context->dates}{qw/ range from to /};

	# normalise from/to formats (accept YYYYMMDD, YYYY/MM/DD and YYYY-MM-DD) to YYYYMMDD

	if( defined $from )
	{
		if( $from =~ m#^(\d{4})[/-]?(\d{2})[/-]?(\d{2})$# )
		{
			$from = "$1$2$3";
		}
		elsif( $from =~ m#^(\d{4})[/-]?(\d{2})$# )
		{
			$from = "$1$2" . "01";
		}
		elsif( $from =~ m#^(\d{4})$# )
		{
			$from = $1."0101";
		}
	}
	
	if( defined $to )
	{
		if( $to =~ m#^(\d{4})[/-]?(\d{2})[/-]?(\d{2})$# )
		{
			$to = "$1$2$3";
		}
		elsif( $to =~ m#^(\d{4})[/-]?(\d{2})$# )
		{
			$to = "$1$2" . Date::Calc::Days_in_Month($1,$2);
		}
		elsif( $to =~ m#^(\d{4})$# )
		{
			$to = $1."1231";
		}
	}

	# 'range' has priority over from/to being defined
	if( EPrints::Utils::is_set( $range ) )
	{
		if( $range eq '_ALL_' )
		{
			# no date conditions as such - perhaps to = TODAY/YESTERDAY from=first record in data
			return( undef, undef );
		}
		elsif( $range =~ /^(\d{4})$/ )
		{
			# $range = a year e.g. 2012
			return	( $1."0101", $1."1231" );
		}

		my( $to_y, $to_m, $to_d );

		# if 'range' is defined and we have a upper limit (use YESTERDAY if not)
                if( defined $to && $to =~ /^(\d{4})(\d{2})(\d{2})$/ )
                {
                        ($to_y,$to_m,$to_d) = ($1,$2,$3);
                }
                else
                {
			# to = YESTERDAY
                        ($to_y, $to_m, $to_d) = Date::Calc::Add_Delta_YMD( Date::Calc::Today(), 0, 0, -1 );
                        $to = $to_y * 10000 + $to_m * 100 + $to_d;
                }

        	my ($from_y, $from_m, $from_d ) = Date::Calc::Add_Delta_YMD( $to_y, $to_m, $to_d, @{&range_to_offset($range)} );
		$from = $from_y * 10000 + $from_m * 100 + $from_d;

		return( $from, $to );
	}
		
	# implicit 'else'
	if( defined $from )
	{
		if( defined $to )
		{
			return( $from, $to );
		}
	
		my( $to_y, $to_m, $to_d ) = Date::Calc::Add_Delta_YMD( Date::Calc::Today(), 0, 0, -1 );
		$to = $to_y * 10000 + $to_m * 100 + $to_d;
		
		return( $from, $to );
	}
	
	return( $from, $to );
}


#####################
#
# Rendering methods
#
#####################

# turns a number eg. 1234567 into a more human-readable form: 1,234,567
sub human_display
{
        my( $repo, $data ) = @_;
        
	my $display = $data || 0;
	return $display if( $display lt 1000 );

	my $decimal;
	if( $repo->get_lang->has_phrase( "lib/irstats2/decimal_separator" ) )
	{
		$decimal = $repo->phrase( "lib/irstats2/decimal_separator" );
	}
	$decimal ||= ",";	# in English

        if( $data =~ /^\d+$/ )
        {
                my $d = $data;
                my $human = "";
                while( $d =~ s/(\d{3})$// )
                {
                        $human = ( $d ? "$decimal"."$1" : "$1" ).$human;
                }

                $human = $d.$human if( $d );
                $display = $human;
        }
        
	return $display;
}

# code duplication in here (with normalise_dates())
sub render_date
{
	my( $session, $context ) = @_;
	
	my $frag = $session->make_doc_fragment;

	if( EPrints::Utils::is_set( $context->{range} ) && $context->{range} eq '_ALL_' )
	{
		$frag->appendChild( $session->html_phrase( "lib/irstats2/dates:forever" ) );
		return $frag;
	}

	if( EPrints::Utils::is_set( $context->{range} ) )
	{
		if( $context->{range} =~ /^(\d{4})$/ )
		{
			return $session->make_text( "$1" );
		}
		if( $context->{range} =~ /^(\d+)([ymd])$/ )
		{
			my $granularity = ( $1 > 1 ) ? $session->html_phrase( "lib/irstats2/dates:granularity:plural:$2" ) : $session->html_phrase( "lib/irstats2/dates:granularity:$2" );

			# limit to -20years
			my $value;
			if( $2 eq 'y' && $1 > 20 )
			{
				$value = $session->make_text( '20' );
			}
			else
			{
				$value = ( $1 > 1 ) ? $session->make_text( "$1" ) : $session->make_doc_fragment;
			}
			$frag->appendChild( $session->html_phrase( 'lib/irstats2/dates:range', 
						value => $value, 
						granularity => $granularity 
			) );
		}
		else
		{
			$frag->appendChild( $session->html_phrase( 'lib/irstats2/dates:invalid_range' ) );
		}
	}
	elsif( defined $context->{from} )
	{
		if( $context->{from} =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			my $day = sprintf( "%01d", $3 );
			my $month = sprintf( "%02d", $2 );
			$frag->appendChild( $session->html_phrase( "lib/utils:month_short_$month" ) );
			$frag->appendChild( $session->make_text( " $day," ) );
			$frag->appendChild( $session->make_text( " $1" ) );
		
			if( defined $context->{to} && $context->{to} =~ /^(\d{4})(\d{2})(\d{2})$/ && $context->{to} > $context->{from} )
			{
				$frag->appendChild( $session->html_phrase( 'lib/irstats2/dates:join_dates' ) );
				my $day = sprintf( "%01d", $3 );
				my $month = sprintf( "%02d", $2 );
				$frag->appendChild( $session->html_phrase( "lib/utils:month_short_$month" ) );
				$frag->appendChild( $session->make_text( " $day," ) );
				$frag->appendChild( $session->make_text( " $1" ) );
			}
			elsif( !defined $context->{to} )
			{
				# up to today then...
				my ($to_y, $to_m, $to_d) = Date::Calc::Today();
				$frag->appendChild( $session->html_phrase( 'lib/irstats2/dates:join_dates' ) );
				my $day = sprintf( "%01d", $to_d );
				my $month = sprintf( "%02d", $to_m );
				$frag->appendChild( $session->html_phrase( "lib/utils:month_short_$month" ) );
				$frag->appendChild( $session->make_text( " $day," ) );
				$frag->appendChild( $session->make_text( " $to_y" ) );
			}
		}
		else
		{
			$frag->appendChild( $session->html_phrase( 'lib/irstats2/dates:invalid_range' ) );
		}
	}
	else
	{
		$frag->appendChild( $session->html_phrase( 'lib/irstats2/dates:unknown' ) );
	}

	return $frag;

}

# <epp:phrase id="lib/utils:month_short_01">Jan</epp:phrase>
# <epp:phrase id="lib/utils:month_03">March</epp:phrase>
sub get_month_labels
{
	my( $session, $short ) = @_;

	$short ||= 1;

	my $prefix = $short ? 'lib/utils:month_short_' : 'lib/utils:month_';

	my @labels;
	for( "01".."12" )
	{
		push @labels, $session->phrase( $prefix.$_ );
	}

	return \@labels;
}

##########
#
# Parsing 
# The following two methods are used in
# - EPrints::Plugin::Stats::Processor::Access::Referer
# - EPrints::Plugin::Stats::Processor::Access::SearchTerms
#
# They are *not* used for parsing parameters used in cgi scripts
#
##########

# given a URL, returns ($protocol, $hostname, $uri)
sub parse_url
{
        my $r = shift;

        if( $r =~ /^\d+$/ )
        {
                return( 'http', 'localhost', "/$r" );
        }

	unless( $r =~ /:/ )
	{
		# no protocol delimiter, let's force it to http:// (otherwise the following regex will fail)
		$r = "http://$r";
	}

	$r =~ s/\r?\n//g;
        $r =~ m#^([^\..]*):/?/?([a-z0-9\.\-]*):?(/?.*)$#;       #

        return( $1, $2, $3 );
}

# returns a given param in $uri
sub get_param
{
        my( $uri, $p ) = @_;

        if( $uri =~ /$p=([^&\.]*)/ )
        {
                return $1;
        }

        return undef;
}

1;
