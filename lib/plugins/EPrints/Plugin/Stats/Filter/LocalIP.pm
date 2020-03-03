package EPrints::Plugin::Stats::Filter::LocalIP;

use EPrints::Plugin::Stats::Processor;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;
#-------------------------------------
#MM - 04/05/2017
# Filters IP addresses assigned to $IPS, and works in conjunction with the other IRSTATS filters (robots, repeats, etc). This filter excludes those rows in the access table where requester_id == $IPS from the stats report.
#-------------------------------------


sub new{
	my( $class, %params ) = @_;
    my $self = $class->SUPER::new( %params );

    $self->{disable} = 0;
    # @self->{list} = qw/ /;

	return $self;
}

sub filter_record{
	my ($self, $record) = @_;
	
	my $id = $record->{requester_id};
	return 0 unless( defined $id );
#------------------------------------------
#MM - 04/05/2017
#the value of $IPS, i.e. IP address(es) that need to be filtered, can be assigned by in a overrides.pl file in archives/../cfg.d by using $c->{plugins}->{"Stats::Filter::LocalIP"}->{params}->{IPlist}= [IPs to be blocked];
#------------------------------------------    
    my $IPS = $self->param("IPlist");
	my $is_local = 0;
	
	for my $local_ip ( @$IPS ){
		$local_ip =~ s/\s$//g;
		$is_local = 1, last if($local_ip eq $id);
	}

	return $is_local;
}


1;

