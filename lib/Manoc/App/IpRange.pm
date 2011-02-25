package Manoc::App::IpRange;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;

use Carp;

use base 'Manoc::App::Delegate';
use Manoc::DB;
use Manoc::Utils qw/netmask_prefix2range int2ip ip2int 
		    print_timestamp prefix2wildcard netmask2prefix/;
use Regexp::Common qw /net/;
use POSIX;

use Data::Dumper;

#----------------------------------------------------------------------#

my $DEFAULT_PAGE_ITEMS = 64;
my $MAX_PAGE_ITEMS = 1024;

#----------------------------------------------------------------------#

sub list : Resource(default error) {
    my ($self, $app) = @_;
    my $query = $app->query();
    my $schema = $app->param('schema');
    my %tmpl_param;
   
    
    my ($e,$it);
    $it = $schema->resultset('IPRange')->search({});
    #build the tree
    my 	%tmp_results;
    while ($e = $it->next) {
       	if(defined($e->parent) ){
	    $tmp_results{$e->get_column('parent')}->{$e->name} = 1;
	}
	else {
	    $tmp_results{'root'}->{$e->name} = 1;
	}
    }
    my $sel_node = $query->param('expnode');
   
    #Build Info View
    my $name  = $query->param('name') || 'Policlinico';
    my $range = $schema->resultset('IPRange')->find($name);

    $range or 
	return $app->show_message('Error', 'Range not found');

    my $network = $range->network;
    my $netmask = $range->netmask;
    my $prefix = $network ? netmask2prefix($netmask) : undef;


    my @children = map +{
        name		=> $_->name,
        from		=> $_->from_addr,
        to	    	=> $_->to_addr,
        vlan_id     	=> $_->vlan_id ? $_->vlan_id->id : undef,
        vlan        	=> $_->vlan_id ? $_->vlan_id->name : "-",
        view_url	=> $app->manoc_url("iprange/view?name=" . $_->name),
        edit_url	=> $app->manoc_url("iprange/edit?name=" . $_->name),
        split_url	=> $app->manoc_url("iprange/split?name=" . $_->name),
        merge_url	=> $app->manoc_url("iprange/merge?name=". $_->name),
        delete_url	=> $app->manoc_url("iprange/delete?name=" . $_->name),
        n_children	=> $_->children->count(),
        n_neigh		=> get_neighbour($schema, $name, ip2int($_->from_addr), ip2int($_->to_addr))->count(),
    }, $range->search_related('children', undef, {order_by => 'inet_aton(from_addr)'});




    #add template parameter
    $tmpl_param{name}	           = $name;
    $tmpl_param{network}           = $network;
    $tmpl_param{netmask}           = $netmask;
    $tmpl_param{prefix}            = $prefix;
    $tmpl_param{from_addr}         = $range->from_addr;
    $tmpl_param{to_addr}           = $range->to_addr;
    $tmpl_param{description}       = $range->description;
    $tmpl_param{expnode}           = $sel_node ; 
    $tmpl_param{html_code}         = _create_HTML($app,\%tmp_results,'root');
    $tmpl_param{details_link}      = $app->manoc_url("iprange/view", name=>$name); 
    $tmpl_param{edit_link}         = $app->manoc_url("iprange/edit",  name=>$name);

    $tmpl_param{rangelist_widget}  = $self->make_rangelist($app, \@children);
    $tmpl_param{add_link}	   = $app->manoc_url("iprange/create?parent=$name");


    my $template = $app->prepare_tmpl(	
					tmpl  => 'iprange/list.tmpl',
					title => 'IP Address Management',
					);
    $template->param(%tmpl_param);
    return $template->output();
}

sub _create_HTML {
    my ($app,$tree, $root, $network)=@_;
    my $code='';
  
   
    my @children =   sort (keys  %{$tree->{$root}});
    
    if($root eq 'root'){
	return _create_HTML($app,$tree,$children[0]);
    }
    else{
	my @children_html = map +{
	    node => _create_HTML($app,$tree,$_)
	},  @children;

	my $tmpl = $app->prepare_tmpl(
				tmpl  => 'iprange/_tree_node.tmpl',
				widget => 1
				      );
	$tmpl->param(root => $root);
	$tmpl->param(children => \@children_html);
	$code = $tmpl->output;   
	return $code;
    }
}

