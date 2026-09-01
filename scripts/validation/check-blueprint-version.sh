#!/usr/bin/env bash
# Reports which blueprint version this repository carries, and which synced files have drifted.
# POSIX counterpart of check-blueprint-version.ps1.
#
# Needs no access to the source blueprint: it compares the hashes recorded in blueprint.version
# against the files on disk. A local edit is not a failure -- it is a fact the next sync must
# know, because sync-blueprint skips locally modified files rather than overwriting them.
#
# Usage: check-blueprint-version.sh [--fail-on-drift]

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/lib/blueprint-manifest.json"

FAIL_ON_DRIFT=0
[ "${1:-}" = "--fail-on-drift" ] && FAIL_ON_DRIFT=1

[ -f "$MANIFEST" ] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }

# Capability, not presence: on Windows/Git Bash a Microsoft Store python3 stub sits on PATH and
# cannot run anything, so probe with a real parse -- and try python before giving up. Probed only
# when jq is absent, so the common path pays nothing.
JSON_PY=''
if ! command -v jq >/dev/null 2>&1; then
  for _py in python3 python; do
    if command -v "$_py" >/dev/null 2>&1 && "$_py" -c 'import json' >/dev/null 2>&1; then
      JSON_PY="$_py"
      break
    fi
  done
fi

read_json() {   # read_json <file> <jq-filter> <python-expression>
  if command -v jq >/dev/null 2>&1; then jq -r "$2" "$1" 2>/dev/null
  elif [ -n "$JSON_PY" ]; then "$JSON_PY" -c "
import json,sys
d = json.load(open(sys.argv[1]))
$3
" "$1" 2>/dev/null | tr -d '\r'
  else echo "check-blueprint-version.sh requires jq or a working python3/python." >&2; exit 1; fi
}

VERSION_FILE="$(read_json "$MANIFEST" '.distribution.versionFile' 'print(d["distribution"]["versionFile"])')"

# read_json runs inside a command substitution, so its `exit 1` ends that subshell only. This check
# fails closed either way, but it would report a missing version file rather than an unreadable
# manifest. Name the real cause.
if [ -z "$VERSION_FILE" ]; then
  echo "Cannot read blueprint manifest. Install jq or python3." >&2
  echo "  manifest : $MANIFEST" >&2
  echo "  jq       : $(command -v jq || echo MISSING)" >&2
  echo "  python3  : $(command -v python3 || echo MISSING)" >&2
  exit 1
fi

VERSION_PATH="$REPO_ROOT/$VERSION_FILE"

if [ ! -f "$VERSION_PATH" ]; then
  echo 'Blueprint version check FAILED'
  echo "  $VERSION_FILE is missing."
  echo ''
  echo 'Without it, this repository cannot say which blueprint it carries, and'
  echo 'sync-blueprint cannot tell a local customization from an upstream change.'
  exit 1
fi

VERSION="$(read_json "$VERSION_PATH" '.version // "unknown"' 'print(d.get("version","unknown"))')"
ROLE="$(read_json "$VERSION_PATH" '.role // "unknown"' 'print(d.get("role","unknown"))')"

if [ -z "$VERSION" ]; then
  echo 'Blueprint version check FAILED'
  echo "  $VERSION_FILE is not valid JSON."
  exit 1
fi

echo 'Blueprint version'
printf '  version   %s\n' "$VERSION"
printf '  role      %s\n' "$ROLE"

SYNCED_AT="$(read_json "$VERSION_PATH" '.syncedAt // empty' 'print(d.get("syncedAt",""))')"
SOURCE="$(read_json "$VERSION_PATH" '.source // empty' 'print(d.get("source",""))')"
RELEASED="$(read_json "$VERSION_PATH" '.releasedAt // empty' 'print(d.get("releasedAt",""))')"
[ -n "$SYNCED_AT" ] && printf '  synced    %s  from  %s\n' "$SYNCED_AT" "$SOURCE"
[ -n "$RELEASED" ] && printf '  released  %s\n' "$RELEASED"

if [ "$ROLE" = "source" ]; then
  echo ''
  echo 'This is the source blueprint. Nothing to compare against.'
  exit 0
fi

entries="$(
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.files // {}) | to_entries[] | [.key, .value] | @tsv' "$VERSION_PATH" 2>/dev/null
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c '
import json,sys
for k,v in json.load(open(sys.argv[1])).get("files",{}).items(): print(k+"\t"+v)
' "$VERSION_PATH" 2>/dev/null | tr -d '\r'
  fi
)"

if [ -z "$entries" ]; then
  echo ''
  echo "No file hashes recorded in $VERSION_FILE. Drift cannot be detected."
  echo 'Re-run scripts/blueprint/sync-blueprint.sh --apply to record them.'
  exit 1
fi

drifted=''; missing=''; intact=0

while IFS=$'\t' read -r rel expected; do
  [ -z "$rel" ] && continue
  file="$REPO_ROOT/$rel"
  if [ ! -f "$file" ]; then missing="${missing}    - ${rel}"$'\n'; continue; fi
  actual="$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)"
  if [ "$actual" != "$expected" ]; then drifted="${drifted}    ! ${rel}"$'\n'; else intact=$((intact + 1)); fi
done <<< "$entries"

drift_count=0; missing_count=0
[ -n "$drifted" ] && drift_count="$(printf '%s' "$drifted" | grep -c '')"
[ -n "$missing" ] && missing_count="$(printf '%s' "$missing" | grep -c '')"

echo ''
printf '  intact             %s\n' "$intact"
printf '  locally modified   %s\n' "$drift_count"
printf '  missing            %s\n' "$missing_count"

if [ -n "$drifted" ]; then
  echo ''
  echo '  LOCALLY MODIFIED since the last sync:'
  printf '%s' "$drifted" | sort
  echo ''
  echo '  sync-blueprint will skip these rather than overwrite them. That is deliberate.'
  echo '  If a change here is generally useful, contribute it back to the source blueprint'
  echo '  instead of maintaining a fork of it in this project.'
fi

if [ -n "$missing" ]; then
  echo ''
  echo '  MISSING (recorded but no longer present):'
  printf '%s' "$missing" | sort
fi

if [ "$FAIL_ON_DRIFT" -eq 1 ] && { [ "$drift_count" -gt 0 ] || [ "$missing_count" -gt 0 ]; }; then
  echo ''
  echo 'FAILED: --fail-on-drift was requested and the synced set has drifted.'
  exit 1
fi

exit 0
