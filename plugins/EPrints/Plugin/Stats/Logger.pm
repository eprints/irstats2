package EPrints::Plugin::Stats::Logger;

use Fcntl qw(:flock);
use EPrints::Plugin;
@ISA = ('EPrints::Plugin');

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new( %params );

	return $self;
}

sub _filter_text
{
	my( $str ) = @_;

	$str = "" unless defined( $str );
	$str =~ s/"/ /g;
	$str =~ y/\x{20}-\x{7f}//cd;

	return $str;
}

sub create_access
{
	my( $self, $epdata ) = @_;

	my $repository = $self->{repository};

        my $datestamp = $epdata->{datestamp};

	my $access_base_dir = $repository->config( 'archiveroot' ) . "/var/access";
	my $current_dir = $access_base_dir . "/current";
	my $log_file = $current_dir . "/" . substr( $datestamp, 0, 10 ) . ".log";

	mkdir( $access_base_dir ) unless -e $access_base_dir;
	mkdir( $current_dir ) unless -e $current_dir;

	my $log_entry = $datestamp . "\t" .
		_filter_text( $epdata->{requester_id} ) . "\t" .
		_filter_text( $epdata->{requester_user_agent} ) . "\t" .
		_filter_text( $epdata->{referring_entity_id} ) . "\t" .
		_filter_text( $epdata->{service_type_id} ) . "\t" .
		_filter_text( $epdata->{referent_id} ) . "\t" .
		_filter_text( $epdata->{referent_docid} ) . "\n";

	open my $fh, ">>", $log_file or EPrints::abort( "Unable to log access" );

	flock $fh, LOCK_EX; # flock starts the critical section
	print $fh $log_entry;
	close $fh; # close ends the critical section
}

1;
