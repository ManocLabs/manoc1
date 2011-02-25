package Manoc::App::Rack;
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
use Data::Dumper;

sub view : Resource(default error){
    my ($self, $app) = @_;
    my $query 	= $app->query();
    my $id 	= clean_string($query->param('id'));
    my $schema = $app->param('schema');
    
    my  $rack  = $schema->resultset('Rack')->find({id => $id});
    

    if (!defined($rack)) {
	return $app->show_message('Error', 'Rack not found');
    }
    my $building		= $rack->building;
    my $name			= $rack->name;

    my %tmpl_param;
    
    $tmpl_param{name}       	= $name;
    $tmpl_param{notes}		= $rack->notes;
    $tmpl_param{floor}		= $rack->floor;
    $tmpl_param{building_id}	= $building->id;
    $tmpl_param{building_name}	= $building->name;
    $tmpl_param{building_descr}	= $building->description;

    $tmpl_param{edit_link} = "edit?id=$id";
    $tmpl_param{delete_link} = "delete?id=$id";
    $tmpl_param{add_link}  = $app->manoc_url("device/create?rack=$id");
    
    my @devices = map +{
	address		=> $_->id,
	name		=> $_->name,
	level		=> $_->level,
	edit_link	=> $app->manoc_url('device/edit?id=' . $_->id)
	}, $rack->devices;
    @devices = sort { $a->{level} <=> $b->{level} } @devices;
    
      my $template = $app->prepare_tmpl(
				       tmpl  => "rack/view.tmpl",
				       title => "Rack $name"
				       );    
    $template->param(%tmpl_param);
    $template->param(devices => \@devices);
    return $template->output;
}

sub create : Resource {
    my ($self, $app) = @_;
        
    # Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");
    
    my $query = $app->query();
    my $schema = $app->param('schema');
   
    my $building_id = clean_string($query->param('building'));
    defined($building_id) or
	return 	$app->show_message('Error', 
				    'Trying to create a rack without a valid building');
    
    my $building = $schema->resultset('Building')->find($building_id);
    defined($building) or
	return 	$app->show_message('Error', 
				    'Trying to create a rack without a valid building');
    

    my $message;
    if ($query->param('submit')) {
	my $done;
	($done, $message) = $self->process_new_rack($app, $building);
	if ($done) {
	    my $back_ref = $query->param('backref');
	    $back_ref and
		return $app->manoc_redirect($back_ref, rack=>$message);

	    return $app->manoc_redirect("rack/view", id=>$message);
	}
    }

   
    my $floor     = $query->param('floor');
    my $name 	  = 'new rack';
    my $template = $app->prepare_tmpl(
				      tmpl  => 'rack/create.tmpl',
				      title => 'New Rack',
				      );

    $template->param(message		=> $message);
    $template->param(backref    	=> $query->param('backref') || '');

    $template->param(
		     name		=> $name,
		     building_name	=> $building->name,
		     building_id	=> $building_id,
		     floor		=> $floor
		     );

    return $template->output;
}

sub process_new_rack {
    my ($self, $app, $building) = @_;
    my $query = $app->query;
    my $schema = $app->param('schema');


    # validate name
    my $name = $query->param('name');
    $name =~ /\w/ or return (0, 'Invalid name');
   
    my $count_duplicates = $schema->resultset('Rack')->search({
	name => $name})->count();
    if ($count_duplicates > 0) {
	return (0, 'Duplicated name');
    }    

    # validate floor
    my $floor	= $query->param('floor');
    $floor =~ /^-?\d+$/o or
	return (0, 'Invalid floor');

	
    # create rack
    my $rack = $schema->resultset('Rack')->create({
	name		=> $name,
	building	=> $building->id,
	floor		=> $floor
	});

    return (1, $rack->id);
}

sub edit : Resource  {
    my ($self, $app) = @_;
    
    #Check permissio
    Manoc::UserAuth->check_permission($app, ('admin')) or 
	return $app->manoc_redirect("forbidden");
    
    my $query = $app->query();
    my $schema = $app->param('schema');

    my $id = $query->param('id');
    defined($id) or
	return $app->show_message('Error', 'Unspecified rack');

    my $rack = $schema->resultset('Rack')->find({id => $id});
    defined($rack) or
	return $app->show_message('Error', 'Rack not found');
    
    my $message;
    if ($query->param('submit')) {
	my $done;
	
	($done, $message) = $self->process_edit_rack($app, $rack);
	if ($done) {
	    return $app->manoc_redirect("rack/view", id => $id);
	}
    }
  
    my %tmpl_param;

    $tmpl_param{id}	= $id;
    $tmpl_param{name}	= $query->param('name') || $rack->name;
    $tmpl_param{floor}	= $query->param('floor') || $rack->floor;
    $tmpl_param{notes}	= $query->param('notes') || $rack->notes;
    $tmpl_param{building_label} = 'Building ' . $rack->building->id . ' (' . $rack->building->description .')';
    $tmpl_param{message}= $message;
    
    my $template = $app->prepare_tmpl(
				       tmpl  => 'rack/edit.tmpl',
				       title => 'Edit Rack'
				       );    
    $template->param(%tmpl_param);
    return $template->output;
}

sub process_edit_rack {
    my ($self, $app, $rack) = @_;

    my $query = $app->query();
    my $schema = $app->param('schema'); 

    # validate floor
    my $floor = $query->param('floor');
    $floor =~ /^-?\d+$/ or 
	return (0, 'Invalid floor '.$floor);

    # validate name
    my $name = $query->param('name');
    $name =~ /\w/ or return (0, 'Invalid name');   
    my $count_duplicates = $schema->resultset('Rack')->search({
	id => { '!=', $rack->id },
	name => $name})->count();
    if ($count_duplicates > 0) {
	return (0, 'Duplicated name');
    }

    my $notes = $query->param('notes');
    
    $rack->name($name);
    $rack->notes($notes);
    $rack->floor($floor);
    $rack->update;

    return 1;
}

sub delete:Resource {
    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission
    
    my $id     = $app->query->param('id');
    my $schema = $app->param('schema');

    defined($id) or
	return $app->show_message('Error', 'Rack not found');
    
    my $rack = $schema->resultset('Rack')->find({id => $id});
    defined($rack) or
	return $app->show_message('Error', 'Rack not found');
    
    if ($schema->resultset('Device')->search({ rack => $id})->count) {
	return $app->show_message('Error', 'Rack is not empty. Cannot be deleted.');
    }

    my $building = $rack->building->id;
    $rack->delete;
    return $app->show_message('Success', 'Rack deleted. Back to '.'<a href="' . $app->manoc_url("building/view?id=$building") . '">building</a>.');
}

1;
