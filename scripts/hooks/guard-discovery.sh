#!/usr/bin/env bash
# Claude Code PreToolUse hook for Write, Edit, and NotebookEdit. Blocks code changes while the
# project is still undefined. POSIX counterpart of guard-discovery.ps1.
#
# .ai/contract/core.md section 0 and .ai/contract/discovery.md section 1 state the rule: a project
# whose always-loaded context still carries blocking TBD markers is undefined, and the only
# permitted activity is the discovery interview. Until now that rule was prose, and prose does not
# stop a write.
#
# Allowed while undefined: everything discovery and adoption legitimately write -- .ai/, docs/, and
# the blueprint's own surfaces. Blocked: everything else, which is where a project's source,
# manifests, and scaffolding would land.
#
# Blocking targets come from placeholderScan in the manifest, so "what counts as undefined" has one
# home shared with check-placeholders. Only the word markers are counted, not the bracketed
# prompts: .ai/context is written entirely in the TBD style, so markers alone answer the question,
# and duplicating the bracket regex here would create a second home for the trickiest pattern in
# the repository.
#
# Exit 2 blocks the write. Exit 0 allows it.
#
# Fails OPEN when the manifest cannot be read -- deliberate, and consistent with _json.sh: a hook
# is a safety net, not a security boundary, and a hook that blocks every write on a machine with no
# JSON parser is a hook that gets switched off. The fail-CLOSED half of this control is
# check-placeholders --fail-on-blocking, which since 1.7.2 refuses to report a clean result it did
# not compute.

set -uo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_json.sh
. "$HOOK_DIR/_json.sh"

payload="$(cat)"
file_path="$(json_field "$payload" tool_input file_path)"
[ -z "$file_path" ] && exit 0

# Project root: the harness sets CLAUDE_PROJECT_DIR; fall back to this script's repository.
project_root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$project_root" ] || [ ! -d "$project_root" ]; then
  project_root="$(cd "$HOOK_DIR/../.." && pwd)"
else
  project_root="$(cd "$project_root" && pwd)"
fi

MANIFEST="$project_root/scripts/lib/blueprint-manifest.json"

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

read_gate() {   # read_gate <jq-filter> <python-expression-over-d>
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$MANIFEST" 2>/dev/null
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c "
import json,sys
d = json.load(open(sys.argv[1]))
$2
" "$MANIFEST" 2>/dev/null | tr -d '\r'
  fi
}

fail_open() {
  echo "guard-discovery: manifest unreadable, allowing the write. Run check-placeholders --fail-on-blocking to check the gate properly." >&2
  exit 0
}

[ -f "$MANIFEST" ] || fail_open

mapfile -t ALLOW_PREFIX < <(read_gate '.policy.discoveryGate.allowedPrefixes[]?' \
  'print("\n".join(d["policy"]["discoveryGate"]["allowedPrefixes"]))')
mapfile -t ALLOW_FILES  < <(read_gate '.policy.discoveryGate.allowedFiles[]?' \
  'print("\n".join(d["policy"]["discoveryGate"]["allowedFiles"]))')
mapfile -t MARKERS      < <(read_gate '.placeholderScan.markers[]?' \
  'print("\n".join(d["placeholderScan"]["markers"]))')
mapfile -t BLOCKING     < <(read_gate '[.placeholderScan.targets[] | select(.weight=="blocking") | .path][]' \
  'print("\n".join(t["path"] for t in d["placeholderScan"]["targets"] if t["weight"]=="blocking"))')

if [ "${#ALLOW_PREFIX[@]}" -eq 0 ] || [ "${#MARKERS[@]}" -eq 0 ] || [ "${#BLOCKING[@]}" -eq 0 ]; then
  fail_open
fi

