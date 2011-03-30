package Manoc::App::Device;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;
use Carp;
use base 'Manoc::App::Delegate';
use Manoc::DB;
use Manoc::Utils qw(clean_string print_timestamp);
use Text::Diff;
use Manoc::CiscoUtils;

########################################################################

sub list : Resource(default error) {
    my ($self, $app) = @_;
    my $query  = $app->query();
    my $schema = $app->param('schema');
    
    # get optional query parameters
    my $rack_id = $query->param('rack') || 'all';
    my $building_id = $query->param('building') || 'all';

    # use paramater to create objects list
    my @buildings;
    my @racks;
    my @devices;
    my $device_search_filter;

    # check rack_id building_id consistency
    if ($rack_id ne 'all') {
	my $rack = $schema->resultset('Rack')->find($rack_id);	
	if ( !defined($rack) )  {
	    $rack_id = 'all';
	} elsif ($building_id eq 'all') {
	    $building_id = $rack->building->id;
	} else {
	    $rack_id = 'all';
	}
    }    

    if ($rack_id ne 'all') {	
	# get devices by rack
	$device_search_filter = { rack => $rack_id};
	
	# get racks in building
	@racks = $schema->resultset('Rack')->search( { building => $building_id} );	
    } elsif ($building_id ne 'all') {
	# devices in building
	$device_search_filter = { building => $building_id};

	# get racks in building
	@racks = $schema->resultset('Rack')->search( { building => $building_id} );
    } else {
	# get everything
	$device_search_filter = undef;
	@racks = $schema->resultset('Rack')->all();
    }
    @buildings = $schema->resultset('Building')->all();


    @devices = $schema->resultset('Device')->search($device_search_filter,
						       {
							   join => {
							       rack => 'building'
							   },
								   prefetch => { 'rack' => 'building' },
								   order_by => [
								       'building.description',
								       'rack.id'
								   ]
						       }
						       );

    # transform db object to template objects
    
    my @device_table = map {
	ipaddr		=> $_->id, 
	name		=> $_->name, 
	vendor		=> $_->vendor || 'n/a',
	model		=> $_->model  || 'n/a',
	rack_id		=> $_->rack->id, 
	rack_name	=> $_->rack->name, 
	floor		=> $_->rack->floor,
	building_id	=> $_->rack->building->id,
	building_name	=> $_->rack->building->name,
    }, @devices;
    
    my @rack_list =  map +{ 
	id		=> $_->id,
	label		=> $_->name,
	selected	=> defined($rack_id) && $rack_id eq $_->id
	}, @racks;
    unshift @rack_list, { 
	id		=> 'all',
	label		=> '(all)',
	selected	=> !defined($rack_id) || $rack_id eq 'all'
	};
    

    my @building_list =  map +{ 
	id		=> $_->id,
	label		=> $_->name,
	selected	=> defined($building_id) && $building_id eq $_->id
	}, @buildings;
    unshift @building_list, { 
	id		=> 'all',
	label		=> '(all)',
	selected	=> !defined($building_id) || $building_id eq 'all'
	};

    my $minisearch = Manoc::App::Search::make_minisearch_widget($app, {scope => 'device'});
    
    my %tmpl_param;
    $tmpl_param{device_table}	= \@device_table;
    $tmpl_param{rack_list}    	= \@rack_list;
    $tmpl_param{building_list} 	= \@building_list;
    $tmpl_param{new_device_link} =  $app->manoc_url("device/create");
    $tmpl_param{minisearch}	= $minisearch;

    # prepare template
    my $template = $app->prepare_tmpl(
				       tmpl  => "device/list.tmpl",
				       title => "Device List"
 				       );    
    $template->param(%tmpl_param);
    return $template->output;
}

########################################################################

