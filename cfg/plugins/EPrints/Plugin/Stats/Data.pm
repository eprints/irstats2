package EPrints::Plugin::Stats::Data;

our @ISA = qw/ EPrints::Plugin /;

use strict;

# Stats::Data
#
# Abstraction of data retrieval from the database. Typically used by View plugins to get their data. 
#
# This also renders objects which are retrieved from the DB which is a tricky operation (see Data::render_objects below)
#

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new( %params );

	$self->{handler} = $params{handler};
	$self->{context} = $params{context};	# || {};

	$self->{data} = $params{data} || [];

	if( defined $self->context && defined $self->context->{datatype} )
	{
		$self->{processor} = $self->handler->get_processor( $self->context->{datatype} );
	}

	$self->{conf} = {};

	return $self;
}

# default configuration to select data. Processor plugins will over-ride this if necessary (esp. to tell which fields/columns to 
#  select from the DB)
sub defaults
{
	shift->{conf} = {
		type => 'sum',
		order_desc => 1,
		fields => [],
	};
}

# This merges some local configuration options with the Processor plugin configuration.
# For example, a Processor plugin knows how to render its data (Country -> phrase (with flags), Referrer -> string...) while Data is unaware of this
sub parse_conf
{
	my( $self, $conf ) = @_;

	if( EPrints::Utils::is_set( $conf ) && ref( $conf ) eq 'HASH' )
	{
		$self->{conf} = $conf;
	}
	else
	{
		$self->defaults();
	}

	if( defined $self->processor )
	{
		my $proc_conf = $self->processor->conf();

		foreach my $key ( keys %$proc_conf )
		{
			my $value = $proc_conf->{$key};
			$self->{conf}->{$key} = $value;
		}
	}
		
	my %fields = map { $_ => 1 } @{$self->fields() || [] };

	if( defined $conf->{order_by} && !$fields{$conf->{order_by}} )
	{
		# error, asked to ORDER BY a field that's not selected!
		$self->handler->log( "Stats::Data: cannot order by $conf->{order_by} without selecting that field.", 1 );
	}

	$self->conf->{render_dates} ||= 0;
	$self->conf->{do_render} ||= 0;
}

# a few helper methods:
sub context { shift->{context} }
sub conf { shift->{conf} }
sub handler { shift->{handler} }
sub processor { shift->{processor} }
sub data { return shift->{data} || [] }
sub count { return scalar( @{shift->data} ) }

sub fields
{
	my( $self ) = @_;

	my @fields = @{$self->conf->{fields} || [] };

	# the 'count' field is always selected
	push @fields, 'count';

	return \@fields;
}


# check if the field is in the configuration i.e. if it'll be select'ed from the DB.
sub has_field
{
	my( $self, $fn ) = @_;

	my %fields = map { $_ => 1 } @{$self->fields() || [] };

	return exists $fields{$fn} ? 1 : 0;
}

# main method: this will select the data from the DB (via Stats::Handler) and optionally fix things (e.g. missing dates)
#  and render objects (when the View plugin requires this)
sub select
{
	my( $self, %conf ) = @_;

	# parses the local conf, and merge the Processor's conf
	$self->parse_conf( \%conf );

	my( $context, $handler ) = ( $self->context, $self->handler );

        my $stats;
        if( !EPrints::Utils::is_set( $context->{set_name} ) || $context->{set_name} eq 'eprint' )
        {
		# simply case when no Sets are involved
                # note that $set->{value} may still carry out an eprintid
                $stats = $handler->extract_eprint_data( $context, $self->conf );
        }
        else
        {
		# more complex cases: Sets and/or Groupings
                $stats = $handler->extract_set_data( $context, $self->conf );
        }

	$self->{data} = $stats;

	# render objects if required by the conf
	if( $self->conf->{do_render} )
	{
		$self->render_objects();
	}

	return $self;
}

