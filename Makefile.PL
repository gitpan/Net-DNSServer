use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile
  NAME           => 'Net::DNSServer',
  AUTHOR         => 'Rob Brown, rob@roobik.com',
  VERSION_FROM   => 'lib/Net/DNSServer.pm', # finds $VERSION
  ABSTRACT_FROM  => 'lib/Net/DNSServer.pm',
  PREREQ_PM      => {
    # e.g., Module::Name => 1.1
    'Net::DNS'            => 0.19,  # Root NS patch
    'Net::Server'         => 0.62,  # UDP support
    'IPC::SharedCache'    => 1.3,   # PreFork support
    'Storable'            => 1.0,   # Any Storable should work
    'Net::Bind'           => 0.03,  # Resolv parser
  },
  ;
