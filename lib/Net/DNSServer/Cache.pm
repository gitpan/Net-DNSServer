package Net::DNSServer::Cache;

# $Id: Cache.pm,v 1.3 2001/05/26 18:00:13 rob Exp $
# Implement a DNS Cache using IPC::SharedCache with shared memory
# so Net::Server::PreFork (different processes) can share the
# same cache to follow the rfcs.

use strict;
use Exporter;
use vars qw(@ISA);
use Net::DNSServer::Base;
use Net::DNS;
use Net::DNS::RR;
use Net::DNS::Packet;
use Carp qw(croak);

@ISA = qw(Net::DNSServer::Base);

# Created and passed to Net::DNSServer->run()
sub new {
  my $class = shift || __PACKAGE__;
  my $self  = shift || {};
  $self -> {structure_cache} ||= {};
  $self -> {lookup_cache}    ||= {};
  return bless $self, $class;
}

# Check if the TTL is still good
sub validate_ttl {
  my $value = shift or return undef;
  return undef unless (ref $value) eq "ARRAY";
  foreach my $entry (@$value) {
    # If this entry has expired, then throw the whole thing out
    return undef if (ref $entry) ne "ARRAY" || $entry->[0] < time;
  }
  # If nothing has expired, the data is still valid
  return $value;
}

