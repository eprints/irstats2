package EPrints::Plugin::Stats::Sets;

our @ISA = qw/ EPrints::Plugin /;

use strict;
use HTML::Entities;
use Encode qw(encode_utf8);
use Digest::MD5 qw(md5_hex);

# Stats::Sets
#
# One of the core classes of the Stats package. This handles the definition, processing and rendering of Sets.
# 
# Sets are configured in z_irstats2.pl. Have a look there to see how to configure new Sets.
# 

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new( %params );
	
	if( defined $self->{session} )
	{
		$self->load_conf();
	}

	return $self;
}

sub handler { shift->{handler} }


# Loads the 'sets' configuration (from cfg.d/z_stats.pl) and parse the sets/groupings definition
sub load_conf
{
	my( $self ) = @_;

	my $sets = $self->{session}->config( 'irstats2', 'sets' );

	return unless( EPrints::Utils::is_set( $sets ) );
	
	my $epds = $self->{session}->dataset( 'eprint' );

	foreach my $set ( @$sets )
	{
		my $fieldname = $set->{field};

		if( !defined $fieldname || !$epds->has_field( $fieldname ) )
		{
			printf STDERR "Warning: field '%s' does not exist on dataset 'eprint'\n", "$fieldname";
			next;
		}

		# custom name?
		my $set_name = $set->{name} || $fieldname;

		my $field = $epds->field( $fieldname );

		my $type = $field->get_type;

		# defaults
		my $set_properties = {
			type => $type,
			field => $fieldname,
			anon => ( defined $set->{anon} && $set->{anon} ) ? 1 : 0,
		};
	
		if( EPrints::Utils::is_set( $set->{render_single_value} ) )
		{
			if( ref( $set->{render_single_value} ) eq 'CODE' )
			{
				$set_properties->{render_single_value} = $set->{render_single_value};
			}
			else
			{
				printf STDERR "Error: 'render_single_value' should be a CODE reference for set %s\n", $set_name;
			}
		}
		
		if( EPrints::Utils::is_set( $set->{blacklist} ) )
		{
			if( ref( $set->{blacklist} ) eq 'ARRAY' )
			{
				my %bl = map { $_ => 1 } @{ $set->{blacklist} || [] };
				$set_properties->{blacklist} = \%bl;
			}
			else
			{
				printf STDERR "Error: 'blacklist' should be an ARRAY reference for set %s\n", $set_name;
			}
		}
	
		if( $type eq 'subject' && defined $set->{whitelist} && ref( $set->{whitelist} ) eq 'ARRAY' )
		{
			my %whitelist = map { $_ => 1 } @{ $set->{whitelist} || [] };
			$set_properties->{whitelist} = \%whitelist;
		}

		if( $type eq 'compound' )
		{
			# does the _name part of the field exists?

			if( !$epds->has_field( $fieldname."_name" ) )
			{
				$self->handler->log( "Stats::Sets: compound field '$fieldname' does not have sub-field 'name'", 1 );
				next;	# cannot carry on processing...
			}

			if( defined $set->{use_ids} && $set->{use_ids} )
			{
				# need to check that the _id part of the field exists (the only kind we can process)

				my $id_field = $set->{id_field} || 'id';	# eg 'creators_id'

				if( !$epds->has_field( $fieldname."_".$id_field ) )
				{
					$self->handler->log( "Stats::Sets: compound field '$fieldname' does not have sub-field '$id_field'", 1 );
					next;	# cannot carry on processing...
				}

				$set_properties->{id_field} = $id_field;
			}
			else
			{
				# not using the 'id' field means only use the 'name' part. For creators, this is the same as simply using the pseudo 'creators_name' field 
				# so we can simply alter the set definition to use 'creators_name'								
			
				$set_properties->{field} = $fieldname.'_name';
				$set_properties->{type} = $epds->field( $set_properties->{field} )->get_type;
			}
		}
		$self->{sets}->{$set_name} = $set_properties;
	}

	# groupings need to be done after sets are parsed
	foreach my $set ( @$sets )
	{
		my $set_name = $set->{name} || $set->{field};
		next unless( $self->set_exists( $set_name ) );
		
		my $groupings = $set->{groupings};
		next unless( EPrints::Utils::is_set( $groupings ) );
		
		my $fieldname = $self->get_fieldname( $set_name );

		$groupings = [$groupings] if( ref($groupings) eq '' );
		foreach my $gr_name (@$groupings)
		{
			my $gr_fieldname = $self->get_fieldname( $gr_name );
			next unless( $epds->has_field( $gr_fieldname ) );
			next if( $gr_fieldname eq $fieldname || $gr_name eq $set_name );	# you can't have the same grouping and set names (eg. top Authors per Author?)
			next unless( $self->set_exists( $gr_name ) );				# a grouping also needs to be a valid set
			push @{$self->{sets}->{$set_name}->{groupings}}, $gr_name;
		}
	}
}

