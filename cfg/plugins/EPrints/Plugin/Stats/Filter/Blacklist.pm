package EPrints::Plugin::Stats::Filter::Blacklist;

use EPrints::Plugin::Stats::Processor;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;
use NetAddr::IP;

our @IPS = map { NetAddr::IP->new($_) } <DATA>;

sub new
{
	my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

	$self->{disable} = 0;

	return $self;
}

sub filter_record
{
	my ($self, $record) = @_;

	my $id = $record->{requester_id};
	return 0 unless( defined $id );
	my $ip = NetAddr::IP->new($id);
	return 0 unless( defined($ip) );

	my $is_blacklisted = 0;
	
	for( @IPS )
	{
		$is_blacklisted = 1, last if $ip->within($_);
	}

	return $is_blacklisted;
}


1;

__DATA__
103.25.156.0/24
103.36.96.0/24
111.221.28.0/24
123.125.71.0/24
180.76.15.0/24
202.89.235.0/24