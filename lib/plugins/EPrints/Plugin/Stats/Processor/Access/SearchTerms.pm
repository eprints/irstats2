package EPrints::Plugin::Stats::Processor::Access::SearchTerms;

our @ISA = qw/ EPrints::Plugin::Stats::Processor::Access /;

use strict;

# Processor::Access::SearchTerms
#
# Processes the Search terms from Access records. Provides the 'eprint_search_terms' datatype
# 
# Note that search terms are extracted from Referrers: this can parse EPrints searches as well as Google's, Yahoo's and Bing's
#

# single-letter words will also be ignored
my $IGNORE_WORDS = [qw{
or
of
at
and
in
to
the
a
an
for
how
what
why
whom
which
into
on
is
are
have
has
do
does
go
goes
with
com
by
up
}];

my %IGNORE_LIST = map { $_ => 1 } @$IGNORE_WORDS;

sub new
{
        my( $class, %params ) = @_;
	my $self = $class->SUPER::new( %params );
        $self->{provides} = [ "search_terms" ];
	$self->{disable} = 0;
	$self->{cache} = {};

	$self->{base_url} = "";
	if( defined $self->{session} )
	{
		$self->{base_url} = $self->{session}->config( "base_url" );
	}

	$self->{conf} = {
		render => 'string',
	};
	if ($self->{session}->config( "index") eq '1') {
		%IGNORE_LIST=();
		$self->{'indexing'}=$self->{session}->config( 'indexing' );
		foreach (keys %{$self->{'indexing'}{'freetext_stop_words'}}) {
			$IGNORE_LIST{$_}=$self->{'indexing'}{'freetext_stop_words'}{$_};
		}
	}
	return $self;
}

sub process_record
{
	my ($self, $record, $is_download) = @_;

	return unless( $is_download );

	my $ref = $record->{referring_entity_id};
	return unless( EPrints::Utils::is_set( $ref ) );

        my $epid = $record->{referent_id};
        return unless( defined $epid );

	my $date = $record->{datestamp}->{cache};

	# and unescaping the %XX characters:
	$ref =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	my ($protocol, $hostname, $uri) = EPrints::Plugin::Stats::Utils::parse_url( $ref );

	return unless( defined $hostname );

	# Internal search?
	if( $hostname eq $self->{base_url} || $hostname eq 'localhost' )
	{
		if( $uri =~ m#(/secure|)/cgi/search/(simple|advanced)\?# )
		{
			my $type = $2;

			if( $type eq 'simple' )
			{
				my $q = EPrints::Plugin::Stats::Utils::get_param( $uri, 'q' );
				if( defined $q )
				{
					my @words = split( /\+/, $q );
					foreach(@words)
					{
						my $w = $self->normalize_word( $_ );
						next unless( EPrints::Utils::is_set( $w ) );
						$self->{cache}->{"$date"}->{$epid}->{"$w"}++;
					}
				}
				return;
			}

			if( $type eq 'advanced' )
			{
				foreach( 'title', 'creators_name', 'abstract', 'keywords' )
				{
					my $q = EPrints::Plugin::Stats::Utils::get_param( $uri, $_ );
					next unless( defined $q );
					
					foreach( split( /\+/, $q ) )
					{
						my $w = $self->normalize_word( $_ );
						next unless( EPrints::Utils::is_set( $w ) );
						$self->{cache}->{"$date"}->{$epid}->{"$w"}++;
					}
				}
			}
		}
		# Unknown...
		return;
	}

	# Google / MSN / Bing
	if( $hostname =~ m#(google|msn|bing)\.# )
	{
		my $q = EPrints::Plugin::Stats::Utils::get_param( $uri, 'q' );

		if( defined $q )
		{
			foreach( split( /\+/, $q ) )
			{
				my $w = $self->normalize_word( $_ );
				next unless( EPrints::Utils::is_set( $w ) );
				$self->{cache}->{"$date"}->{$epid}->{"$w"}++;
			}
		}
		return;
	}
	
	if( $hostname =~ m#yahoo\.# )
	{
		my $q = EPrints::Plugin::Stats::Utils::get_param( $uri, 'p' );

		if( defined $q )
		{
			foreach( split( /\+/, $q ) )
			{
				my $w = $self->normalize_word( $_ );
				next unless( EPrints::Utils::is_set( $w ) );
				$self->{cache}->{"$date"}->{$epid}->{"$w"}++;
			}
		}
		return;
	}
}

sub normalize_word
{
	my( $self, $w ) = @_;

	return undef unless( defined $w );

	$w =~ s/["',;\.]//g;
	$w =~ s/^(.*?)(\&.*)$/$1/g;
	$w =~ s/^\s+//g;
	$w =~ s/\s+$//g;
	$w =~ s/[^\N{U+0000}-\N{U+FFFF}]//g; # Remove unsupported UTF8-MB4 characters that will cause issues when inserting into database.

	return undef unless( EPrints::Utils::is_set( $w ) );
	
	$w = lc($w);
	return undef if( $IGNORE_LIST{$w} );
	if ($self->{'indexing'}) {
		return undef if( length $w < $self->{'indexing'}{'freetext_min_word_size'} && ! exists $self->{'indexing'}{'freetext_always_words'}{$w});
	}
	else {
		return undef if( length $w < 2 );
	}
	
	return $w;
}

1;