#------------------------------------------------------------------------#
sub iprange_view{
  my ($self, $app, $from, $endrange, $prefix, $netmask, $host, $n_hosts) = @_;
  my $query  = $app->query();
  my $page   = $query->param('page');
  my $schema = $app->param('schema');
  my $rs = $schema->resultset('Arp')->search(
					     {
					      'inet_aton(ipaddr)' => {
								      '>=' => ip2int($from),
								      '<=' => ip2int($endrange),
								     }
					     },					       
					     { 
					      select     => 'ipaddr',
					      order_by   => 'ipaddr',
					      distinct   => 1,
	});


  my %tmpl_param;
  $tmpl_param{host}             = $host;
  $tmpl_param{network}          = $from;
  $tmpl_param{netmask}          = $netmask;
  $tmpl_param{min_host}         = int2ip(ip2int($from) + 1);
  $tmpl_param{max_host}         = $endrange;
  $tmpl_param{numhost}          = $n_hosts - 1;
  $tmpl_param{wildcard}         = prefix2wildcard($prefix);
  $tmpl_param{prefix}           = $prefix;
  $tmpl_param{iplist_widget}    = $self->make_iplist($app, undef, $from, 
						     $endrange, $prefix, $page, $host);
  $tmpl_param{iplist_def}       = $page ? 1 : 0;
  $tmpl_param{ipaddr_num}       = $rs->count();

  my $template = $app->prepare_tmpl(	
				    tmpl  => 'iprange/view.tmpl',
				    title => 'IpRange',
				   );
  $template->param(%tmpl_param);
  return $template->output();
}
#------------------------------------------------------------------------#

sub view : Resource {
    my ($self, $app) = @_;

    my $schema = $app->param('schema');
    my $query  = $app->query();
    my $name   = $query->param('name');
    my $page   = $query->param('page');
    my ($range,$prefix);

    unless($name){
      #Resource View was called with "from" and "prefix" parameters
      my $host = $query->param('from') or 
	return $app->show_message('Error', 'Bad Range Start');
      $prefix = $query->param('prefix') or 
	return $app->show_message('Error', 'Bad Range Prefix');
      
      my ($from_i, $to_i, $network_i, $netmask) = netmask_prefix2range($host,$prefix);
      $netmask  = int2ip($netmask);
      my $from  = int2ip($from_i);
      my $to    = int2ip($to_i);
      $range   = $schema->resultset('IPRange')->search({ -and =>[ 
							      from_addr => $from,
							      to_addr   => $to,
							     ]})->single;
      return $self->iprange_view($app,$from,$to,$prefix,$netmask,$host,$to_i-$from_i) 
	if(!defined($range));
    }

    #Resource View was called with "name" parameter
    $range or $range = $schema->resultset('IPRange')->find($name);
    return $app->show_message('Error', 'Range not found') unless($range);
    
    $name   = $range->name;
    my @children = map +{
        name		=> $_->name,
        from		=> $_->from_addr,
        to	    	=> $_->to_addr,
        vlan_id     	=> $_->vlan_id ? $_->vlan_id->id : undef,
        vlan        	=> $_->vlan_id ? $_->vlan_id->name : "-",
        view_url	=> $app->manoc_url("iprange/view?name=" . $_->name),
        edit_url	=> $app->manoc_url("iprange/edit?name=" . $_->name),
        split_url	=> $app->manoc_url("iprange/split?name=" . $_->name),
        merge_url	=> $app->manoc_url("iprange/merge?name=". $_->name),
        delete_url	=> $app->manoc_url("iprange/delete?name=" . $_->name),
        n_children	=> $_->children->count(),
        n_neigh		=> get_neighbour($schema, $name, ip2int($_->from_addr), ip2int($_->to_addr))->count(),
    }, $range->search_related('children', undef, {order_by => 'inet_aton(from_addr)'});

    my %tmpl_param;
    my $parent_name = $range->parent ? $range->parent->name : undef;

    my $rs = $schema->resultset('Arp')->search(
	{
	    'inet_aton(ipaddr)' => {
		'>=' => ip2int($range->from_addr),
		'<=' => ip2int($range->to_addr),
	    }
	},					       
	{ 
	    select     => 'ipaddr',
	    order_by   => 'ipaddr',
	    distinct   => 1,
	});

    #Subnet Info
    if($range->netmask){
      $prefix =  netmask2prefix($range->netmask);
      $tmpl_param{network}  = $range->network;
      $tmpl_param{netmask}  = $range->netmask;
      $tmpl_param{prefix}   = $prefix;
      $tmpl_param{wildcard} = prefix2wildcard($prefix);
    }

    $tmpl_param{name}	           = $range->name;
    $tmpl_param{description}       = $range->description;
    $tmpl_param{min_host}          = int2ip(ip2int($range->from_addr) + 1);
    $tmpl_param{max_host}          = int2ip(ip2int($range->to_addr)   - 1);
    $tmpl_param{numhost}           = $tmpl_param{max_host} - $tmpl_param{min_host} - 1;
    $tmpl_param{ipaddr_num}        = $rs->count();
    $tmpl_param{parent}            = $parent_name || 'none';
    $tmpl_param{parent_link}	   = (
	$parent_name ? 
	$app->manoc_url("iprange/view?name=$parent_name") : 
	$app->manoc_url("iprange/list")
	);
    $tmpl_param{vlan_id}           = $range->vlan_id ? $range->vlan_id->id   : undef;
    $tmpl_param{vlan}              = $range->vlan_id ? $range->vlan_id->name : "none";
    $tmpl_param{rangelist_widget}  = $self->make_rangelist($app, \@children);
    $tmpl_param{add_link}	   = $app->manoc_url("iprange/create?parent=$name");
    $tmpl_param{edit_url}          = $app->manoc_url("iprange/edit?name=$name");
    $tmpl_param{remove_url}        = $app->manoc_url("iprange/delete?name=$name");
    $tmpl_param{iplist_widget}     = $self->make_iplist
	($app, $name, $range->from_addr, $range->to_addr, $prefix , $page);
    $tmpl_param{iplist_def}       = $page ? 1 : 0;

    
    my $template = $app->prepare_tmpl(	
					tmpl  => 'iprange/view.tmpl',
					title => 'Subnet',
			             );
    $template->param(%tmpl_param);
    return $template->output();
}

