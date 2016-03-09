package EPrints::Plugin::Stats::Export::CSV;

use EPrints::Plugin::Stats::Export;
@ISA = ('EPrints::Plugin::Stats::Export');

use strict;

# Stats::Export::CSV
#
# Export data to the CSV format. Note that numbers are output in a way that prevents MS Excel from formatting the value ($number -> ="$number")
# 

sub mimetype { 'text/csv' }

sub export
{
        my( $self, $stats ) = @_;

	binmode( STDOUT, ":utf8" );
 	$stats->render_objects( 'description', 1 );

	my @header_columns;
	my $header = $stats->data->[0];
	if( defined $header )
	{
		print STDOUT join( ",", sort keys %$header )."\n";
	}

        my @records;
        foreach my $data (@{$stats->data})
        {
                my @record;
                foreach my $k (sort keys %$data)
                {
			push @record, $self->escape_value( $data->{$k} );
                }
		print STDOUT join( ",", @record )."\n";
        }

        return;
}

sub escape_value
{
        my( $plugin, $value ) = @_;

        return '""' unless( defined EPrints::Utils::is_set( $value ) );

        # strips any kind of double-quotes:
        $value =~ s/\x93|\x94|"/'/g;
        # and control-characters
        $value =~ s/\n|\r|\t//g;

        # if value is a pure number, then add ="$value" so that Excel stops the auto-formatting (it'd turn 123456 into 1.23e+6)
        if( $value =~ /^\d+$/ )
        {
                return "=\"$value\"";
        }

        # only escapes values with spaces and commas
        if( $value =~ /,| / )
        {
                return "\"$value\"";
        }

        return $value;
}

1;