# Called once at configuration load time by Net::DNSServer.
# Takes the Net::DNSServer object as an argument
sub init {
  my $self = shift;
  my $net_server = shift;
  unless ($net_server && (ref $net_server) && ($net_server->isa("Net::Server::Single"))) {
    croak 'Usage> '.(__PACKAGE__).'->init(Net::Server::Single object) You gave me a ['.(ref $net_server).'] object';
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
  $self -> {net_server} -> {usecache} = 1;
  return 1;
}

# Called after all pre methods have finished
# Returns a Net::DNS::Packet object as the answer
#   or undef to pass to the next module to resolve
sub resolve {
  my $self = shift;
  my $dns_packet = $self -> {question};
  my ($question) = $dns_packet -> question();
  my $key = $question->string();
  my $cache_structure = $self -> {structure_cache} -> {$key} || undef;
  unless ($cache_structure &&
          (ref $cache_structure) eq "ARRAY" &&
          (scalar @$cache_structure) == 3) {
    print STDERR "DEBUG: Structure Cache miss on [$key]\n";
    return undef;
  }
  print STDERR "DEBUG: Structure Cache hit on [$key]\n";
  # Structure key found in cache, so lookup actual values

  # ANSWER Section
  my $answer_ref      = $self->fetch_rrs($cache_structure->[0]);

  # AUTHORITY Section
  my $authority_ref   = $self->fetch_rrs($cache_structure->[1]);

  # ADDITIONAL Section
  my $additional_ref  = $self->fetch_rrs($cache_structure->[2]);

  # Make sure all sections were loaded successfully from cache.
  unless ($answer_ref && $authority_ref && $additional_ref) {
    # If not, flush structure key to ensure
    # it will be re-stored in the post() phase.
    delete $self -> {structure_cache} -> {$key};
    return undef;
  }

  # Initialize the response packet with a copy of the request
  # packet in order to set the header and question sections
  my $response = bless \%{$dns_packet}, "Net::DNS::Packet"
    || die "Could not initialize response packet";

  # Install the RRs into their corresponding sections
  $response->push("answer",      @$answer_ref);
  $response->push("authority",   @$authority_ref);
  $response->push("additional",  @$additional_ref);

  $self -> {net_server} -> {usecache} = 0;
  return $response;
}

sub fetch_rrs {
  my $self = shift;
  my $array_ref = shift;
  my @rrs = ();
  if (ref $array_ref ne "ARRAY") {
    return undef;
  }
  foreach my $rr_string (@$array_ref) {
    my $lookup = validate_ttl($self -> {lookup_cache} -> {$rr_string});
    unless ($lookup) {
      print STDERR "DEBUG: Lookup Cache miss on [$rr_string]\n";
      return undef;
    }
    print STDERR "DEBUG: Lookup Cache hit on [$rr_string]\n";

    foreach my $entry (@$lookup) {
      return undef unless ref $entry eq "ARRAY";
      my ($expire,$rdatastr) = @$entry;
      my $rr = Net::DNS::RR->new ("$rr_string\t$rdatastr");
      $rr->ttl($expire - time);
      push @rrs, $rr;
    }
  }
  return \@rrs;
}

# Called after response is sent to client
sub post {
  my $self = shift;
  if ($self -> {net_server} -> {usecache}) {
    # Store the answer into the cache
    my $dns_packet = $self -> {net_server} -> {answer_packet};
    my ($question) = $dns_packet -> question();
    my $key = $question->string();
    my @s = ();
    push @s, $self->store_rrs($dns_packet->answer);
    push @s, $self->store_rrs($dns_packet->authority);
    push @s, $self->store_rrs($dns_packet->additional);
    print STDERR "DEBUG: Storing cache for [$key]\n";
    $self -> {structure_cache} -> {$key} = \@s;
  }
  return 1;
}

# Subroutine: store_rrs
# PreConds:   Takes a list of RR objects
# PostConds:  Stores rdatastr components into cache
#             and returns a list of uniques
sub store_rrs {
  my $self = shift;
  my $answer_hash = {};
  my $lookup_cache = $self -> {lookup_cache};
  foreach my $rr (@_) {
    my $key = join("\t",$rr->name.".",$rr->class,$rr->type);
    my $rdatastr = $rr->rdatastr();
    my $ttl = $rr->ttl();
    if (!exists $answer_hash->{$key}) {
      $answer_hash->{$key} = [];
    }
    push @{$answer_hash->{$key}},
    [$ttl + time, $rdatastr];
  }
  foreach my $key (keys %{$answer_hash}) {
    print STDERR "DEBUG: Storing lookup cache for [$key] (".(scalar @{$answer_hash->{$key}})." elements)\n";
    # Save the rdatastr values into the lookup cache
    $lookup_cache->{$key} = $answer_hash->{$key};
  }
  return [keys %{$answer_hash}];
}

1;
__END__

DBM key/value storage format

Key:
Question;struct

"netscape.com.	IN	ANY;structure"

Note that [TAB] delimites the three parts of the question.


Value:
[
 # ANSWERS
 ["netscape.com.	IN	NS",
  "netscape.com.	IN	A",
  "netscape.com.	IN	SOA"],
 # AUTHORITIES
 ["netscape.com.	IN	NS"],
 # ADDITIONALS
 ["ns.netscape.com.	IN	A",
  "ns2.netscape.com.	IN	A"]
]


-OR-


Key:
Question;lookup
"netscape.com.	IN	A;lookup"

Value:
[
 # TTL, VALUE (rdatastr)
 [time + 100193, "207.200.89.225"],
 [time + 100193, "207.200.89.193"]
]


;; ANSWER SECTION (5 records)
netscape.com.	100193	IN	NS	NS.netscape.com.
netscape.com.	100193	IN	NS	NS2.netscape.com.
netscape.com.	1190	IN	A	207.200.89.225
netscape.com.	1190	IN	A	207.200.89.193
netscape.com.	100	IN	SOA	NS.netscape.com. dnsmaster.netscape.com. (
					2001051400	; Serial
					3600	; Refresh
					900	; Retry
					604800	; Expire
					600 )	; Minimum TTL

;; AUTHORITY SECTION (2 records)
netscape.com.	100193	IN	NS	NS.netscape.com.
netscape.com.	100193	IN	NS	NS2.netscape.com.

;; ADDITIONAL SECTION (2 records)
NS.netscape.com.	138633	IN	A	198.95.251.10
NS2.netscape.com.	115940	IN	A	207.200.73.80
