package Net::DNSServer::MemCache;

# $Id: MemCache.pm,v 1.4 2001/05/24 15:00:18 rob Exp $
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
use IPC::SharedCache;

use O::Is qw(is_text); # DEBUG

@ISA = qw(Net::DNSServer::Base);

# Created and passed to Net::DNSServer->run()
sub new {
  my $class = shift || __PACKAGE__;
  my $self  = shift || {};
  if (! $self -> {ipc_key} || ! exists $self -> {max_size}) {
    croak 'Usage> new({ipc_key => "fred" [ , max_size => 50_000_000 ] [, fresh => 0 ] })';
  }
  if ($self -> {fresh}) {
    &IPC::SharedCache::remove( $self -> {ipc_key} );
  }
  my %dns_cache=();
  tie (%dns_cache, 'IPC::SharedCache',
       ipc_key             => $self->{ipc_key},
       load_callback       => \&load_answer,
       validate_callback   => \&validate_ttl,
       max_size            => $self->{max_size},
       ) || die "IPC::SharedCache failed for ipc_key [$self->{ipc_key}]";
  if ($self -> {fresh}) {
    %dns_cache = ();
  }
  $self -> {dns_cache} = \%dns_cache;
  return bless $self, $class;
}

# If the TTL expires, there is nothing to use anymore.
sub load_answer {
  my $key = shift;
  print STDERR "DEBUG: load_answer called for [$key]\n";
  return \undef;
}

# Check if the TTL is still good
sub validate_ttl {
  my ($key, $value) = @_;
  print STDERR "DEBUG: validate_ttl called for [$key]\n";
  # There is no TTL stored in the DNS structure result
  return 1 if $key =~ /\;(structure)$/;
  return 1 unless $key =~ /\;(lookup)$/;
  return 0 unless (ref $value) eq "ARRAY";
  foreach my $entry (@$value) {
    # If this entry has expired, then throw the whole thing out
    return 0 if (ref $entry) ne "ARRAY" || $entry->[0] < time;
  }
  # If nothing has expired, the data is still valid
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
  my $cache_structure = $self -> {dns_cache} -> {"$key;structure"} || undef;
  unless ($cache_structure &&
          (ref $cache_structure) eq "ARRAY" &&
          (scalar @$cache_structure) == 3) {
    print STDERR "DEBUG: Cache miss on [$key;structure]\n";
    return undef;
  }
  print STDERR "DEBUG: Cache hit on [$key;structure]\n";
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
    delete $self -> {dns_cache} -> {"$key;structure"};
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
    my $lookup = $self -> {dns_cache} -> {"$rr_string;lookup"} || undef;
    unless ($lookup && ref $lookup eq "ARRAY") {
      return undef;
    }
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
    print STDERR "DEBUG: Storing cache for [$key;structure]\n";
    print STDERR is_text \@s;
    $self -> {dns_cache} -> {"$key;structure"} = \@s;
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
  my $dns_cache = $self -> {dns_cache};
  foreach my $rr (@_) {
    my $key = join("\t",$rr->name,$rr->class,$rr->type);
    my $rdatastr = $rr->rdatastr();
    my $ttl = $rr->ttl();
    if (!exists $answer_hash->{$key}) {
      $answer_hash->{$key} = [];
    }
    push @{$answer_hash->{$key}},
    [$ttl + time, $rdatastr];
  }
  foreach my $key (keys %{$answer_hash}) {
    # Save the rdatastr values into the lookup cache
    $dns_cache->{"$key;lookup"} = $answer_hash->{$key};
  }
  return [keys %{$answer_hash}];
}

# Called once prior to server shutdown
sub cleanup {
  my $self = shift;
  if ($self -> {fresh}) {
    %{$self -> {dns_cache}} = ();
  }
  untie %{$self -> {dns_cache}};
  if ($self -> {fresh}) {
    &IPC::SharedCache::remove( $self -> {ipc_key} );
  }
  return 1;
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
