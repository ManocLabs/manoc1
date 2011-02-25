package Manoc::App::User;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;
use Carp;
use base 'Manoc::App::Delegate';
use Manoc::DB;
use Regexp::Common qw[Email::Address];
use Email::Address;

sub list : Resource(default error){

    my ($self, $app) = @_;
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");             #Check permission

    my $schema = $app->param('schema');
    my %tmpl_param;

    my @rs = $schema->resultset('User')->search(
                                                    {},
                                                    {
                                                        'prefetch' => {'map_user_role' => 'role'},
                                                        'include_columns' => [{ 'role' => 'role.role' }],
                                                        order_by => 'login'
                                                    }
                                               );

    my @users = map {
                        login           => $_->login,
                        full_name       => $_->fullname,
                        email           => $_->email,
                        active          => $_->active,
                        roles           => join( ", ", map { $_->role->role } $_->map_user_role->all()),
                        auto_edit       => lc($app->session->param('MANOC_USER')) eq lc($_->login),
                        view_url        => "view?user_id=". $_->id,
                        edit_url        => "edit?user_id=". $_->id,
                        delete_url      => "delete?user_id=". $_->id,
                        switch_stat_url => "switch_status?user_id=" . $_->id
                    },  @rs;

    $tmpl_param{users} = \@users;

    my $template = $app->prepare_tmpl(	
					tmpl  => 'user/list.tmpl',
					title => 'Users'
 				     ); 

    $template->param(%tmpl_param);
    $template->param(new_user_url => $app->manoc_url("user/edit"));
    $template->param(role_url => $app->manoc_url("role/"));
    return $template->output();
}

