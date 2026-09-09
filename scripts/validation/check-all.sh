#!/usr/bin/env bash
# Runs the full blueprint validation suite and reports each check's observed result.
# POSIX counterpart of check-all.ps1.
#
# Usage: check-all.sh [--strict] [--compact] [--verbose]
#   --strict   also fail when blocking placeholders remain (right setting for an adopted project)
#   --compact  suppress per-check banners and child output (default; accepted for explicitness)
#   --verbose  show per-check banners and full child output (old behaviour); overrides --compact
#
# Exit 0 only when every gating check passed.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STRICT=0
IS_COMPACT=1  # default: compact
IS_VERBOSE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --strict)  STRICT=1 ;;
    --compact) IS_COMPACT=1 ;;
    --verbose) IS_COMPACT=0; IS_VERBOSE=1 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

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

  if [ ! -f "$REPO_ROOT/$script" ]; then
    if [ "$IS_VERBOSE" -eq 1 ]; then
      echo ''
      printf '%.0s=' {1..78}; echo ''
      echo "CHECK: $name"
      printf '%.0s=' {1..78}; echo ''
      echo "SKIPPED: script not found at $script"
    fi
    names+=("$name"); codes+=("-1"); gates+=("$gating")
    return
  fi

  local code tmpout tmperr
  if [ "$IS_COMPACT" -eq 1 ]; then
    # In compact mode: auto-pass --compact to selftest; capture output; show on failure only.
    local compact_extra=()
    [ "$script" = 'scripts/hooks/selftest.sh' ] && compact_extra=(--compact)
    tmpout="$(mktemp)"
    tmperr="$(mktemp)"
    bash "$REPO_ROOT/$script" "$@" "${compact_extra[@]}" > "$tmpout" 2>"$tmperr"
    code=$?
    cat "$tmpout" >> "$RUN_LOG"
    if [ "$code" -ne 0 ]; then
      echo ''
      echo "CHECK FAILED: $name (exit $code)"
      cat "$tmpout"
      [ -s "$tmperr" ] && cat "$tmperr" >&2
    fi
    rm -f "$tmpout" "$tmperr"
  else
    echo ''
    printf '%.0s=' {1..78}; echo ''
    echo "CHECK: $name"
    printf '%.0s=' {1..78}; echo ''
    bash "$REPO_ROOT/$script" "$@" | tee -a "$RUN_LOG"
    code=$?
  fi

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
