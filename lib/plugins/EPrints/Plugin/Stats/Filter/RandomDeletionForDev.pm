package EPrints::Plugin::Stats::Filter::RandomDeletionForDev;

# delete 2/3 records to make the processing quicker - only useful while DEV!


our @ISA = qw/ EPrints::Plugin /;

use strict;

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

        $self->{disable} = 0;
	$self->{priority} = 1;
	
	srand;
	
	return $self;
}

sub filter_record
{
	my ($self, $record) = @_;

	return 0 unless( int(rand(3)) == 0 );

	return 1;
}

1;

