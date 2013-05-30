package EPrints::Plugin::Stats::Export::JSON;

use EPrints::Plugin::Stats::Export;
@ISA = ('EPrints::Plugin::Stats::Export');

use strict;

# Stats::Export::JSON
#
# Exports stats data to JSON
#

sub mimetype { 'application/json' }

sub export
{
	my( $self, $stats ) = @_;

	my $statistics = {};
	
	my $context = $self->get_export_context( $stats );

	foreach( 'origin', 'set', 'timescale' )
	{
		next unless( EPrints::Utils::is_set( $_ ) );
		$statistics->{$_} = $context->{$_};
	}

	my @data;
	foreach my $data (@{$stats->data})
	{
		my $fields = {};
		foreach my $k (keys %$data)
		{
			my $v = $data->{$k};
			$v =~ s/'/\\'/g;
			$fields->{$k} = $v;
		}
		push @data, $fields;
	}

	$statistics->{records} = \@data;

	print STDOUT $self->to_json( $statistics );

        return;
}

sub to_json
{
        my( $self, $object ) = @_;

        if( ref( $object ) eq 'HASH' )
        {
                my @stuff;
                while( my( $k, $v ) = each( %$object ) )
                {
                        next if( !EPrints::Utils::is_set( $v ) );       # or 'null' ?
                        push @stuff, $self->js_escape( $k ).':'.$self->to_json( $v );
                }
                return '{' . join( ",", @stuff ) . '}';
        }
        elsif( ref( $object ) eq 'ARRAY' )
        {
                my @stuff;
                foreach( @$object )
                {
                        next if( !EPrints::Utils::is_set( $_ ) );
                        push @stuff, $self->to_json( $_ );
                }
                return '[' . join( ",", @stuff ) . ']';
        }

        return $self->js_escape( $object );
}

sub js_escape
{
	my( $self, $string ) = @_;

	return '""' unless( defined $string );

	$string =~ s/"/\\"/g;

	return '"'.$string.'"';
}

1;

