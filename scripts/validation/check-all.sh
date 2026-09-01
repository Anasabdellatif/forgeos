#!/usr/bin/env bash
# Runs the full blueprint validation suite and reports each check's observed result.
# POSIX counterpart of check-all.ps1.
#
# Usage: check-all.sh [--strict]
#   --strict  also fail when blocking placeholders remain (right setting for an adopted project)
#
# Exit 0 only when every gating check passed.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

# Every check prints the number the public page claims -- the self-test total, the policy control
# count, the link counts. Until now the audit could not see them and reported them UNCHECKED, and
# they drifted twice in two phases. Tee each check into a run log and hand it to public-surface,
# which runs last: measured once, verified once, no check run twice.
RUN_LOG="$(mktemp "${TMPDIR:-/tmp}/blueprint-check-all-XXXXXX")"
trap 'rm -f "$RUN_LOG"' EXIT

names=()
codes=()
gates=()

run_check() {   # run_check <name> <relative-script> <gating:0|1> [args...]
  local name="$1" script="$2" gating="$3"
  shift 3

  echo ''
  printf '%.0s=' {1..78}; echo ''
  echo "CHECK: $name"
  printf '%.0s=' {1..78}; echo ''

  if [ ! -f "$REPO_ROOT/$script" ]; then
    echo "SKIPPED: script not found at $script"
    names+=("$name"); codes+=("-1"); gates+=("$gating")
    return
  fi

  bash "$REPO_ROOT/$script" "$@" | tee -a "$RUN_LOG"
  local code=$?
  names+=("$name"); codes+=("$code"); gates+=("$gating")
}

run_check 'structure'     'scripts/validation/check-structure.sh'    1 --quiet
run_check 'empty-files'   'scripts/validation/check-empty-files.sh'  1
run_check 'policy'        'scripts/validation/check-policy.sh'       1
run_check 'links'         'scripts/validation/check-links.sh'        1
run_check 'bp-version'    'scripts/validation/check-blueprint-version.sh' 1
run_check 'secrets'       'scripts/hooks/scan-secrets.sh'            1 --scan-tree
run_check 'hook-selftest' 'scripts/hooks/selftest.sh'                1

if [ "$STRICT" -eq 1 ]; then
  run_check 'placeholders' 'scripts/validation/check-placeholders.sh' 1 --fail-on-blocking
else
  run_check 'placeholders' 'scripts/validation/check-placeholders.sh' 0
fi

run_check 'context-budget' 'scripts/validation/check-context-budget.sh' 0
run_check 'state-freshness' 'scripts/validation/check-state-freshness.sh' 0
run_check 'public-surface' 'scripts/validation/check-public-surface.sh' 1 --fail-on-drift --measured "$RUN_LOG"

echo ''
printf '%.0s=' {1..78}; echo ''
echo 'SUMMARY'
printf '%.0s=' {1..78}; echo ''

failed=0
for i in "${!names[@]}"; do
  status='passed'
  [ "${codes[$i]}" != "0" ] && status='failed'
  gate='info  '
  [ "${gates[$i]}" = "1" ] && gate='gating'
  printf '  %-14s  %-8s  exit=%-3s  %s\n' "${names[$i]}" "$status" "${codes[$i]}" "$gate"
  if [ "${gates[$i]}" = "1" ] && [ "${codes[$i]}" != "0" ]; then
    failed=$((failed + 1))
  fi
done

echo ''
if [ "$failed" -gt 0 ]; then
  printf 'VALIDATION FAILED: %s gating check(s) did not pass.\n' "$failed"
  exit 1
fi

echo 'VALIDATION PASSED: every gating check exited 0.'
exit 0
