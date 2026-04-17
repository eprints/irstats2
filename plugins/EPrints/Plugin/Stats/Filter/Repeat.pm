package EPrints::Plugin::Stats::Filter::Repeat;

use EPrints::Plugin::Stats::Processor;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;

# Stats::Filter::Repeat
#
# Will attempt to detect so-called double-click downloads / abstract hits - does not provide any data to show on the reports.
#
# The default time-out is set to one hour
#

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

        $self->{provides} = [];

        $self->{disable} = 0;
	$self->{priority} = 200;

	$self->{cache} = {};

	# defined locally
	$self->{timeout} ||= 3600;

	return $self;
}

sub create_tables 
{
        my( $self, $handler ) = @_;
}

sub clear_cache
{
	my( $self ) = @_;

	my @keys = keys %{$self->{cache}};

	if( scalar @keys > 0 )
	{
		my $time = $self->{cache}->{$keys[-1]};

		for( @keys )
		{
			delete $self->{cache}->{$_} if abs($time - $self->{cache}->{$_}) > $self->{timeout};
		}
	}

	@keys = keys %{$self->{cache}};
}

sub commit_data
{
        my( $self, $handler ) = @_;
}

# double-click based on { epoch, source_ip, item }
sub filter_record
{
	my ($self, $record) = @_;

        my $ip = $record->{requester_id};
        return 0 unless( defined $ip );
	
	my $time = $record->{datestamp}->{epoch};

        my $epid = $record->{referent_id};
        my $docid = $record->{referent_docid};

	my $time_ref;
	my $key;
	if( defined $docid )
	{
		# download
		$key = "$epid-$docid-$ip";
	}
	else
	{
		# abstract hit
		$key = "$epid-X-$ip";
	}

	if( defined ( $time_ref = $self->{cache}->{$key} ) )
	{
		if( abs( $time - $time_ref ) <= $self->{timeout} )
		{
			return 1;	# double-click detected - filtered out				
		}
	}

	# new time ref
	$self->{cache}->{$key} = $time;
	
	return 0;

}


1;
