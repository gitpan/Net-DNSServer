package Net::DNSServer::Proxy;

# $Id: Proxy.pm,v 1.8 2001/06/08 07:48:50 rob Exp $
# This module simply forwards a request to another name server to do the work.

use strict;
use Exporter;
use vars qw(@ISA);
use Net::DNSServer::Base;
use Net::DNS;
use Net::DNS::Packet;
use Net::Bind 0.03;
use Carp qw(croak);
use IO::Socket;

@ISA = qw(Net::DNSServer::Base);

# Created before calling Net::DNSServer->run()
sub new {
  my $class = shift || __PACKAGE__;
  my $self = shift || {};
  if (! $self -> {real_dns_server} ) {
    # Use the first nameserver in resolv.conf as default
    my $res = new Net::Bind::Resolv('/etc/resolv.conf');
    ($self -> {real_dns_server}) = $res -> nameservers();
    # XXX - This should probably cycle through all the
    # nameserver entries until one successfully accepts.
  }
  # XXX - It should allow a way to override the port
  #       (like host:5353) instead of forcing to 53
  # Initial "connect" to a remote resolver
  my $that_server = new IO::Socket::INET
    (PeerAddr     => $self->{real_dns_server},
     PeerPort     => "domain",
     Proto        => "udp");
  unless ( $that_server ) {
    croak "Remote dns server [$self->{real_dns_server}] is down.";
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
__END__

=head1 NAME

Net::DNSServer::Proxy
- A Net::DNSServer::Base which simply forwards
a request to another name server to resolve.

=head1 SYNOPSIS

  #!/usr/bin/perl -w -T
  use strict;
  use Net::DNSServer;
  use Net::DNSServer::Proxy;

  # Specify which remote server to proxy to
  my $resolver = new Net::DNSServer::Proxy {
    real_dns_server => "12.34.56.78",
  };

    -- or --

  # Or, it will default to the first "nameserver"
  # entry in /etc/resolv.conf
  my $resolver = new Net::DNSServer::Proxy;

  run Net::DNSServer {
    priority => [$resolver],
  };

=head1 DESCRIPTION

This resolver does not actually do any
resolving itself.  It simply forwards the
request to another server and responds
with whatever the response is from other
server.

=head2 new

The new() method takes a hash ref of properties.

=head2 real_dns_server (optional)

This value is the IP address of the server to
proxy the requests to.  This server should
have a nameserver accepting connections on
the standard named port (53).
It defaults to the first "nameserver" entry
found in the /etc/resolv.conf file.

=head1 AUTHOR

Rob Brown, rob@roobik.com

=head1 SEE ALSO

L<Net::Bind::Resolv>,
L<Net::DNSServer::Base>,
resolv.conf(5),
resolver(5)

=head1 COPYRIGHT

Copyright (c) 2001, Rob Brown.  All rights reserved.
Net::DNSServer is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

$Id: Proxy.pm,v 1.8 2001/06/08 07:48:50 rob Exp $

=cut
