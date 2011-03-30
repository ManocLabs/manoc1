package Manoc::App;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;
use Carp;

use base 'CGI::Application';
use HTML::Template;
use CGI::Application::Plugin::Config::Simple;
use CGI::Application::Plugin::Session;
use URI::Escape;

use Manoc::DB;
use Manoc::UserAuth;
use Manoc::Taglib;
use Manoc::App::Search;

use Manoc::Utils qw(print_timestamp clean_string int2ip ip2int);
use Regexp::Common qw /net/;

use File::Spec;


sub setup {
    my $self = shift;
    
    $self->start_mode('search');
    $self->error_mode('error');

    my @run_modes = qw(
                       AUTOLOAD
		       about 
                       asset
                       netdb
                       login logout
		       search ip mac
		       interface ifnotes_edit ifnotes_delete
                       ipnotes_edit ipnotes_delete
                       forbidden
		       ssid dot11client
		       );
    $self->run_modes(map { $_ => "rm_$_" } @run_modes);

    my $path_info_idx = 1;
    $self->param('path_info_idx', $path_info_idx);

    # mode name from $ENV{PATH_INFO}.
    $self->mode_param(
		      path_info	=> $path_info_idx,
		      param	=>'rm'
		      );

    $self->set_delegate(reports   => 'Reports');
    $self->set_delegate(device    => 'Device');
    $self->set_delegate(building  => 'Building');
    $self->set_delegate(rack      => 'Rack');
    $self->set_delegate(iprange   => 'IpRange');
    $self->set_delegate(user      => 'User');
    $self->set_delegate(role      => 'Role');
    $self->set_delegate(vlan      => 'Vlan');
    $self->set_delegate(vlanrange => 'VlanRange');
    $self->set_delegate(ssid      => 'SSID');
}

sub cgiapp_init {
    my $self = shift;
    my %args = @_;
    
    my $home = $args{home} || croak "missing param home";

    $self->config_file($args{conf});    
    my $app_path = $self->config_param('cgi.app_path');

    # start db
    my $schema = Manoc::DB->connect(Manoc::Utils::get_dbi_params($self->config));
    confess("cannot connect to DB") unless $schema;
    $self->param('schema', $schema);

    # set templates dir
    $self->tmpl_path(File::Spec->catfile($home, 'tmpl'));

    # session setup
    my $session_expire = $self->config_param('cgi.session_expire') || '+1h';
    $session_expire = Manoc::Utils::str2seconds($session_expire);

    $self->session_config(
			  COOKIE_PARAMS => {
			      -expires => '+' . $session_expire . 's',
			      -path    => '/' . "$app_path",
			  },
			  CGI_SESSION_OPTIONS => [
						  'driver:dbixc',
						  undef,
						  { Schema => $schema },
						  ],
			  );
}


sub cgiapp_prerun {
    my $self = shift;

    # get base url
    my $base_url = $self->config_param('cgi.app_url');
    if (!defined($base_url)) {
	my $app_path = $self->config_param('cgi.app_path');
	my $prefix   = $self->query->url(-base => 1);    
	$base_url = "$prefix/$app_path";
    }

    $self->param('base_url', $base_url);

    # init taglib
    Manoc::Taglib->base_url($base_url);
    Manoc::Taglib->img_base_url($base_url);

    if (!$self->query->path_info()) {
	return $self->manoc_redirect();
    }
  
    if (!$self->session->param('MANOC_USER') &&
	$self->get_current_runmode ne 'login') 
    {
	my $url = $self->query->self_url;
	$self->param(login_redirect => $url);
	$self->prerun_mode('login');
    }
}

sub teardown {
    my ($self) = @_;

    $self->session->flush();
    my $schema = $self->param('schema');
    $schema->storage->disconnect();
}

#----------------------------------------------------------------------#
#                                                                      #
#                          Utilities                                   #
#                                                                      #
#----------------------------------------------------------------------#

sub set_delegate {
    my $self = shift;
    my ($run_mode, $delegate) = @_;

    my $class = "Manoc::App::$delegate";
    my $idx = $self->param('path_info_idx') + 2;

    eval "require $class";
    croak $@ if $@;
    my $obj = $class->new(path_info => $idx);

    $self->run_modes($run_mode => 
		     sub {
			 $class->new(path_info => $idx)->dispatch($self);
		       });
}

