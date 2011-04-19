use warnings;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.
use strict;

package Manoc::Netwalker;

use base qw(Class::Accessor);


use FindBin;
use lib "$FindBin::Bin/../lib";

use SNMPLib;
use Manoc::DB;
use Manoc::Utils;

use Pod::Usage;
use Carp;
use Data::Dumper;

use IO::Socket;
use POSIX ":sys_wait_h";
use Fcntl ':flock'; # import LOCK_* constants


Manoc::Netwalker->mk_accessors( qw(logger schema debug comm SNMP_Version 
                            conf timestamp vlan update_if_status iface_filter
                            ignore_portchannel VTP_servers N_Procs MP_Lock_W 
                            MP_Lock_R ) );


# my $Logger;       # log4perl
# my $Schema;       # DB connection
# my $Debug;        # debug flag
# my $Comm;         # community
# my $SNMP_Version; # default version

# my $Conf;	# configuration

# my $Timestamp;		# timestamp associated to this walk
# my $Vlan;		# native vlan
# my $Update_If_Status;	# should we retrieve interface status?
# my $Iface_filter;	# set to skip vlan|null interfaces
# my $Ignore_Portchannel;	# set to skip port-channell interfaces in mat
# my $VTPServers;		# set of IP addresses of the "authoritative" 
# 			# vtp servers

# my $N_Procs;
# my $MP_Lock_W;		# to synchronize children writing on socket in MP mode
# my $MP_Lock_R;		# to avoid multiple children blocked on recv
my %Children;		# children (workers) set






sub sig_child {
  my $child;
    
    while (($child = waitpid(-1,WNOHANG)) > 0) {
      $Children{$child} = 0;
  }
  $SIG{CHLD} = \&Manoc::Netwalker::sig_child;  # still loathe sysV
}


sub update_If_Status{
    my $self = shift;
    my $if_last_update_entry =
	    $self->schema->resultset('System')->find("netwalker.if_update");
	$if_last_update_entry->value($self->timestamp);
	$if_last_update_entry->update();
}


sub visit_device {
    my $self    = shift;
    my $addr	= shift;

    my @device_ids = $self->schema->resultset('Device')->get_column('id')->all;
    my %visited = map {$_ => 0} @device_ids;

    $self->do_device($addr, \%visited);
}

sub visit_all {
    my $self    = shift;
    my $comm    = shift;
    my $schema  = $self->schema;
    my @device_ids = $schema->resultset('Device')->get_column('id')->all;
    my %visited = map {$_ => 0} @device_ids;

    foreach my $host (@device_ids) {
	$self->do_device($host, \%visited);
    }
}

sub visit_all_mp {
    my $self = shift;
    my $comm = shift;
    my $schema = $self->schema;
    my $logger = $self->logger;
    #my $Childrens = $self->Childrens;
    my $N_Procs = $self->N_Procs;
    my @device_ids = $schema->resultset('Device')->get_column('id')->all;
    my %visited = map {$_ => 0} @device_ids;

    $SIG{CHLD} = \&Manoc::Netwalker::sig_child;
    

    # create socket pair
    my ($p_socket,  $c_socket) = 
	IO::Socket->socketpair(AF_UNIX, SOCK_SEQPACKET, PF_UNSPEC);

    # spawn workers
    my $pid;
    for (1..$N_Procs) {
	$pid = fork;
	defined($pid) or $logger->logdie("Cannot fork.");
	if ($pid) {
	    $Children{$pid} = 1;
	    next;
	}
	
	$p_socket->close;
	$self->run_child($c_socket, \%visited);
	exit;
    }

    # send jobs requests
    my $host;
    my $line;

    while (@device_ids) {
	$host = shift @device_ids;
	
	$p_socket->recv($line, 1024, 0);
	
	$p_socket->send("HOST $host");
    }

    for (1..$N_Procs) {
	$p_socket->send("STOP");
    }
    
    foreach (grep { $Children{$_} } keys %Children) {
	waitpid($_, 0);
    }
}

