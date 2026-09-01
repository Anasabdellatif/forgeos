#!/usr/bin/env bash
# Reports how far the state ledger lags the repository. POSIX counterpart of
# check-state-freshness.ps1.
#
# The persistence gate (.ai/contract/reporting.md section 0) says no final report ships before
# durable state lands in its file. Nothing mechanical can read a conversation, but the ledger's
# lag behind HEAD is measurable: a ledger many commits old is either stale or the sessions since
# produced nothing durable -- and the second claim deserves to be made out loud.
#
# Advisory by design, and deliberately never a failure: a pre-v1.12 adoption has no ledger yet,
# an unborn repository has no history -- both are findings to report, not reasons to block a
# validation run on an old project. Always exits 0.
#
# Usage: check-state-freshness.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER_REL='.ai/context/current-state.md'
LEDGER="$REPO_ROOT/$LEDGER_REL"

echo 'State ledger freshness'
printf '  ledger    %s\n' "$LEDGER_REL"

if [ ! -f "$LEDGER" ]; then
  echo "State freshness NOTE  (no state ledger -- pre-v1.12 adoption; sync from the blueprint to seed it)"
  exit 0
fi

if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo 'State freshness NOTE  (not a git repository -- freshness cannot be measured here)'
  exit 0
fi

# A truncated history cannot answer this question, and answering it anyway produces the one
# result a validation must never produce: a false all-clear. `git log -1 -- <ledger>` walks only
# the commits that were fetched, so under actions/checkout's default fetch-depth of 1 it returns
# HEAD for ANY ledger -- a ledger untouched for a hundred commits reads as "updated by the latest
# commit". Measured against this repository at 987f907: full clone reported NOTE (1 commit behind),
# a depth-1 clone of the same commit reported OK. A check that cannot see the evidence says so.
shallow="$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)"
if [ "$shallow" != 'true' ]; then
  # --is-shallow-repository arrived in git 2.15. Older git answers nothing, so ask the file that
  # makes a repository shallow in the first place.
  git_dir="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir 2>/dev/null)"
  [ -n "$git_dir" ] && [ -f "$git_dir/shallow" ] && shallow='true'
fi
if [ "$shallow" = 'true' ]; then
  echo 'State freshness NOTE  (shallow history -- the ledger lag cannot be measured here; fetch full history to measure it)'
  exit 0
fi

last_commit="$(git -C "$REPO_ROOT" log -1 --format='%h %cs' -- "$LEDGER_REL" 2>/dev/null)"
if [ -z "$last_commit" ]; then
  echo 'State freshness NOTE  (the ledger exists but was never committed -- commit it with the work it describes)'
  exit 0
fi
printf '  last touched   %s\n' "$last_commit"

if [ -n "$(git -C "$REPO_ROOT" status --porcelain -- "$LEDGER_REL" 2>/dev/null)" ]; then
  echo 'State freshness OK  (the ledger is modified in the working tree -- being refreshed now)'
  exit 0
fi

last_hash="${last_commit%% *}"
behind="$(git -C "$REPO_ROOT" rev-list --count "$last_hash..HEAD" 2>/dev/null || echo 0)"
printf '  behind HEAD    %s commit(s)\n' "$behind"

if [ "$behind" -eq 0 ]; then
  echo 'State freshness OK  (the ledger was updated by the latest commit)'
else
  echo "State freshness NOTE  ($behind commit(s) since the last ledger update -- refresh it, or the report must say why the state is unchanged)"
fi
exit 0
