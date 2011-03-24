#!/usr/bin/perl -w

use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use SNMPLib;
use Manoc::DB;
use Manoc::Utils;
use Manoc::Netwalker;
use Config::Simple;
use Getopt::Long;
use Pod::Usage;
use Carp;
use Data::Dumper;


#use IO::Socket;
#use POSIX ":sys_wait_h";
#use Fcntl ':flock'; # import LOCK_* constants




sub main {
    my ($conf_file, $help, $man);
    my ($device, $force_ifstatus, $serial, $debug);

    GetOptions(
	       'device=s'		=> \$device,
	       'debug'			=> \$debug,
	       'update-ifstatus'	=> \$force_ifstatus,
	       'conf=s'			=> \$conf_file,
	       'force-serial'		=> \$serial,
	       'help|?'			=> \$help,
	       'man'			=> \$man,	       
		) or pod2usage(2);

    pod2usage(1) if $help;
    pod2usage(-exitstatus => 0, -verbose => 2) if $man;

    # search and open config file
    if (!defined $conf_file) {
	$conf_file = "/etc/manoc.conf";
	-f $conf_file or
	  $conf_file = File::Spec->catfile(Manoc::Utils::get_manoc_home(),
					   'etc',
					   'manoc.conf');
	-f $conf_file or die 'Cannot find manoc.conf';
    }
    $debug and print  "Reading conf from $conf_file\n";

    my $conf = new Config::Simple($conf_file);

    # start logger and db
    my $logger = Manoc::Utils::init_log(
				     conf	=> $conf, 
				     name	=> 'my_netwalker.log',	     
				     debug	=> $debug
				     );
    $logger || die "Cannot init logger";
    my $schema = Manoc::DB->connect(Manoc::Utils::get_dbi_params($conf)) ||
	$logger->logconfess("cannot connect to DB");   

    # set global conf
    my $comm		   = $conf->param('password.snmp') || 'public';
    my $SNMP_Version       = $conf->param('netwalker.snmp_version') || '2';
    my $iface_filter	   = $conf->param('netwalker.iface_filter') ? 1 : 0;
    my $ignore_Portchannel = $conf->param('netwalker.ignore_portchannel') || 1;
    my $vlan		   = $conf->param('netwalker.vlan') || 1;
    my $timestamp	   = time();
    my $N_Procs		   = $conf->param('netwalker.n_procs') || 0;
    my ($VTPServers, $MP_Lock_W, $MP_Lock_R);
    

    my $vtp_server_conf = $conf->param('netwalker.vtp_servers');
    if ($vtp_server_conf) {
	my @address_list = split /\s+/, $vtp_server_conf;
	$VTPServers = { map { $_ => 1 } @address_list };
    } else {
	$logger->info("no VTP servers defined");
    }

    my $walker = Manoc::Netwalker->new({
	                           logger => $logger,
				   comm   => $comm,
				   SNMP_Version => $SNMP_Version,
				   iface_filter => $iface_filter,
				   ignore_Portchannel =>  $ignore_Portchannel,
				   vlan => $vlan,
				   timestamp => $timestamp,
				   N_Procs  => $N_Procs,
				   VTP_servers =>  $VTPServers,
				   debug  => $debug,
				   conf   => $conf,
				   schema => $schema, 
			       });
    
    my $update_If_Status;
    if ($force_ifstatus) {
	$walker->update_If_Status(1);
    } else {
	$walker->set_update_if_status($conf);
    }
    $logger->info('update ifstatus is ', $update_If_Status ? 'ON' : 'OFF');



    # only one device    
    if ($device) {
	$walker->visit_device($device);
	exit 0;
    } 

    # start visit
    if ($N_Procs < 2 || $serial) {

	# serial visit
	$logger->info("Started serial netwalker");
	$walker->visit_all($comm);
    } else {
	# mp visit
	$logger->info("Started mp netwalker");
	
	# open lock files
	my $lock_dir = $conf->param('netwalker.lock_dir');
	$lock_dir ||= File::Spec->catfile(Manoc::Utils::get_manoc_home(), 'my_run');
	
	my $lock1 = File::Spec->catfile($lock_dir, 'my_netwalker.1.lock');
	open ($MP_Lock_W, ">$lock1") or
	    $logger->logdie("cannot open lock file $lock1 ($!)");
	$walker->MP_Lock_W($MP_Lock_W);

	my $lock2 = File::Spec->catfile($lock_dir, 'my_netwalker.2.lock');
	open ($MP_Lock_R, ">$lock2") or
	    $logger->logdie("cannot open lock file $lock2 ($!)");
	$walker->MP_Lock_R($MP_Lock_R);

	$walker->visit_all_mp($comm);
    }
    $logger->info("Done");
    
    # update netwalker if_update timestamp in System table
    $update_If_Status and $walker->update_If_Status();
	
    exit 0;
}
main;
