package Net::DNSServer::Proxy;

# $Id: Proxy.pm,v 1.7 2001/05/24 04:46:01 rob Exp $
# This module simply forwards a request to another name server to do the work.

use strict;
use Exporter;
use vars qw(@ISA);
use Net::DNSServer::Base;
use Net::DNS;
use Net::DNS::Packet;
use Carp qw(croak);
use IO::Socket;

@ISA = qw(Net::DNSServer::Base);

# Created before calling Net::DNSServer->run()
sub new {
  my $class = shift || __PACKAGE__;
  my $self = shift || {};
  if (! $self -> {real_dns_server} ) {
    croak 'Usage> new({real_dns_server => "12.34.56.78"})';
  }
  # Initial "connect" to a remote resolver
  my $that_server = new IO::Socket::INET
    (PeerAddr     => $self->{real_dns_server},
     PeerPort     => "domain",
     Proto        => "udp");
  unless ( $that_server ) {
    die "Remote dns server [$self->{real_dns_server}] is down.\n";
  }
  $self -> {that_server} = $that_server;
  return bless $self, $class;
}

# Called after all pre methods have finished
# Returns a Net::DNS::Packet object as the answer
#   or undef to pass to the next module to resolve
sub resolve {
  my $self = shift;
  my $dns_packet = $self -> {question};
  my $response_data;
  if ($self -> {that_server} -> send($dns_packet->data) &&
      $self -> {that_server} -> recv($response_data,4096)) {
    return new Net::DNS::Packet (\$response_data);
  }
  return undef;
}

1;
