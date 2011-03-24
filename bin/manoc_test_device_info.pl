#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Long;
use Pod::Usage;

use Data::Dumper;
use IO::Socket; # per gethostbyname
use POSIX qw(strftime);
use File::Spec;
use Config::Simple;

use Manoc::DB;
use Manoc::Utils;



my %COLUMNS = (
    'd'            => ['Description', '%s',   'description' ],
    'p'            => ['Interface',   '%28s', 'iface'       ],
    'm'            => ['Mac Address', '%17s', 'macaddr'     ],
    'i'            => ['Ip Address',  '%15s', 'ipaddr'      ],
    'h'            => ['Hostname',    '%32s', 'hostname'    ],
    'l'		   => ['Lastseen',    '%10s', 'lastseen'    ],
    's'		   => ['Status',      '%6s',  'status'      ],
    'v'		   => ['Vlan',        '%4s',  'vlan'        ],
    );
my $DEFAULT_DAYS = 30;


my $Verbose;
my ($Conf, $Schema);
my ($Out_format, $Out_columns, $Out_headers);
my $Need_hostname = 0;


my ($help, $man, $conf_file);
my $opt_days   = $DEFAULT_DAYS;
my $opt_format = 'psihl';

GetOptions(
    'conf=s'		=> \$conf_file,
    'help|?'		=> \$help,
    'man'		=> \$man,
    'days=i'    	=> \$opt_days,
    'format=s'	   	=> \$opt_format,
    'verbose'		=> \$Verbose,
    ) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;

if (!defined $conf_file) {
    $conf_file = File::Spec->catfile(Manoc::Utils::get_manoc_home(),
				     'etc',
				     'manoc.conf');
    -f $conf_file or die 'Cannot find manoc.conf';
}

@ARGV == 1 or pod2usage(2);
my $device_addr = shift @ARGV;


# parse output format
$Out_format  = [];
$Out_columns = [];
foreach (split //, $opt_format) {
    my $e = $COLUMNS{$_};

    $e or pod2usage(
	-exitval => 2,
	-msg => "unknown column descriptor '$_' in format"
	);

    push @$Out_headers, $e->[0];
    push @$Out_format,  $e->[1];
    push @$Out_columns, $e->[2];
}
$opt_format =~ /h/ and $Need_hostname = 1;

########################################################################


$Conf = new Config::Simple($conf_file);
$Schema = Manoc::DB->connect(Manoc::Utils::get_dbi_params($Conf));

if (! defined($opt_days)) {
    $opt_days = $DEFAULT_DAYS;
    $Verbose and print "Using default days limit: $opt_days\n";
}
my $start_time = time() - $opt_days * 86400;

   
my $device = $Schema->resultset('Device')->find({id => $device_addr});
$device || die "Device $device_addr not found";


# get all mac address seen on the device and search for
# their last ip address

my @seen_addresses = $Schema->resultset('Mat')->search(
    {  
	device    => $device_addr,
	lastseen  => { '>=' => $start_time }    
    },
    { 
	select    => [ 'macaddr' ],
	distinct  => 1,
    })->all();
$Verbose and print "Found ", scalar(@seen_addresses), " addresses.\n";
if (@seen_addresses == 0) {
    print "No mac addresses associated with $device_addr";
    exit 0;
}

$Verbose and print "Searching arp info\n";
my %ipaddr_table;
foreach my $a (@seen_addresses) {
    my $macaddr =  $a->get_column('macaddr');
    my $r = $Schema->resultset('Arp')->search(
	{ 
	    macaddr => $macaddr,
	    lastseen  => { '>=' => $start_time }     
	},
	{ 
	    select => [ 'ipaddr', 'lastseen' ],
	    order_by => "lastseen DESC"  
	})->single();

    if (!defined($r)) {
	$Verbose and print "no arp info for $macaddr\n";
	next;
    }
 
    my $ipaddr   = $r->get_column('ipaddr');
    my $lastseen = $r->get_column('lastseen');
    $ipaddr_table{$macaddr} = [ $ipaddr, $lastseen ];
}

my @table;
my %table_iface_idx;

# init output table from ifstatus
my $ifstatus_rs = $device->ifstatus;
while (my $r = $ifstatus_rs->next()) {
    my $iface = $r->interface;
    my ($controller, $port) = split /[.\/]/, $iface, 2;

      my $entry = {
	  iface      => $iface,
	  controller => $controller,
	  port       => $port,
	  macaddr    => 'none',
	  ipaddr     => 'none',
	  hostname   => 'none',
	  lastseen   => 'never',	      
	  status     => $r->up,
	  vlan       => $r->vlan || 'none',
      };
    push @table, $entry;
    $table_iface_idx{lc($iface)} = $entry; 
}

# fetch mat_entries and populate result table joining %ipaddr_table
my $mat_rs = $Schema->resultset('Mat')->search(
    {
	device   => $device_addr,
	lastseen => { '>=' => $start_time }
    },
    {
	select	 => [ 'interface', 'macaddr', { max =>  'lastseen' } ],
	as       => [ 'interface', 'macaddr', 'lastseen'  ],
	group_by => [ 'interface', 'macaddr' ],
    });

while (my $r = $mat_rs->next()) {
    my $iface = $r->interface;
    my $entry = $table_iface_idx{lc($iface)};

    if (! $entry ) {
	$Verbose and print "Skipping $iface with no entries in IfStatus\n";
	next;
    }

    my $macaddr = $r->macaddr;
    $entry->{macaddr} = $macaddr;

    my @timestamp = localtime($r->lastseen);
    $entry->{lastseen}  = strftime("%Y-%m-%d", @timestamp);

    my $ipaddr;
    $ipaddr_table{$macaddr} and
	$ipaddr = $ipaddr_table{$macaddr}->[0];
    if ($ipaddr) {
	$entry->{ipaddr} = $ipaddr;

	if ($Need_hostname) {
	    my $hostname = gethostbyaddr(inet_aton($ipaddr), AF_INET);
	    $hostname ||= $ipaddr;
	    $entry->{hostname} = $hostname;
	}
    }
}



########################################################################

# sort by interface
@table = sort { 
    $a->{controller} cmp $b->{controller} || 
	$a->{port} <=> $b->{port}
} @table;


# print
my $format = join(' ', @$Out_format);

my $header = sprintf $format, @$Out_headers;
print "$header\n", '-' x length($header), "\n";

foreach my $row (@table) {
    printf "$format\n", map { $row->{$_} } @$Out_columns;
}
1;

########################################################################

=head1 NAME

manoc_device_info - Per device host info

=head1 SYNOPSIS

manoc_test_device_info [options] <device>

=head1 OPTIONS

=over 8

=item B<--conf=PATH>
                       
=item B<--debug>

=item B<--days=d>

=item B<--format>

=item B<--help|?>

=item B<--man>