sub run_child {
    my $self    = shift;
    my $socket  = shift;
    my $visited = shift;
    my $schema = $self->schema;
    my $logger = $self->logger;

    # reopen db connection
    $schema = Manoc::DB->connect(Manoc::Utils::get_dbi_params($self->conf)) ||
	$logger->logconfess("child $$: cannot connect to DB");

    $socket->send("DONE");
    
    my $msg;
    while(1) {
	flock($self->MP_Lock_R, LOCK_EX);
	$socket->recv($msg, 1024, 0);
	flock($self->MP_Lock_R, LOCK_UN);	

	if ($msg =~ /HOST\s+([\d\.+]+)/o ) {
	    my $host = $1;
	    $self->do_device($host, $visited);

	    flock($self->MP_Lock_W, LOCK_EX);
	    $socket->send("DONE $msg");
	    flock($self->MP_Lock_W, LOCK_UN);

	    next;
	} 

	if ($msg eq "STOP") {
	    exit 0;
	}
    }
    
}
#----------------------------------------------------------------------#

sub do_device {
    my $self = shift;
    my ($addr, $visited) = @_;
    my $schema = $self->schema;

    my $device = $schema->resultset('Device')->find($addr);

    $device or $self->logger->logdie("$addr not in device list\n");

    # get device community and version or use default
    my $comm    = $device->snmp_com() || $self->comm;
    my $version = $device->snmp_ver() || $self->SNMP_Version;

    # error message printed by open_device
    my $info = $self->open_device($addr, $comm, $version);
    
    if (!$info) {
	$device->offline(1);
	$device->update;
	$self->logger->error("can't connect to $addr");

	# remove pseudo-realtime infos
	$device->ssids()->delete();
	$device->dot11clients->delete();

	return 0;
    }

    $visited->{$addr} = 1;
    
    my $name = $info->class_name;
    $self->logger->info("Connected to $addr $name");
    
    # A transaction for each device
    $schema->txn_do( sub {
	    $self->update_device_info($info, $device);
	    
	    # update if_status table if required
	    $self->update_If_Status and
		$self->update_if_table($info, $device);

	    $device->get_mat() and
		$self->update_mat_tables($info, $device, $comm, $version, $visited);

	    #$device->get_dot11() and
		#$self->update_dot11($info, $device);

	    $device->get_arp() and
		$self->update_arp($info, $device);

	    $self->VTP_servers->{$addr} and
		$self->update_vtp($info, $device);
	});
    
    if ( $@ ) {
	my $commit_error = $@;
	$self->logger->error("commit error on $addr : $commit_error");
    }
    # end of transaction
}

#---------------------------------------------------------------------#

sub open_device {
    my $self = shift || die "nientedfsfa";
    my ($host, $comm, $version) = @_;


    my $f = SNMPLib::SessionFactory->new(
  				     post_req => \&factory_method,
  				    );

    my $info = $f->open( 
			host	    => $host,
			debug       => $self->debug,
			community   => $comm,
			version	    => $version,
			logger      => $self->logger,
		       ) or return;
    
    if ( !defined($info)) {
	$self->logger->error("Can't connect to $host");
	return undef;
    }

    my $name  = $info->sysName();
    my $class = $info->class_name;

    $self->logger->info("Connected to device $host");
    $self->logger->debug("SNMPLib is using this device class: $class");

    return $info;
}

#---------------------------------------------------------------------#

sub update_arp {
    my $self = shift;
    my ($info, $device) = @_;

    my $vlan = $device->vlan_arpinfo() || $self->vlan;
    my $ip_table   = $info->ipNetToMediaTable;
    my $schema = $self->schema;
    my $logger = $self->logger,
    my ($k, $v);
    
    foreach my $k (keys %$ip_table) {
    #while (($k, $v) = each(%$ip_table)) {
        my $ip_addr  = $ip_table->{$k}->{'ipNetToMediaNetAddress'};#$at_netaddr->{$k};
        my $mac_addr = $ip_table->{$k}->{'ipNetToMediaPhysAddress'};

        # broadcast IP will show up in the node table.
        next if uc($mac_addr) eq 'FF:FF:FF:FF:FF:FF';
 
        # Skip Passport 8600 CLIP MAC addresses
        next if uc($mac_addr) eq '00:00:00:00:00:01';

        # Skip VRRP addresses
        next if $mac_addr =~ /^00:00:5e:00:/i;

        $logger->debug(sprintf("%15s at %17s\n", $ip_addr, $mac_addr));

	my @entries = $schema->resultset('Arp')->search({
	    ipaddr	=> $ip_addr,
	    macaddr	=> $mac_addr,
	    vlan	=> $vlan,
	    archived => 0
	    });
	
	scalar(@entries) > 1 and
	    $logger->error("More than one non archived entry for $ip_addr,$mac_addr");

	if (@entries) {
	    my $entry = $entries[0];	
	    $entry->lastseen($self->timestamp);
	    $entry->update();
	} else {
	    $schema->resultset('Arp')->create({
		ipaddr    => $ip_addr,
		macaddr   => $mac_addr,
		firstseen => $self->timestamp,
		lastseen  => $self->timestamp,
		vlan      => $vlan,
		archived  => 0
	    });
	}
    }
}