sub view : Resource {
    my ($self, $app) = @_;
    my $query  = $app->query();
    my $schema = $app->param('schema');
    
    my $id = clean_string($query->param('id'));
    my %tmpl_param;
    my @iface_info;

    my $device = $schema->resultset('Device')->find($id);
    
    if (!defined($device)) {
        return $app->show_message('Error', 'Device not found');
    }


    $tmpl_param{name}		    = $device->name;
    $tmpl_param{boottime}	    = ( $device->boottime ? 
					print_timestamp($device->boottime) : 
					'n/a' );
    $tmpl_param{last_visited}	    = ( $device->last_visited ? 
					print_timestamp($device->last_visited) :
					'Never visited' );
    $tmpl_param{ipaddr}		    = $id;
    $tmpl_param{vendor}		    = $device->vendor;
    $tmpl_param{model}		    = $device->model;
    $tmpl_param{notes}		    = $device->notes;
    $tmpl_param{os}		    = $device->os;
    $tmpl_param{os_ver}		    = $device->os_ver;
    $tmpl_param{vtp_domain}	    = $device->vtp_domain;

    $tmpl_param{level}		    = $device->level;
    $tmpl_param{rack_id}	    = $device->rack->id;
    $tmpl_param{rack_name}	    = $device->rack->name;
    $tmpl_param{building_id}        = $device->rack->building->id;
    $tmpl_param{building_name}      = $device->rack->building->name;
    $tmpl_param{building_descr} = $device->rack->building->description;
    
    $tmpl_param{backup_date}	= $device->config ? print_timestamp($device->config->config_date) : undef;
    $tmpl_param{backup_enabled}	= $device->backup_enabled ? "Enabled" : "Not enabled";
    
    $tmpl_param{dot11_enabled}	= $device->get_dot11 ? "Enabled" : "Not enabled";
    $tmpl_param{arp_enabled}	= $device->get_arp   ? "Enabled" : "Not enabled";
    $tmpl_param{mat_enabled}	= $device->get_mat   ? "Enabled" : "Not enabled";
    $tmpl_param{vlan_arpinfo}	= $device->vlan_arpinfo;
    $tmpl_param{uplinks}        = join(", ", map { $_->interface  } $device->uplinks->all());

    $tmpl_param{config_link}	= "view_config?device=$id";
    $tmpl_param{edit_link}	= "edit?id=$id";
    $tmpl_param{changeip_link}	= "change_ip?id=$id";
    $tmpl_param{delete_link}	= "delete?id=$id";
    $tmpl_param{edituplink_link}= "uplinks?id=$id";


    # CPD
    my @neighs = $schema->resultset('CDPNeigh')->search(
	         { from_device => $id },
		 {
		     '+columns' => [ { 'name' => 'dev.name' } ],
		     order_by   => 'last_seen DESC, from_interface',
		     from  => [
			       { 'me' => 'cdp_neigh' },  
			       [
				{ 
				    'dev' 	=> 'devices',
				    -join_type	=> 'LEFT',
				},
				{ 
				    'me.to_device' => 'dev.id'}
				]
			       ]});
    my @cdp_links = map {
       from_iface      => $_->from_interface,
       to_device       => $_->to_device,
       to_iface        => $_->to_interface,
       date            => print_timestamp($_->last_seen),
       to_name         => $_->get_column('name')
       }, @neighs;
    
    #------------------------------------------------------------
    # Interfaces info
    #------------------------------------------------------------

    # prefetch notes
    my %if_notes = map {
	$_->interface => 1
	} $device->ifnotes;

    # prefetch interfaces last activity
    my @iface_last_mat_rs = $schema->resultset('IfStatus')->search(
		      {
			  'me.device'		=> $id,
		      },
		      {
			  alias => 'me',
			  from  => [ 
				     { me => 'if_status' },
				     [
				      { 'mat_entry' => 'mat', -join_type => 'LEFT' },
				      { 
					  'mat_entry.device'    => 'me.device',
					  'mat_entry.interface' => 'me.interface',
				      }
				      ]
				     ],
			  group_by  => [qw(me.device me.interface)],
			  select    => [
					'me.interface',
					{ max => 'lastseen' },
					],
			  as        =>  [qw(interface lastseen)]
		      });
    my %if_last_mat;
    foreach (@iface_last_mat_rs) {
	$if_last_mat{$_->interface} =
	    $_->get_column('lastseen') ?
	    print_timestamp($_->get_column('lastseen')) :
	    'never';
    }

    # fetch ifstatus and build result array
    my @ifstatus = $device->ifstatus;
    foreach my $r (@ifstatus) {
        my ($controller, $port) = split /[.\/]/, $r->interface;
	my $lc_if = lc($r->interface);

        push @iface_info, {
            controller	=> $controller, # for sorting
            port	=> $port,	# for sorting
            interface   => $r->interface,
            speed	=> $r->speed        || 'n/a',
            up		=> $r->up           || 'n/a',
            up_admin	=> $r->up_admin     || '',
            duplex	=> $r->duplex       || '',
            duplex_admin=> $r->duplex_admin || '',
            cps_enable  => $r->cps_enable && $r->cps_enable eq 'true',
            cps_status  => $r->cps_status   || '',
            cps_count   => $r->cps_count    || '',
            description => $r->description  || '',
            vlan	=> $r->vlan  || '',
	    last_mat	=> $if_last_mat{$r->interface},
            has_notes   => (exists($if_notes{$lc_if}) ? 1 : 0), 
            edit_note_link	=> $app->manoc_url("ifnotes_edit?device=$id&iface=".$r->interface),
            updown_status_link	=> "updown_status_link?device=$id&iface=".$r->interface,
            enable_updown	=> check_enable_updown($app, $r->interface, @cdp_links)         
		
        };
    }
    @iface_info = sort { ($a->{controller} cmp $b->{controller}) || ($a->{port} <=> $b->{port})} @iface_info;
    
    #Unused interfaces
    my @unused_ifaces;
    
    if ($id) {
		my ($rs, $r);
		$rs = $schema->resultset('IfStatus')->search(
				 {
				  'me.device'		=> $id,
				  'mat_entry.macaddr'   => undef
				 },
				 {
					 alias => 'me',
					 from  => [ 
						{ me => 'if_status' },
						[
						 { 'mat_entry' => 'mat', -join_type => 'LEFT' },
						 { 
							 'mat_entry.device'    => 'me.device',
							 'mat_entry.interface' => 'me.interface',
						 }
						 ]
						]						
				 });
	
		while ($r = $rs->next()) {
			push @unused_ifaces, {
					  device	=> $r->device,
					  interface	=> $r->interface,
					  description 	=> $r->description,
			};
		}
    }

    #------------------------------------------------------------
    # wireless info
    #------------------------------------------------------------

    # ssid
    my @ssid_list = map +{ 
	interface	=> $_->interface,
	ssid		=> $_->ssid,
	broadcast	=> $_->broadcast ? 'yes' : 'no',
	channel	=> $_->channel
	}, $device->ssids;


    # wireless clients
    my @dot11_clients = map +{
	ssid		=> $_->ssid,
	macaddr		=> $_->macaddr,
	ipaddr		=> $_->ipaddr,
	vlan		=> $_->vlan,
	quality		=> $_->quality . '/100',
	state		=> $_->state,
	detail_link	=> $app->manoc_url("dot11client?device=$id&macaddr=" . $_->macaddr),
    }, $device->dot11clients;
	

    # prepare template
    my $template = $app->prepare_tmpl(
				       tmpl  => "device/view.tmpl",
				       title => "Device $id"
 				       );    
    $template->param(%tmpl_param);
    $template->param(
		     iface_info		=> \@iface_info,
		     cdp_links		=> \@cdp_links,
		     ssid_list		=> \@ssid_list,
		     dot11_clients	=> \@dot11_clients,
			 unused_ifaces	=> \@unused_ifaces
		     );
    
    return $template->output();
}

