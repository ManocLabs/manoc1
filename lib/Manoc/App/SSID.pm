package Manoc::App::SSID;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;
use Carp;
use base 'Manoc::App::Delegate';
use Manoc::DB;

sub list : Resource(default error) {

    my ($self, $app) = @_;

    my $schema = $app->param('schema');

    my %tmpl_param;

    my @results = $schema->resultset('SSIDList')->search(undef,
				 {
				     select => [
						 'ssid',
						 { count => 'device' },
						 ],
				     as => ['ssid', 'ndev'],
				     group_by => ['ssid'],
				     order_by => 'ssid',
				 });
    my @ssids = map {
                    ssid       => $_->ssid,
                    ndev      => $_->get_column('ndev'),
                 }, @results;

    my $template = $app->prepare_tmpl(	
					tmpl  => 'ssid/list.tmpl',
					title => 'SSID list'
 				     ); 
    $template->param(ssids => \@ssids);
    return $template->output();
}

sub info : Resource {
    my ($self, $app) = @_;

    my $query  = $app->query();
    my $ssid   = $query->param('ssid');

    my $schema = $app->param('schema');
    
    my @devices = map {
	device		=> $_->device,
	interface	=> $_->interface,
	broadcast	=> $_->broadcast,
	channel		=> $_->channel,
    }, $schema->resultset('SSIDList')->search({ ssid => $ssid });
    
    my $message = '';
    @devices or $message = 'No devices is using this SSID';

    my @clients = map +{
	device		=> $_->device,
	macaddr		=> $_->macaddr,
	ipaddr		=> $_->ipaddr,
	vlan		=> $_->vlan,
	quality		=> $_->quality . '/100',
	state		=> $_->state,
	detail_link	=> $app->manoc_url("dot11client" . 
					    "?device=" . $_->device .
					    "&macaddr=" . $_->macaddr)
    }, $schema->resultset('Dot11Client')->search({ ssid => $ssid });

    my $template = $app->prepare_tmpl(
				       tmpl  => 'ssid/info.tmpl',
				       title => "SSID $ssid"
 				       );    
    $template->param(
		     devices => \@devices,
		     clients => \@clients,
		     message => $message
		     );    
    return $template->output();
}


1;