#------------------------------------------------------------------------#
sub make_iplist {
  my ($self, $app, $name, $query_from, $query_to, $prefix, $page ) = @_;
  $page  =  1 unless($page);

  my $schema = $app->param('schema');
  my $query  = $app->query();
  my $max_page_items = $query->param('items') || $DEFAULT_PAGE_ITEMS;
  my $page_start_addr = ip2int($query_from);
  my $page_end_addr   = ip2int($query_to);
  my $range;
  my $backref = $name ? 
      "iprange/view?name=$name&page=" : "iprange/view?from=$query_from&prefix=$prefix&page=";
  
  # sanitize;
  $page < 0 and $page = 1;
  $max_page_items > $MAX_PAGE_ITEMS and $max_page_items = $MAX_PAGE_ITEMS;

  # paging arithmetics
  my $page_size	= $page_end_addr - $page_start_addr;
  my $num_pages = ceil($page_size / $max_page_items);
  if ($page > 1) {	
    $page_start_addr += $max_page_items * ($page - 1);
    $page_size       = $page_end_addr - $page_start_addr;
  }
    
  if ($page_size > $max_page_items) {
    $page_end_addr = $page_start_addr + $max_page_items;
    $page_size     = $max_page_items;
  }
  
  my @rs;
  @rs = $schema->resultset('Arp')->search({
					   'inet_aton(ipaddr)' => {
								   '>=' => $page_start_addr,
								   '<=' => $page_end_addr,
								  }
					  },					       
					  { 
					   select    => [
							 'ipaddr',
							 {
							  'max' => 'lastseen'}
							],
					   group_by  => 'ipaddr',
					   as	     => ['ipaddr', 'max_lastseen'],
					  }); 
  my %arp_info = map { 
    $_->ipaddr => print_timestamp($_->get_column('max_lastseen'))
  } @rs;
  
  @rs = $schema->resultset('IpNotes')->search({
					       'inet_aton(ipaddr)' => {
								       '>=' => $page_start_addr,
								       '<=' => $page_end_addr,
								      }
					      });
  my %ip_note = map {
    $_->ipaddr => $_->notes
  } @rs;
    
  my @addr_table;
  foreach my $i (0 .. $page_size-1) {
    my $ipaddr = int2ip($page_start_addr + $i);

    push @addr_table, {
		       ipaddr      => $ipaddr,
		       lastseen	   => $arp_info{$ipaddr} || 'na',
		       notes	   => $ip_note{$ipaddr}  || '',
		       edit_url    => $app->manoc_url("ipnotes_edit",
						      ipaddr=>$ipaddr,
						      backref=>$backref.$page),
		       delete_url  => $app->manoc_url("ipnotes_delete", 
						      ipaddr=>$ipaddr,
						      backref=>$backref.$page),
		      };
  }      
 
    my %tmpl_param;
	    
    $tmpl_param{name}		  = $name;
    $tmpl_param{addr_table}       = \@addr_table;
    $tmpl_param{prev_page_link}   = $app->manoc_url($backref.($page-1));
    $tmpl_param{next_page_link}   = $app->manoc_url($backref.($page+1));
    $tmpl_param{page}             = $page;
    $tmpl_param{first_page}       = $page == 1;
    $tmpl_param{last_page}        = $page == $num_pages;
   
    my $template = $app->prepare_tmpl(	
					tmpl   => 'iprange/iplist.tmpl',
				        widget => 1,
				     ); 
    $template->param(%tmpl_param);
    return $template->output();
}

#----------------------------------------------------------------------#