sub prepare_tmpl {
    my $self = shift;
    my %args = @_;
    my $tmpl      = $args{tmpl}  || croak "missing tmpl";
    my $title     = $args{title};
    my $is_widget = $args{widget};

    my $template = $self->load_tmpl($tmpl,
				    die_on_bad_params	=> 0,
				    loop_context_vars	=> 1,
				    global_vars		=> 1,
				    cache		=> 1,
				    filter => \&Manoc::Taglib::filter
				    );

    $template->param(base_url	=> $self->param('base_url'));
    if (! $is_widget) {
	$title or croak "missing title";
	$template->param(
			 message	=> 0,
			 title		=> $title);
    }

    return $template;
}

sub _make_url_params {
    my @pairs;
    while (@_) {
	my $k = shift @_;
	my $v = shift @_;
	push @pairs, uri_escape($k) . "=" . uri_escape($v); 	
    }
    @_ and push @pairs, uri_escape(shift @_);

    return join("&", @pairs);
}

sub manoc_redirect {
    my $self   = shift;
    my $module = shift;  
    my @params = @_;

    my $url;
    $module ||= $self->start_mode();
    $url = $self->param('base_url') . '/manoc/' . $module;
    @params and $url .=  "?" . _make_url_params(@params);

    return $self->redirect($url);
}

sub manoc_url {
    my $self = shift;
    my $path = shift;
    my @params = @_;

    my $url = $self->param('base_url') . '/manoc/' . $path;
    @params and $url .=  "?" . _make_url_params(@params);

    return $url;
}

sub redirect {
    my ($self, $url) = @_;

    $self->header_type('redirect');
    $self->header_props(-url=>$url);
    return "Redirecting to $url";
}

#----------------------------------------------------------------------#

sub show_message {
    my ($self, $title, $message) = @_;  
    $message ||= '';

    my $template = $self->prepare_tmpl(
				       tmpl	=> 'message.tmpl',
				       title	=> $title
				       );
    $template->param(message => $message);
    return $template->output;
}


#----------------------------------------------------------------------#
#                                                                      #
#                               Run Modes                              #
#                                                                      #
#----------------------------------------------------------------------#

sub error {
    my $self  = shift;
    my $error = shift;
    return "MANOC ERROR\nThere has been an error: <pre>\n$error</pre>";
}

sub rm_AUTOLOAD {
    my $self = shift;
    return $self->manoc_redirect()
}

#----------------------------------------------------------------------#

sub rm_forbidden {
    my $self = shift;

    my $template = $self->prepare_tmpl(
				       tmpl	=> 'forbidden.tmpl',
				       title	=> 'Forbidden');
    return $template->output();
}

#----------------------------------------------------------------------#
#                         Login/logout                                 #
#----------------------------------------------------------------------#

sub rm_login {
    my $self     = shift;
    
    my $query        = $self->query;
    my $username     = $query->param('user'); 
    my $password     = $query->param('password');
    my $redirect_url = uri_unescape($query->param('redirect')) ||
	$self->param('login_redirect');
    my $authfail     = 0;

    if ($username && $password) { 
	# Perform authentication 
	my $userAuth = Manoc::UserAuth->new(
					    username => $username, 
					    password => $password,
                                            app      => $self
                                           );
	if ($userAuth->auth) { 
	    $self->session_recreate;
	    my $session = $self->session;
	    $session->param('MANOC_USER', $username);

	    my $template = $self->prepare_tmpl(
					       tmpl	=> 'welcome.tmpl', 
					       title	=> 'Login successful'
				       );
	    if ($redirect_url) {
		$template->param(message => "<a href=\"$redirect_url\">Back to requested page.</a>");
	    }  else {
		$template->param(message => q{});
	    }
	    return $template->output;
	} else {
	    $authfail = 1;
	}
    }

    my $template = $self->prepare_tmpl(
				       tmpl	=> 'login.tmpl', 
				       title	=> 'Login'
				       );
    my $message  = $authfail ? 'authentication failure' : '';

    $template->param(
		     title	=> 'Login',
		     message	=> $message,
		     redirect	=> $redirect_url
		     );
    return $template->output();
}

sub rm_logout {
    my $self = shift;

    $self->session_delete;
    return $self->manoc_redirect()
}

#----------------------------------------------------------------------#
#                        Entrypoints  runmodes                         #
#----------------------------------------------------------------------#