########################################################################

sub create : Resource {
    my ($self, $app) = @_;
    
    # Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");
    
    my $query  = $app->query();
    my $schema = $app->param('schema');

    my $rack_id     = clean_string($query->param('rack'));
    my $building_id = clean_string($query->param('building'));
    
    my $rack;
    my $building;
    
    # for the wizard mode
    my @rack_list;
    my @building_list;
    
    if ($rack_id) {
	$rack = $schema->resultset('Rack')->find($rack_id);
	defined($rack) or
	    return $app->show_message('Error', 'Trying to create a device without a valid rack');

	$building    = $rack->building;
	$building_id = $rack->building->id;
    } elsif ($building_id) {
	$building = $schema->resultset('Building')->find($building_id);

	defined($building) or
	    return $app->show_message('Error', 'Trying to create a device without a valid building');
	@rack_list = map +{ 
	    id		=> $_->id,
	    label	=> $_->name,
	}, $building->racks->all();
	
    } else {
	@building_list =  map +{ 
	    id		=> $_->id,
	    label	=> $_->name,
	}, $schema->resultset('Building')->all()
    }
    
    my $message;
    if ($query->param('submit') && $query->param('step') == 3) {
	my $done;
	($done, $message) = $self->process_create_device($app, $rack);
	$done and	    
	    return $app->manoc_redirect("device/edit", id=>$message);	
    }

    my $template = $app->prepare_tmpl(
	tmpl  => 'device/create.tmpl',
	title => 'New Device',
	);

    $template->param(message	        => $message);
    
    $template->param(rack_name         => $rack ? $rack->name : '' );
    $template->param(building_name     => $building ? $building->name : '');

    $template->param(rack               => $rack_id);
    $template->param(rack_list          => \@rack_list);    
    $template->param(building           => $building_id);       
    $template->param(building_list      => \@building_list);

    $template->param(new_building_link  => $app->manoc_url("building/create", backref=>"device/create"));
    $template->param(new_rack_link      => ( $building_id
					     ? $app->manoc_url("rack/create", building=> $building_id, backref=>"device/create") 
					     : '')	     
	);

    foreach (qw(ip model name)) {
	$template->param($_ => $query->param($_));
    }       

    return $template->output;
}

