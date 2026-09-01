#!/usr/bin/env bash
# Reports unfilled placeholder markers, weighted by how much they degrade agent behavior.
# POSIX counterpart of check-placeholders.ps1.
#
# Usage: check-placeholders.sh [--fail-on-blocking] [--detailed]
# Exit 0 by default; 1 with --fail-on-blocking when blocking markers remain.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/lib/blueprint-manifest.json"

FAIL_ON_BLOCKING=0
DETAILED=0
for arg in "$@"; do
  case "$arg" in
    --fail-on-blocking) FAIL_ON_BLOCKING=1 ;;
    --detailed) DETAILED=1 ;;
  esac
done

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

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

read_manifest() {   # emits "path<TAB>weight<TAB>note" per target, then a marker regex line
  if command -v jq >/dev/null 2>&1; then
    jq -r '.placeholderScan.targets[] | [.path, .weight, .note] | @tsv' "$MANIFEST"
    printf 'MARKERS\t'
    jq -r '.placeholderScan.markers | join("|")' "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c '
import json,sys
d = json.load(open(sys.argv[1]))["placeholderScan"]
for t in d["targets"]:
    print("\t".join([t["path"], t["weight"], t["note"]]))
print("MARKERS\t" + "|".join(d["markers"]))
' "$MANIFEST" | tr -d '\r'
  else
    echo "check-placeholders.sh requires jq or a working python3/python to read the manifest." >&2
    exit 1
  fi
}

manifest_lines="$(read_manifest)"

# read_manifest runs inside a command substitution, so its `exit 1` ends that subshell and nothing
# else. An unread manifest therefore leaves zero scan targets, and this script reports "0 blocking"
# and "This project is fully adopted" about a project it never looked at. That answer is what the
# discovery gate in .ai/contract/core.md consults, so a false clean here opens the gate on an
# undefined project -- the single failure the gate exists to prevent.
target_count="$(printf '%s' "$manifest_lines" | grep -vc '^MARKERS' || true)"
if [ "${target_count:-0}" -eq 0 ]; then
  echo "Cannot read blueprint manifest. Install jq or python3." >&2
  echo "  manifest : $MANIFEST" >&2
  echo "  jq       : $(command -v jq || echo MISSING)" >&2
  echo "  python3  : $(command -v python3 || echo MISSING)" >&2
  exit 1
fi

marker_alternation="$(printf '%s' "$manifest_lines" | grep '^MARKERS' | cut -f2)"
[ -z "$marker_alternation" ] && marker_alternation='TBD|TODO|FIXME'
# Whole-word matching so "TBD", "TBD:", "TBD." and "TBD," all count. This pattern runs under
# grep -E, where \b is honoured. It is never handed to awk -- see the scan loop for why.
marker_pattern="\\b(${marker_alternation})\\b"

# The templates use a second convention: bracketed prompts such as [requirements and approach].
# A document written entirely in that style has zero TBD and would otherwise report as ready.
# Markdown links are excluded; fenced code blocks are skipped by the awk filter below.
# ERE has no negative lookahead, so the "not a markdown link" test is spelled as
# "followed by something that is not '(' -- or by end of line". Most placeholders sit at the
# end of a line, so omitting the '$' alternative silently misses almost all of them.
# [A-Za-z] is spelled out, not [a-z]: PowerShell's -match is case-insensitive by default and
# grep -E is case-sensitive, so [a-z] matched [Component Name] on Windows and skipped it here.
bracket_pattern='\[[A-Za-z][^]]{4,}\]([^(]|$)'

total=0
blocking=0

echo 'Blueprint adoption readiness'
echo '============================'
echo ''