sub edit : Resource {
    my ($self, $app) = @_;

    # Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");
    
    my $query  = $app->query;
    my $schema        = $app->param('schema');
    my $name          = $query->param('name');
    my $new_name      = $query->param('new_name');
    my $from_addr     = $query->param('from_addr');
    my $to_addr       = $query->param('to_addr');
    my $network       = $query->param('network');
    my $type          = $query->param('type');
    my $vlan_id       = $query->param('vlan');
    my $prefix        = $query->param('prefix');
    my $netmask;

    my $message;
    if ($query->param('submit')) {
	my $done;
	($done, $message) = $self->process_edit($app);
	if ($done) {	    
	    return $app->manoc_redirect("iprange/view?name=$new_name");
	}
    }

    my %tmpl_param;
    my $range = $schema->resultset('IPRange')->find($name);
    $range or 
	return $app->show_message('Error', 'Bad iprange name');

    $name      = $range->name;
    $new_name  ||= $name;

    $from_addr ||= $range->from_addr;
    $to_addr   ||= $range->to_addr;
    $network   ||= $range->network;
    $netmask   = $range->netmask;
    $vlan_id   = $range->vlan_id ? $range->vlan_id->id : undef;

    if (!$type && defined($network) && defined($netmask)) {
	    $type   = 'subnet';
	    $prefix = Manoc::Utils::netmask2prefix($netmask);
    }

    if (!defined($prefix) ) {
	$type = 'range';
	$network = $netmask = undef;

    }

    my @vlans_rs = $schema->resultset('Vlan')->search();
    my @vlans = map {
	id       => $_->id,
	name     => $_->name,
	selected => $_->id eq $vlan_id,
    }, @vlans_rs;

    $tmpl_param{name} 		= $name;
    $tmpl_param{new_name} 	= $new_name;
    $tmpl_param{message}	= $message;
    $tmpl_param{type_subnet}    = $type eq 'subnet';
    $tmpl_param{type_range}     = $type eq 'range';
    $tmpl_param{vlans}    	= \@vlans;
    $tmpl_param{from_addr} 	= $from_addr;
    $tmpl_param{to_addr} 	= $to_addr;
    $tmpl_param{network} 	= $network;
    $tmpl_param{prefixes} = [ map { 
	id       => $_,
	label    => $_,
	selected => $prefix && $prefix == $_,
    }, (0 .. 32) ];

    my $template = $app->prepare_tmpl(
				      tmpl  => 'iprange/edit.tmpl',
				      title => 'Edit Address Range'
				      ); 

    $template->param(%tmpl_param);
    return $template->output();
}

sub process_edit {
    my ($self, $app) = @_;

    my $schema = $app->param('schema');

    my $query     = $app->query;
    my $name      = $query->param('name');	
    my $new_name  = $query->param('new_name'); 
    my $vlan_id   = $query->param('vlan');
    my $desc      = $query->param('description');
    my $type      = $query->param('type');

    my ($from_addr_i, $to_addr_i, $network_i, $netmask_i);

    my ($res, $mess);

    my $range = $schema->resultset('IPRange')->find($name);
    $range or return (0, "Range not found");
    
    $vlan_id eq "none" and undef $vlan_id;

    # check name parameter
    if (lc($name) ne lc($new_name)) {
	($res, $mess) = check_name($new_name, $schema);
	$res or return (0, $mess);
    }

    if ($type eq 'subnet') {
	 my $network   = $query->param('network');
	 my $prefix    = $query->param('prefix');

	$network or return (0, "Missing network");
	$prefix  or return (0, "Missing prefix");
	check_addr($network) or return (0, "Bad network address");

	$prefix =~ /^\d+$/ and ($prefix >= 0 || $prefix <= 32) or
	    return (0, "Bad subnet prefix");

	($from_addr_i,	$to_addr_i, $network_i,	$netmask_i)  =
	    Manoc::Utils::netmask_prefix2range($network, $prefix);

	 if ($network_i != $from_addr_i) {
	     return (0, "Bad network. Do you mean ". int2ip($from_addr_i) ."?");
	 }
    } elsif ($type eq 'range') {
	my $from_addr = $query->param('from_addr');
	my $to_addr   = $query->param('to_addr');   

	defined($from_addr) or
	    return (0, "Please insert range from address");
	check_addr($from_addr) or
	    return (0, "Start address not a valid IPv4 address");

	defined($to_addr) or
	    return (0, "Please insert range to address");
	check_addr($to_addr) or
	    return (0, "End address not a valid IPv4 address");
	
	$network_i   = undef;
	$netmask_i   = undef;

	$to_addr_i   = ip2int($to_addr);
	$from_addr_i = ip2int($from_addr);
        return (0, "Invalid range") unless ($to_addr_i >= $from_addr_i);
	

    } else {
	return (0, "Unexpected form parameter (type)");
    }

    # check parent parameter and overlappings
    my $parent = $range->parent;
    if ($parent) {
	# range should be inside its parent
	unless ($from_addr_i >= ip2int($parent->from_addr) && $to_addr_i <= ip2int($parent->to_addr)) {
	    return (0, "Invalid range: overlaps with its parent (" . $parent->from_addr . " - " . $parent->to_addr . ")");
	}

        #Check if the range is the same of the father
        (($from_addr_i == ip2int($parent->from_addr)) && ($to_addr_i == ip2int($parent->to_addr)))
            and return (0, "Invalid range: can't be the same as the parent range");
	
    } 

    # cannot overlap any sibling range
    my $conditions = [
		      {
			  'inet_aton(from_addr)'  => { '<=' => $from_addr_i },
			  'inet_aton(to_addr)'	  => { '>=' => $from_addr_i },
			  name  	=> { '!=' => $name }
		      },
		      {
			  'inet_aton(from_addr)'  => { '<=' => $to_addr_i },
			  'inet_aton(to_addr)'    => { '>=' => $to_addr_i },
			  name  	=> { '!=' => $name }
		      },
		      {
			  'inet_aton(from_addr)'  => { '>=' => $from_addr_i },
			  'inet_aton(to_addr)'	  => { '<=' => $to_addr_i },
 			  name  	=> { '!=' => $name }
		      }
	];
    if (defined($parent)) {
	foreach my $condition (@$conditions) {
	    $condition->{parent} = $parent->name;
	}
    }else {
	foreach my $condition (@$conditions) {
	    $condition->{parent} = undef;
	}
    }
    my @rows = $schema->resultset('IPRange')->search($conditions);
    @rows and
 	return (0, "Invalid range: overlaps with " . $rows[0]->name ." (" . $rows[0]->from_addr . " - " . $rows[0]->to_addr . ")" );

    # cannot overlap any son range and must have them inside the range
    $conditions = [
		      {
			  'inet_aton(from_addr)'  => { '<' => $from_addr_i },
			  'inet_aton(to_addr)'    => { '>' => $from_addr_i },
			  parent  	=> { '=' => $name }
		      },
		      {
			  'inet_aton(from_addr)'  => { '<' => $to_addr_i },
			  'inet_aton(to_addr)'	  => { '>' => $to_addr_i },
			  parent  	=> { '=' => $name }
		      },
		      {
			  'inet_aton(to_addr)'    => { '<' => $from_addr_i },
			  parent  	=> { '=' => $name }
		      },
		      {
			  'inet_aton(from_addr)'  => { '>' => $to_addr_i },
			  parent  	=> { '=' => $name }
		      },
		     ];
    @rows = $schema->resultset('IPRange')->search($conditions);
    @rows and
 	return (0, "Invalid range (conflicts " . $rows[0]->name . ")");

    #Update range
    $range->set_column('name',        $new_name);
    $range->set_column('from_addr',   int2ip($from_addr_i));
    $range->set_column('to_addr',     int2ip($to_addr_i));
    $range->set_column('network',     $network_i ? int2ip($network_i) : undef);
    $range->set_column('netmask',     $netmask_i ? int2ip($netmask_i) : undef);
    $range->set_column('vlan_id',     $vlan_id);
    $range->set_column('description', $desc);
    $range->update or 
	return(0, "Cannot update range");

    return (1, "updated '$name' (" . int2ip($from_addr_i) . "-" . int2ip($to_addr_i) . ")");
}

