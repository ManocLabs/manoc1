package Manoc::App::Building;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;
use Carp;
use base 'Manoc::App::Delegate';
use Manoc::DB;
use Manoc::Utils qw(clean_string);
use Manoc::App::Search;

sub num {
  my ($self, $name) = @_;
  if( $name =~ m/\w+\s*(\d+\w*)/ ){
      return $1;
  }
}

sub list : Resource(default error) {
    my ($self, $app) = @_;
    my $schema = $app->param('schema');
    
    my @building_table = map +{
	id 	=> $_->id,
	name	=> $_->name,
	desc    => $_->description,
	n_racks => $_->racks->count()
	},  $schema->resultset('Building')->all();

    @building_table = sort { $a->{name} cmp $b->{name} } @building_table;
   

    my $minisearch = Manoc::App::Search::make_minisearch_widget($app, {scope => 'building'});

    my $template  = $app->prepare_tmpl(
				       tmpl  => "building/list.tmpl",
				       title => "Building list"
				       );
    $template->param(building_table => \@building_table);
    $template->param(minisearch     => $minisearch);

    return $template->output();
}

sub view : Resource {
    my ($self, $app) = @_;
    my $query = $app->query();

    my $schema = $app->param('schema');

    my $id       = clean_string($query->param('id'));
    my $building = $schema->resultset('Building')->find($id);
    
    if (!defined($building)) {
	return $app->show_message('Error', 'Building not found');
    }

    my @racks;
    my %floor_rack;
    foreach my $rack ($building->racks) {
	push @{$floor_rack{$rack->floor}}, $rack; 
    }
    foreach my $floor (sort { $a <=> $b } keys %floor_rack) {
	my @r = sort { $a <=> $b } @{$floor_rack{$floor}};
	push @racks, {	    
	    floor	=> $floor,
	    list	=> [map +{ id => $_->id, name => $_->name  }, @r ]
	}
    }

    my $name = $building->name;

    my %tmpl_param;
    $tmpl_param{name} 		= $name;
    $tmpl_param{description}	= $building->description;
    $tmpl_param{notes}    	= $building->notes;
    $tmpl_param{edit_link}	= "edit?id=$id";
    $tmpl_param{delete_link}	= "delete?id=$id";
    $tmpl_param{add_link}	= $app->manoc_url("rack/create?building=$id");

    my $template  = $app->prepare_tmpl(
				       tmpl  => "building/view.tmpl",
				       title => "Building $name"
				       );    
    $template->param(%tmpl_param);
    $template->param(racks => \@racks);

    return $template->output();
}

sub create : Resource {
    my ($self, $app) = @_;
    
    #Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");             
    
    my $query = $app->query;
    my $schema = $app->param('schema');

    my $message;
    if ($query->param('submit')) {
	my $done;
	($done, $message) = $self->process_create_building($app);
	if ($done) {
	    my $backref = $query->param('backref');
	    $backref and
		return $app->manoc_redirect($backref, building => $message);

	    return $app->manoc_redirect("building/view", id => $message);
	}
    }

    my %tmpl_param;

    $tmpl_param{name}		= $query->param('name') || '';
    $tmpl_param{description}	= $query->param('description') || '';
    $tmpl_param{backref}	= $query->param('backref') || '';
    $tmpl_param{message}	= $message;

    my $template  = $app->prepare_tmpl(
				       tmpl  => 'building/create.tmpl',
				       title => 'New Building'
				       );    

    $template->param(%tmpl_param);

    return $template->output();
    
}

sub process_create_building {
    my ($self, $app) = @_;
    
    my $query = $app->query;
    my $schema = $app->param('schema');

    my $name = $query->param('name');

    $name =~ /\w/ or return (0, 'Invalid name');

    my $count_duplicates = $schema->resultset('Building')->search({
	name => $name})->count();
    if ($count_duplicates > 0) {
	return (0, 'Duplicated name');
    }    

    my $description = $query->param('description');

    my $building =  $schema->resultset('Building')->create({
	name		=> $name,
	description	=> $description
    });


    return (1, $building->id);
}


sub edit : Resource {
    my ($self, $app) = @_;
    
    # check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or 
	return $app->manoc_redirect("forbidden");             
    
    my $query = $app->query;
    my $schema = $app->param('schema');

    my $id = $query->param('id');
    defined($id) or
	return $app->show_message('Error', 'Invalid building ID');
    my $building = $schema->resultset('Building')->find($id);
    defined($building) or
	return $app->show_message('Error', 'Building not found');       

    my $message;
    if ($query->param('submit')) {
	my $done;
	($done, $message) = $self->process_edit_building($app, $building);
	if ($done) {
	    return $app->manoc_redirect("building/view", id=>$id);
	}
    }


    my $description = $query->param('description') 
	|| $building->description
	|| '';
    my $notes = $query->param('notes') 
	|| $building->notes
	|| '';

    my $name = $query->param('name') || $building->name;

    my %tmpl_param;
    $tmpl_param{id}		= $id;
    $tmpl_param{name}		= $name;
    $tmpl_param{description}	= $description;
    $tmpl_param{notes}	        = $notes;
    $tmpl_param{message}	= $message;

    my $template  = $app->prepare_tmpl(
				       tmpl  => 'building/edit.tmpl',
				       title => 'Edit Building'
				       );    

    $template->param(%tmpl_param);

    return $template->output();
    
}

sub process_edit_building {
    my ($self, $app, $building) = @_;

    my $query = $app->query;    
    my $schema = $app->param('schema');

    # validate name
    my $name = $query->param('name');
    $name =~ /\w/ or return (0, 'Invalid name');
    my $count_duplicates = $schema->resultset('Building')->search({
	id => { '!=', $building->id },
	name => $name})->count();
    if ($count_duplicates > 0) {
	return (0, 'Duplicated name');
    }

    my $description = $query->param('description'); 
    my $notes = $query->param('notes'); 

    $building->name($name);    
    $building->description($description);    
    $building->notes($notes);
    $building->update;
    return 1;
}

sub delete:Resource {
    my ($self, $app) = @_;
    
    #Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");
    
    my $id     = $app->query->param('id');
    my $schema = $app->param('schema');

    defined($id) or
	return $app->show_message('Error', 'Building not found');
    
    my $building = $schema->resultset('Building')->find($id);
    defined($building) or
	return $app->show_message('Error', 'Building not found');
    
    if ($schema->resultset('Rack')->search({ building => $id})->count) {
	return $app->show_message('Error', 'Building is not empty. Cannot be deleted.');
    }

    $building->delete;
    return $app->show_message('Success', 'Building deleted. Back to the'.'<a href="' . $app->manoc_url("device/list") . '"> device list</a>.');
}

1;
