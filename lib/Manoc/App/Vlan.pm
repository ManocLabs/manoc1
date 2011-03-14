package Manoc::App::Vlan;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;
use Carp;
use base 'Manoc::App::Delegate';
use Manoc::DB;

sub list : Resource(default error){

    my ($self, $app) = @_;
    my $schema = $app->param('schema');
    my (@vlans_rs, @vlans, $template);
    my %tmpl_param;
    my $description_length = 30;

    @vlans_rs = $schema->resultset('Vlan')->search();
    @vlans = map {
                    id              => $_->id,
                    name            => $_->name,
                    description     => short_descr($_->description, $description_length), 
                    vlan_range_id   => $_->vlan_range->id,
                    vlan_range      => get_vlan_range($schema, $_->id)->name,
                    edit_url        => "edit?id=". $_->id . "&origin=vlan/list",
                    delete_url      => "delete?id=". $_->id  . "&origin=vlan/list",
                 }, @vlans_rs;

    $tmpl_param{vlans} = \@vlans;
    $tmpl_param{new_vlan_url} = $app->manoc_url("vlan/new_vlan?origin=vlan/list");
    $template = $app->prepare_tmpl(	
				    tmpl  => 'vlan/list.tmpl',
				    title => 'Vlan'
 				  ); 

    $template->param(%tmpl_param);

    return $template->output();
}

