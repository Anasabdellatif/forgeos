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

# --- Manifest reader resolution ---------------------------------------------------------------
# This script is the discovery gate: .ai/contract/core.md §0 reads "more than 0 blocking markers
# means discovery mode". A gate that reports 0 because it could not read its manifest fails OPEN
# -- it tells an agent discovery is complete while .ai/context/ is still nothing but TBD. That is
# the worst failure mode available to this script, so an unreadable manifest is a hard error and
# never a zero.
#
# The concrete trap: on Windows `python3` resolves to the Microsoft Store alias stub, which prints
# an install message to stdout and exits without running anything. `command -v python3` succeeds,
# so a presence check is not enough. Every candidate is probed by actually executing it and
# checking for a sentinel on stdout -- which rejects the stub without matching its (localized)
# message text, and rejects any other interpreter that cannot run the reader.

READER=''       # 'jq' or 'python' once resolved
PY_ARGV=()      # argv prefix of the working Python, e.g. (python) or (py -3)

resolve_reader() {
  if command -v jq >/dev/null 2>&1 && [ "$(jq -rn '"PROBE_OK"' 2>/dev/null)" = 'PROBE_OK' ]; then
    READER='jq'
    return 0
  fi

  local candidate cand_argv out
  for candidate in 'python3' 'python' 'py -3'; do
    read -r -a cand_argv <<< "$candidate"
    command -v "${cand_argv[0]}" >/dev/null 2>&1 || continue
    out="$("${cand_argv[@]}" -c 'import json,sys; sys.stdout.write("PROBE_OK")' 2>/dev/null)" || continue
    if [ "$out" = 'PROBE_OK' ]; then
      READER='python'
      PY_ARGV=("${cand_argv[@]}")
      return 0
    fi
  done

  return 1
}

read_manifest() {   # emits "path<TAB>weight<TAB>note" per target, then a marker regex line
  case "$READER" in
    jq)
      jq -r '.placeholderScan.targets[] | [.path, .weight, .note] | @tsv' "$MANIFEST" || return 1
      printf 'MARKERS\t'
      jq -r '.placeholderScan.markers | join("|")' "$MANIFEST" || return 1
      ;;
    python)
      "${PY_ARGV[@]}" -c '
import json,sys
d = json.load(open(sys.argv[1]))["placeholderScan"]
for t in d["targets"]:
    print("\t".join([t["path"], t["weight"], t["note"]]))
print("MARKERS\t" + "|".join(d["markers"]))
' "$MANIFEST" || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

if ! resolve_reader; then
  {
    echo 'check-placeholders.sh: no working manifest reader found.'
    echo 'Tried: jq, python3, python, py -3 -- each was absent or failed to execute.'
    echo 'On Windows, a bare "python3" is usually the Microsoft Store alias stub, which is not a'
    echo 'usable interpreter. Install jq or Python, or run check-placeholders.ps1 instead.'
    echo 'Refusing to continue: this script is the discovery gate and must not report 0 markers'
    echo 'when it cannot read its own manifest.'
  } >&2
  exit 2
fi

if ! manifest_lines="$(read_manifest)"; then
  echo "check-placeholders.sh: the $READER reader failed on $MANIFEST." >&2
  echo 'Refusing to continue rather than report an unverified 0.' >&2
  exit 2
fi

marker_alternation="$(printf '%s\n' "$manifest_lines" | grep '^MARKERS' | cut -f2)"
target_lines="$(printf '%s\n' "$manifest_lines" | grep -cv -e '^MARKERS' -e '^[[:space:]]*$')"

# The reader ran, but a reader that emits nothing (or loses the marker list) is indistinguishable
# from a fully adopted project unless the output itself is validated. So validate it, and record
# the result -- MANIFEST_READ_OK is what earns the right to report a zero later on.
MANIFEST_READ_OK=0
if [ -n "$marker_alternation" ] && [ "$target_lines" -gt 0 ]; then
  MANIFEST_READ_OK=1
else
  echo "check-placeholders.sh: $READER produced unusable manifest output" >&2
  echo "(targets: $target_lines, markers: '${marker_alternation}')." >&2
  echo 'Refusing to continue rather than report an unverified 0.' >&2
  exit 2
fi

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
targets_scanned=0

echo 'Blueprint adoption readiness'
echo '============================'
echo ''

while IFS=$'\t' read -r path weight note; do
  [ "$path" = "MARKERS" ] && continue
  [ -z "$path" ] && continue
  targets_scanned=$((targets_scanned + 1))
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

# Last guard before the one output an agent acts on. "0 blocking" is only a fact if the manifest
# was genuinely read AND targets were genuinely scanned; otherwise it is the absence of evidence,
# which must never be reported as evidence of absence.
if [ "$MANIFEST_READ_OK" -ne 1 ] || [ "$targets_scanned" -eq 0 ]; then
  echo 'check-placeholders.sh: refusing to report a marker count -- the manifest was not read' >&2
  echo "successfully or no target was scanned (read_ok=$MANIFEST_READ_OK, scanned=$targets_scanned)." >&2
  exit 2
fi

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