IRR Slurp
=========

This code carefully mirrors:

  - local copies of the most recent RIR delegated stats files
  - local copies of the most recent RIR resource transfer logs
  - the most recent copy of the RIPE nonauth whois database

then runs a patricia trie search to assess which prefixes in the RIPE nonauth
db are invalid.  The code lists a prefix as being invalid if the route entry
refers to unallocated or reserved address space, or if the route entry was
part, or all, of a network block wwhich was subsequently transferred to
another organisation.

Usage
-----

```
% perl Makefile.PL && make
% perl -I lib bin/bogonsearch.pl --debug info > ipv4-invalids.json
% perl -I lib bin/bogonsearch.pl --debug info --protocol 6 > ipv6-invalids.json
```

The invalid prefixes are emitted in json format on stdout.  These can be parsed on the
command-line using gron[1] or jq[2], or fed into another json consumer.

All debugging information is emitted on stderr.

```
    --authsource [delegated|transfers]			# check delegated files, or transfer files. defaults to both
    --[no]checkregstatus				# invalidate objects based on delegated registration status
    --[no]checkregtime					# invalidate objects based on time-based status transfer check
    --debug [error|warning|notice|info|debug]		# set minimum level for logging output
    --protocol [4|6]					# specify the protocol to check
    --rirs <rirname> [--rirs <rirname> ...]		# list of RIRs to check. defaults to: afrinic apnic arin lacnic
```

Examples
--------

1. Check database for reserved and unregistered address space in LACNIC and
Afrinic only. Check delegated files only.  Check IPv4 only.  Reasonable
debugging output.

```
% perl -I lib bin/bogonsearch.pl --debug info --protocol 4 --no-checkregtime --authsource delegated --rirs lacnic --rirs afrinic
```

2. Check all RIRs database for transfers only, ipv6:

```
% perl -I lib bin/bogonsearch.pl --protocol 6 --nocheckregstatus --authsource transfers
```

The output of this is "null", indicating no whois objects could be viewed as
invalid on the basis that the ipv6 address space was transferred to another
party.

Perl dependencies
-----------------

The perl library depends on several modules from CPAN. The `perl Makefile.PL`
command will provide a list of which ones are missing.  These can be
installed on Ubuntu / Macos using the following commands:

Ubuntu:

```
# apt update
# apt install -y git libnet-patricia-perl libdatetime-format-iso8601-perl libnet-ip-perl liblog-dispatch-perl libjson-perl liblwp-protocol-https-perl
```

Macos with Macports:

```
# port -N install git perl5 p5-datetime-format-iso8601 p5-json p5-log-dispatch p5-lwp-protocol-https p5-net-ip p5-net-patricia
# port upgrade -s -n --force p5-net-patricia
```

The extra command for macos rebuilds the `p5-net-patricia` port from
scratch.  This can be necessary if there is a misalignment in the operating
system build environment.


Bugs
----

  - the code does not handle the great RIPE-NONAUTH db modification of
    2018-09-04.  This means that any prefix which was subject to a transfer
    or reregistration before that date may end up not being listed as invalid.

  - the code could handle ARIN-NONAUTH analysis if ARIN supported last-modified:
    lines on DB entries.

  - doesn't handle supernet nonauth prefixes, i.e. where there is a route
    entry for a network block, and part of that network block is transferred.

  - doesn't handle merger/acquisitions unless the RIR specifies this in the
    transfers json blob.

[1] https://github.com/tomnomnom/gron
[2] https://stedolan.github.io/jq/
