package Manoc::DB::Result::Building;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.
use base 'DBIx::Class';

__PACKAGE__->load_components(qw/PK::Auto Core/);

__PACKAGE__->table('buildings');
__PACKAGE__->add_columns(
			 id => {
			     data_type => 'integer',
			     is_nullable	=> 0,
			     is_auto_increment 	=> 1,
			 },
			 name => {
			     data_type	=> 'varchar',
			     size	=> '32',
			 },
			 description => {
			     data_type => 'varchar',
			     size      => '255',			     
			 },
			 notes => {
			     data_type => 'text',		     
			 },
			 );

__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint([ qw/name/ ]);

__PACKAGE__->has_many(racks => 'Manoc::DB::Result::Rack',
		     'building',  { cascade_delete => 0 });

1;
