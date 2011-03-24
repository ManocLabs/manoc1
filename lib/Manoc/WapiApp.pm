package Manoc::WapiApp;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;

use base 'CGI::Application';
use Manoc::DB;
use Manoc::Utils;

use CGI::Application::Plugin::Config::Simple;
use CGI::Carp qw(fatalsToBrowser warningsToBrowser);
use YAML::Any ();

use Encode;

use POSIX qw(strftime);

sub setup {
    my $self = shift;
    
    $self->start_mode('about');
    $self->error_mode('error');

    $self->run_modes([qw(about winlogon hostinfo
			 dhcp_leases dhcp_reservations
			 )]);

    # mode name directly from $ENV{PATH_INFO}.
    $self->mode_param(
		      path_info=> 1,
		      param =>'rm'
		      );
}

sub cgiapp_init {
    my $self = shift;
    my %args = @_;

    my $home = $args{home} || croak "missing param home";

    $self->param('home', $home);
    $self->config_file($args{conf});    

    # start db
    my $schema = Manoc::DB->connect(Manoc::Utils::get_dbi_params($self->config));
    confess("cannot connect to DB") unless $schema;
    $self->param('schema', $schema);
}

sub teardown {
    my ($self) = @_;

    my $schema = $self->param('schema');
    $schema->storage->disconnect();
}


#----------------------------------------------------------------------#
#                                                                      #
#                               Run Modes                              #
#                                                                      #
#----------------------------------------------------------------------#

sub error {
    my $self  = shift;
    my $error = shift;
    return "<p>There has been an error: $error</p>";
}

#----------------------------------------------------------------------#

sub about {
    my $self = shift;

    return "Manoc WebAPI";
}

#----------------------------------------------------------------------#

sub winlogon {
    my $self     = shift;    
    my $query    = $self->query;
    my $schema   = $self->param('schema');

    my $user   = $query->param('user'); 
    my $ipaddr = $query->param('ipaddr');

    $user or 
	return "Missing user param";
    $ipaddr =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/o or
	return "Bad ipaddr";

    my $timestamp = time();

    # computer logon
    if ($user =~ /([^\$]+)\$$/) {
	my $name = $1;

	my @entries = $schema->resultset('WinHostname')->search({
	    ipaddr    => $ipaddr,
	    name      => $name,
	    archived  => 0 });
	
	if ( scalar(@entries) > 1 ) {
	    return "Error";
	}

	if (@entries) {
	    my $entry = $entries[0];	
	    $entry->lastseen($timestamp);
	    $entry->update();
	} else {
	    $schema->resultset('WinHostname')->create({
		ipaddr    => $ipaddr,
		name	  => $name,
		firstseen => $timestamp,
		lastseen  => $timestamp,
		archived  => 0});
	}
	
	return "OK";
    }

    my @entries = $schema->resultset('WinLogon')->search({
							 user	  => lc($user),
							 ipaddr	  => $ipaddr,
							 archived => 0
							 });


    scalar(@entries) > 1 and 
	return "Error";
    
    if (@entries) {
	my $entry = $entries[0];	
	$entry->lastseen($timestamp);
	$entry->update();
    } else {
	$schema->resultset('WinLogon')->create({
	    ipaddr    => $ipaddr,
	    user      => lc($user),
	    firstseen => $timestamp,
	    lastseen  => $timestamp,
	    archived  => 0
	    });
    }
    
    return "OK";
}

#----------------------------------------------------------------------#

sub hostinfo {
    my $self     = shift;    
    my $query    = $self->query;

    my $user   = $query->param('user'); 
    my $ipaddr = $query->param('ipaddr');

    my $r = "";
    foreach my $name ($query->param) {
	my $val = $query->param($name);
	$r .= "NAME: $name\nVAL: $val\n";
	$r .= "UTF8: " . Encode::is_utf8($val) . "\n";
	$r .= "DECODED: " . decode_utf8($val) . "\n";
    }
    return $r;
}

#----------------------------------------------------------------------#

sub dhcp_leases {
    my $self     = shift;    
    my $schema   = $self->param('schema');
    
    my $rs = $schema->resultset('DHCPLease');

    my $query    = $self->query;
    my $server   = $query->url_param('server');
    $server ||= $query->remote_host();
    my $data = $query->param('POSTDATA');    

    my $records = YAML::Any::Load($data);
    
    $rs->search({server => $server})->delete();

    my $n_created;
    foreach my $r (@$records) {
	my $macaddr  = $r->{macaddr}  or next;
	my $ipaddr   = $r->{ipaddr}   or next;
	my $start    = $r->{start}    or next;
	my $end      = $r->{end}      or next;

	my $hostname = $r->{hostname};
	my $status   = $r->{status};

	$rs->update_or_create({
	    server   => $server,
	    macaddr  => $macaddr,
	    ipaddr   => $ipaddr,
	    hostname => $hostname,
	    start    => $start,
	    end      => $end,
	    status   => $status,
	});
	$n_created++;
    }
    
    return "$server: $n_created/" . scalar(@$records);
}
 

sub dhcp_reservations {
    my $self     = shift;    

    my $schema   = $self->param('schema');
    my $rs = $schema->resultset('DHCPReservation');

    my $query    = $self->query;
    my $server   = $query->url_param('server');
    $server ||= $query->remote_host();
    my $data = $query->param('POSTDATA');    

    my $records = YAML::Any::Load($data);
    
    $rs->search({server => $server})->delete();

    my $n_created;
    foreach my $r (@$records) {
	my $macaddr  = $r->{macaddr}  or next;
	my $ipaddr   = $r->{ipaddr}   or next;
	my $hostname = $r->{hostname} or next;
	my $name     = $r->{name}     or next;

	$rs->create({
	    server   => $server,
	    macaddr  => $macaddr,
	    ipaddr   => $ipaddr,
	    name     => $name,
	    hostname => $hostname,
	});
	$n_created++;
    }

    return "$server: $n_created/" . scalar(@$records);
}


#----------------------------------------------------------------------#
1;