sub view : Resource {

    my ($self, $app) = @_;
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");

    my $schema  = $app->param('schema');
    my $query   = $app->query;
    my $user_id = $query->param('user_id');
    my ($user, %tmpl_param, @user_roles);

    $user = $schema->resultset('User')->find({'id'=>$user_id});
    (!defined($user)) and return $app->show_message('Error', 'User not found');

    @user_roles = map {role => $_->role->role}, $user->map_user_role;

    $tmpl_param{username}   = $user->login;
    $tmpl_param{full_name}  = $user->fullname;
    $tmpl_param{email}	    = $user->email;
    $tmpl_param{active}	    = $user->active;
    $tmpl_param{roles}      = \@user_roles;
    $tmpl_param{auto_edit}  = lc($app->session->param('MANOC_USER')) eq lc($user->login);
    $tmpl_param{new_url}    = "edit";
    $tmpl_param{edit_url}   = "edit?user_id=" . $user_id;
    $tmpl_param{delete_url} = "delete?user_id=" . $user_id;

    my $template = $app->prepare_tmpl(	
					tmpl  => 'user/view.tmpl',
					title => $user->login
 				     ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub edit : Resource {

    my ($self, $app) = @_;
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");

    my ($done, $message);
    my $schema      = $app->param('schema');
    my $query       = $app->query;
    my $username    = $query->param('username');
    my $full_name   = $query->param('full_name');
    my $email       = $query->param('email');
    my $active      = $query->param('active');
    my $user_id     = $query->param('user_id');
    my $edit_enable = 0;
    my (@user_roles, @all_roles, $user, %tmpl_param, $ar, $ur);

    #Check to enable the edit mode
    if ($user_id){
        $user = $schema->resultset('User')->find({'id'=>$user_id});  #Retrieve user attributes
        (!defined($user)) and return $app->show_message('Error', 'User not found');
        $edit_enable = 1;
    }

    #Call the new/edit user subroutine
    if ($query->param('submit')) {
        if ($edit_enable){
            ($done, $message) = $self->process_edit_user($app);
        } else {
            ($done, $message) = $self->process_new_user($app);
        } 
        if ($done){
           return $app->manoc_redirect("user");
        }
    }

    #Edit mode
    if ($edit_enable){
        $username      = $user->login;                               #Set the user's attributes
        $email         = $user->email;
        $full_name     = $user->fullname;
        $active        = $user->active;

        my @rs_roles = $schema->resultset('Role')->search();                #Retrieve all roles to show
        @all_roles = map {
                            role => $_->role,
                            id   => $_->id
                         }, @rs_roles;

        @user_roles = map {role => $_->role->role}, $user->map_user_role;   #Retrieve the user roles

        foreach $ar(@all_roles){                                            #Check the user's roles
            foreach $ur(@user_roles){
                if ($ar->{role} eq ($ur->{role})){
                    $ar->{checked} = 1;
                }
            }
        }
    }

    #Set template parameters
    $tmpl_param{message}	= $message;
    $tmpl_param{user_id}        = $user_id;
    $tmpl_param{username}	= $username;
    $tmpl_param{full_name}	= $full_name;
    $tmpl_param{email}	        = $email;
    $tmpl_param{active}	        = $active;
    $tmpl_param{edit_enable}    = $edit_enable;
    $tmpl_param{auto_edit}      = lc($app->session->param('MANOC_USER')) eq lc($username);
    $tmpl_param{user_roles}     = \@user_roles;
    $tmpl_param{all_roles}      = \@all_roles;
    $tmpl_param{delete_url}     = "delete?user_id=" . $user_id;

    #Call the tamplate
    my $template = $app->prepare_tmpl(	
					tmpl  => 'user/edit.tmpl',
					title => 'User'
 				       ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_edit_user{

    my $pw_len          = 6;
    my ($self, $app)    = @_;
    my $schema          = $app->param('schema');
    my $query           = $app->query;
    my $user_id         = $query->param('user_id');
    my $username        = $query->param('username');
    my $password        = $query->param('password');
    my $conf_password   = $query->param('conf_password');
    my $full_name       = $query->param('full_name');
    my $email           = $query->param('email');
    my $active          = $query->param('active');
    my (@all_roles_rs, $user_roles_rs);

    my $user = $schema->resultset('User')->find({'id'=>$user_id});

    #Check parameters
    $username or return (0, "Please insert username");
    $active or $active=0;

    #Check username
    if ($schema->resultset('User')->search(login => $username)->count()){
        return (0, "Duplicated username") unless ($username eq $user->login);             #In this case we don't have to warn about the duplicated username
    }
    $username =~ /^\w[\w-]*$/ or return (0, "Invalid username");

    #Check password
    ($password eq $conf_password) or return (0, "Confirmed password not valid");
    if ($password){
        ($pw_len <= length($password)) or return (0, "Password must be at least $pw_len characters");
    } 

    #Check e-mail
    $email =~ /($RE{Email}{Address})/g or return (0, "Invalid email");

    #Update user in DB
    $password and $user->password(Digest::MD5::md5_base64($password));
    $user->set_column('email', $email);

    unless (lc($app->session->param('MANOC_USER')) eq lc($username)) {                          #Autoedit check
        $user->set_column('login', $username);
        $user->set_column('fullname', $full_name);
        $user->set_column('active', $active);

        #Set user's roles
        $user_roles_rs = $schema->resultset('UserRole')->search({'user_id' => $user_id});       #Delete old roles
        $user_roles_rs->delete;
        @all_roles_rs = $schema->resultset('Role')->search();                                   #Retrieve all roles
        foreach (@all_roles_rs){                                                                #Add new roles
            my $role = $_->role;
            my $user_role_id = $query->param($role);
            if ($user_role_id){
                $schema->resultset('UserRole')->create({
                                                            user_id => $user_id,
                                                            role_id => $query->param($_->role)
                                                        });
            }
        }
    }

    $user->update or return (0, "Impossible update database");
    return(1, "Done");
}

sub process_new_user{

    my $pw_len          = 6;
    my ($self, $app)    = @_;
    my $schema          = $app->param('schema');
    my $query           = $app->query;
    my $username        = $query->param('username');
    my $password        = $query->param('password');
    my $conf_password   = $query->param('conf_password');
    my $full_name       = $query->param('full_name');
    my $email           = $query->param('email');

    #Check parameters
    $username or return (0, "Please insert username");
    $password or return (0, "Please insert password");
    $conf_password or return (0, "Please confirm password");

    #Check username
    $schema->resultset('User')->search(login => $username)->count() and return (0, "Duplicated username");
    $username =~ /^\w[\w-]*$/ or return (0, "Invalid username");

    #Check password
    ($password eq $conf_password) or return (0, "Confirmed password not valid");
    ($pw_len <= length($password)) or return (0, "Password must be at least $pw_len characters");

    #Check e-mail
    $email =~ /($RE{Email}{Address})/g or return (0, "Invalid email");

    #Insert user in DB
    $schema->resultset('User')->create({
                                        login       => $username,
                                        password    => Digest::MD5::md5_base64($password),
                                        fullname    => $full_name,
                                        email       => $email,
                                        active      => 1
                                       }) or return (0, "Impossible create user");
    return(1, "Done");
}

sub delete : Resource{

    my ($self, $app) = @_;
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");

    my $schema       = $app->param('schema');
    my $query        = $app->query;
    my $user_id      = $query->param('user_id');

    my $user = $schema->resultset('User')->find($user_id);
    (!defined($user)) and return $app->show_message('Error', 'User not found');
    $user->delete() or return(0, "Impossible update user");

    return $app->manoc_redirect("user");
}

sub switch_status : Resource{

    my ($self, $app) = @_;
    Manoc::UserAuth->check_permission($app, ('admin')) or return $app->manoc_redirect("forbidden");

    my $schema       = $app->param('schema');
    my $query        = $app->query;
    my $user_id      = $query->param('user_id');

    my $user = $schema->resultset('User')->find($user_id);
    (!defined($user)) and return $app->show_message('Error', 'User not found');
    $user->active(!$user->active);
    $user->update() or return(0, "Impossible change user status");            #TODO: redirect to an error page

    return $app->manoc_redirect("user");
}

1;