#---------------------------------------------------------------------#

sub update_device_info {
    my $self = shift;
    my ($info, $device) = @_;
    my $name       = $info->sysName();
    my $model      = $info->model();
    
    if ($device->name eq "") {
	$device->name($name);	
    } elsif ($name ne $device->name) {
	$self->logger->error("Name mismatch ", $device->name, " ", $name);
    }

    if ($device->model eq "") {
	$device->model($model);
    } elsif ($model ne $device->model) {
	$self->logger->error("Model mismatch ", $device->model," ", $model);
    }

    # VTP Management Domain -- get only the first
    my $vtpdomains = $info->managementDomainTable('managementDomainName');
    my $vtpdomain;
    if (defined $vtpdomains and scalar(values(%$vtpdomains))) {
        $vtpdomain = (values(%$vtpdomains))[-1]->{'managementDomainName'};
    }
    my $boottime = time() - $info->sysUpTime/100;

    $device->set_column(os		=> $info->os 	);
    $device->set_column(os_ver		=> $info->os_ver);
    $device->set_column(vendor		=> $info->vendor);
    $device->set_column(vtp_domain	=> $vtpdomain  	);
    $device->set_column(boottime	=> $boottime	);
    $device->set_column(last_visited	=> $self->timestamp  	);
    $device->set_column(offline		=> 0		);
    $device->update;

}

#---------------------------------------------------------------------#

sub update_if_table {
    my $self = shift;
    my ($info, $device) = @_;
    my $host = $info->{'host'};
    my $logger = $self->logger;

    $logger->debug("update_if_table");

    # get interface info
    my $interfaces 	= $info->interfaces();
    #IF_TABLE
    my $ifTable         = $info->ifTable('ifName','ifOperStatus','ifAdminStatus','ifSpeed','ifAlias');
    #CISCO_STACK MIB
    my $i_duplex   	= $info->i_duplex();
    my $i_duplex_admin	= $info->i_duplex_admin();    
    #CISCO_VTP
    my $i_vlan      	= $info->vlan();
    my $i_stp_state	= $info->portState();
    #Cisco_Port_security
    my $cps_ifTable	= 
	$info->cpsIfConfigTable('cpsIfPortSecurityEnable','cpsIfPortSecurityStatus','cpsIfViolationCount');

    # delete old infos
    $device->ifstatus()->delete;
    
    # update
  INTERFACE:
    foreach my $iid (keys %$interfaces) {
	my $port = $interfaces->{$iid}->{'ifDescr'};

	unless (defined $port and length($port)) {
            $logger->debug("Ignoring $iid (no port mapping)");
            next INTERFACE;
        }
	$self->iface_filter && lc($port) =~ /^(vlan|null|unrouted vlan)/o and next INTERFACE;

	$logger->debug("Getting status for $port");

	my %ifstatus;


	my $alias = $ifTable->{$iid}->{'ifAlias'};
	my $desc = ( defined $alias and $alias !~ /^\s*$/ )
            ? $alias :  $ifTable->{$iid}->{'ifName'};
	$ifstatus{description}		= $desc;
	$ifstatus{up}     		= $ifTable->{$iid}->{'ifOperStatus'};
	$ifstatus{up_admin} 		= $ifTable->{$iid}->{'ifAdminStatus'};
	$ifstatus{duplex} 		= $i_duplex->{$iid};
	$ifstatus{duplex_admin} 	= $i_duplex_admin->{$iid};
	$ifstatus{speed}  		= $ifTable->{$iid}->{'ifSpeed'};
	$ifstatus{vlan} 		= $i_vlan->{$iid};
	$ifstatus{stp_state}		= $i_stp_state->{$iid};
	
	$ifstatus{cps_enable}		= $cps_ifTable->{$iid}->{'cpsIfPortSecurityEnable'};
	$ifstatus{cps_status}		= $cps_ifTable->{$iid}->{'cpsIfPortSecurityStatus'};
	$ifstatus{cps_count}		= $cps_ifTable->{$iid}->{'cpsIfViolationCount'};

	$device->add_to_ifstatus({
	    interface	=> $port,
	    %ifstatus
	    });
    }

}

