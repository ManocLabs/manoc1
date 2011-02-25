package Manoc::App::Role;
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
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my $schema = $app->param('schema');
    my (@roles_rs, @roles, $users_rs);
    my %tmpl_param;

    @roles_rs = $schema->resultset('Role')->search();
    @roles = map {
                    id         => $_->id,
                    role       => $_->role,
                    delete_url => "delete_role?role_id=". $_->id,
                 }, @roles_rs;

    foreach (@roles){
        $users_rs = $schema->resultset('UserRole')->search({'role_id' => $_->{id}});
        $_->{num_users} = $users_rs->count;
    }

    $tmpl_param{roles} = \@roles;

    my $template = $app->prepare_tmpl(	
					tmpl  => 'role/list.tmpl',
					title => 'Roles'
 				     ); 

    $template->param(%tmpl_param);
    $template->param(new_role_url => $app->manoc_url("role/new_role"));
    $template->param(user_url => $app->manoc_url("user/"));
    return $template->output();
}

sub new_role : Resource {

    my ($self, $app) = @_;
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my ($done, $message);
    my $schema    = $app->param('schema');
    my $query     = $app->query;
    my $role      = $query->param('role');
    my %tmpl_param;

    #Call the new role subroutine
    if ($query->param('submit')) {
        ($done, $message) = $self->process_new_role($app);
        if ($done){
           return $app->manoc_redirect("role");
        }
    }

    #Set template parameters
    $tmpl_param{message} = $message;
    $tmpl_param{role} = $role;

    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'role/new.tmpl',
					title => 'Add Role'
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_new_role{

    my ($self, $app)    = @_;
    my $schema          = $app->param('schema');
    my $query           = $app->query;
    my $role            = $query->param('role');

    #Check parameters
    $role or return (0, "Please insert role name");

    #Check username
    $schema->resultset('Role')->search(role => $role)->count() and return (0, "Duplicated role name");
    $role =~ /^\w[\w-]*$/ or return (0, "Invalid role name");

    #Insert user in DB
    $schema->resultset('Role')->create({role => $role}) or return (0, "Impossible create role");

    return (1, "Done");
}

sub delete_role : Resource{

    my ($self, $app) = @_;
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my $schema       = $app->param('schema');
    my $query        = $app->query;
    my $role_id      = $query->param('role_id');

    my $rs = $schema->resultset('Role')->find($role_id);
    (!defined($rs)) and return $app->show_message('Error', 'Role not found');
    $rs->delete() or return (0, "Impossible delete role");

    return $app->manoc_redirect("role");
}


1;