#----------------------------------------------------------------------#

sub create : Resource {
    my ($self, $app) = @_;
    
    #Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");

    my $query   = $app->query;
    my $parent  = $query->param('parent');
    my $vlan_id = $query->param('vlan');

    my $message;
    if ($query->param('submit')) {
	my $done;
	($done, $message) = $self->process_create($app);
	if ($done) {
		if ($parent) {
		    return $app->manoc_redirect("iprange/view?name=$parent");
		} else {
		    return $app->manoc_redirect("iprange/list");
		}
	}
    }

    my $schema = $app->param('schema');
    my $prefix = $query->param('prefix');
    my %tmpl_param;

    $tmpl_param{prefixes} = [ map { 
	id       => $_,
	label    => $_,
	selected => $prefix && $prefix == $_,
    }, (0 .. 32) ];

    my @vlans_rs = $schema->resultset('Vlan')->search();
    my @vlans = map {
                        id       => $_->id,
                        name     => $_->name,
                        selected => $_->id eq $vlan_id
                    }, @vlans_rs;

    $tmpl_param{message} = $message;
    foreach( qw(name network prefix from_addr to_addr parent) ) {
        $tmpl_param{$_} = $query->param($_);
    }
    $tmpl_param{type_subnet} = $query->param('type') eq 'subnet';
    $tmpl_param{type_range}  = $query->param('type') eq 'range';
    $tmpl_param{vlans}       = \@vlans;

    my $template = $app->prepare_tmpl(
				      tmpl  => 'iprange/create.tmpl',
				      title => 'New IP Address Range'
				      ); 

    $template->param(%tmpl_param);
    return $template->output();
}