sub rm_search {
    # use Search package
    Manoc::App::Search::run(@_);
}

sub rm_asset {
    my $self = shift;

    my $template = $self->prepare_tmpl(
	tmpl	=> 'asset.tmpl',
	title	=> 'Assets');

    return $template->output();
}

sub rm_netdb {
    my $self = shift;

    my $template = $self->prepare_tmpl(
	tmpl	=> 'netdb.tmpl',
	title	=> 'Net DB');

    return $template->output();
}

sub rm_about {
    my $self = shift;

    my $template = $self->prepare_tmpl(
				       tmpl	=> 'about.tmpl',
				       title	=> 'About Manoc');

    return $template->output();
}


#----------------------------------------------------------------------#
#                 IP (arp table + hostname) runmode                    #
#----------------------------------------------------------------------#

sub rm_ip {
    my $self  = shift;
    my $query = $self->query();
    my $schema = $self->param('schema');

    my $q = clean_string($query->param('id'));

    my @r;

    @r = $schema->resultset('Arp')->search(ipaddr => $q, { order_by => 'lastseen DESC, firstseen DESC'});
    my @arp_results = map +{
        macaddr   => $_->macaddr,
        vlan      => $_->vlan,
        firstseen => print_timestamp($_->firstseen),
        lastseen  => print_timestamp($_->lastseen)
	}, @r;
    
    my $note = $schema->resultset('IpNotes')->find({ipaddr => $q});

    @r = $schema->resultset('WinHostname')->search(ipaddr => $q,
						   { order_by => 'lastseen DESC'});
    my @hostnames = map +{
	name   => $_->name,
	firstseen => print_timestamp($_->firstseen),
        lastseen  => print_timestamp($_->lastseen)
    }, @r;

    @r = $schema->resultset('IPRange')->search([{
	'inet_aton(from_addr)'	=> { '<=' => ip2int($q) },
	'inet_aton(to_addr)' 	=> { '>=' => ip2int($q) },
						}],
					       {order_by => 'inet_aton(from_addr) DESC, inet_aton(to_addr)'}
	);
    my @subnet = map +{
        subnet_name=> $_->name,
    	from_addr  => $_->from_addr,
    	to_addr    => $_->to_addr,
	}, @r;

    @r = $schema->resultset('WinLogon')->search(
	{ ipaddr => $q },
	{ order_by => 'lastseen DESC, firstseen DESC' });
    my @logons = map +{
	user      => $_->user,
        firstseen => print_timestamp($_->firstseen),
        lastseen  => print_timestamp($_->lastseen)
    }, @r;
	

    # DHCP Stuff
    @r = $schema->resultset('DHCPReservation')->search({ipaddr => $q});
    my @reservations = map +{
	macaddr   => $_->macaddr,
        name      => $_->name,
	hostname  => $_->hostname,
	server    => $_->server,
    }, @r;
    @r = $schema->resultset('DHCPLease')->search({ipaddr => $q});
    my @leases = map +{
	macaddr   => $_->macaddr,
	server    => $_->server,
	start     => print_timestamp($_->start),
	end       => print_timestamp($_->end),
	hostname  => $_->hostname,
	status    => $_->status
    }, @r;
    
    my $template = $self->prepare_tmpl(
				       tmpl  => "ip.tmpl",
				       title => "Info about $q"
				       );    
    $template->param(		     
	ipaddr		=> $q,
	subnet		=> \@subnet,
	arp_results	=> \@arp_results,
	hostnames       => \@hostnames,
	logons	        => \@logons,
	leases          => \@leases,
        reservations    => \@reservations,
	notes           => defined($note) ? $note->notes : '',
	edit_url        => "ipnotes_edit?ipaddr=$q",
	delete_url      => "ipnotes_delete?ipaddr=$q",
		     
	);

    return $template->output();
}

