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

sub appendTextNode
{
        my( $doc, $parent, $name, $value) = @_;

        my $element = $doc->createElement($name);
        $element->appendText($value);

        $parent->addChild($element);

        return $parent;
}


sub print_context
{
	my( $self, $stats ) = @_;

	my $context = $self->get_export_context( $stats );

	my $origin = $context->{origin};

	#construct XML to properly escape special characters
	my $doc = XML::LibXML::Document->new('1.0', 'utf-8');

	#construct origin XML
        my $originElement = $doc->createElement('origin');

        $originElement = appendTextNode($doc, $originElement, 'name', $origin->{name});
        $originElement = appendTextNode($doc, $originElement, 'url', $origin->{url});

        my $originFragment = $originElement->toString();
        print STDOUT $originFragment;

	#construct timescale XML if required
        if( my $timescale = $context->{timescale} )
        {
                my $timescaleElement = $doc->createElement('timescale');

                $timescaleElement = appendTextNode($doc, $timescaleElement, 'format', $timescale->{format});
                $timescaleElement = appendTextNode($doc, $timescaleElement, 'from', $timescale->{from});
                $timescaleElement = appendTextNode($doc, $timescaleElement, 'to', $timescale->{to});

                my $timescaleFragment = $timescaleElement->toString();
                print STDOUT $timescaleFragment;
        }

	#construct set XML if required
        if( my $set = $context->{set} )
        {
                my $setElement = $doc->createElement('set');

                $setElement = appendTextNode($doc, $setElement, 'name', $set->{name});
                $setElement = appendTextNode($doc, $setElement, 'value', $set->{value});
                $setElement = appendTextNode($doc, $setElement, 'description', $set->{description});

                my $setFragment = $setElement->toString();
                print STDOUT $setFragment;
        }

}

1;

