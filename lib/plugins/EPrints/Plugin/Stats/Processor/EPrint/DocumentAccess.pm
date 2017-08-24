package EPrints::Plugin::Stats::Processor::EPrint::DocumentAccess;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;

# Processor::EPrint::DocumentAccess
#
# Checks if the documents are open access and whether full text is attached to eprint objects.
# 
# Provides the 'eprint_doc_access' datatype with the following filters: full_text, no_full_text, open_access and no_open_access
#

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

	$self->{provides} = [ "doc_access" ];

	$self->{disable} = 0;

	return $self;
}

sub process_record
{
	my ($self, $eprint ) = @_;

	my $epid = $eprint->get_id;
	return unless( defined $epid );

	my $status = $eprint->get_value( "eprint_status" );
	unless( defined $status ) 
	{
##		print STDERR "IRStats2: warning - status not set for eprint=".$eprint->get_id."\n";
		return;
	}

	return unless( $status eq 'archive' );

	my $datestamp = $eprint->get_value( "datestamp" ) || $eprint->get_value( "lastmod" );

	my $date = $self->parse_datestamp( $self->{session}, $datestamp );

	my $year = $date->{year};
	my $month = $date->{month};
	my $day = $date->{day};

	my @docs = $eprint->get_all_documents;
	my $fulltext_status = scalar( @docs ) ? 'full_text' : 'no_full_text';

	my $openaccess_status = 'no_open_access';
	if( scalar( @docs ) )
	{
		foreach(@docs)
		{
			if( $_->is_public )
			{
				$openaccess_status = 'open_access';
				last;
			}
		}
	}

	$self->{cache}->{"$year$month$day"}->{$epid}->{$fulltext_status}++;
	$self->{cache}->{"$year$month$day"}->{$epid}->{$openaccess_status}++;
}


1;