sub process_create_device {
    my ($self, $app, $rack) = @_;

    my $schema = $app->param('schema');
    my $query = $app->query();
    my $id  	= clean_string($query->param('id'));
        
    # check if ID is valid IP
    $id =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ or
	return (0, 'Device ID is not a valid IPv4 address');

    # check duplicated ID
    my $device = $schema->resultset('Device')->find($id);
    if ($device) {
	return (0, 'IP Address already in use');
    }

    my $name  = clean_string($query->param('name'));
    my $model = clean_string($query->param('model'));
    
    # create object
    $device = $schema->resultset('Device')->create({
	id	=> $id,
	name	=> $name,
	model	=> $model,
	rack	=> $rack->id
	});
    	
    $device->update;

    return (1, $id);
}

########################################################################

sub edit : Resource {
    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden"); #Check permission
    
    my $query = $app->query();
    my $schema = $app->param('schema');

    my $id = $query->param('id');    
    defined($id) or
	return $app->show_message('Error', 'No device specified');
    
    my $device = $schema->resultset('Device')->find($id);
    defined($device) or
	return $app->show_message('Error', 'Device not found');

    $query->param('discard') and 
	return $app->manoc_redirect("device/view", id => $id);
    my $message;    
    if ($query->param('submit')) {
	my $done;
	
	($done, $message) = $self->process_edit_device($app, $device);	
	$done and 
	    return $app->manoc_redirect("device/view", id => $id);
    }

    my %form_value;
    $form_value{id} = $id;
    foreach my $v (qw(name model level notes 
		      get_mat get_dot11 get_arp vlan_arpinfo
		      telnet_pwd enable_pwd 
		      snmp_com snmp_user snmp_password)) 
    {
        $form_value{$v} = $query->param($v) || $device->get_column($v) || '';
    }      
    # CHANGE when backup_enable column will be renamed to backup_enabled
    $form_value{'backup_enabled'} = 
	$query->param('backup_enabled') || 
	$device->backup_enabled() || '';

    # snmp versions
    my $snmp_ver = $query->param('snmp_ver') || $device->snmp_ver;
    my @snmp_ver_list = map {
	id       => $_,
	label    => $_,
	selected => $snmp_ver == $_
	}, (0, 1, 2, 3);
    $snmp_ver_list[0]->{label} = "Use Default";
    $form_value{snmp_ver_list} = \@snmp_ver_list;


    # create rack list
    my $rack = defined($device) ? $device->rack->id : $query->param('rack');
    my @rack_list = map {
	id 	 => $_->id,
	label	 => 'rack ' . $_->name . ' (' . $_->building->name . ')',
	selected => $rack && $rack == $_->id
	}, $schema->resultset('Rack')->all(); 
    $form_value{rack_list} = \@rack_list;

    my $template = $app->prepare_tmpl(
				       tmpl  => 'device/edit.tmpl',
				       title => 'Edit Device',
 				       );
    $template->param(%form_value);
    $template->param(message => $message);
    return $template->output();
}