sub process_create {
    my ($self, $app) = @_;

    my $schema = $app->param('schema');

    my $query   = $app->query;
    my $name    = $query->param('name');
    my $type    = $query->param('type');
    my $vlan_id = $query->param('vlan');

    $name or return (0, "Please insert range name");
    $type or return (0, "Please insert range type");
    $vlan_id eq "none" and undef $vlan_id;
 
    my ($network_i, $netmask_i, $from_addr_i, $to_addr_i);

    if ($type eq 'subnet') {
	my $network = $query->param('network');  
	my $prefix  = $query->param('prefix');	 
	
	$network or return (0, "Please insert range network");
	$prefix  or return (0, "Please insert range prefix");
	check_addr($network) or return (0, "Invalid network address");

	$prefix =~ /^\d+$/ and ($prefix >= 0 || $prefix <= 32) or
	    return (0, "Invalid subnet prefix");

	( $from_addr_i,	$to_addr_i, $network_i,	$netmask_i )  =
	    Manoc::Utils::netmask_prefix2range($network, $prefix);

	if ($network_i != $from_addr_i) {
	    return (0, "Bad network. Do you mean ". int2ip($from_addr_i) ."?");
	}
    } else {
	$type eq 'range' or die "Unexpected form parameter";

	my $from_addr = $query->param('from_addr');  
	my $to_addr   = $query->param('to_addr');  

	$from_addr or return (0, "Please insert range from address");
	$to_addr   or return (0, "Please insert range to address");

	check_addr($from_addr) or return (0, "Start address not a valid IPv4 address");
	check_addr($to_addr)   or return (0, "End address not a valid IPv4 address");

	$to_addr_i   = ip2int($to_addr);
	$from_addr_i = ip2int($from_addr);
	    
	$to_addr_i >= $from_addr_i or return (0, "Invalid range");

	$network_i = $netmask_i = undef;
    }

    # check name parameter 
    my($res, $mess);
    $name = $query->param('name');
    ($res, $mess) = check_name($name, $schema);
    $res or return (0, $mess);

    # check parent parameter and overlappings
    my $parent_name = $query->param('parent');
    if ($parent_name) {
	my $parent = $schema->resultset('IPRange')->find($parent_name);
	$parent or
	    return (0, "Invalid parent name '$parent_name'");
	
	# range should be inside its parent
	unless ($from_addr_i >= ip2int($parent->from_addr) && $to_addr_i <= ip2int($parent->to_addr)) {
	    	    return (0, "Invalid range: overlaps with its parent (" . 
			    $parent->from_addr . " - " . $parent->to_addr . ")");
	}

        #Check if the range is the same of the father
        (($from_addr_i == ip2int($parent->from_addr)) && ($to_addr_i == ip2int($parent->to_addr))) 
            and return (0, "Invalid range: can't be the same as the parent range");
    } else {
	$parent_name = undef;
    }

    # cannot overlap any sibling range
    my $conditions = [
		      {
			  'inet_aton(from_addr)' => { '<=' => $from_addr_i },
			  'inet_aton(to_addr)'   => { '>=' => $from_addr_i }
		      },
		      {
			  'inet_aton(from_addr)' => { '<=' => $to_addr_i },
			  'inet_aton(to_addr)'   => { '>=' => $to_addr_i }
		      },
		      {
			  'inet_aton(from_addr)' => { '>=' => $from_addr_i },
			  'inet_aton(to_addr)'   => { '<=' => $to_addr_i }
		      },
		      ];
    if (defined($parent_name)) {
	foreach my $condition (@$conditions) {
	    $condition->{parent} = $parent_name;
	}
    }

    my @rows = $schema->resultset('IPRange')->search($conditions);
    @rows and
        return (0, "Invalid range: overlaps with " . $rows[0]->name . 
		" (" . $rows[0]->from_addr . " - " . $rows[0]->to_addr . ")" );

    $schema->resultset('IPRange')->create({ 
		name		=> $name,
		parent		=> $parent_name,
		from_addr       => int2ip($from_addr_i),
		to_addr 	=> int2ip($to_addr_i),
		network		=> $network_i ? int2ip($network_i) : undef,
		netmask		=> $netmask_i ? int2ip($netmask_i) : undef,
		vlan_id         => $vlan_id,
	    }) or return (0, "Impossible create subnet");

    return (1, "created '$name' (" . int2ip($from_addr_i) . "-" . int2ip($to_addr_i) . ")");
}

#----------------------------------------------------------------------#

