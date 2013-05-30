package EPrints::Plugin::Stats::Processor::EPrint::DocumentFormat;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;

# TODO could also group by major MIME eg video, image, documents etc.
#
# Processor::EPrint::DocumentFormat
#
# Processes the document format (MIME types), provides the 'eprint_doc_format' datatype.
# 

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

	$self->{provides} = [ "doc_format" ];

	$self->{disable} = 0;

	$self->{conf} = {
		fields => [ 'value' ],
		render => 'phrase',
		render_phrase_prefix => 'document_typename_',
	};

	return $self;
}

sub process_record
{
	my ($self, $eprint ) = @_;

	my $epid = $eprint->get_id;
	return unless( defined $epid );

	my $status = $eprint->get_value( "eprint_status" );
	return if( !defined $status || $status ne 'archive' );

	my $datestamp = $eprint->get_value( "datestamp" ) || $eprint->get_value( "lastmod" );

	my $date = $self->parse_datestamp( $self->{session}, $datestamp );

	my $year = $date->{year};
	my $month = $date->{month};
	my $day = $date->{day};

	my @docs = $eprint->get_all_documents;

	foreach(@docs)
	{
		my $format = $_->get_value( 'format' );
		next unless( defined $format );
		$self->{cache}->{"$year$month$day"}->{$epid}->{$format}++;
	}

}

1;
