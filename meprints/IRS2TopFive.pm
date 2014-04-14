package EPrints::Plugin::MePrints::Widget::IRS2TopFive;

# top five publications for the user, using the IRStats2 API

use EPrints::Plugin::MePrints::Widget;
@ISA = ( 'EPrints::Plugin::MePrints::Widget' );

use strict;

sub new
{
	my( $class, %params ) = @_;
	
	my $self = $class->SUPER::new( %params );
	
	if ( !$self->{session} )
	{
		$self->{session} = $self->{processor}->{session};
	}

	$self->{name} = "EPrints Profile System: IRStats2 Top 5";
	$self->{visible} = "all";
	$self->{advertise} = 1;

	return $self;
}

sub render_content
{
	my( $self ) = @_;

	my $session = $self->{session};
	my $user = $self->{user};

	my $frag = $session->make_doc_fragment;

	my $repo_url = $session->get_repository->get_conf( "base_url" );
	
	# just need a container, a JS callback, a way to translate the current user ID into a IRStats2 Set value (??)

	my $set_value = Digest::MD5::md5_hex( $user->get_id ); 

	$frag->appendChild( $session->make_element( 'div', id => 'irstats2_top5' ) );

	$frag->appendChild( $session->make_javascript( <<TABLE ) );
	
new EPJS_Stats_Table( { 'context': { 
	'range': '_ALL_', 
	'datatype': 'downloads',
	'set_name': 'authors',
	'set_value': '$set_value'
}, 'options': { 
	'container_id': 'irstats2_top5', 
	'top': 'eprint', 
	'limit': '5' 
} } );

TABLE

	return $frag;

}

