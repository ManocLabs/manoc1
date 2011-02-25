# netwalker device
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.
package Manoc::SNMPInfo;

use base SNMP::Info;

use Carp;
use strict;

our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    my $sub_name = $AUTOLOAD;
    
    return if $sub_name =~ /DESTROY$/;
    $sub_name =~ s/.*:://;

    {
	no strict 'refs';
	my $info = $self->{info};
	return $info->$sub_name(@_);
    }
}

sub new {
    my $class = shift;
    my $self  = {};
    bless ($self, $class);

    my %param = @_;



    my $host	= $param{host} 		|| croak "Missing host parameter";
    my $comm	= $param{community} 	|| croak "Missing community parameter";
    my $debug	= $param{debug}		|| 0;
    my $version = $param{version}	|| 2;
    my $logger  = $param{logger};

    my %snmp_info_args = (
	# Auto Discover more specific Device Class
	Debug       => $debug,
	
	# The rest is passed to SNMP::Session
	DestHost    => $host,
	Community   => $comm,
	Version     => $version,
    );

    my $info = new SNMP::Info(
			      %snmp_info_args,
			      AutoSpecify => 1
			      ) or return;

    $self->{info}		= $info;
    $self->{snmp_info_args}	= \%snmp_info_args;
    $self->{manoc_logger} 	= $logger;
    $self->{host}		= $host;

    $self->try_specify;

    return $self;
}

sub class {
    my $self = shift;
    return $self->{info}->class;
}

sub host {
    my $self = shift;
    return $self->{host};
}


sub cisco_comm_indexing {
    my $self = shift;
    return $self->{info}->cisco_comm_indexing();
}


#----------------------------------------------------------------------#

sub try_specify {
    my $self = shift;

    my $info = $self->{info};

    my $class;


    my $desc   = $info->description() || 'undef';
    $desc =~ s/[\r\n\l]+/ /g;

    $desc =~ /Cisco IOS Software, C1240 / and 
	$class = "SNMP::Info::Layer2::Aironet1240";

    $desc =~ /Cisco.*?IOS.*?CIGESM/ and
	$class = "SNMP::Info::Layer3::C3550";

    #broken
    # $desc =~ /Cisco Controller/ and
    #	$class = "SNMP::Info::Layer2::CiscoWCS";

    return unless $class;

    # check if snmp::info::specify did it right
    return if $class eq $info->class;   

    print "Manoc::SNMPInfo::try_specify() - New class: $class\n" if $info->debug(); 

    eval "require $class";
    if ($@) {
	croak "Manoc::SNMPInfo::try_specify() Loading $class failed. $@\n";
    }

    my $args    = $self->{snmp_info_args};
    my $session = $info->session();
    my $sub_obj = $class->new(%$args,
			      'Session'=>$session,
			      'AutoSpecify' => 0);
    
    unless ($sub_obj) {
        $self->{logger}->error("Manoc::SNMPInfo::try_specify() - Could not connect with new c
lass ($class)");
    }


    $self->{info} = $sub_obj;
    return;
}

#----------------------------------------------------------------------#

sub get_neighbors {
    my $self = shift;

    my $neighbors = $self->{_manoc_neighbors};
    defined($neighbors) and return $neighbors;
    
    $neighbors = $self->_discover_neighbors();
    $self->{_manoc_neighbors} = $neighbors;
    return $neighbors;
}


# Get CDP Neighbor info
sub _discover_neighbors {
    my $self = shift;

    my $logger = $self->{manoc_logger};
    my $host   = $self->{host};

    my %res;

    my $interfaces      = $self->interfaces();
    my $c_if            = $self->c_if();
    my $c_ip            = $self->c_ip();
    my $c_port          = $self->c_port();
    my $c_capabilities  = $self->c_capabilities();

    foreach my $neigh (keys %$c_if) {
	my $port  = $interfaces->{$c_if->{$neigh}};
	
	my $neigh_ip     = $c_ip->{$neigh}   || "no-ip";
	my $neigh_port   = $c_port->{$neigh} || "";

	my $cap = $c_capabilities->{$neigh};
	$logger && $logger->debug("$host/$port connected to $neigh_ip ($cap)");
	$cap = pack('B*', $cap);
	my $entry = {
	    		port		=> $neigh_port,
			addr		=> $neigh_ip,
			bridge		=> vec($cap, 2, 1),
			switch		=> vec($cap, 4, 1),
		    };
	push @{$res{$port}}, $entry;
    }
    return \%res;
}

#----------------------------------------------------------------------#

sub get_mat {
    my $self = shift;
    
    my $mat = $self->{_manoc_mat};
    defined($mat) and return $mat;

    my $interfaces = $self->interfaces();
    my $fw_mac     = $self->fw_mac();
    my $fw_port    = $self->fw_port();
    my $fw_status  = $self->fw_status();
    my $bp_index   = $self->bp_index();

    my ($status, $mac, $bp_id, $iid, $port);
    $mat = {};
    foreach my $fw_index (keys %$fw_mac) {
        $status = $fw_status->{$fw_index};
        next if defined($status) and $status eq 'self';
        $mac   = $fw_mac->{$fw_index};
        $bp_id = $fw_port->{$fw_index};
        next unless defined $bp_id;
        $iid = $bp_index->{$bp_id};
        next unless defined $iid;
        $port  = $interfaces->{$iid};

        $mat->{$mac} = $port;
    }

    $self->{_manoc_mat} = $mat;
    return $mat;
}


#----------------------------------------------------------------------#


1;
