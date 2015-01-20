package EPrints::Plugin::Stats::Export::XML;

use EPrints::Plugin::Stats::Export;
@ISA = ('EPrints::Plugin::Stats::Export');

use strict;

# Stats::Export::XML
#
# Export stats data to XML.

sub mimetype { 'text/xml' }

sub export
{
        my( $self, $stats ) = @_;

	# should be set by something else:
	binmode( STDOUT, ":utf8" );
	print STDOUT "<?xml version='1.0'?>\n<statistics>\n";

	$self->print_context( $stats );
 	
	$stats->render_objects( 'description', 1 );

        my @records;
        foreach my $data (@{$stats->data})
        {
                my @record;
                foreach my $k (keys %$data)
                {
                        my $v = $data->{$k};
			push @record, "<$k>$v</$k>";
                }
		push @records, "<record>".join("\n",@record)."</record>";
        }

	print STDOUT "<records>".join("",@records)."</records>\n</statistics>";

        return;
}

# TODO: any print'ed values should be XML escape'd
sub print_context
{
	my( $self, $stats ) = @_;

	my $context = $self->get_export_context( $stats );

	my $origin = $context->{origin};
	print STDOUT <<ORIGIN;
<origin>
	<name>$origin->{name}</name>
	<url>$origin->{url}</url>
</origin>
ORIGIN

	if( my $timescale = $context->{timescale} )
	{
		print STDOUT <<TIMESCALE;
<timescale>
	<format>$timescale->{format}</format>
	<from>$timescale->{from}</from>
	<to>$timescale->{to}</to>
</timescale>
TIMESCALE
	}

	if( my $set = $context->{set} )
	{
		print STDOUT <<SET;
<set>
	<name>$set->{name}</name>
	<value>$set->{value}</value>
	<description>$set->{description}</description>
</set>
SET
	}
}

1;

