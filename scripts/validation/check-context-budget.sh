#!/usr/bin/env bash
# Reports the always-loaded context against its recorded budget. POSIX counterpart of
# check-context-budget.ps1.
#
# The file set and the budget are data -- policy.contextBudget in
# scripts/lib/blueprint-manifest.json -- so the meter and the contract cannot drift apart.
# Since v1.12.3 the set is split: platformFiles is the floor the blueprint imposes and a project
# cannot reduce; projectFiles is what the project owns and can trim. The project's allowance is
# derived -- the target minus the measured platform floor -- so an overrun is attributed to its
# owner: a bloated ledger is the project's to fix, a grown core.md is the blueprint's, and the
# verdict says which. Tokens are estimated as characters / charsPerToken.
#
# Informational by design: it warns, it does not gate. --fail-on-over turns either OVER verdict
# into exit 1 for projects that want the budget enforced.
#
# Usage: check-context-budget.sh [--fail-on-over]
# Exit 0 normally (including WARN and OVER); 1 with --fail-on-over when a target is exceeded,
# and 1 whenever the manifest or a budgeted file is missing -- a meter that cannot read its
# inputs must not report a clean result.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/lib/blueprint-manifest.json"

FAIL_ON_OVER=0
[ "${1:-}" = "--fail-on-over" ] && FAIL_ON_OVER=1

if [ ! -f "$MANIFEST" ]; then
  echo "Context budget check FAILED"
  echo "  Manifest not found: scripts/lib/blueprint-manifest.json"
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

# read_budget runs inside command substitutions, so an exit there ends the subshell only and the
# downstream guard would blame an incomplete contextBudget for a missing parser. Name the real
# cause up front -- a wrong diagnosis costs more than the failure it reports.
if [ -z "$JSON_PY" ] && ! command -v jq >/dev/null 2>&1; then
  echo "Context budget check FAILED"
  echo "  No JSON reader: jq is absent and neither python3 nor python can run ('import json' failed)."
  echo "  jq       : $(command -v jq || echo MISSING)"
  echo "  python3  : $(command -v python3 || echo MISSING)"
  exit 1
fi

read_budget() {   # read_budget <jq expr> <python expr>
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$MANIFEST" 2>/dev/null
  elif [ -n "$JSON_PY" ]; then
    # The manifest path travels as argv, never interpolated into Python source: under Git
    # Bash/MSYS, path translation applies to arguments, not to strings embedded in code -- and a
    # path with a quote would break the program besides. Same shape as every sibling script.
    "$JSON_PY" -c "import json,sys; d=json.load(open(sys.argv[1]))['policy']['contextBudget']; $2" "$MANIFEST" 2>/dev/null | tr -d '\r'
  else
    echo "check-context-budget.sh requires jq or a working python3/python." >&2
    exit 1
  fi
}

mapfile -t PLATFORM_FILES < <(read_budget '.policy.contextBudget.platformFiles[]?' 'print("\n".join(d["platformFiles"]))')
mapfile -t PROJECT_FILES  < <(read_budget '.policy.contextBudget.projectFiles[]?'  'print("\n".join(d["projectFiles"]))')
CHARS_PER_TOKEN="$(read_budget '.policy.contextBudget.charsPerToken // empty' 'print(d["charsPerToken"])')"
TARGET="$(read_budget '.policy.contextBudget.targetTokens // empty' 'print(d["targetTokens"])')"
WARN="$(read_budget '.policy.contextBudget.warnTokens // empty' 'print(d["warnTokens"])')"

if [ "${#PLATFORM_FILES[@]}" -eq 0 ] || [ "${#PROJECT_FILES[@]}" -eq 0 ] || \
   [ -z "$CHARS_PER_TOKEN" ] || [ -z "$TARGET" ] || [ -z "$WARN" ]; then
  echo "Context budget check FAILED"
  echo "  policy.contextBudget is missing or incomplete in the manifest."
  exit 1
fi

missing=0
platform_chars=0
project_chars=0

report_group() {   # report_group <label> <chars-var-name> <file...>
  local label="$1" var="$2"; shift 2
  echo "  $label"
  local rel full chars
  for rel in "$@"; do
    full="$REPO_ROOT/$rel"
    if [ ! -f "$full" ]; then
      printf '    %-36s MISSING\n' "$rel"
      missing=$((missing + 1))
      continue
    fi
    chars="$(wc -c < "$full" | tr -d ' ')"
    eval "$var=\$(( $var + chars ))"
    printf '    %-36s %6d chars  ~%5d tokens\n' "$rel" "$chars" "$((chars / CHARS_PER_TOKEN))"
  done
}

echo 'Context budget -- always-loaded files'
report_group 'platform (the blueprint floor -- a project cannot reduce these):' platform_chars "${PLATFORM_FILES[@]}"
report_group 'project (project-owned -- trim here when over):' project_chars "${PROJECT_FILES[@]}"

platform_tk=$((platform_chars / CHARS_PER_TOKEN))
project_tk=$((project_chars / CHARS_PER_TOKEN))
total_chars=$((platform_chars + project_chars))
total_tk=$((total_chars / CHARS_PER_TOKEN))
allow_target=$((TARGET - platform_tk))
allow_warn=$((WARN - platform_tk))

echo   '  --------------------------------------------------------------'
printf '  %-38s %6d chars  ~%5d tokens\n' 'platform subtotal' "$platform_chars" "$platform_tk"
printf '  %-38s %6d chars  ~%5d tokens\n' 'project subtotal' "$project_chars" "$project_tk"
printf '  %-38s %6d chars  ~%5d tokens\n' 'always-loaded total' "$total_chars" "$total_tk"
printf '  budget: target %s tokens, warn %s (chars/token: %s)\n' "$TARGET" "$WARN" "$CHARS_PER_TOKEN"
printf '  project allowance: ~%s tokens to target, ~%s to warn (target minus the platform floor)\n' "$allow_target" "$allow_warn"

if [ "$missing" -gt 0 ]; then
  echo "Context budget check FAILED  ($missing budgeted file(s) missing -- seed or sync the project first)"
  exit 1
fi

# Attribution order: a floor that exceeds the budget on its own is the blueprint's problem and
# must be named before any advice to trim project files -- which could not help anyway.
if [ "$platform_tk" -gt "$TARGET" ]; then
  echo "Context budget PLATFORM OVER  (the blueprint floor alone ~$platform_tk > target $TARGET -- a blueprint problem, not this project's)"
  [ "$FAIL_ON_OVER" -eq 1 ] && exit 1
elif [ "$project_tk" -gt "$allow_target" ]; then
  echo "Context budget PROJECT OVER  (project files ~$project_tk > their ~$allow_target allowance -- trim the project files listed above)"
  [ "$FAIL_ON_OVER" -eq 1 ] && exit 1
elif [ "$platform_tk" -gt "$WARN" ]; then
  echo "Context budget PLATFORM WARN  (the blueprint floor alone ~$platform_tk > warn $WARN -- the next trim is the blueprint's, not this project's)"
elif [ "$project_tk" -gt "$allow_warn" ]; then
  echo "Context budget PROJECT WARN  (project files ~$project_tk of ~$allow_target, past the ~$allow_warn warn room -- the next trim belongs to the project files)"
else
  echo "Context budget OK  (total ~$total_tk of $TARGET tokens; project ~$project_tk of ~$allow_target)"
fi
exit 0