# helper methods below - they read and return 'sets' properties
sub get_groupings
{
	my( $self, $set_name ) = @_;

	return $self->get_property( $set_name, 'groupings' ) || [];
}

sub is_anon
{
	my( $self, $set_name ) = @_;

	return $self->get_property( $set_name, 'anon' ) || 0;
}

sub get_field_type
{
	my( $self, $set_name ) = @_;

	return $self->get_property( $set_name, 'type' ) || 'text';
}

sub get_property
{
	my( $self, $set_name, $property ) = @_;

	return $self->{sets}->{$set_name}->{$property};
}

sub get_fieldname
{
	my( $self, $set_name ) = @_;

	return $self->{sets}->{$set_name}->{field};
}

sub set_exists
{
	my( $self, $set_name ) = @_;

	return ( defined $self->{sets}->{$set_name} ) ? 1 : 0;
}

sub get_sets_names
{
	my( $self ) = @_;

	my @names = keys %{$self->{sets}};
	return \@names;
}

# populate_tables: the main method. This will extract set values (from EPrint objects) and store the values in the DB
sub populate_tables
{
	my( $self ) = @_;

	my $sets_names = $self->get_sets_names;
	return unless( EPrints::Utils::is_set( $sets_names ) );

	# must delete values from the sets table first.
	$self->handler->create_sets_tables( $sets_names );

	# cache => so don't insert twice the same keys
	my $cache = {};
	my $display_cache = {};

	my $process_fn = sub {

		my( undef, undef, $eprint ) = @_;

		return unless( defined $eprint );

		my $eprintid = $eprint->get_id;

		$self->handler->{dbh}->begin;
		
		foreach my $set_name ( @$sets_names )
		{
			# $values = ARRAY, $groupings = HASH
			my( $values, $groupings ) = $self->get_set_values( $set_name, $eprint );

			next unless( EPrints::Utils::is_set( $values ) );
		
			foreach my $value ( @$values )
			{
				next unless( EPrints::Utils::is_set( $value ) );
				my $raw_value = $value->{key};
				my $rendered_value = $value->{display};
				
				next if( defined $cache->{$set_name}->{$eprintid}->{$raw_value} );
				$self->handler->insert_set_value( $set_name, $raw_value, $eprintid );
				$cache->{$set_name}->{$eprintid}->{$raw_value} = 1;

				while( my( $k, $v ) = each( %$groupings ) )
				{
					$self->handler->insert_grouping_value( $set_name, $raw_value, $eprintid, $k, $_ ) for( @$v );
				}

				next if( defined $display_cache->{$set_name}->{$raw_value} );
				$self->handler->insert_rendered_set_value( $set_name, $raw_value, $rendered_value );
				$display_cache->{$set_name}->{$raw_value} = 1;
			}
		}
		
		$self->handler->{dbh}->commit;
	};

	my $info = {};
	$self->{session}->dataset( 'archive' )->map( $self->{session}, $process_fn, $info );

	$cache = {};
	$display_cache = {};
	$self->{subject_cache} = {};	# used by normalise_set_values()
	$self->{user_cache} = {};

	return;
}

		
# get_set_values: return raw values for a given set. the values come from EPrint objects. see normalise_set_values for more details on how those are processed.
sub get_set_values
{
	my( $self, $set, $eprint ) = @_;

	my $fieldname = $self->get_fieldname( $set );
	my $raw_values = $eprint->get_value( $fieldname );
	return [] unless( EPrints::Utils::is_set( $raw_values ) );

	$raw_values = [$raw_values] if( ref( $raw_values ) ne 'ARRAY' );
	my @values;

	my $blacklist = $self->get_property( $set, "blacklist" ) || {};

	foreach my $raw_value ( @$raw_values )
	{
		next if( !EPrints::Utils::is_set( $raw_value ) || $blacklist->{$raw_value} );
		foreach( @{$self->normalise_set_values( $set, $raw_value ) || []} )
		{
			push @values, $_;
		}
	}

	# the groupings are relations between two sets - they are processed/extracted in a similar way than sets.
	my %groupings;
	foreach my $grouping ( @{$self->get_groupings( $set ) } )
	{
		my $gr_fieldname = $self->get_fieldname( $grouping ) || next;
		my $gr_values = $eprint->get_value( $gr_fieldname );
		next unless( EPrints::Utils::is_set( $gr_values ) );
		$gr_values = [$gr_values] if( ref($gr_values) eq '' );
	
		my $blacklist = $self->get_property( $grouping, "blacklist" ) || {};

		my @actual_gr_values;
		foreach my $gr_value ( @$gr_values )
		{
			next if( !EPrints::Utils::is_set( $gr_value ) || $blacklist->{$gr_value} );
			my $norm_gr_values = $self->normalise_set_values( $grouping, $gr_value, 0 );
			next if( !EPrints::Utils::is_set( $norm_gr_values ) );

			push @actual_gr_values, $_->{key} for( @$norm_gr_values );

			$groupings{$grouping} = \@actual_gr_values;
		}
	}

	return( \@values, \%groupings );
}

