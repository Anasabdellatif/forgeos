#!/usr/bin/env bash
# Proves selftest.ps1 and selftest.sh ran the same cases, in the same order, with the same labels.
#
# WHY THIS EXISTS
# Both self-tests claim parity in their headers, and for nine versions that claim was wrong: the
# POSIX file carried 33 cases to the PowerShell file's 34 and said otherwise. Nothing could catch
# it, because no single job runs both -- the Windows job runs the .ps1 and the Ubuntu jobs run the
# .sh. This is the check that compares them.
#
# WHY IT COMPARES OUTPUT INSTEAD OF RUNNING BOTH ITSELF
# Running both from one host was tried and does not work. Git Bash on Windows keeps its temporary
# fixtures under a POSIX /tmp that native Windows tools cannot open, so the POSIX suite cannot
# complete there; and Windows PowerShell is absent from a Linux runner. Each suite therefore runs
# on the host it was written for, and this script compares what they printed.
#
# It reads self-test output and nothing else. It knows no guard rules and duplicates none.
#
# Usage: check-selftest-parity.sh <powershell-output> <posix-output>
# Exit 0 when the case lists are identical, 1 otherwise.

set -uo pipefail

PS_OUT="${1:-}"
SH_OUT="${2:-}"

if [ -z "$PS_OUT" ] || [ -z "$SH_OUT" ]; then
  sed -n '2,19p' "$0"
  exit 1
fi

for f in "$PS_OUT" "$SH_OUT"; do
  [ -f "$f" ] || { echo "Self-test output not found: $f" >&2; exit 1; }
done


work="$(mktemp -d)"
cleanup() { rm -rf "${work:?}"; }
trap cleanup EXIT

# NORMALISE FIRST, THEN READ.
# Windows PowerShell 5.1 writes UTF-16LE when output is redirected, so every character arrives
# followed by a NUL and a POSIX grep matches nothing at all -- which is exactly how v1.10.4 failed:
# a complete 60-case file that read as zero cases. Stripping NULs makes UTF-16LE readable, stripping
# CR lets a Windows-produced file compare against a POSIX one, and stripping a leading UTF-8 BOM
# keeps the first line clean. Everything below reads only these normalised copies -- including the
# failure scan, which would otherwise miss a FAIL line in an unnormalised file and wrongly report
# a healthy suite.
normalise() { tr -d '\000\r' < "$1" | sed $'1s/^\xEF\xBB\xBF//'; }

normalise "$PS_OUT" > "$work/ps.txt"
normalise "$SH_OUT" > "$work/sh.txt"

# The label is everything between the status word and the expected= column. Nothing else is
# compared: the exit codes are each suite's own business, the case list is the contract between them.
labels() { grep -E '^(PASS|FAIL)' "$1" | sed -e 's/^....  //' -e 's/ *expected=.*//'; }

labels "$work/ps.txt" > "$work/ps.labels"
labels "$work/sh.txt" > "$work/sh.labels"

ps_n="$(grep -c '' "$work/ps.labels")"
sh_n="$(grep -c '' "$work/sh.labels")"

printf '  selftest.ps1 : %s case(s)\n' "$ps_n"
printf '  selftest.sh  : %s case(s)\n' "$sh_n"

# Zero cases means a suite did not really run, or its output never arrived. An empty file lands
# here too, and must never pass.
if [ "$ps_n" -eq 0 ] || [ "$sh_n" -eq 0 ]; then
  echo ''
  echo 'A self-test produced no cases at all, so there is nothing to compare.'
  echo 'Check that both suites ran and that their output was captured.'
  exit 1
fi

# A suite that failed tells us nothing reliable about parity, and hiding that behind a parity
# verdict would be its own kind of lie.
if grep -qE '^FAIL' "$work/ps.txt" "$work/sh.txt"; then
  echo ''
  echo 'A self-test reported failing cases. Fix those before judging parity:'
  grep -hE '^FAIL' "$work/ps.txt" "$work/sh.txt" | sed 's/^/  /'
  exit 1
fi

# diff catches all three shapes at once: a different count, a different order, and a label present
# on one side only.
if diff -u "$work/ps.labels" "$work/sh.labels" > "$work/diff.txt"; then
  echo ''
  echo "Self-test parity check passed  ($ps_n case(s), same order, same labels)"
  exit 0
fi

echo ''
echo 'Self-test parity check FAILED. The two shells do not run the same cases.'
echo '  -  only in selftest.ps1'
echo '  +  only in selftest.sh'
echo ''
sed -e '1,2d' "$work/diff.txt" | sed 's/^/  /'
echo ''
echo 'A case added on one side must be added on the other in the same commit.'
exit 1
