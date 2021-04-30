package EPrints::Plugin::Stats::Context;

our @ISA = qw/ EPrints::Plugin /;

use strict;
use EPrints::Plugin::Stats::Utils;

# sf2 - Represents the Context of a query, that is to say:
# - report
# - set
# - dates
# - data types and filters

my @FIELDS = (qw/
irs2report
set_name
set_value
from
to
range
datatype
datafilter
grouping
cache
/);

my %FIELDSMAP = map { $_ => 1 } @FIELDS;

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new( %params );

	$self->{handler} = $params{handler} if( defined $params{handler} );

	$self->parse_context( %params );

	return $self;
}

sub handler { shift->{handler} }

sub from_request
{
	my( $self ) = @_;

	my $session = $self->handler->{session};

	# reset our state:
	foreach(@FIELDS)
	{
		delete $self->{$_};
	}

	# Then check via URI
        my $uri = $session->get_uri();

	return $self unless defined $uri;

        # remove the trailing slash
        $uri =~ s/\/$//g;

	# remove double slashes
	$uri =~ s/\/\/+/\//g;

	# First check params in the URL	
	# /cgi/stats/report/report_name
	# /cgi/stats/report/set_name/set_value/report_name
	if( $uri =~ m#^/cgi/stats/report/?(.*)$# ) #
        {
                my @paths = split( /\//, $1 );
                if( scalar(@paths) == 1 )
                {
                        $self->{irs2report} = $paths[0];
                }
                elsif( scalar(@paths) > 1 )
                {
                        $self->{set_name} = $paths[0];
                        $self->{set_value} = $paths[1];
                        $self->{irs2report} = $paths[2] if( defined $paths[2] );

			if( !defined $self->{irs2report} && defined $session->config( 'irstats2', 'report', $self->{set_name} ) )
			{
				$self->{irs2report} = $self->{set_name};
			}
                }

		$self->{irs2report} = 'main' if( !defined $self->{irs2report} );
        }
	elsif( $uri =~ m#^/cgi/stats/export/?(.*)$# )
	{
                my @paths = split( /\//, $1 );
                if( scalar(@paths) == 1 )
                {
                        $self->{format} = $paths[0];
                        $self->{set_name} = $paths[0];
                }
                elsif( scalar(@paths) > 1 )
                {
                        $self->{set_name} = $paths[0];
                        $self->{set_value} = $paths[1];
                        $self->{format} = $paths[2] if( defined $paths[2] );
		}
	}

	# Then check URI parameters, priority over the rest
	foreach( $session->param() )
	{
		next if( !$FIELDSMAP{$_} ); 
		$self->{$_} = $self->validate_param( $_, $session->param( "$_" ) );
	}

	$self->parse_context();

	return $self;
}

sub current_report
{
	my( $self ) = @_;

	return $self->{irs2report} || 'main';
}

# adjust from/to dates given a date resolution ('day','month','year')
sub date_resolution
{
	my( $self, $date_res ) = @_;

	return if( !defined $date_res || $date_res eq 'day' );

	if( $date_res eq 'month' )
	{
		if( $self->{from} =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			$self->{from} = $1.$2.'01';
		}
		if( $self->{to} =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			$self->{to} = $1.$2.'01';
		}
	}
	elsif( $date_res eq 'year' )
	{
		if( $self->{from} =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			$self->{from} = $1.'0101';
		}
		if( $self->{to} =~ /^(\d{4})(\d{2})(\d{2})$/ )
		{
			$self->{to} = $1.'1231';
		}
	}
}

sub default_range
{
	my( $self ) = @_;

	return $self->{session}->config( 'irstats2', 'default_range' ) if( defined $self->{session} );

	return '_ALL_';
}

sub forever
{
	my( $self ) = @_;
	$self->dates( { range => '_ALL_' } );
	$self->parse_context;
	return $self;
}

sub base_url
{
	my( $self ) = @_;

	return $self->handler->{session}->config( 'http_cgiurl' ).'/stats/report';
}

# so why doesn't this also include the set? and the range/ from-to dates?
sub current_url
{
	my( $self, %includes ) = @_;

	if( !EPrints::Utils::is_set( %includes ) )
	{
		return $self->base_url;
	}

        my $report = $self->{irs2report} || "";

	my $url = $self->handler->{session}->config( 'http_cgiurl' ).'/stats/report';

	# the 'main' report is the default 
	if( defined $report && $report ne 'main' )
	{
		$url .= "/$report";
	} 

	return $url;
}

sub parse_context
{
	my( $self, %params ) = @_;

	if( EPrints::Utils::is_set( %params ) )
	{
		foreach(@FIELDS)
		{
			next if( !defined $params{$_} );
			$self->{$_} = $params{$_};
		}
	}

	if( !defined $self->{from} && !defined $self->{to} && !defined $self->{range} )
	{
		# use default range in this case
		$self->{range} = $self->default_range;
	}

	( $self->{from}, $self->{to} ) = EPrints::Plugin::Stats::Utils::normalise_dates( $self );
}

sub fields
{
	return \@FIELDS;
}

# if called without $dates -> return current dates
# if called with $dates -> set values
sub dates
{
	my( $self, $dates ) = @_;

	if( !defined $dates )
	{
		return { from => $self->{from}, to => $self->{to}, range => $self->{range} };
	}

	foreach( 'from', 'to', 'range' )
	{
		next if( !exists $dates->{$_});
		$self->{$_} = $dates->{$_};
	}
	$self->parse_context();
}

# same as above for the behaviour, but with sets
sub set
{
	my( $self, $set ) = @_;

	if( !defined $set )
	{
		return { set_name => $self->{set_name}, set_value => $self->{set_value } }
	}

	foreach( 'set_name', 'set_value' )
	{
		$self->{$_} = $set->{$_};
	}

	return $self;
}

sub has_valid_set
{
	my( $self ) = @_;

	my $set = $self->set;

	if( defined $set->{set_name} && defined $set->{set_value} )
	{
		return $self->handler->valid_set_value( $set->{set_name}, $set->{set_value} );
	}
	elsif( defined $set->{set_name} )
	{
		return $self->handler->sets->set_exists( $set->{set_name} );
	}

	# no set defined so it's valid
	return 1;
}

sub get_property
{
	my( $self, $name ) = @_;

	return $self->{$name};
}

# set / reset a value
sub set_property
{
	my( $self, $name, $value ) = @_;

	return unless( exists $FIELDSMAP{$name} );
	
	if( EPrints::Utils::is_set( $value ) )
	{
		$self->{$name} = $value;
	}
	else
	{
		delete $self->{$name};
	}
}

sub clone
{
	my( $self ) = @_;

	my %o;
	for( @FIELDS )
	{
		$o{$_} = $self->{$_};
	}
	$o{handler} = $self->handler;

	return __PACKAGE__->new( %o );
}

sub to_json
{
	my( $self ) = @_;

	my @json;
	foreach( @FIELDS )
	{
		next unless( defined $self->{$_} );
		my $value = $self->{$_};
		$value =~ s/'/\\'/g;
		push @json, "'$_': '$value'";
	}

	return "{".join(", ", @json)."}";
}

sub to_hash
{
	my( $self ) = @_;

	my %h;
	foreach( @FIELDS )
	{
		$h{$_} = $self->{$_};
	}

	return \%h;
}

sub render_hidden_bits
{
	my( $self, $extra_params ) = @_;

	my $session = $self->handler->{session};
	my $frag = $session->make_doc_fragment;

	my $hcontext = $self->to_hash;
	foreach my $k ( keys %$hcontext )
	{
		my $v = $hcontext->{$k};
		next if( !EPrints::Utils::is_set( $v ) );
		$frag->appendChild( $session->make_element( 'input', type => 'hidden', name => "$k", value => "$v" ) );
	}

	foreach my $k ( %{$extra_params || {}} )
        {
		my $v = $extra_params->{$k};
                next if( ref( $v ) =~ /::/ );   # don't include code/objects :-)
                next if( !EPrints::Utils::is_set( $v ) );
		$frag->appendChild( $session->make_element( 'input', type => 'hidden', name => "$k", value => "$v" ) );
        }

	return $frag;
}

# TODO URL escape
sub to_form_params
{
	my( $self, $extra_params ) = @_;

        my @tmp;
	my $hcontext = $self->to_hash;
	foreach my $k ( keys %$hcontext )
	{
		my $v = $hcontext->{$k};
		next if( !EPrints::Utils::is_set( $v ) );
		push @tmp, "$k=$v";
	}

	foreach my $k ( %{$extra_params || {}} )
        {
		my $v = $extra_params->{$k};
                next if( ref( $v ) =~ /::/ );   # don't include code/objects :-)
                next if( !EPrints::Utils::is_set( $v ) );
                push @tmp, "$k=$v";
        }

        return join( "&", @tmp );
}

# for debugging
sub to_string
{
	my( $self ) = @_;

	my $h = $self->to_hash;
	my $s="";
	foreach my $k ( keys %$h )
	{
		my $v = $h->{$k};
		$s .= "$k => $v ; ";
	}
	return $s;
}

# creates a data object from a context
sub data
{
	my( $self ) = @_;
	return $self->handler->data( $self );
}

# select() actually belongs to Stats::Data but it's a nice shortcut here
sub select
{
	my( $self, @params ) = @_;
	return $self->data( $self )->select( @params );
}

sub validate_param
{
	my( $self, $field, $value ) = @_;

	# Not sure if IRStats understands undef and '' to be the same.
	# Being cautious
	return $value if !defined $value || $value eq '';

	my $validation_method = "_validate_field_$field";

	# use a config/data aware validation method if there is one
	if( $self->can( $validation_method ) )
	{
		$value = $self->$validation_method( $value );
	}
	else
	{
		# Strip possibly bad characters. 
		# See: https://github.com/eprints/irstats2/issues/95 
		$value =~ s/[<>\/\\;=\&\?\%\'[:cntrl:]]//gm;
	}

	$self->repository->log( "IRStats: bad param removed from $field : ". $_[2] ) if !defined $value;

	return $value;
}

sub _validate_field_set_name
{
	my( $self, $v ) = @_;

	if( $self->handler->sets->set_exists( $v ) )
	{
		return $v;
	}
	elsif( $v =~ m/^([\w\-]*)$/ )
	{
		return $1;
	}

	return;
}

# NB duplication with has_valid_set.
sub _validate_field_set_value
{
	my( $self, $v ) = @_;

	# if set name has already been set/validated
	if( defined $self->{set_name} )
	{
		return $v if $self->handler->valid_set_value( $self->{set_name}, $v );
	}
	elsif( $v =~ m/^([\w\.-]*)$/ )
	{
		return $1;
	}
	# otherwise...?
	return;
}

sub _validate_field_from { &_validate_field_date }
sub _validate_field_to   { &_validate_field_date }
sub _validate_field_date
{
	my( $self, $v ) = @_;

	# YYYY, YYYYMM, YYYYMMDD ({2,4} == 4, 6 or 8 digits)
	if( $v =~ m/^((?:\d{2}){2,4})$/ )
	{
		return $1;
	}
	elsif( $v =~ m#^(\d{2})[/-](\d{2})[/-](\d{4})$# )
	{
		#DD-MM-YYYY, DD/MM/YYYY
		return $3.$2.$1;
	}
	elsif( $v =~ m#^(\d{4})[/-](\d{2})[/-](\d{2})$# )
	{
		#YYYY-MM-DD, YYYY/MM/DD
		return $1.$2.$3;
	}
	elsif( $v =~ #^(\d{4})[/-](\d{2})$# ) 
	{
		#YYYY-MM, YYYY/MM
		return $1.$2;
	}

	return; #undef
}

sub _validate_field_range
{
	my( $self, $v ) = @_;

	# can be a year, a period (e.g. '6m' (six months)) or everything.
	if( $v =~ /^(\d{4}|\d+[dmy]|_ALL_)$/i )
	{
		return $1;
	}

	return; #undef
}

sub _validate_field_datatype
{
	my( $self, $v ) = @_;

	return $v if defined $self->handler->get_processor( $v );

	return; #undef
}

# NB the following are not specifically defined, so the warpping method will sanitise the input
# sub _validate_field_datafilter
# sub _validate_field_grouping

1;
