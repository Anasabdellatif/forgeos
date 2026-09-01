#!/usr/bin/env bash
# Self-test for the release artifact builder. SOURCE-ONLY, like the builder it tests.
#
# scripts/hooks/selftest.sh cannot host these cases: it is portable, so it runs inside every
# adopting project -- where scripts/release/ does not exist by design, and every case here would
# fail for the right reason. Portable tests cover portable behaviour; this covers ours.
#
# The two guarantees adopters DO depend on -- sync never copies a source-only path, and a fresh
# register is seeded from the template -- live in the portable self-test where they belong.
#
# Exit 0 all passed, 1 something failed.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILDER="$REPO_ROOT/scripts/release/build-artifact.sh"

total=0; failed=0; failed_cases=''
assert_code() {   # assert_code <case> <expected> <actual>
  total=$((total + 1))
  if [ "$2" = "$3" ]; then
    printf 'PASS  %-58s %s/%s\n' "$1" "$3" "$2"
  else
    failed=$((failed + 1)); failed_cases="$failed_cases  - $1 (expected $2, got $3)"$'\n'
    printf 'FAIL  %-58s %s/%s\n' "$1" "$3" "$2"
  fi
}

command -v git >/dev/null 2>&1 || { echo 'git is required for the release self-test.' >&2; exit 1; }
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo 'Not a git repository; the builder reads tracked state, so there is nothing to test.' >&2
  exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# An untracked file must never reach an artifact. Create one so its absence proves something.
PROBE="$REPO_ROOT/.ai/rules/RELEASE-SELFTEST-PROBE.md"
printf '# untracked probe\n' > "$PROBE"

# --- 1. List mode reports the set and writes nothing ---------------------------------------------
list_out="$(bash "$BUILDER" --list --out "$TMP/never" 2>&1)"; list_code=$?
ok=0
[ "$list_code" -eq 0 ] && ok=$((ok + 1))
printf '%s' "$list_out" | grep -q 'Nothing was written' && ok=$((ok + 1))
[ -d "$TMP/never" ] || ok=$((ok + 1))
assert_code 'release: list mode reports the set and writes nothing' 3 "$ok"

# --- 2. A build produces an archive and a checksum that verifies ---------------------------------
bash "$BUILDER" --out "$TMP/dist" --name selftest-artifact >/dev/null 2>&1; build_code=$?
ARCHIVE="$TMP/dist/selftest-artifact.tar.gz"
ok=0
[ "$build_code" -eq 0 ] && ok=$((ok + 1))
[ -f "$ARCHIVE" ] && ok=$((ok + 1))
[ -f "$ARCHIVE.sha256" ] && ok=$((ok + 1))
assert_code 'release: a build writes an archive and a checksum' 3 "$ok"

ok=0
if [ -f "$ARCHIVE.sha256" ]; then
  ( cd "$TMP/dist" && sha256sum -c selftest-artifact.tar.gz.sha256 >/dev/null 2>&1 ) && ok=1
fi
assert_code 'release: the checksum verifies the archive it names' 1 "$ok"

# A checksum file that only its author can read is not a checksum. sha256sum -c rejects a line
# with a carriage return, and the Windows half writes this file too.
ok=0
[ -f "$ARCHIVE.sha256" ] && [ "$(tr -cd '\r' < "$ARCHIVE.sha256" | wc -c)" -eq 0 ] && ok=1
assert_code 'release: the checksum file carries no carriage return' 1 "$ok"

# --- 3. The boundary --------------------------------------------------------------------------
entries="$TMP/entries.txt"
if [ -f "$ARCHIVE" ]; then
  tar -tzf "$ARCHIVE" 2>/dev/null | sed 's|^selftest-artifact/||' | grep -v '/$' > "$entries"
else
  : > "$entries"
fi

