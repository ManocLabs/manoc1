#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use local::lib "$FindBin::Bin/../support";

use Getopt::Long;
use File::Spec;
use Config::Simple;
use Manoc::DB;
use Manoc::Utils;

my ($verbose, $conf_file);
my ($Conf, $Schema);

GetOptions ( 
    'conf=s'  => \$conf_file,
    'verbose' => \$verbose 
    );

if (!defined $conf_file) {
    $conf_file = File::Spec->catfile(Manoc::Utils::get_manoc_home(),
				     'etc',
				     'manoc.conf');
    -f $conf_file or die 'Cannot find manoc.conf';
}

$Conf = new Config::Simple($conf_file);
$Schema = Manoc::DB->connect(Manoc::Utils::get_dbi_params($Conf));


my $device_port = {};

my ($host, $port, $line);
while ($line = <>) {
    $line =~ /^\s*#/o and next;
    $line =~ /^\s*(\d+\.\d+\.\d+\.\d+)\s+([\w\/]+)/o or next;
    $host = $1;
    $port = $2;
    
    $device_port->{$host} ||= {};
    $device_port->{$host}->{$port} = 1;
}

if ($verbose) {
    print  "-" x 72, "\nPort list\n", "-" x 72, "\n\n";    
    foreach my $host (keys %$device_port) { 
	print "$host\n";
	print "\t$_\n" foreach (keys %{$device_port->{$host}});
    }
}


$| = 1;
my @shutted_ports;

foreach my $host (keys %$device_port) {
    $verbose and print "$host\n";

    foreach my $port (keys %{$device_port->{$host}}) {

      my $filter = {
		    device => $host,
		    interface => $port,
		   };

      my $r = $Schema->resultset('IfStatus')->find($filter);
      
      $verbose and print "\t$port ", $r->up, "/", $r->up_admin, "\n";

      $r->up_admin ne 'up' and push @shutted_ports, [$host, $port];
    }
}

if ( @shutted_ports ) {
    print scalar(@shutted_ports), " errors\n\n";
    foreach (@shutted_ports) {
	printf "%-15s %s\n", $_->[0], $_->[1];
    }
} else {
    print "OK\n";
}