# Relative path, forward slashes. A file outside the project is not this gate's business.
case "$file_path" in
  /*|[A-Za-z]:[\\/]*) full="$file_path" ;;
  *)                  full="$project_root/$file_path" ;;
esac
full="$(printf '%s' "$full" | tr '\\' '/')"
root_slash="$(printf '%s' "$project_root" | tr '\\' '/')"

case "$full" in
  "$root_slash"/*) relative="${full#"$root_slash"/}" ;;
  *)               exit 0 ;;
esac
[ -z "$relative" ] && exit 0

for f in ${ALLOW_FILES[@]+"${ALLOW_FILES[@]}"}; do
  [ "$relative" = "$f" ] && exit 0
done
for p in "${ALLOW_PREFIX[@]}"; do
  case "$relative" in "$p"*) exit 0 ;; esac
done

# Count blocking markers in always-loaded context -- with EXACTLY the rules check-placeholders uses,
# because the reporter and the enforcer must agree on what "undefined" means. They did not: this
# hook counted every marker on every line while the checker skipped fenced code blocks and, since
# v1.11.0, inline code spans too. A real adoption then saw check-placeholders report zero blocking
# and this hook still refuse src/ -- the reporter said defined, the enforcer disagreed.
#
# Three rules, shared: skip fenced blocks, strip `inline code` before matching, whole words only.
# awk strips, grep -E matches -- never awk alone, because mawk (default on Debian/Ubuntu) cannot
# parse \b and would count nothing, reading an undefined project as defined.
# Sharing the RULES was not enough; the answer is to share the DETECTOR. This hook used to count
# markers itself, copying three rules from check-placeholders -- and it still counted something
# different, because the checker also treats bracketed prompts like [the project name] as
# placeholders and this hook never did. A project whose context was written entirely in bracket
# style therefore opened the gate while the checker called it blocking: reporter and enforcer
# disagreeing again, one layer down from the last time (open question 013).
#
# So ask the checker instead of imitating it. It owns the grammar -- markers, brackets, fenced
# blocks, inline spans, and the ubuntu grep limits its patterns are written around -- and there is
# now exactly one place where "undefined" is defined. The cost lands only here: every permitted
# prefix returned above, so this runs only when something wants to write code.
#
# The PROJECT's checker, not this repository's: check-placeholders resolves its scan root from its
# own location, so the copy that ships with the project under audit is the only one that can answer
# for it. Every adopting project has one -- it is portable.
CHECKER="$project_root/scripts/validation/check-placeholders.sh"
if [ ! -f "$CHECKER" ]; then
  cat >&2 <<EOF
BLOCKED by the discovery gate (scripts/hooks/guard-discovery.sh).

File    : $relative
Reason  : the gate cannot confirm this project is defined. Its placeholder checker is missing:
          $CHECKER

This refuses rather than allows: a gate that cannot see is not a gate. Restore the file from the
blueprint, or run a sync, then try again.
EOF
  exit 2
fi

checker_out="$(bash "$CHECKER" --fail-on-blocking 2>/dev/null)"
checker_code=$?
[ "$checker_code" -eq 0 ] && exit 0

blocking_count="$(printf '%s' "$checker_out" | grep -oE '\(blocking: [0-9]+\)' | grep -oE '[0-9]+' | head -1)"
if [ -z "$blocking_count" ]; then
  cat >&2 <<EOF
BLOCKED by the discovery gate (scripts/hooks/guard-discovery.sh).

File    : $relative
Reason  : the gate cannot confirm this project is defined. check-placeholders exited $checker_code
          without reporting a blocking count.

Run it directly to see why:
  bash scripts/validation/check-placeholders.sh --fail-on-blocking
EOF
  exit 2
fi

cat >&2 <<EOF
BLOCKED by the discovery gate (scripts/hooks/guard-discovery.sh).

File    : $relative
Reason  : this project is still undefined. $blocking_count blocking marker(s) remain in
          $(printf '%s, ' "${BLOCKING[@]}" | sed 's/, $//').

.ai/contract/core.md section 0: in an undefined project the only permitted activity is the
discovery interview. No code, no scaffolding, no dependency, no technology choice -- regardless
of what was asked, and not overridable by a request to "just start".

Permitted right now: ${ALLOW_PREFIX[*]}

Do this instead:
  1. Run the discovery interview -- .ai/contract/discovery.md, six phases, in order.
  2. Write each phase's answers to the document that phase owns.
  3. Confirm with check-placeholders --fail-on-blocking. Zero blocking markers opens the gate.

If the user insists on code first, say what is still undefined and ask the next question.
A starting point built on invented requirements is the most expensive artifact in software.
EOF
exit 2