sub process_edit_device {
    my ($self, $app, $device) = @_;
    my $query  = $app->query();
    my $schema = $app->param('schema');

    my $message;

    # validate level
    my $level	= $query->param('level');
    if ($level =~ /\w/ ) {
	$level =~ /^-?\d+$/o or return (0, 'Invalid level');
    } else {
	$level = undef;
    }
	
    # validate rack
    my $rack_id  = $query->param('rack');
    my $rack = $schema->resultset('Rack')->find($rack_id);
    defined($rack) or return (0, 'Rack not found');

    # validate vlan for arp info
    my $vlan_arpinfo = $query->param('vlan_arpinfo');
    if ($vlan_arpinfo =~ /\w/ ) {
	$vlan_arpinfo =~ /^\d+$/o or return (0, 'Invalid vlan');
    } else {
	$vlan_arpinfo = undef;
    }  

    # passwords: empty values are null
    my $telnet_pwd = $query->param('telnet_pwd');
    $telnet_pwd =~ /\w/ or $telnet_pwd = undef;

    my $enable_pwd = $query->param('enable_pwd');
    $enable_pwd =~ /\w/ or $enable_pwd = undef;

    my $snmp_com = $query->param('snmp_com');
    $snmp_com =~ /\w/ or $snmp_com = undef;

    foreach my $v (qw(name model notes telnet_pwd enable_pwd 
		      snmp_com snmp_user snmp_password snmp_ver)) 
    {
        $device->set_column($v, $query->param($v));
    }
    foreach my $v (qw(get_dot11 get_arp get_mat)) {
	$device->set_column($v, $query->param($v) ? 1 : 0);
    }
    # CHANGE move to the previous foreach loop when backup_enable column
    # will be renamed to backup_enabled
    $device->backup_enabled( $query->param('backup_enabled') ? 1 : 0 );

    # not in foreach because there can be null values 
    $device->level($level);
    $device->vlan_arpinfo($vlan_arpinfo);
    $device->telnet_pwd($telnet_pwd);
    $device->enable_pwd($enable_pwd);    

    $device->rack($rack_id);

    # the end :)
    $device->update;

    return 1;
}

########################################################################

sub change_ip : Resource {
    my ($self, $app) = @_;
    
    #Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");  
    
    my $query = $app->query();
    my $schema = $app->param('schema');
    
    my $id = $query->param('id');
    defined($id) or 
	return $app->show_message('Error', 'Device not specified');
    
    my $device = $schema->resultset('Device')->find($id);
    defined($device) or
	return $app->show_message('Error', 'Device not found');
    my $message;    
    if ($query->param('submit')) {
	my $done;
	my $new_id = $query->param('new_id');
	($done, $message) = $self->process_change_ip($app, $schema, $id, $new_id);	
	if ($done) {
	    return $app->manoc_redirect("device/view", id=>$new_id);
	}
    }

    my $template = $app->prepare_tmpl(
				       tmpl  => 'device/change_ip.tmpl',
				       title => 'Device - Change IP',
 				       );
   
    $template->param(id		=> $id,
		     message	=> $message,
		     name	=> $device->name);
    return $template->output;


}