sub rm_ipnotes_edit {
    my $self = shift;
    
    #Check permission
    Manoc::UserAuth->check_permission($self, ('admin')) or 
	return $self->manoc_redirect("forbidden");
    
    my $query = $self->query;
    my $schema = $self->param('schema');

    my $ip_addr = $query->param('ipaddr');
   
    my $message;

    if (!defined($ip_addr)) {
        return $self->show_message('Error', 'No interface specified.');
    }
    
    if ($query->param('cancel')) {
        return $self->manoc_redirect("ip", id => $ip_addr);    
    }
    if ($query->param('save')) {
        my $done;
        ($done, $message) = $self->process_ipnotes_edit($ip_addr);
    	if ($done) {
            return $self->manoc_redirect("ip", id => $ip_addr);
        }
    }
    
    my $ipnotes = $schema->resultset('IpNotes')->find({ipaddr => $ip_addr});
    my $text = defined($ipnotes) ? $ipnotes->notes : '';

    my $template = $self->prepare_tmpl(
				       tmpl  => 'ipnotes-edit.tmpl',
				       title => 'Edit Ip Notes'
 				       );    
    $template->param(
                        ipaddr => $ip_addr,
                        notes  => $text,
                    );

    return $template->output();
}

sub process_ipnotes_edit {
    my $self = shift;
    my $ip_addr = shift;


    my $schema = $self->param('schema');

    my $query = $self->query;
    my $notes  = $query->param('notes');
    
    my $arp_entry  = $schema->resultset('Arp')->find({ipaddr => $ip_addr});
    defined($arp_entry) or return (0, 'Invalid IP address');

    my $ipnotes = $schema->resultset('IpNotes')->find({ipaddr => $ip_addr});

    if ($ipnotes) {
	# update 
	defined($ipnotes) or return (0, 'Cannot create ip address notes');
	if ($notes) {
	    $ipnotes->notes($notes);
	    $ipnotes->update;
	} else {
	    $ipnotes->delete;
	}
    } else {
        $notes or return 1; # do not insert an empty note
        $ipnotes = $schema->resultset('IpNotes')->create({
            ipaddr => $ip_addr,
    	    notes	=> $notes
	    });
	$ipnotes->update;	
    }
    return 1;
}

sub rm_ipnotes_delete {
    my $self = shift;
    
    Manoc::UserAuth->check_permission($self, ('admin')) or return $self->manoc_redirect("forbidden");             #Check permission

    my $query = $self->query;
    my $ip_addr = $query->param('ipaddr');
    my $schema = $self->param('schema');
    
    $schema->resultset('IpNotes')->search({ipaddr => $ip_addr})->delete;

    return $self->manoc_redirect("ip", id => $ip_addr);
}

#----------------------------------------------------------------------#
#                     MAC runmode (arp + mat)                          #
#----------------------------------------------------------------------#

sub rm_mac {
    my $self  = shift;
    my $query = $self->query();
    my $schema = $self->param('schema');

    my $q = clean_string($query->param('id'));
    my @r;

    # Get ARP info

    @r = $schema->resultset('Arp')->search(macaddr => $q, 
			{ order_by => 'lastseen DESC, firstseen DESC' });

    my @arp_results = map +{
	ipaddr    => $_->ipaddr,
	vlan      => $_->vlan,
	firstseen => print_timestamp($_->firstseen),
	lastseen  => print_timestamp($_->lastseen)
    }, @r;

    # Get MAT info from mat and mat_archive, join and sort
    
    @r = $schema->resultset('Mat')->search(macaddr => $q);
    my @mat_entries = map +{
	device    => $_->device,
	iface     => $_->interface,
	vlan      => $_->vlan,
	firstseen_i 		=> $_->firstseen,
	lastseen_i  		=> $_->lastseen,
	firstseen => print_timestamp($_->firstseen),
	lastseen  => print_timestamp($_->lastseen)
    }, @r;

    @r = $schema->resultset('MatArchive')->search({macaddr => $q});
    my @mat_archive_entries = map +{
	arch_device_ip 		=> $_->device->ipaddr,
	arch_device_name	=> $_->device->name,
	vlan		      	=> $_->vlan,
	firstseen_i 		=> $_->firstseen,
	lastseen_i  		=> $_->lastseen,
	firstseen 		=> print_timestamp($_->firstseen),
	lastseen  		=> print_timestamp($_->lastseen)
    }, @r;

    my @mat_results = sort {
	$b->{lastseen_i} <=> $a->{lastseen_i}  ||
	    $b->{firstseen_i} <=> $a->{firstseen_i}
      } (@mat_entries, @mat_archive_entries);

    # get 802.11 info

    @r = $schema->resultset('Dot11Assoc')->search(macaddr => $q, 
			{ order_by => 'lastseen DESC, firstseen DESC' });
    my @dot11_results =  map +{
	device    => $_->device,
	ssid      => $_->ssid,
	ipaddr    => $_->ipaddr,
	vlan      => $_->vlan,
	firstseen => print_timestamp($_->firstseen),
	lastseen  => print_timestamp($_->lastseen)
    }, @r;

    my $vendor = 'UNKNOWN';
    my $oui = $schema->resultset('Oui')->find(substr($q,0,8));
    defined($oui) and $vendor = $oui->vendor;

    # DHCP Stuff
    @r = $schema->resultset('DHCPReservation')->search({macaddr => $q});
    my @reservations = map +{
	ipaddr    => $_->ipaddr,
        name      => $_->name,
	hostname  => $_->hostname,
	server    => $_->server,
    }, @r;
    @r = $schema->resultset('DHCPLease')->search({macaddr => $q});
    my @leases = map +{
	ipaddr    => $_->ipaddr,
	server    => $_->server,
	start     => print_timestamp($_->start),
	end       => print_timestamp($_->end),
	hostname  => $_->hostname,
	status    => $_->status
    }, @r;

    my $msg = "Information on $q";
    my $template = $self->prepare_tmpl(
				       tmpl  => "mac.tmpl",
				       title => "Info about $q"
				       );    
    $template->param(
		     arp_results	=> \@arp_results,
		     mat_results	=> \@mat_results,
		     leases             => \@leases,
		     reservations       => \@reservations,
		     vendor             => $vendor,
		     message		=> $msg
	);

    return $template->output;
}


