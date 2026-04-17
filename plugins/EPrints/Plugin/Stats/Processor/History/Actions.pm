package EPrints::Plugin::Stats::Processor::History::Actions;

our @ISA = qw/ EPrints::Plugin::Stats::Processor /;

use strict;

# Processor::History::Actions
#
# Analyses certain actions recorded in the 'history' table
# 

my $VALID_ACTIONS = {
	modify => 1,
	destroy => 1,
	create => 1,
	move_inbox_to_buffer => 1,
	move_buffer_to_archive => 1,
	move_buffer_to_inbox => 1,
	move_archive_to_buffer => 1,
	move_archive_to_deletion => 1,
	move_inbox_to_archive => 1,
};

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );

	$self->{provides} = [ "history" ];

	$self->{disable} = 0;

	return $self;
}

sub process_record
{
	my ($self, $record ) = @_;

	my $action = $record->value( 'action' );
	return if( !defined $action || !$VALID_ACTIONS->{$action} );

	my $ds = $record->value( 'datasetid' );
	return if( !defined $ds || $ds ne 'eprint' );

	my $epid = $record->value( 'objectid' );
	return unless( defined $epid );

	my $timestamp = $record->get_value( "timestamp" );
	return unless( defined $timestamp );

	my $date = $self->parse_datestamp( $self->{session}, $timestamp );

	my $year = $date->{year};
	my $month = $date->{month};
	my $day = $date->{day};

	$self->{cache}->{"$year$month$day"}->{$epid}->{$action}++;
}


1;