# This is quite complex, since there are many different kinds of objects that can be rendered
# The option '$fieldname' is used by Export plugins and will store the "rendering" of the object
# The option '$to_string' will render objects as a string rather than a DOM object
#
# The method will try to guess how to render each object, then will call Data::render_single_object to do the actual rendering
sub render_objects
{
	my( $self, $fieldname, $to_string ) = @_;

	my $fields = $self->fields();

	# no fields selected, surely there's nothing to render then!
	return unless( EPrints::Utils::is_set( $fields ) );

	# need to find out what type of fields is selected and how these get rendered:
	#
	# - "eprintid" => ok, easy
	# - "value" => Processor plugin decides (eg Country -> phrase/country code, Referrer -> string ...)
	# - "set_value" => Sets.pm decide

	my %fields_render_type;
	foreach my $field (@$fields)
	{
		next if( $field eq 'count' );
		
		if( $field eq 'eprintid' )
		{
			$fields_render_type{$field} = { type => 'eprint' };		# an EPrint object...
		}
		elsif( $field eq 'value' )
		{
			# Processor plugin decides...
			my $proc_conf = $self->processor->conf();
			my $render = $proc_conf->{render} || '';

			if( $render eq 'phrase' )
			{
				$fields_render_type{$field} = { type => 'phrase', render_phrase_prefix => $proc_conf->{render_phrase_prefix} };
			}
			elsif( $render eq 'string' )
			{
				$fields_render_type{$field} = { type => 'string' };
			}
			else
			{
				$self->handler->log( "Stats::Data: field 'value' selected but I don't know how to render it.", 1 );
				$fields_render_type{$field} = { type => 'string' };
			}
		}
		elsif( $field eq 'set_value' )
		{
			if( EPrints::Utils::is_set( $self->context->{grouping} ) )
			{
				$fields_render_type{$field} = { type => 'set', set_name => $self->context->{grouping} };

			}
			else
			{
				$fields_render_type{$field} = { type => 'set', set_name => $self->context->{set_name} };

			}
		}
	}

	my @new_data;
	foreach my $row ( @{$self->data} )
	{
		foreach my $field ( @$fields )
		{
			next if( $field eq 'count' );
			my $value = $row->{$field};
			next unless( defined $value );

			my $desc = $self->render_single_object( $fields_render_type{$field}, $value );

			if( defined $to_string && $to_string )
			{
				$desc = EPrints::XML::to_string( $desc );
			}

			if( defined $fieldname )
			{
				$row->{$fieldname} = $desc if( !defined $row->{$fieldname} );
			}
			else
			{
				$row->{$field} = $desc;
			}

			push @new_data, $row;
		}
	}

	$self->{data} = \@new_data;
}

sub render_single_object
{
	my( $self, $conf, $value ) = @_;

	if( $conf->{type} eq 'eprint' )
	{
		my $eprint = $self->{session}->dataset( 'archive' )->dataobj( $value );
		return (defined $eprint) ? $eprint->render_citation_link( 'brief' ) : $self->{session}->html_phrase( 'lib/irstats2/unknown:eprint', id => $self->{session}->make_text( $value ) );
	}
	elsif( $conf->{type} eq 'phrase' )
	{
		return $self->{session}->html_phrase( $self->conf->{render_phrase_prefix}."$value" );
	}
	elsif( $conf->{type} eq 'subject' )
	{
		my $subject = EPrints::DataObj::Subject->new( $self->{session}, $value );
		return (defined $subject) ? $subject->render_description() : $self->{session}->html_phrase( 'lib/irstats2/unknown:subject', id => $self->{session}->make_text( $value ) );
	}
	elsif( $conf->{type} eq 'set' )
	{
		return $self->handler->sets->render_set( $conf->{set_name}, $value );
	}

	return $self->{session}->make_text( $value );
}

# will sum all 'count' - useful to show for instance a download counter
sub sum_all
{
	my( $self ) = @_;

	my $c = 0;
	foreach( @{$self->{data}} )
	{
		$c += $_->{count} || 0;
	}

	return $c;
}

# called when an export of the data is requested
sub export
{
	my( $self, $params ) = @_;

	# the plug-in is instanciated by /cgi/stats/get
	if( defined $params->{export_plugin} )
	{
		$params->{export_plugin}->export( $self );
	}
}

1;