#----------------------------------------------------------------------#
#                        Interface  runmodes                           #
#----------------------------------------------------------------------#


sub rm_interface {
    my $self  = shift;
    my $query = $self->query();
    my $schema = $self->param('schema');

    my $device_id = clean_string($query->param('device'));
    my $iface_id  = clean_string($query->param('iface'));

    my $if_status = $schema->resultset('IfStatus')->find({
	device		=> $device_id,
	interface	=> $iface_id,
    });
    if (!defined($if_status)) {
	return $self->show_message('Error', 'Interface not found');
    }
    
    my $device = $if_status->device_info;

    my %tmpl_param;
    $tmpl_param{interface}	= $iface_id;
    $tmpl_param{name}   	= $device->name;
    $tmpl_param{model}		= $device->model;
    $tmpl_param{rack_id}	= $device->rack->id;
    $tmpl_param{rack_name}	= $device->rack->id;
    $tmpl_param{building_id}    = $device->rack->building->id;
    $tmpl_param{building_name}  = $device->rack->building->description;

    $tmpl_param{if_vlan}	= $if_status->vlan;
    $tmpl_param{if_description} = $if_status->description;
    $tmpl_param{if_speed}	= $if_status->speed,
    $tmpl_param{if_up}		= $if_status->up;
    $tmpl_param{if_up_admin}	= $if_status->up_admin;
    $tmpl_param{if_duplex}	= $if_status->duplex;
    $tmpl_param{if_duplex_admin}= $if_status->duplex_admin;
    $tmpl_param{if_stp_status}	= $if_status->stp_state;
    $tmpl_param{if_cps_enable}  = $if_status->cps_enable &&
					$if_status->cps_enable eq 'true';
    $tmpl_param{if_cps_status}  = $if_status->cps_status;
    $tmpl_param{if_cps_count}   = $if_status->cps_count;

    # notes
    my $note = $schema->resultset('IfNotes')->find({
						   device	=> $device_id,
						   interface	=> $iface_id,
						   });
    $tmpl_param{if_notes} = defined($note) ? $note->notes : '';

    $tmpl_param{edit_note_link} = "ifnotes_edit?device=$device_id&iface=$iface_id";
    $tmpl_param{delete_note_link} = 
	defined($note) ? 
	"ifnotes_delete?device=$device_id&iface=$iface_id" : 
	q{};    

    my @mat_rs = $schema->resultset('Mat')->search(
							    {
								device		=> $device_id,
								interface	=> $iface_id,
							    },
							    { 
								order_by => 'lastseen DESC, firstseen DESC',
							    });
    my @mat_results = map +{
	macaddr   => $_->macaddr,
	vlan      => $_->vlan,
	firstseen => print_timestamp($_->firstseen),
	lastseen  => print_timestamp($_->lastseen)
	}, @mat_rs;
    

    my $template = $self->prepare_tmpl(
				       tmpl  => 'interface.tmpl',
				       title => 'Interface Info'
 				       );    
    $template->param(%tmpl_param);
    $template->param(
		     mat_results	=> \@mat_results,
		     ipaddr		=> $device_id,
		     );

    return $template->output();
}


