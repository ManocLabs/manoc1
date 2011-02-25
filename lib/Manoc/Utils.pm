package Manoc::Utils;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(
		    clean_string print_timestamp
		    ip2int int2ip str2seconds
		    netmask_prefix2range netmask2prefix
                    prefix2wildcard
		);

use POSIX qw(strftime);

use FindBin;
use File::Spec;

use Log::Log4perl;
use Log::Log4perl::Layout;
use Log::Log4perl::Level;

use Manoc::DB;
use Carp;

########################################################################

# get manoc home and cache it
my $Manoc_Home;

sub set_manoc_home {
    my $home = shift || croak "Missing path";

    # manoc home cannot be changed!
    if (defined $Manoc_Home) {
	carp "Manoc home already set";
	return;
    }

    $Manoc_Home = $home;
}

sub get_manoc_home {
    return $Manoc_Home if defined $Manoc_Home;

    $Manoc_Home = $ENV{MANOC_HOME};
    $Manoc_Home ||= File::Spec->catfile(
					$FindBin::Bin,
					File::Spec->updir()
					);
    return $Manoc_Home;
}

########################################################################

# create dbi connect parameter (dsn, user, auth) 
# from Config::Simple istance and connect

sub get_dbi_params {
    my $conf = shift @_ || carp "Missing configuration";
    my ($dsn, $user, $auth);

    my $db = $conf->param('db.source') || return undef;
    if ($db eq 'sqlite') {
	$dsn  = 'dbi:SQLite:dbname='. 
	    File::Spec->catfile(get_manoc_home(), 'db', 'manoc.db');
	$user = '';
	$auth = '';
    } else {
	$dsn  = $db;
	$user = $conf->param('db.user');
	$auth = $conf->param('db.auth');
    }

    return ($dsn, $user, $auth, { AutoCommit => 1});
}

# for CDBI compability
sub init_db {
    my $conf = shift @_ || carp "Missing configuration";
    return Manoc::DB::DBI->connection(get_dbi_params($conf));
}


########################################################################


# init logger
#   Note for multiprocess logging: Log::Dispatch::FileRotate uses flock!

sub init_log {
    my %param = @_;

    my $conf     = $param{conf} || carp "Missing configuration";
    my $log_name = $param{name} || 'manoc.log';
    my $debug	 = $param{debug};

    my $logger = Log::Log4perl->get_logger();

    my $appender;

    if ($debug) {
	# write to screen

	$appender =
	    Log::Log4perl::Appender->new(
					 "Log::Log4perl::Appender::Screen",
					 name => 'screenlog'
					 );
    } else {
	# setup file-rotate appender

	my ($log_dir, $log_file);
	
	$log_dir   = $conf->param('log.dir');
	$log_dir ||= File::Spec->catfile(get_manoc_home(), 'log');
	$log_file  = File::Spec->catfile($log_dir, $log_name);

	my $rotate_max = $conf->param('log.rotate-max') || '7';
        $appender = 
	    Log::Log4perl::Appender->new(
					 "Log::Dispatch::FileRotate",
					 name        => "filelog",
					 filename    => $log_file,
					 mode        => 'append' ,
					 TZ          => 'CET',
					 DatePattern => 'yyyy-MM-dd',
					 max         => $rotate_max
					 );
    }
    
    # Define a layout
    my $layout = Log::Log4perl::Layout::PatternLayout->new("[%d] %p %m%n"); 
    $appender->layout($layout);

    $logger->add_appender($appender);

    my $conf_level   = $conf->param('log.level') || 'info';
    $debug and $conf_level = 'all';

    my %name2level = (
		      OFF       => $OFF,
		      DEBUG 	=> $DEBUG,
		      INFO	=> $INFO,
		      WARN	=> $WARN, 	 
		      ERROR 	=> $ERROR,
		      FATAL	=> $FATAL,
		      ALL       => $ALL		      
		      );
    my $log_level = $name2level{uc($conf_level)};
    defined($log_level) || 
	Carp::croak("bad log level '$conf_level' while creating logger");
    $logger->level($log_level);

    return $logger;
}

########################################################################
#                                                                      #
#                   S t r i n g   F u n c t i o n s                    #
#                                                                      #
########################################################################


sub clean_string {
    my $s     = shift;
    return '' unless defined $s;
    $s =~ s/^\s+//o;
    $s =~ s/\s+$//o;
    return lc($s);
}

########################################################################
#                                                                      #
#           D a t e   &   t i m e   F u n c t i o n s                  #
#                                                                      #
########################################################################


sub print_timestamp {
    my $timestamp = shift @_;
    defined ($timestamp) || croak "Missing timestamp";
    my @timestamp = localtime($timestamp);
    return strftime("%d/%m/%Y %H:%M:%S", @timestamp);
}