sub process_change_ip {
    my ($self, $app, $schema, $id, $new_id) = @_;
    my $device =  $schema->resultset('Device')->search({id => $id});
    my $new_ip =  $schema->resultset('Device')->find($new_id);

    if(!defined($device)){
	return (0,"Device not defined: $id");
    }
    if($new_ip){
	return (0, "The ip is already in use. Try again with another one!");
    }
    if( $new_id =~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/ ){

	$schema->txn_do( sub {
	    $device->update({id => $new_id});
	});
	if ( $@ ) {
	    return (0,$@);
	}
	else {
	    return (1,"");
	}
    }
    else {
	return (0,'Bad ip format');
    }
}

########################################################################

sub view_config : Resource {
    my ($self, $app) = @_;
    my $query = $app->query();
    my $schema = $app->param('schema');
    my $device_id = $query->param('device');
    my ($dev_config, $curr_config, $curr_date, 
	$prev_config, $prev_date, $has_prev_config, $template, %tmpl_param);
    
    #Retrieve device configuration from DB
    $dev_config = $schema->resultset('DeviceConfig')->find({device => $device_id});
    defined($dev_config) or
	return $app->show_message('Error', 'Device backup not found');
    
    #Set configuration parameters
    $prev_config = $dev_config->prev_config;
    if (defined($prev_config)) {
        $has_prev_config = 1;
        $prev_date = print_timestamp($dev_config->prev_config_date);
    } else {    
        $has_prev_config = 0;
        $prev_date = "";
    }
    $curr_config = $dev_config->config;
    $curr_date   = print_timestamp($dev_config->config_date);
    
    #Get diff and modify diff string
    my $diff = diff(\$prev_config, \$curr_config);
    #Clear "@@...@@" stuff
    $diff =~ s/@@[^@]*@@/<hr>/g;
    
    #Insert HTML "font" tag to color "+" and "-" rows
    $diff =~ s/^\+(.*)$/<font color=green> $1<\/font>/mg;
    $diff =~ s/^\-(.*)$/<font color=red> $1<\/font>/mg;
    
    $tmpl_param{prev_config}      = $prev_config;
    $tmpl_param{prev_config_date} = $prev_date;
    $tmpl_param{has_prev_config}  = $has_prev_config;
    $tmpl_param{curr_config}      = $curr_config;
    $tmpl_param{curr_config_date} = $curr_date;
    $tmpl_param{diff}             = $diff;
    $tmpl_param{device_link}	  = "view?id=$device_id";
    #Prepare template
    $template = $app->prepare_tmpl(
                                    tmpl  => 'device/view-config.tmpl',
                                    title => "Device $device_id configuration"
                                   );
    $template->param(%tmpl_param);
    return $template->output;
}

########################################################################

sub delete : Resource {
    my ($self, $app) = @_;
    
    #Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");             
    
    my $schema = $app->param('schema');
    my $query  = $app->query;
    
    my $id = $query->param('id');    
    defined($id) or
	return $app->show_message('Error', 'No device specified');
    
    my $device = $schema->resultset('Device')->find($id);
    defined($device) or
	return $app->show_message('Error', 'Device not found');
    
    my ($e, $it); # entry and interator
    
    $schema->txn_do(sub {
	 # transaction....
	# 1) create a new deletedevice d2
	# 2) move mat for $device to archivedmat for d2
	# 3) $device->delete
	my  $del_device = $schema->resultset('DeletedDevice')->create({
	    ipaddr	   => $device->id,
	    name	   => $device->name,
	    model	   => $device->model,
	    vendor         => $device->vendor,
	    timestamp      => time()
	    });
	
	$it = $schema->resultset('Mat')->search(
		      {
			  device => $id,
		      },
		      {
			  select    => [
					 'macaddr',
					 'vlan',
					{ 'min'  => 'firstseen' },
					{ 'max'  => 'lastseen' },
					],
			  group_by  =>  [qw(macaddr vlan)],
			      as    =>  ['macaddr','vlan',
					 'min_firstseen','max_lastseen']
		      });

	while ($e = $it->next) {
	    $del_device->add_to_mat_assocs({
		macaddr	       => $e->macaddr,
		firstseen      => $e->get_column('min_firstseen'),
		lastseen       => $e->get_column('max_lastseen'),
		vlan           => $e->vlan
		});
	}
	$device->delete;
        });	
    if ($@) {
	my $commit_error = $@;
	return $app->show_message('Error', $commit_error);
    }
    
    return $app->show_message('Success', 'Device deleted. Back to the'.'<a href="' . $app->manoc_url("device/list") . '"> device list</a>.');

}