sub generate_key
{
	my( $self, $set, $value ) = @_;

	if( $self->is_anon( $set ) )
	{
		return $self->anonymise_value( $value );
	}

	return $value;
}

sub anonymise_value
{
	my( $self, $value ) = @_;

	return undef if(!EPrints::Utils::is_set( $value ) );

	return md5_hex( encode_utf8( $value ) );
}

# normalise_set_values: this will:
# 1- extract all values (for subjects, this will also retrieve the ancestors because they inherit the stats of their children. For creators, this will normalise the names etc)
# 2- optionally anonymise the value using a MD5 hash
sub normalise_set_values
{
	my( $self, $set, $raw_value, $do_display ) = @_;

	return [] unless( EPrints::Utils::is_set( $set ) && EPrints::Utils::is_set( $raw_value ) );

	$do_display = 1 unless( defined $do_display );

	my $type = $self->get_property( $set, 'type' );

	my $value = {};
	my @extracted_values;

	if( $type eq 'compound' )
	{
		# raw_value = _id
		# rendered value = _name

		# name of the subfield part (e.g. 'id' as in 'creators_id' or $creators->{id})
		my $id_field = $self->get_property( $set, 'id_field' );
		return [] unless( defined $id_field && EPrints::Utils::is_set( $raw_value->{$id_field} ) );

		# e.g. md5( creators_id ) || creators_id
		$value->{key} = $self->generate_key( $set, lc( $raw_value->{$id_field} ) );
		$value->{display} = $self->normalise_name( $raw_value->{name} ) if( $do_display );

		push @extracted_values, $value;
	}
	elsif( $type eq 'name' )
	{
		# use special rendering for names

                $value->{display} = $self->normalise_name( $raw_value );
                $value->{key} = $self->generate_key( $set, $value->{display} );

		push @extracted_values, $value;
	}
	elsif( $type eq 'subject' )
	{
		# potentiall retieve subject's ancestors (because the ancestors will inherit the download stats of its child nodes)

		my $all_values = $self->{subject_cache}->{$set}->{$raw_value};
		unless( defined $all_values )
		{
			my $subject = $self->{session}->dataset( 'subject' )->dataobj( $raw_value );
			return [] unless( defined $subject );
			my $ancestors = $self->get_subject_ancestors( $set, $subject );
			$self->{subject_cache}->{$set}->{$raw_value} = $ancestors;
			$all_values = $ancestors;
		}

		foreach( @$all_values )
		{
			my $value = {};
			$value->{key} = $self->generate_key( $set, $_ );
			$value->{display} = EPrints::XML::to_string( $self->render_set( $set, $_, 0 ) ) if( $do_display );

			push @extracted_values, $value;
		}
	}
	elsif( $type eq 'authorid' )
	{
		# the values are user ids in this case
		my $value = $self->{user_cache}->{$set}->{$raw_value};

		if( defined $value )
		{
			push @extracted_values, $value;
		}
		else
		{
			my $user = $self->handler->{session}->dataset( 'user' )->dataobj( $raw_value );
			if( defined $user )
			{
				$value->{key} = $self->generate_key( $set, $raw_value );
				$value->{display} = EPrints::Utils::tree_to_utf8( $self->render_set( $set, $raw_value, 0 ) ) if( $do_display );
				$self->{user_cache}->{$set}->{$raw_value} = $value; 

				push @extracted_values, $value;
			}
		}
	}
	else
	{
#		# nothing special to do
		$value->{key} = $self->generate_key( $set, $raw_value );
		$value->{display} = EPrints::XML::to_string( $self->render_set( $set, $raw_value, 0 ) ) if( $do_display );

		push @extracted_values, $value;
	}

	return \@extracted_values;
}


