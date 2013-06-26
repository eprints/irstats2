package EPrints::Plugin::Stats::Utils;

our @ISA = qw/ EPrints::Plugin /;

use strict;
use Date::Calc;

# Stats::Utils
#
# Provides a few useful methods for the Stats package, mostly around the handling of dates.

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
sub get_dates
{
	my( $handler, $context ) = @_;

	my( $from, $to ) = EPrints::Plugin::Stats::Utils::normalise_dates( $handler, $context );

	return [] unless( defined $from && defined $to );
        
	my ($to_y, $to_m, $to_d);
        my ($from_y, $from_m, $from_d );

	# safety mechanim
	if( $from !~ /^\d{4}\d{2}\d{2}$/ || $to !~ /^\d{4}\d{2}\d{2}$/ || $from >= $to )
	{
		# inconsitent request
		return [];
	}
	else
	{
		$from =~ /^(\d{4})(\d{2})(\d{2})$/;
		($from_y, $from_m, $from_d) = ($1,$2,$3);
		
		$to =~ /^(\d{4})(\d{2})(\d{2})$/;
		($to_y, $to_m, $to_d) = ($1,$2,$3);
	}
	
	my @dates;
	push @dates, $to;

	my( $cur_y, $cur_m, $cur_d ) = ( $to_y, $to_m, $to_d );

	while(1)
	{
		my( $y, $m, $d ) = Date::Calc::Add_Delta_YMD( $cur_y, $cur_m, $cur_d, 0, 0, -1 );

		my $fdate = $y*10000 + $m*100 + $d;

		last if( $fdate < $from );

		push @dates, $fdate;

		( $cur_y, $cur_m, $cur_d ) = ( $y, $m, $d );

	}

	# TODO try to compute the @dates in the right order above so the 'reverse' (below) can be removed? 
	my @rdates = reverse @dates;
	return \@rdates;
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

# Turns a {daterange} structure into a valid (from, to) dates
# {daterange}->{range} may be defined eg. '1m' to mean last month
# {daterange}->{from} may be defined to signal the lower limit of the date range
# {daterange}->{to} may be defined to signal the upper limit of the date range
#
# a combinaison of the 3 above might be used hence the parsing/validation below
#
# N.B.: Add_Delta_YMD( Today(), 0, 0, -1 ) returns Yesterday - The reason is that we cannot show stats for "today" as they - very likely - haven't been processed yet (so it would
# always shows a graph going down, not good for spark lines)
sub normalise_dates
{
	my( $handler, $context ) = @_;
        
	my $daterange = {
		range => $context->{range},
		from => $context->{from},
		to => $context->{to},
	};

	my ($to_y, $to_m, $to_d);
        my ($from_y, $from_m, $from_d );
	my ($to, $from);

	if( defined $daterange->{range} && $daterange->{range} eq '_ALL_' )
	{
		delete $daterange->{range};

		($to_y, $to_m, $to_d) = Date::Calc::Add_Delta_YMD( Date::Calc::Today(), 0, 0, -1 );
		$to = $to_y * 10000 + $to_m * 100 + $to_d;

		return( '19000101', $to );
	}
	
	if( EPrints::Utils::is_set( $daterange->{range} ) )
	{
		if( $daterange->{range} =~ /^(\d{4})$/ )
		{
			return	( $1."0101", $1."1231" );
		}
                if( defined $daterange->{to} && $daterange->{to} =~ /^(\d{4})(\d{2})(\d{2})$/ )
                {
                        $to = $daterange->{to};
                        ($to_y,$to_m,$to_d) = ($1,$2,$3);
                }
                else
                {
                        ($to_y, $to_m, $to_d) = Date::Calc::Add_Delta_YMD( Date::Calc::Today(), 0, 0, -1 );
                        $to = $to_y * 10000 + $to_m * 100 + $to_d;
                }
        	($from_y, $from_m, $from_d ) = Date::Calc::Add_Delta_YMD( $to_y, $to_m, $to_d, @{&range_to_offset($daterange->{range})} );
		$from = $from_y * 10000 + $from_m * 100 + $from_d;
	}
	elsif( defined $daterange->{from} )
	{
		if( defined $daterange->{to} && $daterange->{to} =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			$to = $daterange->{to};
			($to_y,$to_m,$to_d) = ($1,$2,$3);
		}
		else
		{
			($to_y, $to_m, $to_d) = Date::Calc::Add_Delta_YMD( Date::Calc::Today(), 0, 0, -1 );
			$to = $to_y * 10000 + $to_m * 100 + $to_d;
		}

		$from = $daterange->{from};
	}

	if( !defined $from || !defined $to )
	{
		return undef;
	}

        if( $from !~ /^(\d{4})(\d{2})(\d{2})$/ || $to !~ /^(\d{4})(\d{2})(\d{2})$/ || $from >= $to )
        {
                # inconsitent request
                return undef;
	}
	return ( $from, $to );
}

#####################
#
# Rendering methods
#
#####################

# turns a number eg. 1234567 into a more human-readable form: 1,234,567
sub human_display
{
        my( $data ) = @_;
        
	my $display = $data || 0;
	return $display if( $display lt 1000 );

        if( $data =~ /^\d+$/ )
        {
                my $d = $data;
                my $human = "";
                while( $d =~ s/(\d{3})$// )
                {
                        $human = ( $d ? ",$1" : "$1" ).$human;
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
		
			if( defined $context->{to} && $context->{to} =~ /^(\d{4})(\d{2})(\d{2})$/ )
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