ok=0
grep -qxF 'scripts/lib/blueprint-manifest.json' "$entries" && ok=$((ok + 1))
grep -qxF 'blueprint.version' "$entries" && ok=$((ok + 1))
grep -qxF 'CLAUDE.md' "$entries" && ok=$((ok + 1))
grep -qxF 'scripts/blueprint/sync-blueprint.sh' "$entries" && ok=$((ok + 1))
assert_code 'release: the artifact carries what sync needs to run' 4 "$ok"

ok=0
grep -q '^scripts/release/' "$entries" || ok=$((ok + 1))
grep -q '^\.git/' "$entries" || ok=$((ok + 1))
grep -q 'RELEASE-SELFTEST-PROBE' "$entries" || ok=$((ok + 1))
assert_code 'release: no source-only tooling, git internals, or untracked file' 3 "$ok"

# Every seed target backed by a template holds THIS repository's answers -- identity, constraints,
# governance (codeAuthorized true), the ledger, the register. Shipping one would hand a new project
# our answers, which is the failure seedTemplates exists to prevent.
ok=0
for f in .ai/context/project.md .ai/context/constraints.md .ai/context/governance.json \
         .ai/context/current-state.md .ai/memory/open-questions.md; do
  grep -qxF "$f" "$entries" || ok=$((ok + 1))
done
assert_code 'release: the artifact carries none of our own answers' 5 "$ok"

ok=0
grep -q '^\.ai/memory/decisions/2026-' "$entries" || ok=$((ok + 1))
grep -q '^\.ai/memory/lessons/2026-'   "$entries" || ok=$((ok + 1))
grep -q '^\.ai/tasks/completed/2026-'  "$entries" || ok=$((ok + 1))
grep -qxF '.ai/memory/decisions/README.md' "$entries" && ok=$((ok + 1))
assert_code 'release: history stays home but its scaffolding travels' 4 "$ok"

# --- 4. Same commit, same bytes -----------------------------------------------------------------
bash "$BUILDER" --out "$TMP/dist2" --name selftest-artifact >/dev/null 2>&1
ok=0
if [ -f "$ARCHIVE.sha256" ] && [ -f "$TMP/dist2/selftest-artifact.tar.gz.sha256" ]; then
  [ "$(cut -d' ' -f1 < "$ARCHIVE.sha256")" = \
    "$(cut -d' ' -f1 < "$TMP/dist2/selftest-artifact.tar.gz.sha256")" ] && ok=1
fi
assert_code 'release: the same commit builds the same bytes' 1 "$ok"

# --- 5. ...and a different platform builds the same bytes too ------------------------------------
# The case above proves determinism within one shell, which is the easy half. `* text=auto` pins a
# file's content but not its line ending, and git archive then converts using the BUILDER's
# platform -- CRLF on Windows, LF on POSIX. Five paths matched nothing more specific until v1.15.7,
# so one tag produced two archives: 282,144 bytes here, 281,685 there, differing in exactly those
# five entries and identical once CR was stripped.
#
# Two operating systems cannot be compared inside one shell, but the property that makes them agree
# can be: every text file the artifact carries must have an explicit eol, because an explicit eol is
# the only thing git archive resolves without asking the platform. `attr/text=auto` means unpinned;
# `i/-text` means binary, which has no line endings to convert.
git -C "$REPO_ROOT" ls-files --eol > "$TMP/eol.txt" 2>/dev/null || : > "$TMP/eol.txt"
unpinned=0
if [ -s "$entries" ] && [ -s "$TMP/eol.txt" ]; then
  awk -F'\t' 'NR == FNR { want[$0] = 1; next }
              NF < 2 || !($2 in want) { next }
              $1 ~ /i\/-text/ || $1 ~ /eol=/ { next }
              { print $2 }' "$entries" "$TMP/eol.txt" > "$TMP/unpinned.txt"
  unpinned="$(grep -c . "$TMP/unpinned.txt")"
  [ "$unpinned" -gt 0 ] && sed 's/^/      follows the platform: /' "$TMP/unpinned.txt"
fi
assert_code 'release: no artifact file inherits the builder line endings' 0 "$unpinned"