#---------------------------------------------------------------------#

sub update_mat_tables {
    my $self = shift;
    my ($info, $device, $comm, $version, $visited) = @_;
    my $logger = $self->logger; 

    my $host = $info->{'host'};
    my $interfaces = $info->interfaces();
 
    # hash reference: is port connected to another switch?
    my $port_to_switch = $self->discover_switch($info, $host, $visited);

    foreach ($device->uplinks->all) {
      $port_to_switch->{ $_->interface } = 1;
    }
    
    $logger->debug("Device uplinks: ", join(",", keys %$port_to_switch));


    # update MAT
    my $mat   = $info->get_mat();
    my $def_vlan = $device->def_vlan || $self->vlan;
    $self->merge_mat($mat, $host, $port_to_switch, $def_vlan);

    if($info->cisco_comm_indexing()) {
	$logger->debug("Device supports Cisco commuinty string indexing. Connecting to each VLAN");
		
	my $v_name = $info->vtpVlanTable('vtpVlanName') || {};
	my $i_vlan = $info->vlan() || {};
	
	# Get list of VLANs currently in use by ports
	my %vlans;
	foreach my $key (keys %$i_vlan){
	    my $vlan = $i_vlan->{$key};
	    $vlans{$vlan}++;
	}
	
	# For each VLAN: connect, get mat and merge
	my ($vlan_name, $vlan);
	foreach my $vid (keys %$v_name) {
	    
	    $vlan_name = $v_name->{$vid}->{'vtpVlanName'} || '(Unnamed)';
	    # VLAN id comes as 1.142 instead of 142

	    next if $vlan_name eq "default";
	    $vlan = $v_name->{$vid}->{'vtpVlanIndex'};
	    
	    # TODO check for configured skipped vlans
	    
	    # Only use VLAN in use by port
	    #  but check to see if device serves us that list first
	    if (scalar(keys(%$i_vlan)) and !defined($vlans{$vlan})) {
		next;
	    }
	    
	    $logger->debug(" VLAN:$vlan_name ($vlan)");
	    my $vlan_comm        = $comm . '@' . $vlan; 
	    my $vlan_device_info = $self->open_device($host, $vlan_comm, $version);
	    next unless defined($vlan_device_info);
	    
	    $mat = $vlan_device_info->get_mat();
	    $self->merge_mat($mat, $host, $port_to_switch, $vlan);
	}
    } # end of cisco vlan comm indexing
}

sub merge_mat {
    my $self = shift;
    my ($mat, $host, $switch_port, $vlan) = @_;
    my $logger = $self->logger;
    my $schema = $self->schema;
    my ($p, $n, $m);

    while (($m, $p) = each %$mat) {
	
	next if(!$m || !$p);

	$logger->debug(" VLAN $vlan $m->$p");

        next if $switch_port->{$p};

	next if $self->ignore_portchannel && lc($p) =~ /^port-channel/;
        
	my @entries = $schema->resultset('Mat')->search({
	    macaddr	=> $m,
	    device	=> $host,
	    interface	=> $p,
	    archived	=> 0,
	});
	scalar(@entries) > 1 and
	  $logger->error("More than one non archived entry for $host,$m,$p");

	my $create_new_entry = 0;

	if (@entries) {
	    my $entry = $entries[0];	

	    # check for a vlan change

	    if ( $entry->vlan() != $vlan ) {
		$entry->archived(1);
		$entry->update();
		$create_new_entry = 1;
	    } else {
		$entry->lastseen($self->timestamp);
		$entry->update();
	    }
	} else {
	    $create_new_entry = 1;
	}
        if ($create_new_entry) {
	    $schema->resultset('Mat')->update_or_create({
		macaddr	=> $m,
		device	=> $host,
		interface => $p,
		firstseen => $self->timestamp,
		lastseen  => $self->timestamp,
		vlan	  => $vlan,
		archived  => 0,
	    });
	}
    }
}
#---------------------------------------------------------------------#