# get_subject_ancestors: return the list of ancestors for a given subject.
sub get_subject_ancestors
{
	my( $self, $set, $subject ) = @_;

	return [] unless( defined $subject );

	my @ancestors;

	foreach my $a ( $subject->_get_ancestors() )
	{
		my $s = EPrints::DataObj::Subject->new( $self->{session}, $a );
		next unless( defined $s );

		if( !$s->can_post )
		{
			# is it in the white-list of non-depositable subjects?
			my $whitelist = $self->get_property( $set, 'whitelist' );
			next if( !defined $whitelist || !exists $whitelist->{$s->value( 'subjectid' )} );
		}

		push @ancestors, $a;
	}

	return \@ancestors;
}

# normalise_name: normalise a name for display
sub normalise_name
{
	my( $self, $name ) = @_;
        my $g = $name->{given} || "";
        my $f = $name->{family} || "";
	foreach( $g, $f )
	{
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
	}

	return nc( EPrints::Utils::is_set( $g ) ? "$f, $g" : "$f" );
}

# From http://search.cpan.org/dist/Lingua-EN-NameCase/NameCase.pm
# Copyright (c) Mark Summerfield 1998-2008. All Rights Reserved.
sub nc
{
        my( $name ) = @_;

        return if !EPrints::Utils::is_set( $name );

        # TODO-sf2: need a way to set this globally? disabled for now
        my $SPANISH = 0;

        $name = lc( $name );                           # Lowercase the lot.

        $name =~ s{ \b (\w)   }{\u$1}gox ;           # Uppercase first letter of every word.
        $name =~ s{ (\'\w) \b }{\L$1}gox ;           # Lowercase 's.

        # Name case Mcs and Macs - taken straight from NameParse.pm incl. comments.
        # Exclude names with 1-2 letters after prefix like Mack, Macky, Mace
        # Exclude names ending in a,c,i,o, or j are typically Polish or Italian
        if ( $name =~ /\bMac[A-Za-z]{2,}[^aciozj]\b/o || $name =~ /\bMc/o )
        {
                $name =~ s/\b(Ma?c)([A-Za-z]+)/$1\u$2/go;

                # Now correct for "Mac" exceptions
                $name =~ s/\bMacEvicius/Macevicius/go ;  # Lithuanian
                $name =~ s/\bMacHado/Machado/go ;        # Portuguese
                $name =~ s/\bMacHar/Machar/go ;
                $name =~ s/\bMacHin/Machin/go ;
                $name =~ s/\bMacHlin/Machlin/go ;
                $name =~ s/\bMacIas/Macias/go ;
                $name =~ s/\bMacIulis/Maciulis/go ;
                $name =~ s/\bMacKie/Mackie/go ;
                $name =~ s/\bMacKle/Mackle/go ;
                $name =~ s/\bMacKlin/Macklin/go ;
                $name =~ s/\bMacQuarie/Macquarie/go ;
                $name =~ s/\bMacOmber/Macomber/go ;
                $name =~ s/\bMacIn/Macin/go ;
                $name =~ s/\bMacKintosh/Mackintosh/go ;
                $name =~ s/\bMacKen/Macken/go ;
                $name =~ s/\bMacHen/Machen/go ;
                $name =~ s/\bMacisaac/MacIsaac/go ;
                $name =~ s/\bMacHiel/Machiel/go ;
                $name =~ s/\bMacIol/Maciol/go ;
                $name =~ s/\bMacKell/Mackell/go ;
                $name =~ s/\bMacKlem/Macklem/go ;
                $name =~ s/\bMacKrell/Mackrell/go ;
                $name =~ s/\bMacLin/Maclin/go ;
                $name =~ s/\bMacKey/Mackey/go ;
                $name =~ s/\bMacKley/Mackley/go ;
                $name =~ s/\bMacHell/Machell/go ;
                $name =~ s/\bMacHon/Machon/go ;
        }
        $name =~ s/Macmurdo/MacMurdo/go ;

        # Fixes for "son (daughter) of" etc. in various languages.
        $name =~ s{ \b Al(?=\s+\w)  }{al}gox ;       # al Arabic or forename Al.
        $name =~ s{ \b Ap        \b }{ap}gox ;       # ap Welsh.
        $name =~ s{ \b Ben(?=\s+\w) }{ben}gox ;      # ben Hebrew or forename Ben.
        $name =~ s{ \b Dell([ae])\b }{dell$1}gox ;   # della and delle Italian.
        $name =~ s{ \b D([aeiu]) \b }{d$1}gox ;      # da, de, di Italian; du French.
        $name =~ s{ \b De([lr])  \b }{de$1}gox ;     # del Italian; der Dutch/Flemish.
        $name =~ s{ \b El        \b }{el}gox unless $SPANISH ;   # el Greek or El Spanish.
        $name =~ s{ \b La        \b }{la}gox unless $SPANISH ;   # la French or La Spanish.
        $name =~ s{ \b L([eo])   \b }{l$1}gox ;      # lo Italian; le French.
        $name =~ s{ \b Van(?=\s+\w) }{van}gox ;      # van German or forename Van.
        $name =~ s{ \b Von       \b }{von}gox ;      # von Dutch/Flemish

        # Fixes for roman numeral names, e.g. Henry VIII, up to 89, LXXXIX
        $name =~ s{ \b ( (?: [Xx]{1,3} | [Xx][Ll]   | [Ll][Xx]{0,3} )?
            (?: [Ii]{1,3} | [Ii][VvXx] | [Vv][Ii]{0,3} )? ) \b }{\U$1}gox ;

        utf8::encode( $name );

        return $name;
}



sub render_set_name
{
	my( $self, $setname ) = @_;

	return $self->{session}->html_phrase( "lib/irstats2/sets:$setname" );
}

# render_set: render a set or set value given its type. For instance, for an EPrint, this will render it via its citation.
sub render_set
{
	my( $self, $setname, $setvalue, $use_cache ) = @_;

	my $session = $self->{session};

	unless( defined $setname )
	{
		return $session->html_phrase( 'lib/irstats2/sets:repository' );
	}

	if( defined $setname && !defined $setvalue )
	{
		return $session->html_phrase( "lib/irstats2/sets:$setname" );
	}	
	
	# use cache by default...
	if( !defined $use_cache || $use_cache )
	{
		my $cache_value = $self->handler->get_rendered_set_value( $setname, $setvalue );
		HTML::Entities::decode_entities( $cache_value );	# to be safe
		return $session->make_text( $cache_value );
	}

	my $render_fn = $self->get_property( $setname, "render_single_value" );
	if( defined $render_fn && ref( $render_fn ) eq 'CODE' )
	{
		my $ret = eval { return &$render_fn( $session, $setname, $setvalue ) };
		if( $@ )
		{
			$session->log( "Stats::Sets: error in local render_single_function for '$setname': $@" );
			return $session->make_doc_fragment;
		}

		return $ret;
	}

	if( $setname eq 'eprint' )
	{
		my $eprint = $session->dataset( 'archive' )->dataobj( $setvalue );
		if( defined $eprint )
		{
			return $eprint->render_citation( 'brief' );
		}
		return $session->html_phrase( 'lib/irstats2/unknown:eprint', id => $session->make_text( $setvalue ) );
	}

	my $type = $self->get_field_type( $setname );
	
	if( defined $type )
	{
		if( $type eq 'name' || $type eq 'compound' )
		{
			return $session->make_text( "$setvalue" );
		}
		elsif( $type eq 'subject' )
		{
			my $subject = $session->dataset( 'subject' )->dataobj( $setvalue );
			return $subject->render_description if( defined $subject );
		}
		elsif( $type eq 'authorid' )
		{
			my $user = $session->dataset( 'user' )->dataobj( $setvalue );
			return $user->render_description if( defined $user );
		}
		else
		{
			my $field = $session->dataset( 'eprint' )->field( $setname );
			if( defined $field )
			{
				if( $field->get_property( "multiple" ) )
				{
					return $field->render_value( $session, [$setvalue], 0, 0, undef );
				}
				else
				{
					return $field->render_value( $session, $setvalue, 0, 0, undef );
				}
			}
		}
	}

	return $session->html_phrase( 'lib/irstats2/unknown:set', set_name => $session->make_text( $setname ), set_value => $session->make_text( $setvalue ) );
}

1;
