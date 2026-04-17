package EPrints::Plugin::Screen::EPMC::IRStats2;

use EPrints::Plugin::Screen::EPMC;

@ISA = ( 'EPrints::Plugin::Screen::EPMC' );

use strict;

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new( %params );

	$self->{actions} = [qw( enable disable configure )];
	$self->{disable} = 0; # always enabled, even in lib/plugins

	$self->{package_name} = "irstats2";

	return $self;
}

sub render_messages
{
	my( $self ) = @_;

	my $repo = $self->{repository};
	my $xml = $repo->xml;

	my $frag = $xml->create_document_fragment;
	my @missing;
	my $datecalc = EPrints::Utils::require_if_exists('Date::Calc');
	my $geoip = EPrints::Utils::require_if_exists( 'Geo::IP' );
	push @missing, "Date::Calc" unless defined $datecalc;
	push @missing, "Geo::IP" unless defined $geoip;
	if( scalar @missing >0  )
	{
		$frag->appendChild(
			$repo->render_message(
				'error',
				$self->html_phrase(
					'error:no_plugins',
					 packages => $repo->xml->create_text_node( join(", ",@missing) )
				)
			)
		);
	}

	$frag->appendChild(
		$repo->render_message( 'message', $self->html_phrase( 'message:cron' ) )
	);

	return $frag;
}

sub allow_configure { shift->can_be_viewed( @_ ) }

sub action_configure
{
	my( $self ) = @_;

	my $epm = $self->{processor}->{dataobj};
	my $epmid = $epm->id;

	foreach my $file ($epm->installed_files)
	{
		my $filename = $file->value( "filename" );
		next if $filename !~ m#^epm/$epmid/cfg/cfg\.d/(.*)#;
		my $url = $self->{repository}->current_url( host => 1 );
		$url->query_form(
			screen => "Admin::Config::View::Perl",
			configfile => "cfg.d/$1",
		);
		$self->{repository}->redirect( $url );
		exit( 0 );
	}

	$self->{processor}->{screenid} = "Admin::EPM";

	$self->{processor}->add_message( "error", $self->html_phrase( "missing" ) );
}

1;

