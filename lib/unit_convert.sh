#!/usr/bin/env bash
# Unit conversion utilities for pmemtester
# All values are integers. Conversions use floor division (truncation).

kb_to_mb() { echo $(( $1 / 1024 )); }
mb_to_kb() { echo $(( $1 * 1024 )); }
bytes_to_kb() { echo $(( $1 / 1024 )); }
kb_to_bytes() { echo $(( $1 * 1024 )); }
mb_to_memtester_arg() { echo "${1}M"; }