while IFS=$'\t' read -r path weight note; do
  [ "$path" = "MARKERS" ] && continue
  [ -z "$path" ] && continue
  dir="$REPO_ROOT/$path"

  # A missing target is not "ready" -- it is the most unfilled a project can be. Treating it as
  # ready would let the discovery gate fail open on a brand-new project, which is the one case
  # the gate exists for.
  if [ ! -d "$dir" ]; then
    total=$((total + 1))
    [ "$weight" = "blocking" ] && blocking=$((blocking + 1))
    printf 'MISSING   [%-8s]  %-24s  directory does not exist\n' "$weight" "$path"
    printf '            %s\n' "$note"
    echo '            Run sync-blueprint to seed the project-specific scaffolding.'
    echo ''
    continue
  fi

  # Scan each file with fenced code blocks stripped, so array[index] in a sample is not
  # mistaken for an unfilled gap. awk toggles on ``` / ~~~ and suppresses everything between.
  matches=''
  while IFS= read -r -d '' mdfile; do
    # Two stages per file, each in the engine that can actually run its pattern.
    #
    # awk: skip fenced blocks and emit one record per prose line -- "file:line<TAB>prose<TAB>original"
    # -- where prose is the line with inline code spans removed. A `TBD` in backticks is a MENTION
    # of the marker, not a gap; counting it held the discovery gate closed by accident.
    #
    # grep -E: the matching. Deliberately NOT awk -- mawk, the default on Debian and Ubuntu and so
    # on every ubuntu-latest runner, supports neither \b nor the {4,} interval the bracket pattern
    # needs, and a pattern it cannot parse matches nothing. That would read a fully unfilled project
    # as ready and open the discovery gate. Measured: 59 bracket placeholders in
    # docs/architecture/overview.md under grep -E, 1 under mawk. The marker test runs against the
    # prose column, the bracket test against the original column.
    hits="$(
      awk '
        /^[[:space:]]*(```|~~~)/ { inf = !inf; next }
        inf { next }
        { prose = $0; gsub(/`[^`]*`/, "", prose); print FILENAME ":" FNR "\t" prose "\t" $0 }' "$mdfile" \
        | grep -E -- "^[^	]*	[^	]*($marker_pattern)|^[^	]*	[^	]*	.*($bracket_pattern)" \
        | awk -F'\t' '{ print $1 ":" $3 }' || true
    )"
    [ -n "$hits" ] && matches="${matches}${hits}"$'\n'
  done < <(find "$dir" -type f -name '*.md' -print0)

  matches="$(printf '%s' "$matches" | grep -v '^$' || true)"
  if [ -z "$matches" ]; then
    count=0
  else
    count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  fi

  total=$((total + count))
  [ "$weight" = "blocking" ] && blocking=$((blocking + count))

  status='READY   '
  [ "$count" -gt 0 ] && status='UNFILLED'
  printf '%s  [%-8s]  %-24s  %s marker(s)\n' "$status" "$weight" "$path" "$count"

  if [ "$count" -gt 0 ]; then
    printf '            %s\n' "$note"
    if [ "$DETAILED" -eq 1 ]; then
      printf '%s\n' "$matches" | sed "s|^$REPO_ROOT/|            |"
    else
      printf '%s\n' "$matches" | cut -d: -f1 | sort | uniq -c | sort -rn | head -n 4 \
        | sed "s|$REPO_ROOT/||" | awk '{printf "            %s  (%s)\n", $2, $1}'
    fi
    echo ''
  fi
done <<< "$manifest_lines"

echo ''
printf 'Total unfilled markers: %s   (blocking: %s)\n' "$total" "$blocking"

if [ "$total" -eq 0 ]; then
  echo 'This project is fully adopted. Every context and documentation fact is supplied.'
  exit 0
fi

echo ''
echo 'These are not defects in a fresh blueprint. They are the facts the adopting project'
echo 'must supply. Run the /adopt command, or fill them from real evidence — never by guessing.'

if [ "$FAIL_ON_BLOCKING" -eq 1 ] && [ "$blocking" -gt 0 ]; then
  echo ''
  printf 'FAILED: %s blocking marker(s) remain in always-loaded context.\n' "$blocking"
  exit 1
fi

exit 0
