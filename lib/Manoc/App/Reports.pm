package Manoc::App::Reports;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;

use Carp;

use base 'Manoc::App::Delegate';
use Manoc::DB;
use Manoc::Utils;

sub index : Resource(default error) {
    my ($self, $app) = @_;

    my $template = $app->prepare_tmpl(
				       tmpl  => 'reports.tmpl',
				       title => 'Reports'
 				       ); 
    return $template->output();
}


####################################################################

sub stats : Resource {
    my ($self, $app) = @_;
    my $schema = $app->param('schema');

    my ($r, $rs);
    my %vlan_stats;
    

    $rs = $schema->resultset('Mat')->search({},
					    {
						select => [
							   'vlan',
							   { count => { distinct => 'macaddr' } }
							   ],
						as => [ 'vlan', 'count' ],
						group_by => [ 'vlan' ],
					    });   
    while ($r = $rs->next) {
	$vlan_stats{$r->get_column('vlan')}->{macaddr} = $r->get_column('count');
    }
    
    $rs = $schema->resultset('Arp')->search({},
					       {
						   select => [
							      'vlan',
							      { count => { distinct => 'ipaddr' } }
							      ],
						   as => [ 'vlan', 'count' ],
						   group_by => [ 'vlan' ],
					       });
    
    while ($r = $rs->next) {
	$vlan_stats{$r->get_column('vlan')}->{ipaddr} = $r->get_column('count');
    }
    
    my @vlan_table;
    foreach my $vlan (sort {$a <=> $b} keys %vlan_stats) {
	push @vlan_table, {
	    vlan	=> $vlan,
	    macaddr	=> $vlan_stats{$vlan}->{macaddr} || 'na',
	    ipaddr	=> $vlan_stats{$vlan}->{ipaddr}  || 'na',
	};
    }


    my @db_stats = (
		    {
		     name => "Tot racks",
		     val => $schema->resultset('Rack')->count
		    },
		    { 
		     name => "Tot devices",
		     val  => $schema->resultset('Device')->count
		    },
		    {
		     name => "Tot interfaces",
		     val  => $schema->resultset('IfStatus')->count
		    },
		    {
		     name => "CDP entries",
		     val  => $schema->resultset('CDPNeigh')->count
		    },
		    {
		     name => "MAT entries",
		     val  => $schema->resultset('Mat')->count
		    },
		    {
		     name => "ARP entries",
		     val  => $schema->resultset('Arp')->count
		    },
		   );
    my $template = $app->prepare_tmpl(
                                      tmpl  => 'report/stats.tmpl',
                                      title => 'Manoc Statistics'
				      ); 
    $template->param(
		     vlan_table		=> \@vlan_table,
		     db_stats		=> \@db_stats,
		    );
    return $template->output();
}

sub multihost : Resource {
    my ($self, $app) = @_;
    my $schema = $app->param('schema');
    my ($rs, $r);
    
    my @multihost_ifaces;

   $rs = $schema->resultset('Mat')->search(
			 { 'archived' => 0 },
			 {
			     select => 
				 [
				  'me.device' , 
				  'me.interface', 
				  {
				      count => { distinct => 'macaddr' } 
				  },
				  'ifstatus.description'
				  ],   
				      
			     as => [ 'device', 'interface', 'count', 'description' ],
			     group_by => [ 'device', 'interface' ],		     
			     having => { 'COUNT(DISTINCT(macaddr))' => { '>', 1 } },
			     order_by => [ 'me.device', 'me.interface' ],
			     alias => 'me',
			     from  => [ 
					{ me => 'mat' },
					[
					 { 'ifstatus' => 'if_status' },
					 { 
					     'ifstatus.device'    => 'me.device',
					     'ifstatus.interface' => 'me.interface',
					 }
					 ]
					]				    
				    });
    
     while ($r = $rs->next()) {
 	my $device = $r->get_column('device');
 	my $iface  = $r->get_column('interface');
 	my $count  = $r->get_column('count');
 	my $description = $r->get_column('description') || "";
 	push @multihost_ifaces, {
 	    device	=> $device,
 	    interface	=> $iface,
 	    description => $description,
 	    count	=> $count,
 	};
     }

     my $template = $app->prepare_tmpl(
				       tmpl  => 'report/multihost.tmpl',
				       title => 'Interfaces with multiple hosts'
                                       ); 
    $template->param(multihost_ifaces => \@multihost_ifaces);
    return $template->output();
}