sub split : Resource {
    my ($self, $app) = @_;
    my ($done, $message);
    
    #Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");       

    my %tmpl_param;
    my $schema = $app->param('schema');
    my $query  = $app->query;
    my $parent = $query->param('parent');	
    my $name  = $query->param('name');
    my $name1 = $query->param('name1');
    my $name2 = $query->param('name2');
    my $split_point_addr = $query->param('split_point_addr');

    if ($query->param('submit')) {
 	($done, $message)=$self->process_split($app);
 	if ($done) {
		if ($parent) {
		    return $app->manoc_redirect("iprange/view?name=$parent");
		} else {
		    return $app->manoc_redirect("iprange/list");
		}
	}
    }

    my $range		= $schema->resultset('IPRange')->find($name);
    my $from_addr	= ip2int($range->from_addr);
    my $to_addr		= ip2int($range->to_addr);
    $parent = $range->parent;
    $parent and $parent = $parent->name;

    $tmpl_param{message}	= $message;
    $tmpl_param{name}		= $name;
    $tmpl_param{parent}		= $parent;
    $tmpl_param{from_addr}	= int2ip($from_addr);
    $tmpl_param{to_addr}	= int2ip($to_addr);
    $tmpl_param{name1}		= $name1;
    $tmpl_param{name2}		= $name2;
    $tmpl_param{split_point_addr} = $split_point_addr;

    my $template = $app->prepare_tmpl(
				      tmpl  => 'iprange/split.tmpl',
				      title => 'Split Address Range'
				      ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_split
{
 	my ($self, $app) = @_;
	
	#Get parameters
	my $schema = $app->param('schema');
    	my $query  = $app->query;
    	my $name = $query->param('name');  
    	my $name1 = $query->param('name1');
   	my $name2 = $query->param('name2');  
    	my $split_point_addr = $query->param('split_point_addr');
	
 	my $range = $schema->resultset('IPRange')->find($name);
	$range or return (0, "Unknown range");

	$name1 or return (0, "Please insert name subnet 1");
	$name2 or return (0, "Please insert name subnet 2");
	$split_point_addr  or return (0, "Please insert split point address");

	#Check parameters
	my($res, $mess);
	($res, $mess) = check_name($name1, $schema);
	$res or return (0, "Name Subnet 1: $mess");
	($res, $mess) = check_name($name2, $schema); 
	$res or return (0, "Name Subnet 2: $mess");

 	if ($name1 eq $name2) {
	    return (0, "Name Subnet 1 and Name Subnet 2 cannot be the same");
	}

	check_addr($split_point_addr) or
	    return (0, "Split point address not a valid IPv4 address: $split_point_addr");
	
	#Retrieve subnet info
 	my $from_addr 	  = ip2int($range->from_addr);
 	my $to_addr	  = ip2int($range->to_addr);
 	my $parent	  = $range->parent;
	my $vlan_id	  = $range->vlan_id;
 	
	#Check split point address 
	$split_point_addr=ip2int($split_point_addr);
        if (($from_addr > $split_point_addr) || ($to_addr <= $split_point_addr)) {
	    return (0, "Split point address not inside the range");
	}

	if ($range->children->count()) {		
	    # useless:is already checked in rangelist.tmpl
	    return (0, "$name cannot be splitted because it is divided in subranges"); 
	}

	#Update DB
	$schema->txn_do( sub {
	    $range->delete; 
	    $schema->resultset('IPRange')->create({ 
                name		=> $name1,
                parent		=> $parent,
                from_addr       => int2ip($from_addr),
                to_addr	        => int2ip($split_point_addr),
                netmask		=> undef,
                network		=> undef,
                vlan_id         => $vlan_id
		}) or return (0, "Impossible split range");
	    
	    $schema->resultset('IPRange')->create({ 
                name		=> $name2,
                parent		=> $parent,
                from_addr       => int2ip($split_point_addr+1),
                to_addr 	=> int2ip($to_addr),
                netmask		=> undef,
                network		=> undef,
                vlan_id         => $vlan_id
		}) or return (0, "Impossible split range");
	});
        
	if ($@) {
	    my $commit_error = $@;
	    return (0, "Error while updating database: $commit_error");
	}
	
	return (1, "Range splitted succesfully");
}

#----------------------------------------------------------------------#

sub merge : Resource {
    my ($self, $app) = @_;
    my ($done, $message);
    
    #Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");            

    my %tmpl_param;
    my $schema 	= $app->param('schema');
    my $query  	= $app->query;
    my $parent 	= $query->param('parent');	
    my $name 	= $query->param('name');
    my $new_name = $query->param('new_name');
    my $neigh 	= $query->param('neigh');

    if ($query->param('submit')) {
 	($done, $message)=$self->process_merge($app);
 	if ($done) 
	{
		if ($parent) {
		    return $app->manoc_redirect("iprange/range?name=$parent");
		} else {
		    return $app->manoc_redirect("iprange/list");
		}
	}
    }

    my $range		= $schema->resultset('IPRange')->find($name);
    my $from_addr	= ip2int($range->from_addr);
    my $to_addr		= ip2int($range->to_addr);
    
    $parent = $range->parent;
    if ($parent) {$parent=$parent->name;}

    my @neighbours = map {
	name		=> $_->name,
	from		=> $_->from_addr,
	to		    => $_->to_addr,
	checked  	=> ($neigh eq ($_->name)),
	view_url	=> "range?name="  . $_->name,
    }, get_neighbour($schema, $parent, $from_addr, $to_addr);

    $tmpl_param{message} 	= $message;
    $tmpl_param{name} 		= $name;
    $tmpl_param{from_addr} 	= int2ip($from_addr);
    $tmpl_param{to_addr} 	= int2ip($to_addr);
    $tmpl_param{parent} 	= $parent;
    $tmpl_param{neighbours} 	= \@neighbours;
    $tmpl_param{new_name} 	= $new_name;
    $tmpl_param{neigh} 		= $neigh;

    my $template = $app->prepare_tmpl(
				      tmpl  => 'iprange/merge.tmpl',
				      title => 'Merge Address Range'
				      ); 
    $template->param(%tmpl_param);
    return $template->output();
}

sub process_merge {
  	my ($self, $app) = @_;
 
 	#Get parameters
 	my $schema = $app->param('schema');
     	my $query  = $app->query;
     	my $name   = $query->param('name');
	my $neigh  = $query->param('neigh');  
	my $new_name = $query->param('new_name'); 

 	#Check parameters			
	$neigh    or return (0, "Please select the neighbour range");
	$new_name or return (0, "Please insert merged subnet name");
	

        my($res, $mess);
        ($res, $mess) = check_name($new_name, $schema); 
	$res or return (0, "Bad merged subnet name: $mess");

	#Retrieve subnet info
 	my $rs		= $schema->resultset('IPRange')->find($name);
 	my $from_addr	= ip2int($rs->from_addr);
 	my $to_addr	= ip2int($rs->to_addr);
 	my $parent	= $rs->parent;
	my $vlan_id	= $rs->vlan_id;
	
	#Retrieve neigh subnet info
 	$rs = $schema->resultset('IPRange')->find($neigh);
 	my $neigh_from_addr = ip2int($rs->from_addr);
 	my $neigh_to_addr   = ip2int($rs->to_addr);

	if ($parent) {
		#Retrieve parent subnet info
		my $rs = $schema->resultset('IPRange')->find($parent->name);
		my $parent_from_addr = ip2int($rs->from_addr);
		my $parent_to_addr	 = ip2int($rs->to_addr);
	
		#Check if the merged subnet and the parent subnet has the same range 
		if ((($from_addr == $parent_from_addr) && ($neigh_to_addr == $parent_to_addr)) || 
		    (($neigh_from_addr == $parent_from_addr) && ($to_addr == $parent_to_addr))) {
		    return (0, "Merged and parent subnets has the same range!");
		}
	}	

	#Check subnets' children
 	if ($schema->resultset('IPRange')->find($name)->count()) {
	    return (0, "$name cannot be merged because it is divided in subranges"); 
 	}
	if ($schema->resultset('IPRange')->find($neigh)->count()) {
	    return (0, "$name cannot be merged because $neigh it is divided in subranges"); 
 	}

 	#Update DB
	$schema->txn_do( sub {
	    $schema->resultset('IPRange')->search({name => "$name"})->delete;
	    $schema->resultset('IPRange')->search({name => "$neigh"})->delete;  
	    $schema->resultset('IPRange')->create({ 
                name	   => $new_name,
                parent	   => $parent,
                from_addr  => ($from_addr < $neigh_from_addr ? int2ip($from_addr) : int2ip($neigh_from_addr)),
                to_addr	   => ($to_addr > $neigh_to_addr ? int2ip($to_addr) : int2ip($neigh_to_addr)),
                netmask	   => undef,
                network	   => undef,
                vlan_id    => $vlan_id
						  });
			 });
        
	if ($@) {
	    my $commit_error = $@;
	    return (0, "Impossible update database: $commit_error");
	}
	
	return (1, "Range merged succesfully");
}

#----------------------------------------------------------------------#

sub delete : Resource {
    my ($self, $app) = @_;
    
    # Check permission
    Manoc::UserAuth->check_permission($app, ('admin')) or
	return $app->manoc_redirect("forbidden");

    my $iprange_rs = $app->param('schema')->resultset('IPRange');

    my $query = $app->query;
    my $name  = $query->param('name');

    if ($iprange_rs->search({parent => $name})->count()) {
	return $app->show_message("$name cannot be deleted because has been splitted"); 
    }

    my $range  = $iprange_rs->find({name => $name});
    my $parent = $range->parent;
    $parent and $parent = $parent->name;

    $range->delete();
    if ($parent) {
	return $app->manoc_redirect("iprange/view?name=$parent");
    } else {
	return $app->manoc_redirect("iprange/list");
    }
    
}


#----------------------------------------------------------------------#

sub make_rangelist {
    my ($self, $app, $ranges_ref) = @_;
    
    my $rangelist = $app->prepare_tmpl(
				       tmpl   => 'iprange/_rangelist.tmpl',
				       widget => 1
				       );
    $rangelist->param('ranges' => $ranges_ref);
    
    return $rangelist->output;
}


#----------------------------------------------------------------------#
# check for valid name and if a schema is given against duplicates 
# names
sub check_name
{
     	my ($name, $schema) = @_;
        $name =~ /^\w[\w-]*$/ or return (0, "Invalid name");
 
	if ($schema) {
	    $schema->resultset('IPRange')->find($name) and 
		return (0, "Duplicated range name");
	}

	return (1, "");
}

sub check_addr
{
	my $addr = shift;
	return $addr =~ /^$RE{net}{IPv4}$/;
}

sub get_neighbour
{
	my ($schema, $parent, $from_addr, $to_addr) = @_;
	$schema->resultset('IPRange')->search({	    
	    parent => $parent, 
	    -or => [
		{ 'inet_aton(to_addr)'   => $from_addr - 1 },
		{ 'inet_aton(from_addr)' => $to_addr   + 1 }
		]});
}


1;
