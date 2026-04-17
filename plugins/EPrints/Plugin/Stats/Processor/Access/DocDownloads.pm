package EPrints::Plugin::Stats::Processor::Access::DocDownloads;

our @ISA = qw/ EPrints::Plugin::Stats::Processor::Access /;

use strict;

# Processor::Access::Downloads
#
# Arguably the most important Processor plugin. This deals with the download counts (and summary pages hits) per document.
#
# Provides 'doc_downloads'
# 

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new( %params );

	$self->{provides} = [ "doc_downloads" ];
	$self->{disable} = 0;
	$self->{cache} = {};

	return $self;
}

sub clear_cache
{
	my( $self ) = @_;

	delete $self->{cache_doc_downloads};
}

sub process_record
{
	my ($self, $record, $is_download) = @_;

	my $docid = $record->{referent_docid};	
	return unless( defined $docid );

	my $date = $record->{datestamp}->{cache};

	if( $is_download )
	{
		$self->{cache_doc_downloads}->{"$date"}->{$docid}->{downloads}++;
	}

	return;
}

# use this to commit to db:
sub commit_data
{
	my( $self, $handler ) = @_;

	$handler->save_data_values( "doc_downloads", $self->{cache_doc_downloads} );
}


1;

