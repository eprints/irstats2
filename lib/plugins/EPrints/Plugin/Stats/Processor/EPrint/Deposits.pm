package EPrints::Plugin::Stats::Processor::EPrint::Deposits;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;

# Processor::EPrint::Deposits
#
# Processed the number of deposits of eprint objects over time. Provides the 'eprint_deposits' datatype.
# 

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

	$self->{provides} = [ "deposits" ];

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
##		print STDERR "\nstatus not set for eprint=".$eprint->get_id;
		return;
	}

	my $datestamp = $eprint->get_value( "datestamp" ) || $eprint->get_value( "lastmod" );

	my $date = $self->parse_datestamp( $self->{session}, $datestamp );

	my $year = $date->{year};
	my $month = $date->{month};
	my $day = $date->{day};

	$self->{cache}->{"$year$month$day"}->{$epid}->{$status}++;
}


1;