sub str2seconds {
    my ($str) = @_;

    return unless defined $str;

    return $str if $str =~ m/^[-+]?\d+$/;

    my %map = (
        's'       => 1,
        'm'       => 60,
        'h'       => 3600,
        'd'       => 86400,
        'w'       => 604800,
        'M'       => 2592000,
        'y'       => 31536000
    );

    my ($num, $m) = $str =~ m/^([+-]?\d+)([smhdwMy])$/;
    
    (defined($num) && defined($m)) or
        carp "couldn't parse '$str'. Possible invalid syntax";
    
    return $num * $map{$m};
}

########################################################################
#                                                                      #
#                   I P A d d r e s s   F u n c t i o n s              #
#                                                                      #
########################################################################

my @INET_PREFIXES;
my %INET_NETMASK;

sub ip2int { return unpack('N', pack('C4', split(/\./, $_[0]))) }

sub int2ip { return join ".",unpack("CCCC",pack("N",$_[0])); }

sub netmask_prefix2range {
    my $network = shift || croak "Missing network parameter";
    my $prefix  = shift;
    defined($prefix) || croak "Missing prefix parameter";

    ($prefix >= 0 || $prefix <= 32) or
	croak "Invalid subnet prefix";


    my $network_i   = Manoc::Utils::ip2int($network);
    my $netmask_i   = $prefix ? ~((1 << (32-$prefix)) - 1) : 0;
    my $from_addr_i = $network_i & $netmask_i;
    my $to_addr_i   = $from_addr_i + ~$netmask_i;

    return ($from_addr_i, $to_addr_i, $network_i, $netmask_i);
}
 
# sub host2network{
#     my $host = shift || croak "Missing network parameter";
#     my $prefix  = shift;
#     defined($prefix) || croak "Missing prefix parameter";
#     ($prefix >= 0 || $prefix <= 32) or
# 	croak "Invalid subnet prefix";
    
#     my $network_i   = Manoc::Utils::ip2int($host);
#     my $netmask_i   = $prefix ? ~((1 << (32-$prefix)) - 1) : 0;
#     my $from_addr_i = $network_i & $netmask_i; 
#     return int2ip($from_addr_i);
# }

# sub range2netmask{
#     my $begin = shift || croak "Missing Range start";
#     my $end   = shift || croak "Missing Range end";
#     my $begin_i = ip2int($begin);
#     my $end_i   = ip2int($end);
    
#     $begin_i >= $end_i and croak  "Invalid range";

#     my $delta   = $end_i - $begin_i;
  
#     return (int2ip(~0 - $delta));
# }

sub prefix2netmask_i {
    @_ == 1 || croak "Missing prefix parameter";
    my $prefix = shift;
    ($prefix >= 0 || $prefix <= 32) or
	 croak "Invalid subnet prefix";

    return $prefix ? ~((1 << (32-$prefix)) - 1) : 0;
}
  
sub prefix2netmask {
    @_ == 1 || croak "Missing prefix parameter";
    my $prefix = shift;
    ($prefix >= 0 || $prefix <= 32) or
	 croak "Invalid subnet prefix";

    return $INET_PREFIXES[$prefix];
}

sub prefix2wildcard {
    @_ == 1 || croak "Missing prefix parameter";
    my $prefix = shift;
    ($prefix >= 0 || $prefix <= 32) or
	 croak "Invalid subnet prefix";

     return int2ip( $prefix ? ((1 << (32-$prefix)) - 1) : 0xFFFFFFFF  );
}

sub netmask2prefix {
    my $netmask = shift || croak "Missing netmask parameter";
    
    return $INET_NETMASK{$netmask};
}


BEGIN {
    my $netmask_i;

    $INET_PREFIXES[0] = '0.0.0.0';
    $INET_NETMASK{'0.0.0.0'} = 0;

    foreach my $i (1 .. 32) {
	$netmask_i =  ~((1 << (32-$i)) - 1);

	$INET_PREFIXES[$i] = int2ip($netmask_i);
	$INET_NETMASK{int2ip($netmask_i)} = $i;
    }
}

########################################################################
#                                                                      #
#                     S e t    F u n c t i o n s                       #
#                                                                      #
########################################################################


sub decode_bitset {
    my $bits = shift;
    my $names= shift;
    
    my @result;

    my @bitlist = reverse split( //, $bits);
    my ($n, $b);

    while(@$names && @bitlist) {
	$n = shift @$names;
	$b = shift @bitlist;

	$b or next;
	push @result, $n;
    }

    return @result;
}

########################################################################

1;