sub update_vtp {
    my $self = shift;
    my ($info, $device) = @_;
    my $device_id = $device->id;
    my $schema = $self->schema;

    #retrive vlan information 
    my $vlan = $info->vtpVlanTable('vtpVlanName');
    unless($vlan){
	$self->logger->error("Cannot retrieve vtp info in $device");
	return;
    }

    $self->logger->info("Getting vtp info from $device");

    #delete all entries in db
    my $vlan_db = $schema->resultset('VlanVtp')->search();
    $vlan_db->delete();

    # populate db with vlan info
    # foreach my $iid (sort (keys %$vlan) ) {
    my $name;
       
    foreach my $iid  (keys %$vlan)  {
	my $vlan_id = $vlan->{$iid}->{'vtpVlanIndex'};
	$name       = $vlan->{$iid}->{'vtpVlanName'};
	$self->logger->debug("$device_id VTP: ID $vlan_id VLAN_NAME $name");
	
	my $vlan_db = $schema->resultset('VlanVtp')->find_or_create({
	    'id'	=> $vlan_id , 
	    'name'	=> $name
	    });
    }

}

#---------------------------------------------------------------------#

sub discover_switch {
    my $self = shift;
    my ($info, $host, $visited) = @_;
    my $all_neighbors = $info->get_neighbors();
    my %switch_port;
    my $schema = $self->schema;

    my ($p, $n);
    while (($p, $n) = each(%$all_neighbors)) { 
	foreach my $s (@$n) { 
	    $self->logger->debug("$host: found neigh $s->{addr}"); 

	    my $link = $schema->resultset('CDPNeigh')->update_or_create({
		from_device	=> $host,
		from_interface	=> $p,		
		to_device	=> $s->{addr},
		to_interface	=> $s->{port},
		last_seen	=> $self->timestamp
	    });
	    $link->update;

	    next unless $s->{switch}; # it's a switch 

	    if (!defined($visited->{$s->{addr}})) { 
		$self->logger->error("unknown switch: ", $s->{addr}, 
			       " connected to $host/$p");
		$visited->{$s->{addr}} = 0;
	    } else {
		$switch_port{$p} = 1;
	    }
	}
    }
    return \%switch_port;
}


#---------------------------------------------------------------------#

sub set_update_if_status {
  my $self = shift;  
  my $if_update_interval = $self->conf->param('netwalker.ifstatus_interval');
  $self->update_If_Status(0);
  if ($if_update_interval) {
    my $if_last_update_entry =
      $self->schema->resultset('System')->find("netwalker.if_update");
    if (!$if_last_update_entry) {
      $if_last_update_entry =  $self->schema->resultset('System')->create({
									   name  => "netwalker.if_update",
									   value => "0"});				
    }
    my $if_last_update = $if_last_update_entry->value();
    my $elapsed_time   = $self->timestamp - $if_last_update;	
    my $value = $elapsed_time > $if_update_interval;
    $self->update_If_Status($value);
  }
}


#######################################################################
sub factory_method {
    my $desc    = shift or die "Error: Missing Description!";
    my $objtype; 


    $objtype = 'Catalyst' if $desc =~ /(C3550|C3560)/;
    
    #$objtype = 'Catalyst' if $desc =~ /Cisco2900)/;

    #$objtype = 'Catalyst' if $desc =~ /CiscoRouter/;

    #$objtype = 'CiscoVGW' if $desc =~ /CiscoVGW/;

    return $objtype;
}


1;
