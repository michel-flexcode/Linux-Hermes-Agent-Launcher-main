#!/usr/bin/env bash
# ============================================================================
# test_test_suite_tools.sh
#
# The test suite itself relies on ripgrep (`rg`) for most static checks. If
# it is missing, every other test in tests/connectionStatus and
# tests/architecture would fail with a confusing "command not found" instead
# of a clear dependency error. Check it explicitly, first.
# ============================================================================
set -uo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

command -v rg >/dev/null 2>&1 \
  || fail 'ripgrep (rg) is required to run this test suite (install: apt install ripgrep).'

command -v bash >/dev/null 2>&1 \
  || fail 'bash is required to run this test suite.'

printf 'PASS: ripgrep and bash are available for the test suite.\n'
