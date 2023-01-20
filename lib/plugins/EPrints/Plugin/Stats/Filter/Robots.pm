package EPrints::Plugin::Stats::Filter::Robots;

use EPrints::Plugin::Stats::Processor;
use LWP::Simple;
use File::Basename;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;

our ($ROBOTS_UA_PATTERN, $ROBOTS_IP_PATTERN);

sub get_robots
{
	my( $self ) = @_;

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
	if ( $size < 5000 )
	{
		$robots_ua_file = $dirname . "/default_robots_ua.txt";
		print STDERR "Downloaded robot file appear to be incorrect. Reverting to use the default ($robots_ua_file).\n";
	};

	open( my $fh, $robots_ua_file ) || EPrints::abort( "Could not read $robots_ua_file\n" );
	my @robots_ua_patterns = map { s/\s+//g; lc $_ if $_ } <$fh>;
	@robots_ua_patterns = grep { /./ } @robots_ua_patterns;
	my $robots_ua_pattern = join "|", @robots_ua_patterns;
	close($fh);

	$ROBOTS_UA_PATTERN = qr/$robots_ua_pattern/;

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

	if ($size < 2000)
	{
		$robots_ip_file = $dirname . "/default_robots_ip.txt";
		print STDERR "Downloaded robot IP file appear to be incorrect. Reverting to use the default ($robots_ip_file).\n";
	};

	open( $fh, $robots_ip_file ) || EPrints::abort( "Could not read $robots_ip_file\n" );

	my %robots_ip;

	while (my $line = <$fh>)
	{
		chomp $line;
		next if not $line;
		next if $line =~ m/^\#/;
		$robots_ip{$line}=1;	
	}
	close($fh);

	# Calculate regexps for IP filtering

	##
	#to use this feature, define in z_irstats2.pl
	#$c->{irstats2}->{robot_ips} = [
	#        "180.76.15",
	#        "123.125.71",
	#        ];
	#
	##adding locally configed robot IPs:

	my $robots_ip_cfg = $self->{session}->config( 'irstats2', 'robots_ip' ) || [];

	foreach (@{$robots_ip_cfg})
	{
		$robots_ip{$_} = 1;
	}

	my @robots_ip_patterns;

	for(keys %robots_ip)
	{
		next if not $_;
		my $robot_ip = $_;
		my $num_dots = () = $_ =~ /\./g;
		$robot_ip .= "." if ($num_dots < 3 && substr($robot_ip, -1) ne '.');
		$robot_ip =~ s/\./\\\./g;

		push @robots_ip_patterns, $robot_ip;
	}

	my $robots_ip_pattern = join "|", @robots_ip_patterns;
	$ROBOTS_IP_PATTERN = qr/$robots_ip_pattern/;
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
	my( $self, $record ) = @_;

	if(not ( $ROBOTS_UA_PATTERN && $ROBOTS_IP_PATTERN )) ## only need to get robots once.
	{
		$self->get_robots;
	}

	my $ua = $record->{requester_user_agent};
	my $ip = $record->{requester_id} || "";

	if( defined( $ua ))
	{
		return 1 if (lc $ua) =~ $ROBOTS_UA_PATTERN;
	}

	if( $ip ne "" )
	{
		return 1 if $ip =~ $ROBOTS_IP_PATTERN;
	}

	return 0;
}

1;