sub rm_ifnotes_edit {
    my $self = shift;
    
    # Check permission
    Manoc::UserAuth->check_permission($self, ('admin')) or 
	return $self->manoc_redirect("forbidden");
    
    my $query  = $self->query;
    my $schema = $self->param('schema');

    my $device_id = $query->param('device');
    my $iface_id  = $query->param('iface');   
   
    my $message;

    if (!defined($device_id) || !defined($iface_id)) {
	return $self->show_message('Error', 'No interface specified.');
    }
    
    if ($query->param('cancel')) {
	return $self->manoc_redirect("interface",
				     device => $device_id,
				     iface  => $iface_id);    
    }
    if ($query->param('save')) {
	my $done;
	($done, $message) = $self->process_ifnotes_edit($device_id, $iface_id);
	if ($done) {
	    return $self->manoc_redirect("interface", 
					 device => $device_id,
					 iface  => $iface_id);
	}
    }
    
    my $ifnotes = $schema->resultset('IfNotes')->find({
					     device	=> $device_id,
					     interface => $iface_id,
					     });
    my $text = defined($ifnotes) ? $ifnotes->notes : '';

    my $template = $self->prepare_tmpl(
				       tmpl  => 'ifnotes-edit.tmpl',
				       title => 'Edit Interface Notes'
 				       );    
    $template->param(
		     device		=> $device_id,
		     iface		=> $iface_id,
		     notes		=> $text,
		     );

    return $template->output();
}


sub process_ifnotes_edit {
    my $self = shift;
    my $device_id = shift;
    my $iface_id  = shift;

    my $schema = $self->param('schema');

    my $query = $self->query;
    my $notes  = $query->param('notes');
    
    my $device  = $schema->resultset('Device')->find({id => $device_id});
    defined($device) or
	return (0, 'Invalid device');


    my $ifnotes = $schema->resultset('IfNotes')->find({
						      device    => $device_id,
						      interface => $iface_id,
						      });

    if ($ifnotes) {
	# update 
	defined($ifnotes) or
	    return (0, 'Cannot create interface notes');
	if ($notes) {
	    $ifnotes->notes($notes);
	    $ifnotes->update;
	} else {
	    $ifnotes->delete;
	}
    } else {
	$notes or return 1; # do not insert an empty note
	$ifnotes = $schema->resultset('IfNotes')->create({
	    device	=> $device_id,
	    interface	=> $iface_id,
	    notes	=> $notes
	    });
	$ifnotes->update;	
    }
    return 1;
}

sub rm_ifnotes_delete {
    my $self = shift;
    
    # Check permission
    Manoc::UserAuth->check_permission($self, ('admin')) or 
	return $self->manoc_redirect("forbidden");

    my $query = $self->query;
    my $device_id = $query->param('device');
    my $iface_id  = $query->param('iface');

    my $schema = $self->param('schema');
    
    $schema->resultset('IfNotes')->search({
			       device    => $device_id,
			       interface => $iface_id,
			       })->delete;

    return $self->manoc_redirect("interface",
				 device	=> $device_id,
				 iface	=> $iface_id,
				 );
}

#----------------------------------------------------------------------#

sub rm_dot11client {
    my $self = shift;

    my $query     = $self->query();
    my $device_id = $query->param('device');
    my $macaddr   = $query->param('macaddr');

    my $schema = $self->param('schema');
    
    my $dot11client = $schema->resultset('Dot11Client')->find({
	device    => $device_id,
	macaddr   => $macaddr,
    });

    defined($dot11client) or 
	return $self->show_message('Not found');

    my %param;

    foreach (qw(device interface ssid macaddr ipaddr vlan
		power quality m_cipher u_cipher
		keymgt authen addauthen dot1xauthen)) {
	$param{$_} = $dot11client->get_column($_);
    }
    

    my $template = $self->prepare_tmpl(
				       tmpl  => 'dot11client.tmpl',
				       title => '802.11 Association info'
 				       );    
    $template->param(%param);
    return $template->output();
}

#----------------------------------------------------------------------#

1;
