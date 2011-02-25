package Manoc::UserAuth;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.


use strict;
use warnings;

use Manoc::DB;
use Digest::MD5;

use base qw(Class::Accessor);
Manoc::UserAuth->mk_accessors( qw(username password app) );


sub new {
    my($class) = shift;

    my $self = {};
    my $params = @_;

    $params = { @_ } if (ref($params) ne 'HASH');
    $class  =  ref($class) || $class;
    $self   = bless($self, $class);
    return $self->init($params);
}


#
# Object initialization 
#

sub init {
    my $self    = shift;
    my($params) = @_;

    $self->username($params->{username}) if ($params->{username});
    $self->password($params->{password}) if ($params->{password});
    $self->app($params->{app})           if ($params->{app});

    return $self;
}

sub auth {
    my($self) = shift;

    my $schema = $self->app->param('schema');

    return $schema->resultset('User')->search({
                                                    login => $self->username, 
                                                    password => (Digest::MD5::md5_base64($self->password)),
                                                    active => 1
                                              })->count();
}

sub check_permission {
    my ($self, $app, @req_roles) = @_;

    my $user = $app->session->param('MANOC_USER');
    my $schema = $app->param('schema');
    my ($rl, $req_r, @user_roles);

    my $rs = $schema->resultset('User')->find(
                                                {'login' => $user},
                                                {'prefetch' => {'map_user_role' => 'role'}},
                                             );

    @user_roles = map {$_->role->role} $rs->map_user_role->all();

    foreach $rl(@user_roles){
        foreach $req_r(@req_roles){
            if ($rl eq $req_r) {return 1;}
        }
    }

    return 0;
}

1;
