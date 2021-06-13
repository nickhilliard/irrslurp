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
% perl -I blib bin/bogonsearch.pl --debug info
```

The invalid prefixes are emitted in json format.  These can be parsed on the
command-line using gron[1] or jq[2], or fed into another json consumer.

All debugging information is emitted on stderr.

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

  - doesn't handle ipv6.

[1] https://github.com/tomnomnom/gron
[2] https://stedolan.github.io/jq/
