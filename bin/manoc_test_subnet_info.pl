#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Long;

use File::Spec;
use Config::Simple;
use Manoc::DB;
use Manoc::Utils;

use Socket;

use Data::Dumper;


my ($Conf, $Schema);


my ($help, $man, $conf_file, $verbose);
my ($opt_numeric, $opt_days, $opt_sort_address, $opt_show_rack,);

GetOptions(
           'conf=s'		=> \$conf_file,
           'help|?'		=> \$help,
           'man'		=> \$man,
           'days=i'	    	=> \$opt_days,
           'numeric'	   	=> \$opt_numeric,
           'sort-address' 	=> \$opt_sort_address,
           'show-rack'		=> \$opt_show_rack,
           'verbose'		=> \$verbose,
    ) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if (!defined $conf_file) {
    $conf_file = File::Spec->catfile(Manoc::Utils::get_manoc_home(),
				     'etc',
				     'manoc.conf');
    -f $conf_file or die 'Cannot find manoc.conf';
}

my $pattern = shift @ARGV;
$pattern or die "Missing subnet";

$pattern =~ m!^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$! or die "Bad subnet";
my $network = $1;
my $prefix = $2;

($prefix >= 0 || $prefix <= 32) or
    return (0, "Invalid subnet prefix");

my $network_i   = Manoc::Utils::ip2int($network);
my $netmask_i   = $prefix ? ~((1 << (32-$prefix)) - 1) : 0;
my $from_addr_i = $network_i & $netmask_i;
my $to_addr_i   = $network_i + ~$netmask_i;



$Conf = new Config::Simple($conf_file);
$Schema = Manoc::DB->connect(Manoc::Utils::get_dbi_params($Conf));

my $search_filter =  { 'inet_aton(ipaddr)'  => { "-between" => [$from_addr_i,  $to_addr_i]  }};
if ($opt_days) {
    my $min_time = time() - $opt_days * 86400;
    $search_filter->{lastseen} = { '>=' => $min_time };
}

my @seen_addresses = $Schema->resultset('Arp')->search(
    $search_filter,
    { 
      select => [ 'macaddr', { 'max' => 'lastseen' }],
      as => ['macaddr', 'lastseen' ],
      group_by => 'macaddr'
    })->all();

$verbose and print "Found ", scalar(@seen_addresses), " addresses.\n";

my %ipaddr_table;
my %macaddr_table;

foreach my $a (@seen_addresses) {
    my $macaddr =  $a->get_column('macaddr');

    my $r = $Schema->resultset('Arp')->search(
	{ macaddr => $macaddr },
	{ 
	    select => [ 'ipaddr', 'lastseen' ],
	    order_by => "lastseen DESC"  
	})->first();

    if ( $a->get_column('lastseen') == $r->get_column('lastseen') ) {
	my $lastseen = $r->get_column('lastseen');
	my $ipaddr   = $r->get_column('ipaddr');
	    
	if ($macaddr_table{$ipaddr}) {
	    $verbose and print "duplicate macaddr $macaddr for ip $ipaddr\n";
	    my ($old_mac, $old_lastseen) = @{$macaddr_table{$ipaddr}};
	    if ($lastseen > $old_lastseen) {
		$macaddr_table{$ipaddr} = [$macaddr, $lastseen];
		$ipaddr_table{$macaddr} = $ipaddr;
	    }
	} else {
	    # never seen ipaddr
	    $macaddr_table{$ipaddr} = [$macaddr, $lastseen];
	    $ipaddr_table{$macaddr} = $ipaddr; 
	}

    } else {
	$verbose and printf "Skipping %s (updated)\n", $a->get_column('macaddr');
    }    
}

my @addresses = map { $_->[0] } values(%macaddr_table);
$verbose and print "Searching ports for ", scalar(@addresses), " addresses.\n";

my @table;
foreach my $a (@addresses) {
    my $r = $Schema->resultset('Mat')->search(
	{ macaddr => $a },
	{ order_by => "lastseen DESC"  })->first();    

    if (!$r) {
	$verbose and print "No MAT info for $a\n";
	next;
    }

    my ($controller, $port) = split /[.\/]/, $r->interface;
    my $lc_if = lc($r->interface);
    
    my $entry = {
	device   => $r->device,
	device_i => Manoc::Utils::ip2int($r->device),
	iface    => $r->interface,
	controller => $controller,
	port     => $port,
	macaddr  => $r->macaddr,
	ipaddr   => $ipaddr_table{$r->macaddr},
	ipaddr_i => Manoc::Utils::ip2int($ipaddr_table{$r->macaddr}),
	lastseen => $r->lastseen
    };

    $entry->{name} = $entry->{ipaddr};
    unless ($opt_numeric) {
	my $hostname = gethostbyaddr(inet_aton($entry->{ipaddr}), AF_INET);
	$hostname and $entry->{name} = $hostname;
    }

    push @table, $entry;

}

if ($opt_sort_address) {

    @table = sort { 
	$a->{ipaddr_i} <=> $b->{ipaddr_i}
    } @table;
} else { 
    # sort by device
    @table = sort { 
	$a->{device_i} <=> $b->{device_i} || 
	    $a->{controller} cmp $b->{controller} || 
	    $a->{port} <=> $b->{port}
    } @table;
}

if ($opt_numeric) {
    foreach my $row (@table) {
	printf "%15s %28s %20s %s\n", ($row->{device}, $row->{iface},
				       $row->{macaddr}, $row->{ipaddr});
    }
} else {
    foreach my $row (@table) {
	printf "%15s %28s %15s %s\n", ($row->{device}, $row->{iface},
				       $row->{ipaddr}, $row->{name});
    }
}

1;

