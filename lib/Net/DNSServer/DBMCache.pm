package Net::DNSServer::DBMCache;

# $Id: DBMCache.pm,v 1.1 2001/05/24 14:22:16 rob Exp $
# This is meant to be the base class for all Net::DNSServer resolving module handlers

use Exporter;
use vars qw(@ISA);
use Net::DNSServer::Base;
use Net::DNS;
use Carp qw(croak);
use IO::File;
use Fcntl qw(LOCK_SH LOCK_EX LOCK_UN);
use Storable qw(freeze thaw);

@ISA = qw(Net::DNSServer::Base);

# Created and passed to Net::DNSServer->run()
sub new {
  my $class = shift || __PACKAGE__;
  my $self  = shift || {};
  if (! $self -> {dbm_file} ) {
    croak 'Usage> new({dbm_file => "/var/log/dns_cache.db", fresh => 0})';
  }
  # Create lock file to serialize DBM accesses and avoid DBM corruption
  my $lock = IO::File->new ("$self->{dbm_file}.LOCK", "w")
    || croak "Could not write to $self->{dbm_file}.LOCK";

  # Test to make sure it can be locked and unlocked successfully
  flock($lock,LOCK_SH) || die "Couldn't get shared lock on $self->{dbm_file}.LOCK";
  flock($lock,LOCK_EX) || die "Couldn't get exclusive lock on $self->{dbm_file}.LOCK";
  flock($lock,LOCK_UN) || die "Couldn't unlock on $self->{dbm_file}.LOCK";
  $lock->close();

  # Actually connect to dbm file as a test
  my %db=();
  dbmopen(%db, $self->{dbm_file}, 0666)
    || croak "Could not connect to $self->{dbm_file}";
  if ($self -> {fresh}) {
    # Wipe any old information if it exists from last time
    %db=();
  }
  dbmclose(%db);
  return bless $self, $class;
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
  
  die "virtual function not implemented";
}

# Called after response it sent to client
sub post {
  return 1;
}

# Called once prior to server shutdown
sub cleanup {
  my $self = shift;
  unlink "$self->{dbm_file}.LOCK";
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
Question;answer
"netscape.com.	IN	A;answer"

Value:
[
 # TTL, VALUE
 [time + 100193, "netscape.com.	IN	A	207.200.89.225"],
 [time + 100193, "netscape.com.	IN	A	207.200.89.193"]
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