########################################################################

sub uplinks : Resource {
    my ($self, $app) = @_;
    
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden"); #Check permission
    
    my $query = $app->query();
    my $schema = $app->param('schema');

    my $id = $query->param('id');    
    defined($id) or
	return $app->show_message('Error', 'No device specified');
    
    my $device = $schema->resultset('Device')->find($id);
    defined($device) or
	return $app->show_message('Error', 'Device not found');

    $query->param('discard') and 
	return $app->manoc_redirect("device/view", id => $id);
    my $message;    
    if ($query->param('submit')) {
	my $done;
	
	($done, $message) = $self->process_uplinks($app, $device);	
	$done and 
	    return $app->manoc_redirect("device/view", id => $id);
    }
   
    my %uplinks = map { $_->interface => 1 } $device->uplinks->all;
    my @iface_list;

    my $rs = $device->ifstatus;
    while (my $r = $rs->next()) {
        my ($controller, $port) = split /[.\/]/, $r->interface;
	my $lc_if = lc($r->interface);

        push @iface_list, {
            controller	=> $controller, # for sorting
            port	=> $port,	# for sorting
            interface   => $r->interface,
            description => $r->description  || '',
	    checked     => $uplinks{$r->interface},
	}
    }
    @iface_list = sort { ($a->{controller} cmp $b->{controller}) || ($a->{port} <=> $b->{port})} @iface_list;


    my %params;
    $params{id}          = $id;
    $params{name}        = $device->name;
    $params{message}     = $message;
    $params{device_link} = "view?id=$id";
    $params{iface_list}  = \@iface_list;

    my $template = $app->prepare_tmpl(
				       tmpl  => 'device/uplinks.tmpl',
				       title => 'Edit Uplinks',
 				       );
    $template->param(%params);
    return $template->output();
}


sub process_uplinks {
    my ($self, $app, $device) = @_;
    my $query  = $app->query();
    my $schema = $app->param('schema');

    return (1, 'Done') unless $query->param('uplinks');
  
    $schema->txn_do(sub {
	$device->uplinks()->delete();
	foreach ($query->param('uplinks')) {
	    $device->add_to_uplinks({ interface => $_ });
	}
    });
    return (1, 'Done');
}

########################################################################


sub updown_status_link : Resource {
    my ($self, $app) = @_;
    
    #Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");             

    my $schema = $app->param('schema');
    my $query = $app->query;
    my $device_id = $query->param('device');
    my $iface_id  = $query->param('iface');
    my ($res, $mess);
    
    #Find interface in database
    my $interface = $schema->resultset('IfStatus')->find({
	device => $device_id,
	interface => $iface_id
	});
    $interface or return $app->show_message('Error', 'Invalid interface');
    
    #Switch port status via telnet	
    ($res, $mess) = Manoc::CiscoUtils->switch_port_status($device_id, $iface_id, $schema);
    $res or return $app->show_message('Error', $mess);
    
    #Update database
    $interface->up_admin eq "up" ? $interface->up_admin("down") : $interface->up_admin("up");
    $schema->txn_do(sub {
	$interface->update;
    });	
    if ($@) {
	my $commit_error = $@;
	Manoc::CiscoUtils->switch_port_status($device_id, $iface_id, $schema);
	return $app->show_message('Error', $commit_error);
    }
    
    return $app->manoc_redirect("device/view", id => $device_id);
}


sub check_enable_updown {
    my ($app, $interface, @cdp_links) = @_;

    #User check
    Manoc::UserAuth->check_permission($app, ('admin')) or return 0;
    
    #CDP link check
    foreach (@cdp_links) { 
	$_->{from_iface} eq $interface and return 0;
    }
 
    return 1;   
}

########################################################################

1;
