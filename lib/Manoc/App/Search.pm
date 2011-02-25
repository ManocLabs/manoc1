package Manoc::App::Search;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;

use Manoc::Utils qw(str2seconds ip2int);
use Data::Dumper;

sub get_match{
    my $q = shift;
    if( ($q =~ /^:.+:$/) || ($q =~ /^\..+\.$/) ){
	return 'partial';
    }
    elsif( ($q =~ /^[\.:]/) ){
	return 'end';
    }
    elsif( ($q =~ /[\.:]$/) ){
	return 'begin';
    }   
    else {
	return 'exact';
    }
}

#Here we parse the user input in order to identify the scope of the query according to 
#the mini-language keywords  
sub parse_text {
    my ($app, $text, $desc) = @_;    

  READ:
    {
	#type's token (at the beginning of the line)
	if ($text =~ /^(inventory|building|rack|device|logon|ipaddr|macaddr|notes|subnet)\b/gcos){
	    $desc->{'scope'} = $1;
	}
	#explicit type's token
	elsif($text =~ /\G\s*type[:]*\s*(inventory|building|rack|device|logon|ipaddr|macaddr|notes|subnet)\s*/gcos) {
	    $desc->{'scope'} = $1;
	} 
	#limit token
	elsif($text =~ /\G\s*limit[:]*\s*(\d+[smhdwMy])/gcos){
	    $desc->{'limit'} = $1;
	}
	#ipcalc token
  	elsif($text =~ /\G\s*(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s*\/\s*(\d+)/gcos){
	    $desc->{'query'}  = $1;
	    $desc->{'prefix'} = $2; 
	    $desc->{'scope'}  = 'subnet';
  	}
	#default token
	elsif($text =~ /\G\s*([\w\.:-]+|"[^\"]+")/gcos){
	    if(!defined($desc->{'query'}) ){
		$desc->{'query'} = $1;
	    }
	    else {
		$desc->{'query'}.=" ".$1;
	    }
	}
	redo READ if $text =~ /\G(.)/gcos;
	
    }
    if ( defined($desc->{'query'}) ) {
	$desc->{'match'} = get_match( $desc->{'query'} );
    }
   
    query_guess($desc) if (!defined($desc->{'scope'}));    
}

#Here we try to infer the search scope based on the query semantics (e.g. if the query
#include a :, we want to look up a mac address)
sub query_guess{
  my $query_desc = shift;
  my $q = $query_desc->{'query'};
  $q or return;
  
  if ($q =~ m{ ^(
		 ( ([0-9a-f]{2})? ([-:][0-9a-f]{2})+ [-:]? ) |
		 ([0-9a-f]{2}[-:])
		 )$
	     }xo)  {	 
      $q    =~ y/-/:/;
      $query_desc->{'query'} = $q;
      $query_desc->{'scope'} = 'macaddr';
  }
  elsif ($q =~ /^([0-9a-f]{4}(\.[0-9a-f]{4}){2})$/o) {
      # cisco style mac
      $q    = join(':', map { unpack('(a2)*', $_) } split(/\./, $q));
      $query_desc->{'query'} = $q;
      $query_desc->{'scope'} = 'macaddr';
  } 
  elsif ($q =~ /^([0-9\.]+)$/o) {
    if ( $query_desc->{'match'} eq 'exact' && $query_desc->{'scope'} eq 'device') {
      return; 
    }
    $query_desc->{'scope'} = 'ipaddr';    
  }
  else{
      $query_desc->{'scope'} or $query_desc->{'scope'} = 'inventory';    
  }
}

sub add_percent{
    my $query_desc = shift;
    
    if($query_desc->{'match'} eq 'begin'){
	return $query_desc->{'query'}.'%'; 
    }
    elsif ($query_desc->{'match'} eq 'end' ) {
        return  '%'.$query_desc->{'query'};
    }
    elsif ($query_desc->{'match'} eq 'partial' ) {
	return  '%'.$query_desc->{'query'}.'%';      
    }  
    else {
	return $query_desc->{'query'};
    }
}

sub add_opt{
  my ($query,$desc) = @_;

  $query->param('scope')  and $desc->{'scope'} = $query->param('scope') ; 
  $query->param('limit')  and $desc->{'limit'} = $query->param('limit') ;
}

sub add_default{
  my ($app,$desc) = @_;
  
  $desc->{'limit'} = $app->config_param('cgi.default_limit');  
}

sub search_macaddr {
    my ($app, $query_desc, $limit) = @_;

    my $q = add_percent($query_desc);
    my $schema = $app->param('schema');

    my $results = [];
    #hash table with the search results.
    #ex: tmp_results{mac_address}->{db table}->{ip} = timestamp
    my %tmp_results; 
    my ($e, $it); # entry and interator
	
    #prepare conditions
    my $conditions = {};
    $conditions->{'macaddr'} = {'-like', $q };
    if ($limit) {
	$conditions->{lastseen} = { '>=' , $limit };
    }

    # search in ARP table
    $it = $schema->resultset('Arp')->search($conditions);
    while ($e = $it->next) {
	
	$tmp_results{$e->macaddr}->{arp}->{$e->ipaddr} = $e->lastseen;
    }
    # search in MAT table
    $it = $schema->resultset('Mat')->search($conditions);
    while ($e = $it->next) {
	    my $iface = $e->device . '/' . $e->interface;
	    $tmp_results{$e->macaddr}->{mat}->{$iface} = $e->lastseen;
	}
    #search in MatArchived
    $it = $schema->resultset('MatArchive')->search($conditions);
    while ($e = $it->next) {
	$conditions->{prefetch} = {'device'};
	$tmp_results{$e->macaddr}->{mat_archive}->{$e->device->ipaddr} = $e->lastseen;
    }
    
    
    #populate @results
    foreach my $mac (keys %tmp_results) {
	my $items = [];
	my $result_entry = {
			    mac   => $mac,
			    items => $items,
			   };
	
	
	if ( exists $tmp_results{$mac}->{arp} ) {
	    my %ip_set = %{ $tmp_results{$mac}->{arp} };
	    my @temp;
	    foreach my $ip (keys %ip_set) {
		push @temp, {
		    ip		=> $ip,
		    lastseen    => $ip_set{$ip},
		}
	    }
	    @temp = sort {$b->{'lastseen'} <=>  $a->{'lastseen'}} @temp;
	    push @$items, @temp;
	  }

	if ( exists $tmp_results{$mac}->{mat} ) {
	    my %mat_set = %{ $tmp_results{$mac}->{mat} };
	    my @temp;
	    foreach my $i (keys %mat_set) {
		my ($device, $iface) = split qr{/}, $i, 2;
		push  @temp, {
		    device	=> $device,
		    iface	=> $iface,
		    lastseen    => $mat_set{$i},
		}
	    }
	    @temp = sort {$b->{'lastseen'} <=>  $a->{'lastseen'}} @temp;
	    push @$items, @temp;
	}

	if ( exists $tmp_results{$mac}->{mat_archive} ) {
	    my %ip_set = %{ $tmp_results{$mac}->{mat_archive} };
	    my @temp;
	    foreach my $ip (keys %ip_set) {
		push  @temp, {
		    ip_del    => $ip,
		    lastseen  => $ip_set{$ip},
		}
	    }
	    @temp = sort {$b->{'lastseen'} <=>  $a->{'lastseen'}} @temp;
	    push @$items, @temp;
	  }
	
	push @$results, $result_entry;
    }
    return $results;
}

sub search_ipaddr {
    my ($app, $query_desc, $limit) = @_;
    
    my $q = add_percent($query_desc);
    
    my $schema = $app->param('schema');

    my $results = [];
    #hash table with the search results.
    #ex: tmp_results{IP address}->{db table}->{MAC address} = timestamp
    my %tmp_results;
    my ($e, $it); # entry and interator
	
    my $conditions = {};
    $conditions->{'ipaddr'} = {'-like', $q };
    if ($limit) {
	$conditions->{lastseen} = { '>=' , $limit };
    }

    $it = $schema->resultset('Arp')->search($conditions);
    while ($e = $it->next) {
      #in order to sort the subresults
      $tmp_results{$e->ipaddr}->{$e->macaddr} = $e->lastseen;	
    }
 	
    # TODO
    #$it = Manoc::DB::Winhostname->search_like(ipaddr => $q);
    #while ($e = $it->next) {
    #	$tmp_results{$e->ipaddr}->{$e->name} = 1;
    #}
  
    foreach my $ip (keys %tmp_results) {
	my $items = [];
	my $key   = pack('C4', split(/\./, $ip));
	my $result_entry = {
	    key		=> $key,
	    ip		=> $ip,
	    items	=> $items
	    };
	my @temp;
	foreach my $mac (keys %{$tmp_results{$ip}}) {
	  push @temp, { mac      => $mac,
			lastseen => $tmp_results{$ip}{$mac} };
	}
	@$items = sort {$b->{'lastseen'} <=>  $a->{'lastseen'}} @temp;
	push @$results, $result_entry;
	@$results = sort { $a->{key} cmp $b->{key} } @$results;
    }
    return $results;
}

sub search_subnet {
    my ($app, $query_desc, $limit) = @_;
    my $schema = $app->param('schema');
    my $ip_from =  $query_desc->{'query'};

    my @r = $schema->resultset('IPRange')->search({'inet_aton(from_addr)'=> ip2int($ip_from) });
    my @results = map +{
        subnet_name=> $_->name,
    	from_addr  => $_->from_addr,
    	to_addr    => $_->to_addr,
        prefix     => $_->netmask ? Manoc::Utils::netmask2prefix($_->netmask)  : undef,
	}, @r;

    return \@results;

}


sub search_logon {
    my ($app, $query_desc, $limit) = @_;

    my $q = '%'.$query_desc->{'query'}.'%';
    my $schema = $app->param('schema');

    my $results = [];
    my %tmp_results;
    my ($e, $it);
    
    my $conditions = {};
    $conditions->{'user'} = {'-like', $q };
    if ($limit) {
	$conditions->{lastseen} = { '>=' , $limit };
    }

    
    $it = $schema->resultset('WinLogon')->search($conditions, 
						 { order_by => 'user' }
						 );
    while ($e = $it->next) {
	$tmp_results{$e->user}->{$e->ipaddr} = 1;
    }	    
    foreach my $user (keys %tmp_results) {
	my $items = [];
	my $result_entry = {
	    user  => $user,
	    items => $items,
	};
	foreach my $ip (keys %{$tmp_results{$user}}) {
	    push @$items, { host => $ip };
	}
	push @$results, $result_entry;
    }
    return $results;
}

sub search_inventory {
    my ($app, $query_desc) = @_;
    my $schema = $app->param('schema');

    my $q = '%'.$query_desc->{'query'}.'%';
    my $scope = $query_desc->{'scope'};


    my $results = [];
    my %tmp_results;
    my ($it, $e);

    if ($scope eq 'building' || $scope eq 'inventory') {
	$it = $schema->resultset('Building')->search(
	    [ 
	      { description => { -like => $q } }, { name => { -like => $q } } 
	    ],
	    { order_by => 'description'});
	while ($e = $it->next) {
	    push @$results, { 
		building	=> $e->id,
		build_name	=> $e->name,
		name	=> $e->description,
	    };
	}
    }

    if ($scope eq 'device' || $scope eq 'inventory') {
	$it = $schema->resultset('Device')->search( 
	    [ 
	      { id => { -like => $q } }, { name => { -like => $q } } 
	    ],
	    { order_by => 'name'});    
	while ($e = $it->next) {
	    push @$results,  { 
		name	=> $e->name,
		device	=> $e->id,
	    };	
	}
    }

    if ($scope eq 'inventory') {
	$it = $schema->resultset('WinHostname')->search_like(name => $q,
							     { 

								 order_by => 'name',
								 group_by => 'name',
							     });
    
	while ($e = $it->next) {
	    push @$results, { 
		name	=> $e->name,
		host	=> $e->ipaddr,
	    };	
	}
    }
	
    if ($scope eq 'inventory') {
	$it = $schema->resultset('IPRange')->search_like(name => $q,
							 { order_by => 'name'});    
	while ($e = $it->next) {
	    my $desc = $e->network ?
		$e->network . '/' . Manoc::Utils::netmask2prefix($e->netmask) :
		$e->from_addr . '-' . $e->to_addr;
	    
	    push @$results, { 
		iprange    => $e->name,
		name       => $e->name,
		desc       => $desc,
	    };	
	}
    }

  if ($scope eq 'inventory') {
 	$it = $schema->resultset('Vlan')->search_like(name => $q,
 							 { order_by => 'id'});    
 	while ($e = $it->next) {
 	    push @$results, { 
 		name => $e->name,
 		vlan   => $e->id,
 	    };
 	}
      }	

     if ($scope eq 'inventory') {
 	$it = $schema->resultset('VlanRange')->search_like(name => $q,
 							 { order_by => 'id'});    
 	while ($e = $it->next) {
 	    push @$results, { 
 		name => $e->name,
 		vlan_range   => $e->id,
 	    };
 	}
      }


    return $results;
}


sub search_notes {
    my ($app, $query_desc) = @_;

    my $q = $query_desc->{'query'};
    
    my $schema = $app->param('schema');
 
    my $results = [];
    my %tmp_results;
    my ($it, $e);

						      
    $it = $schema->resultset('IfNotes')->search_like(notes => "%$q%",
						{ order_by => 'notes'});
    while ($e = $it->next) {
	push @$results, { 
	    device	=> $e->device->id,
	    interface   => $e->interface,
	    notes	=> $e->notes,
	};
    }

   
    $it = $schema->resultset('IfStatus')->search_like(description => "%$q%",
						       { order_by => 'description'});
    while ($e = $it->next) {
	push @$results, { 
	    device	=> $e->device,
	    interface   => $e->interface,
	    notes	=> $e->description,
	};
    }

    $it = $schema->resultset('IpNotes')->search_like(notes => "$q",
						       { order_by => 'notes'});
    while ($e = $it->next) {
	push @$results, { 
	    ip	=> $e->ipaddr,
	    notes	=> $e->notes,
	};
    }

   return $results;
}

#----------------------------------------------------------------------#

sub run {
    my $app  = shift;
    my $query = $app->query();
    my $schema = $app->param('schema');
    my $q = $query->param('q') || '';
    my $default_query_limit = $app->config_param('cgi.default_limit');
    my ($limit, $query_limit);
    my $button =  $query->param('submit');
    my $advanced_search =  $query->param('advanced') || 0;
    my $type;

    # results array
    my $mac_rs       = [];
    my $ip_rs	     = [];
    my $logon_rs     = [];
    my $inventory_rs = [];
    my $notes_rs     = [];
    my $subnet_rs    = [];
    my $msg;
    my $query_desc;
    my $n_found_objs = 0;

    if ($q =~ /\S/) {
	
	#$q = lc($q);
	$q =~ s/^\s+//o;
	$q =~ s/\s+$//o;

	#fill the query data struct 
	$query_desc = {};                    
	add_default($app, $query_desc);
	add_opt($app->query(), $query_desc);
	parse_text($app, $q, $query_desc);

	my $scope = $query_desc->{'scope'};

        # redirect shortcuts
	# TODO: redirect only if exists id , else go on searching
	if($scope eq 'rack'){
	    my $rack = $schema->resultset('Rack')->search(name => $query_desc->{'query'})->single;
	    $rack and return $app->manoc_redirect('rack/view',   id => $rack->id);
	    return $app->show_message('Error', 'Rack not found');
	}
	$scope eq 'device' and
	    return $app->manoc_redirect('device/view', id => $query_desc->{'query'});

	if($scope eq 'subnet'){
	  my $prefix = $query_desc->{'prefix'};
	  $prefix and return $app->manoc_redirect
	      ('iprange/view', from => $query_desc->{'query'}, prefix => $prefix);
	  return $app->manoc_redirect
	      ('iprange/view', name => $query_desc->{'query'});
	}
	

	#set the limit to the results	
	if(defined($query_desc->{'limit'}) && $query_desc->{'limit'} ne '0'){
	    $limit = time() - str2seconds($query_desc->{'limit'});
	}

	# run the appropriate queries
	$scope eq 'macaddr'   and $mac_rs       = search_macaddr($app, $query_desc, $limit);
	$scope eq 'ipaddr'    and $ip_rs        = search_ipaddr($app, $query_desc, $limit);
	$scope eq 'logon'     and $logon_rs     = search_logon($app, $query_desc, $limit);       
	$scope eq 'inventory' and $inventory_rs = search_inventory($app, $query_desc);
	$scope eq 'building'  and $inventory_rs = search_inventory($app, $query_desc);
	$scope eq 'rack'      and $inventory_rs = search_inventory($app, $query_desc);
	$scope eq 'device'    and $inventory_rs = search_inventory($app, $query_desc);	   
	$scope eq 'notes'     and $notes_rs     = search_notes($app, $query_desc);
	$scope eq 'ipaddr' && $query_desc->{'match'} eq 'exact'	
	                      and $subnet_rs  = search_subnet($app, $query_desc, $limit);


	$n_found_objs = scalar(@$mac_rs) + scalar(@$ip_rs) +
	    scalar(@$logon_rs) +  scalar(@$inventory_rs) + scalar(@$notes_rs) + scalar(@$subnet_rs);
	$msg = "Found $n_found_objs objects.";
    	
    }

    my %search_options = (
			  'ipaddr'      => 'IP',
			  'macaddr'	=> 'MAC',
			  'inventory'	=> 'Inventory',
			  'logon'	=> 'Logon',
			  'notes'       => 'Notes'
			  );
 
    my $radiobox = CGI::radio_group(-name   =>'scope',
				    -values => [ sort keys %search_options ],
				    -default => $query->param('scope') || 'ipaddr',
				    -labels => \%search_options
				    );

    my $template = $app->prepare_tmpl(
	tmpl  => 'search.tmpl',
	title => $n_found_objs ? 'Search' : 'Manoc',
	);

    $query->param('debug') and $msg .= Dumper($query_desc);

    # build links
    my @query_pair = $q ? ('q' => $q) : ();
    my $adv_search_link    = $app->manoc_url('search', 
					     'advanced' => 1, 
					     @query_pair);
    my $simple_search_link = $app->manoc_url('search', @query_pair);

    $template->param(
		     ip_results		=> $ip_rs,
		     mac_results	=> $mac_rs,
		     logon_results      => $logon_rs,
		     inventory_results	=> $inventory_rs,
		     notes_results	=> $notes_rs,
		     subnet_results     => $subnet_rs,
		     targets_radiobox	=> $radiobox,
		     'q'		=> $query->param('q')     || '',
		     limit		=> $query->param('limit') || '',
		     default_limit	=> $default_query_limit,
		     search_message	=> $msg,
 	             advanced_search	=> $advanced_search,
	             adv_search_link    => $adv_search_link,
	             simple_search_link => $simple_search_link,
		     big_title		=> !$q,	
		     );

    my $output_ref = \$template->output();
    return $output_ref;
} 

#----------------------------------------------------------------------#

sub make_minisearch_widget {
    my $app = shift;
    my $args = shift;

    my $scope = $args->{scope};
    
    my $widget = $app->prepare_tmpl(
	tmpl   => '_minisearch.tmpl',
	widget => 1
     );

    $widget->param(search_url => $app->manoc_url('search'));
    $scope and $widget->param(scope => $scope);
    
    return $widget->output;
}

1;
