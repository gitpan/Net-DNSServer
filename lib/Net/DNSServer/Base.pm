package Net::DNSServer::Base;

# $Id: Base.pm,v 1.7 2001/05/24 15:33:15 rob Exp $
# This is meant to be the base class for all Net::DNSServer resolving module handlers

use strict;
use Carp qw(croak);

# Created before calling Net::DNSServer->run()
sub new {
  my $class = shift || __PACKAGE__;
  my $self = shift || {};
  return bless $self, $class;
}

# Called once at configuration load time by Net::DNSServer.
# Takes the Net::DNSServer object as an argument
sub init {
  my $self = shift;
  my $net_server = shift;
  unless ($net_server && (ref $net_server) && ($net_server->isa("Net::Server"))) {
    croak 'Usage> '.(__PACKAGE__).'->init($Net_Server_obj)';
  }
  $self -> {net_server} = $net_server,
  return 1;
}

# Called immediately after incoming request
# Takes the Net::DNS::Packet question as an argument
sub pre {
  my $self = shift;
  my $net_dns_packet = shift || croak 'Usage> $obj->resolve($Net_DNS_obj)';
  $self -> {question} = $net_dns_packet;
  return 1;
}

# Called after all pre methods have finished
# Returns a Net::DNS::Packet object as the answer
#   or undef to pass to the next module to resolve
sub resolve {
  die "virtual function not implemented";
}

# Called after response is sent to client
sub post {
  return 1;
}

# Called once prior to server shutdown
sub cleanup {
  return 1;
}

1;
