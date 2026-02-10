# Pmemtester

A parallel wrapper for memtester for the quickest way to test RAM.

Safe to just run on any host.
 
## Memtester

Homepage https://pyropus.ca./software/memtester/

## Parallel wrapper

A Linux memory tester:

- in Bash
- runs multiple copies of the executable memtester in parallel
- configurable location for the executable (default /usr/local/bin/)
- auto check the available RAM
- Use a configurable percentage of that (default 90%) - optional commandline flag
- have command line flag alternatives for instead of available RAM (default), can specify as % of
-- total RAM 
-- free RAM
- auto check the number of threads on the host
- run a memtester for each thread
-- with the desired RAM test size divided equally amongst those threads
- the default should always be safe and not crash the host
- each thread should log to it’s own file
-- but have an overall log which includes the status of all of them
- memtester requires memory to be locked
-- so test that the kernel memory lock size is large enough
--- and set if not
- Linux EDAC
-- messages and counters should be checked
--- at the start before the memtester
--- at the end after the memtester
- a pass requires
-- all memtesters have run OK, and
-- EDAC strings haven’t changed (no new EDAC messages), and
-- EDAC counters haven’t changed

## Maths in Bash

- Be careful with maths in Bash
- Use best practice for integer maths in Bash
-- division, rounding, overflow, exceptions, etc
-- care for the order of doing the maths to prevent overflow / underflow / major rounding issues
- be careful to use the correct units for each part of the script

## Testsuite

- A comprehensive test suite
- >85% code coverage

## Development methodology

TDD