sub view : Resource {

    my ($self, $app) = @_;
    my $schema  = $app->param('schema');
    my $query   = $app->query;
    my $id      = $query->param('id');
    my (%tmpl_param, $vlan, @ranges_rs, @ranges, $vlan_range);

    $vlan = $schema->resultset('Vlan')->find({'id'=>$id});
    (!defined($vlan)) and return $app->show_message('Error', 'Vlan not found');

    @ranges_rs = $schema->resultset('IPRange')->search({'vlan_id' => $id});
    @ranges = map {
                    name => $_->name,
                    url  => $app->manoc_url("iprange/range?name=" . $_->name)
                  }, @ranges_rs;

    $vlan_range = get_vlan_range($schema, $id);

    #Set template parameters
    $tmpl_param{id}             = $id;
    $tmpl_param{name}           = $vlan->name;
    $tmpl_param{description}    = $vlan->description;
    $tmpl_param{vlan_range_id}  = $vlan_range->id;
    $tmpl_param{vlan_range}     = $vlan_range->name;
    $tmpl_param{ranges}         = \@ranges;
    $tmpl_param{edit_url}       = "edit?id=" . $id . "&origin=vlan/view?id=" . $id;
    $tmpl_param{delete_url}     = "delete?id=" . $id  . "&origin=vlanrange/list";
    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlan/view.tmpl',
					title => 'View Vlan'
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub view_devices : Resource {

    my ($self, $app) = @_;
    my $schema  = $app->param('schema');
    my $query   = $app->query;
    my $id      = $query->param('id');
    my (%tmpl_param, @rs);
    my ($e, $it); # entry and interator

    
    @rs = $schema->resultset('IfStatus')->search(
		      {
			  'me.vlan'		=> $id,
		      },
		      {
			  alias => 'me',
			  from  => [ 
				     { me => 'if_status' },
				     [
				      { 'dev_entry' => 'devices', -join_type => 'LEFT' },
				      { 
					  'dev_entry.id'    => 'me.device',
				      }
				      ]
				     ],
			  group_by  => [qw(me.device)],
			  select    => [
					 'me.device',
					 'dev_entry.name',
					{ count  => { distinct => 'me.interface' } },
					],
			  as        =>  [qw(device name count)]
		      });


    my @ranges = map {
	device => $_->device,
	name   => $_->get_column('name'),
	count  => $_->get_column('count'),
    }, @rs;
    

    if( !scalar(@ranges) ){
	return $app->show_message('Error',"No device on Vlan $id!"); 
    }

    $tmpl_param{results} = \@ranges;
 
     #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlan/view_devices.tmpl',
					title => 'Devices of Vlan '.$id
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();

}

sub new_vlan : Resource {

    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my (%tmpl_param, $done, $message);
    my $schema      = $app->param('schema');
    my $query       = $app->query;
    my $id          = $query->param('id');
    my $origin      = $query->param('origin');

    #Call the new vlan subroutine
    if ($query->param('submit')) {
        ($done, $message) = $self->process_new_vlan($app);
        if ($done){
            $origin and return $app->manoc_redirect($origin);
            return $app->manoc_redirect("vlanrange/list");
        }
    }

    #Set template parameters
    $tmpl_param{message}         = $message;
    $tmpl_param{id}              = $id;
    $tmpl_param{name}            = $query->param('name');
    $tmpl_param{description}     = $query->param('description');
    $tmpl_param{forced_range_id} = $query->param('forced_range_id');
    $tmpl_param{origin}          = $origin;

    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlan/edit.tmpl',
					title => 'New Vlan'
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_new_vlan {

    my ($self, $app)    = @_;
    my $schema          = $app->param('schema');
    my $query           = $app->query;
    my $id              = $query->param('id');
    my $name            = $query->param('name');
    my $description     = $query->param('description');
    my $forced_range_id = $query->param('forced_range_id');
    my ($vlan_range, $res, $message);

    #Check new vlan id
    $id =~ /^\d+$/ or return (0, "Invalid vlan id");
    $schema->resultset('Vlan')->find($id) and return (0, "Duplicated vlan id");

    #Check parameters
    ($res, $message) = check_parameters($schema, $id, $name, 0);
    $res or return ($res, $message);

    #Get and check vlan range
    $vlan_range = get_vlan_range($schema, $id);
    $vlan_range or return(0, "You have to create the vlan inside a vlan range");
    if ($forced_range_id) {
        if ($vlan_range->id != $forced_range_id) {
            my $forced_range = $schema->resultset('VlanRange')->find({'id' => $forced_range_id});
            return(0, "You have to create a vlan inside vlan range: " . $forced_range->name . " (" . $forced_range->start . " - " . $forced_range->end . ")");
        }
    }

    $schema->resultset('Vlan')->create({
                                            id          => $id,
                                            name        => $name,
                                            description => $description,
                                            vlan_range  => $vlan_range->id
                                       }) or return(0, "Impossible create Vlan");

    return (1, "Done");
}

sub edit : Resource {

    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my ($done, $message);
    my $schema      = $app->param('schema');
    my $query       = $app->query;
    my $id          = $query->param('id');
    my $origin      = $query->param('origin');
    my (%tmpl_param, $vlan);

    #Call the edit vlan subroutine
    if ($query->param('submit')) {
        ($done, $message) = $self->process_edit($app);
        if ($done){
            $origin and return $app->manoc_redirect($origin);
            return $app->manoc_redirect("vlanrange/list");
        }
    }

    #Get and check vlan 
    $vlan = $schema->resultset('Vlan')->find($id);
    (!defined($vlan)) and return $app->show_message('Error', 'Vlan not found');

    #Set template parameters
    $tmpl_param{message}      = $message;
    $tmpl_param{id}           = $id;
    $tmpl_param{name}         = $vlan->name;
    $tmpl_param{description}  = $vlan->description;
    $tmpl_param{edit_enable}  = 1;
    $tmpl_param{origin}       = $origin;

    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlan/edit.tmpl',
					title => 'Edit Vlan'
 				     ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_edit {

    my ($self, $app)    = @_;
    my $schema          = $app->param('schema');
    my $query           = $app->query;
    my $id              = $query->param('id');
    my $name            = $query->param('name');
    my $description     = $query->param('description');
    my ($res, $message);

    #Check parameters
    ($res, $message) = check_parameters($schema, $id, $name, 1);
    $res or return ($res, $message);

    #Update vlan values
    my $vlan = $schema->resultset('Vlan')->find({'id' => $id}); 
    $vlan->name($name);
    $vlan->description($description);
    $vlan->update or return(0, "Impossible edit Vlan");

    return (1, "Done");
}

sub delete : Resource {

    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my $schema       = $app->param('schema');
    my $query        = $app->query;
    my $id           = $query->param('id');
    my $origin       = $query->param('origin');
    my (@range_rs, $message); 

    my $vlan = $schema->resultset('Vlan')->find($id);
    (!defined($vlan)) and return $app->show_message('Error', 'Vlan not found');

    @range_rs = $schema->resultset('IPRange')->search('vlan_id' => $id);
    @range_rs and return warning_delete($app, @range_rs);

    $vlan->delete() or return(0, "Impossible delete vlan");

    $origin and return $app->manoc_redirect($origin);
    return $app->manoc_redirect("vlanrange/list");
}

sub warning_delete {
    my ($app, @range_rs) = @_;
    my (@ranges, %tmpl_param);

    @ranges = map {
                    name => $_->name,
                    edit_url => $app->manoc_url("iprange/range?name=" . $_->name)
                  }, @range_rs;

    my $template = $app->prepare_tmpl(	
					tmpl  => 'vlan/warning_delete.tmpl',
					title => 'Warning!'
 				     ); 
    $template->param(ranges => \@ranges);
    $template->param(vlan_url => $app->manoc_url("vlanrange/list"));

    return $template->output();
}

sub check_parameters {

    my ($schema, $id, $name, $edit_enable) = @_;
    my ($dup, $vlan_range);

    $name or return (0, "Please insert vlan name");

    $dup = $schema->resultset('Vlan')->find({'name' => $name});
    if ($dup) {($edit_enable and ($dup->id == $id)) or return (0, "Duplicated vlan name");}
    $name =~ /^\w[\w-]*$/ or return (0, "Invalid vlan name: $name");

    return (1, "Ok");
}

sub get_vlan_range {
    my ($schema, $vlan_id) = @_;
    

    return ($schema->resultset('VlanRange')->find(
		{
		    start => {'<=' => $vlan_id},
		    end   => {'>=' => $vlan_id}
		}
	    ));
}


sub vtp : Resource {
    my ($self, $app) = @_;
    my $schema = $app->param('schema');
    my (@vlans,@vlans_vtp,@vlans_ondb, $template,$e,$e_db);
    my %tmpl_param;
    
    @vlans_vtp =  $schema->resultset('VlanVtp')->search();
    @vlans_vtp = sort { $a->id <=> $b->id } @vlans_vtp;
    @vlans_ondb = $schema->resultset('Vlan')->search();
    @vlans_ondb = sort { $a->id <=> $b->id } @vlans_ondb;

    $e_db = shift @vlans_ondb;
    $e = shift @vlans_vtp;
    while ( defined($e) && defined($e_db) ) {
	if( $e->id == $e_db->id ){
	    my $merge = $e->name cmp $e_db->name ? 1 : 0;
	    push @vlans, {
		id	 => $e->id,
		name_vtp => $e->name,
		name_db  => $e_db->name,
 		ondb     => 0,
		merge    => $merge,
		delete_url      => "delete?id=". $e->id  . "&origin=vlan/vtp",
		
	    };
	    #incrementa $e & $e_db
	    $e_db = shift @vlans_ondb;
	    $e = shift @vlans_vtp;	   
	    next;
	}
	if( $e->id < $e_db->id ) {
	    push @vlans, {
		id	 =>$e->id,
		name_vtp =>  $e->name,
		name_db  => 'Not Present!',
		ondb     => 1,
	    };
	    #incrementa solo $e
	    $e = shift @vlans_vtp;
	    next;
	}
	if( $e->id > $e_db->id ) {
	    push @vlans, {
		id	 => $e_db->id,
		name_vtp => 'Not Present!',
		name_db  => $e_db->name,
		ondb     => 0,
	    };
	    #incrementa solo $e_db
	    $e_db = shift @vlans_ondb;
	    next;
	}
    }
    while(defined($e)){
	push @vlans, {
	    id => $e->id,
	    name_vtp => $e->name,
	    name_db => 'Not Present!',
	    ondb     => 1,
	};
	$e=shift @vlans_vtp;	
    }
    while(defined($e_db)){
	push @vlans, {
	    id => $e_db->id,
	    name_vtp =>'Not Present!',
	    name_db => $e_db->name,
	    ondb     => 0,
	};
	$e_db=shift @vlans_ondb;
    }
    $tmpl_param{vlans} = \@vlans;
    $template = $app->prepare_tmpl(	
					tmpl  => 'vlan/list_vtp.tmpl',
					title => 'Vlan'
					); 
    $template->param(%tmpl_param);
    
    return $template->output();
}

sub add_vlan_ondb : Resource {
    my ($self, $app) = @_;
    my $query        = $app->query;
    my $id           = $query->param('id');
    my $name         = $query->param('name');
    my $schema       = $app->param('schema');
    my $vlan_range   = get_vlan_range($schema,$id);

    
    if (!$vlan_range) {
	my $message = 'Vlan Range not defined.';
	$message   .= '<br><br><a href="../vlan/vtp">Back to Vlan</a>'; 

	return $app->show_message('Error', $message);
    }

    $schema->resultset('Vlan')->create(
	{'id'=>$id , 
	 'name'=>$name,
	 'description' => '',
	 'vlan_range' => $vlan_range }) or
	 return $app->show_message('Error', 'Vlan range not defined!.');
    
    return $app->manoc_redirect("vlan/vtp");

}

sub merge_name : Resource {
    my ($self, $app) = @_;
    my $query   = $app->query;
    my $id      = $query->param('id');
    my $name      = $query->param('name');
    my $schema       = $app->param('schema');
    
    my $rs = $schema->resultset('Vlan')->search(
						{
						    id => $id
						    }) or return(0, "Select Failed!");
    $rs->update({name => $name});
    
    $app->manoc_redirect("vlan/vtp");
}

########################################################################
#
#  Utils
#
########################################################################

sub short_descr {
    my ($description, $len) = @_;
    my $s_descr;
    
    if (defined $description) {
        $s_descr = substr($_->description, 0, $len);
        (length($description) > $len) and $s_descr .= "...";
    } else {
        return undef;
    }
    
    return $s_descr;
}


1;