# --- 6. The release workflow ---------------------------------------------------------------------
# The workflow is the one file here that can act on the outside world: it holds contents: write and
# publishes. Nothing downstream re-reads it, so its safety properties are asserted from its text.
WF="$REPO_ROOT/.github/workflows/release.yml"
MAN="$REPO_ROOT/scripts/lib/blueprint-manifest.json"

# A release workflow that reaches an adopting project tries to release THEIR repository from THEIR
# tags. .github/workflows is portable, so only the declaration keeps this file home.
ok=0
[ -f "$WF" ] && ok=$((ok + 1))
grep -q '"\.github/workflows/release\.yml"' "$MAN" && ok=$((ok + 1))
awk '/"sourceOnly"/{f=1} f && /\.github\/workflows\/release\.yml/{print; exit}' "$MAN" | grep -q 'release\.yml' && ok=$((ok + 1))
assert_code 'release: the workflow exists and is declared source-only' 3 "$ok"

# Publishing must be reachable only by naming a version, never by pushing code. A branch push that
# could publish would make every merge a release.
ok=0
grep -qE "^ *tags: *\['v\*'\]" "$WF" && ok=$((ok + 1))
grep -qE '^ *branches:' "$WF" || ok=$((ok + 1))
grep -qE '^ *pull_request:' "$WF" || ok=$((ok + 1))
# -F, because the thing being looked for IS a regex: in a basic-regex search `\+` is a quantifier,
# not a plus sign, so the pattern silently fails to find the guard it is checking for.
grep -qF 'v[0-9]+\.[0-9]+\.[0-9]+' "$WF" && ok=$((ok + 1))
assert_code 'release: the workflow publishes only from a version tag' 4 "$ok"

# contents: write is the least GitHub offers for creating a release. Read-only at the top means a
# step added later cannot quietly inherit write, and no other scope may appear at all.
ok=0
grep -qE '^permissions:' "$WF" && grep -qE '^ *contents: read' "$WF" && ok=$((ok + 1))
grep -qE '^ *contents: write' "$WF" && ok=$((ok + 1))
[ "$(grep -cE '^ *(actions|packages|id-token|deployments|issues|pull-requests|security-events): ' "$WF")" -eq 0 ] && ok=$((ok + 1))
assert_code 'release: the workflow asks for no scope beyond contents' 3 "$ok"

# What it builds, what it proves, and what it uploads. A release whose checksum nobody verified is
# a checksum nobody can trust, and a remote pipe is what this repository's own hook refuses.
ok=0
grep -q 'build-artifact.sh --ref' "$WF" && ok=$((ok + 1))
grep -q 'sha256sum -c' "$WF" && ok=$((ok + 1))
grep -q 'forgeos-\$VERSION.tar.gz' "$WF" && ok=$((ok + 1))
grep -q 'forgeos-\$VERSION.tar.gz.sha256\|\$archive.sha256' "$WF" && ok=$((ok + 1))
grep -qE '(curl|wget|iwr|Invoke-WebRequest)[^|]*\|[^|]*(sh|bash|iex)' "$WF" || ok=$((ok + 1))
# Every `uses:` must be first-party. Counting both and comparing says that without a lookahead,
# which ERE does not have -- the version that tried printed its own 0 and the fallback's 1 into the
# same substitution and compared "0\n1" against "1".
[ "$(grep -cE '^ *- uses: ' "$WF")" = "$(grep -cE '^ *- uses: actions/' "$WF")" ] && ok=$((ok + 1))
assert_code 'release: the workflow builds from the ref, verifies, and uploads the artifact' 6 "$ok"

rm -f "$PROBE"

echo ''
printf 'Total: %s   Passed: %s   Failed: %s\n' "$total" "$((total - failed))" "$failed"
if [ "$failed" -gt 0 ]; then
  echo ''
  echo 'Failed cases:'
  printf '%s' "$failed_cases"
  exit 1
fi
echo 'Release self-test passed.'
exit 0