####################################################################

sub unused_ifaces : Resource {
    my ($self, $app) = @_;

    my $query    = $app->query;
    my $device_id = Manoc::Utils::clean_string($query->param('device'));
    my $days      = Manoc::Utils::clean_string($query->param('days'));
   
    $days =~ /^\d+$/ or $days = 0;

    my $schema = $app->param('schema');

    my @device_list = 
		sort { $a->{label} cmp $b->{label} }
		map +{ 
		    id		=> $_->id,
		    label	=> lc($_->name) .' (' . $_->id .')',
		    selected	=> $device_id eq $_->id,
		    }, $schema->resultset('Device')->all();
    
    #    unshift @device_list, { id => "(All)", } TODO
    
    my @unused_ifaces;

    if ($device_id) {
	my ($rs, $r);
	$rs = $schema->resultset('IfStatus')->search(
			 {
			  'me.device'		=> $device_id,
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

     my $template = $app->prepare_tmpl(
					tmpl  => 'report/unused-ifaces.tmpl',
					title => 'Unused Interfaces'
                                       ); 
    $template->param(
		     device_list	=> \@device_list,
		     unused_ifaces	=> \@unused_ifaces
		     );
    return $template->output();
}
 
####################################################################

sub unknown_devices : Resource {
    my ($self, $app) = @_;
    
    my $schema = $app->param('schema');
    
    my $search_attribs = {
	alias => 'me',
	from  => [
		  { 
		      me => 'cdp_neigh',		      
		    },
		  [
		   { 
		       to_dev => 'devices',
		       -join_type=>'LEFT' 
		       },
		   { 
		       'to_dev.id' => 'me.to_device',
		   }
		   ],
		  ],				      
    };

    my @results = $schema->resultset('CDPNeigh')->search(
							 { 'to_dev.id' => undef }, 
							 $search_attribs
							 );
    my @unknown_devices = map +{ 
				from_device	=> $_->from_device,
				from_iface	=> $_->from_interface,
				to_device	=> $_->to_device,
				to_iface	=> $_->to_interface,
				date		=> Manoc::App::print_timestamp($_->last_seen)
			       }, @results;

    my $template = $app->prepare_tmpl(
				       tmpl  => 'report/unknown-devices.tmpl',
				       title => 'Unknown devices'
 				       ); 
    $template->param(unknown_devices => \@unknown_devices);
    return $template->output();
}

####################################################################

sub ip : Resource {
    my ($self, $app) = @_;
    my $schema = $app->param('schema');
    my ($r, $rs);

    my @conflicts;
    my @multihomed;
    
    $rs = $schema->resultset('Arp')->search(
					     { archived => '0' },
					     { 
					      select => [
							 'ipaddr',
							 { count => { distinct => 'macaddr' } }
							],
					      as => ['ipaddr', 'count'],
					      group_by => [ 'ipaddr' ],
					      having => { 'COUNT(DISTINCT(macaddr))' => { '>', 1 } },
					      }
					    );
    while ($r = $rs->next) {
	push @conflicts, {
			  ipaddr => $r->get_column('ipaddr'),
	    count  => $r->get_column('count'),
			 }
    }

    $rs = $schema->resultset('Arp')->search(
					     { archived => '0' },
					     { 
					      select => [
							 'macaddr',
							 { count => { distinct => 'ipaddr' } }
							],
					      as => ['macaddr', 'count'],
					      group_by => [ 'macaddr' ],
					      having => { 'COUNT(DISTINCT(ipaddr))' => { '>', 1 } },
					     });
    while ($r = $rs->next) {
	push @multihomed, {
			   macaddr => $r->get_column('macaddr'),
			   count  => $r->get_column('count'),
			  }
    }

    my $template = $app->prepare_tmpl(
				       tmpl  => 'report/ip.tmpl',
				       title => 'IP Status'
 				       ); 
    $template->param(
		     multihomed		=> \@multihomed,
		     conflicts		=> \@conflicts,
		     );
    return $template->output();
}

####################################################################

sub winlogon : Resource {
    my ($self, $app) = @_;

    my $schema = $app->param('schema');

    my ($page, $name_filter);
    
    if ($app->query->param('submit')) {
	$name_filter = $app->query->param('name');
	$app->session->param('name_filter', $name_filter);
	$page = 1;
    } else {
	$name_filter = $app->session->param('name_filter');
	$page = $app->query->param('page') || 1;
	$page < 0 and $page = 1;
    }

    my $search_attrs = {};
    if ($name_filter) {
	$search_attrs->{user} = { like => "%$name_filter%" };
    }

    my $add_attribs =  {
			rows => 15,
			page => $page,
			include_columns => [ { 'name' => 'hostname.name' } ],
			alias => 'logon',
			from  => [
				  {logon => 'win_logon'},
				  [
				   { hostname => 'win_hostname', 
				     -join_type => 'left'},
				   { 'hostname.ipaddr' => 'logon.ipaddr' }
				   ]
				  ]
			      };
    
    my @rs = $schema->resultset('WinLogon')->search(
						    $search_attrs,
						    $add_attribs
						   );
    my @table = map {
	user		=> $_->user,
        ipaddr		=> $_->ipaddr,
	hostname	=> $_->get_column('name')
    }, @rs;

    my $template = $app->prepare_tmpl(
				      tmpl  => 'report/winlogon.tmpl',
				      title => 'WinLogon'
				     );
    $template->param(
		     table		=> \@table,
		     next_page		=> $page+1,
		     prev_page		=> $page > 1 ? $page-1 : undef,
		     );
    return $template->output();
}

####################################################################

sub device_list : Resource {
    my ($self, $app) = @_;
    my $schema = $app->param('schema');

    my @rs = $schema->resultset('Device')->search(undef,
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
    my @table = map {
		      ipaddr	=> $_->id, 
		      name	=> $_->name, 
		      vendor	=> $_->vendor || 'n/a',
		      model	=> $_->model || 'n/a',
		      os	=> (
				    ($_->os || 'n/a') . ' ' . 
				    ($_->os_ver || '')
				    ),
		      rack	=> $_->rack->name, 
		      floor	=> $_->rack->floor,
		      building	=> $_->rack->building->description
	 }, @rs;


    my $template = $app->prepare_tmpl(
				      tmpl  => 'report/device_list.tmpl',
				      title => 'Managed devices list'
				     );
    $template->param(table => \@table);
    return $template->output();
}

####################################################################

sub cps_shutdown : Resource {
    my ($self, $app) = @_;
    my $schema = $app->param('schema');

    my @rs = $schema->resultset('IfStatus')->search(
        { cps_status => 'shutdown' },
	{
	    order_by => 'device, interface',
	    join     => 'device_info' 
	});


    my @table = map {
	device		=> $_->device,
	device_name	=> $_->device_info->name,
	interface	=> $_->interface,
	description 	=> $_->description,
	cps_count	=> $_->cps_count,
    }, @rs;
 
    my $template = $app->prepare_tmpl(
				      tmpl  => 'report/cps_shutdown.tmpl',
				      title => 'Portsecurity Shutdown Interfaces'
				     );
    $template->param(table => \@table);
    return $template->output();  

}

####################################################################

sub multi_mac : Resource {
    my ($self, $app) = @_;
    my $schema = $app->param('schema');
    my $results;
    my $e;
    my @multimacs;

    $results = $schema->resultset('Mat')->search(
						 { archived => '0' },
						 { 
						     select => [
								'macaddr',
								{ count =>   'device'  }
								],
						     as => ['macaddr', 'devs'],
						     group_by => [ 'macaddr' ],
						     having => { 'COUNT(device)' => { '>', 1 } },
						 }
						 );
   
    
    while ($e = $results->next()) {
	my $macaddr = $e->get_column('macaddr');
	my $devs  = $e->get_column('devs');
	
	push @multimacs, {
	    macaddr	=> $macaddr,
	    devs	=> $devs,
	};
    }
    
    my $template = $app->prepare_tmpl(
				      tmpl  => 'report/multi_mac.tmpl',
				      title => 'Mac addresses on multiple devices'
				      ); 
    $template->param(multimacs => \@multimacs);
    return $template->output();   
}

####################################################################

1;
