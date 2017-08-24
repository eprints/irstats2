package EPrints::Plugin::Stats::Filter::Robots;

use EPrints::Plugin::Stats::Processor;
use LWP::Simple;
use File::Basename;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;

our (@ROBOTS_UA, %ROBOTS_IP);


sub get_robots
{
    
    my $robots_ua_href = "http://www.eprints.org/resource/bad_robots/robots_ua.txt";
    my $robots_ip_href = "http://www.eprints.org/resource/bad_robots/robots_ip.txt";
    
    my $conf = $EPrints::SystemSettings::conf;
    
    my $dirname = dirname(__FILE__);

    my $robots_ua_file = $conf->{base_path} . "/var/robots_ua.txt";
    if  (not ( (-e $robots_ua_file) && (-C $robots_ua_file) < 7 ))  
    {
	my $datestring = localtime();
        print  "[$datestring|$robots_ua_file] file does not exist or too old. Downloading new...";
        getstore($robots_ua_href, $robots_ua_file);
	print  "done\n";
    }


    ## Basic sanity check on the downloaded file
    my $size = -s $robots_ua_file || 0;
    if ( $size <10000 )
    {
        $robots_ua_file = $dirname . "/default_robots_ua.txt";
        print STDERR "Downloaded robot file appear to be incorrect. Reverting to use the default ($robots_ua_file).\n";
    };
    open( my $fh, $robots_ua_file ) || EPrints::abort( "Could not read $robots_ua_file\n" );
    @ROBOTS_UA = map { s/\s+//g; qr/$_/i if $_ } <$fh>;
    close($fh);

    my $robots_ip_file = $conf->{base_path} . "/var/robots_ip.txt";
    if  (not ( (-e $robots_ip_file) && (-C $robots_ip_file) < 7 ))  
    {
	my $datestring = localtime();
        print  "[$datestring|$robots_ip_file] file does not exist or too old. Downloading new...";
        getstore($robots_ip_href, $robots_ip_file);
	print  "done\n";
    }

    ## Basic sanity check on the downloaded file
    $size = -s $robots_ip_file || 0;
    if ($size <120)
    {
        $robots_ip_file = $dirname . "/default_robots_ip.txt";
        print STDERR "Downloaded robot IP file appear to be incorrect. Reverting to use the default ($robots_ip_file).\n";
    };
    open( $fh, $robots_ip_file ) || EPrints::abort( "Could not read $robots_ip_file\n" );
    
    while (my $line = <$fh>)
    {
        chomp $line;
        next if not $line;
        next if $line =~ m/^\#/;
	$ROBOTS_IP{$line}=1;	
    }
    close($fh);
}


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
    if (not (%ROBOTS_IP && @ROBOTS_UA)) ## only need to get robots once.
    {
        $self->get_robots;
    }

	my $ua = $record->{requester_user_agent};
	return 0 unless( defined $ua );

    my $is_robot = 0;

	for( @ROBOTS_UA )
	{
		$is_robot = 1, last if $ua =~ $_;
	}
    
    return $is_robot if $is_robot; 

    ##
    #to use this feature, define in z_irstats2.pl
    #$c->{irstats2}->{robot_ips} = [
    #        "180.76.15.34",
    #        "123.125.71",
    #        ];
    #
    ##adding locally configed robot IPs:
    my $robots_ip_cfg = $self->{session}->config( 'irstats2', 'robots_ip' ) || [];
    foreach (@{$robots_ip_cfg})
    {
	$ROBOTS_IP{$_}=1;
    }

    my $ip = $record->{requester_id} || "";
    return $is_robot if $ip eq "";
    for(keys %ROBOTS_IP)
    {	
        next if not $_;
        my $robot_ip = $_;
        my $num_dots = () = $_ =~ /\./g;
        $robot_ip .= "." if ($num_dots < 3 && substr($robot_ip, -1) ne '.');
        $robot_ip =~ s/\./\\\./g;
        $is_robot = 1, last if $ip =~ /^$robot_ip/i ;
    }

    return $is_robot;
}


1;
