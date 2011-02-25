package Bundle::Manoc;
# Copyright 2011 by the Manoc Team
#
# This library is free software. You can redistribute it and/or modify
# it under the same terms as Perl itself.

$VERSION = '0.3';

1;

__END__

=head1 NAME

Bundle::Manoc - A bundle to install Manoc prerequisites.

=head1 SYNOPSIS

C<perl -MCPAN -e 'install Bundle::Manoc'>

=head1 CONTENTS

CGI::Application

Config::Simple

CGI::Application::Plugin::Config::Simple

HTML::Template::Expr

CGI::Session

CGI::Application::Plugin::Session

DBIx::Class

Digest::MD5

Class::Accessor

Class::Data::Inheritable

Log::Log4perl

Log::Log4perl::Layout

Log::Log4perl::Level

Log::Dispatch::FileRotate

Net::Pcap

NetPacket::Ethernet

NetPacket::ARP

Config::Simple

SNMP::Info

Net::Telnet

Net::Telnet::Cisco

Regexp::Common

Regexp::Common::Email::Address

Text::Diff

URI::Escape

local::lib

=head1 DESCRIPTION

This bundle includes all that's needed to run Manoc.
