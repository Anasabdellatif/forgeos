#!/usr/bin/env bash
# Claude Code PreToolUse hook for Write, Edit, and NotebookEdit. Blocks writes to protected
# application paths until the project has explicitly authorized code. POSIX counterpart of
# guard-governance.ps1.
#
# This is NOT the discovery gate. Discovery asks "is the project defined?" and answers it from TBD
# markers in always-loaded context. That gate opens the moment the documents are filled -- and then
# nothing stood between a defined project and its first source file, even when the humans running
# it had three open decision gates and had authorized no code at all. A real adoption stayed safe
# only because a stray TBD in a documentation sentence kept discovery shut by accident. Protection
# by accident is not protection.
#
# This hook reads the project's own governance file, .ai/context/governance.json:
#   codeAuthorized  false until a human flips it. There is no default that opens it.
#   blockedUntil    the named gates still open -- printed so the agent can say which one.
#   protectedPaths  globs for application code, manifests, migrations, infrastructure.
#   decidedIn       where the authorization is recorded when it happens.
#   implementationWindow
#                   optional and closed by default: { active, allowedPaths, decidedIn }. While the
#                   project stays closed, an ACTIVE window makes only the paths it lists writable
#                   -- one approved slice, not the project.
#
# Exit 2 blocks the write. Exit 0 allows it.
#
# Missing governance file = not governed (the file is seeded into every adopted project, so absence
# means a project that predates this hook). An UNREADABLE file fails CLOSED for protected paths: a
# corrupted gate must not read as an open one.

set -uo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_json.sh
. "$HOOK_DIR/_json.sh"

payload="$(cat)"
file_path="$(json_field "$payload" tool_input file_path)"
[ -z "$file_path" ] && exit 0

project_root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$project_root" ] || [ ! -d "$project_root" ]; then
  project_root="$(cd "$HOOK_DIR/../.." && pwd)"
else
  project_root="$(cd "$project_root" && pwd)"
fi

GOV="$project_root/.ai/context/governance.json"
[ -f "$GOV" ] || exit 0

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

gov_read() {   # gov_read <jq-filter> <python-expression over d>
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$GOV" 2>/dev/null
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c "
import json,sys
d = json.load(open(sys.argv[1]))
$2
" "$GOV" 2>/dev/null | tr -d '\r'
  fi
}

readable=1
authorized="$(gov_read '.codeAuthorized' 'print(str(d.get("codeAuthorized", "")).lower())')"
case "$authorized" in true|false) ;; *) readable=0 ;; esac

mapfile -t PATTERNS < <(gov_read '.protectedPaths[]?' 'print("\n".join(d.get("protectedPaths", [])))')
if [ "$readable" -eq 0 ] || [ "${#PATTERNS[@]}" -eq 0 ]; then
  # Corrupted or empty: decide with the template defaults, closed being the safe direction.
  TPL="$project_root/templates/governance-template.json"
  if [ -f "$TPL" ]; then
    if command -v jq >/dev/null 2>&1; then
      mapfile -t PATTERNS < <(jq -r '.protectedPaths[]?' "$TPL" 2>/dev/null)
    elif [ -n "$JSON_PY" ]; then
      mapfile -t PATTERNS < <("$JSON_PY" -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1])).get("protectedPaths", [])))' "$TPL" 2>/dev/null | tr -d '\r')
    fi
  fi
  [ "${#PATTERNS[@]}" -eq 0 ] && PATTERNS=('src/**' 'app/**' 'migrations/**' 'package.json')
fi

# Glob match via bash extglob-free expansion: ** crosses directories, * stays within a segment.
glob_match() {   # glob_match <glob> <path>
  local g="$1" p="$2" re
  re="$(printf '%s' "$g" | sed -e 's/[.+^$(){}|]/\\&/g' -e 's#\*\*/#\x01#g' -e 's/\*\*/\x02/g' -e 's/\*/[^\/]*/g' -e 's/?/[^\/]/g' -e 's#\x01#(.*/)?#g' -e 's/\x02/.*/g')"
  [[ "$p" =~ ^${re}$ ]]
}

protected=0
for g in "${PATTERNS[@]}"; do
  [ -z "$g" ] && continue
  if glob_match "$g" "$relative"; then protected=1; break; fi
done
[ "$protected" -eq 0 ] && exit 0

[ "$readable" -eq 1 ] && [ "$authorized" = "true" ] && exit 0

# A narrow implementation window. The project stays closed -- codeAuthorized is still false -- while
# ONE approved slice becomes writable, because the first implementation of anything is a migration
# or a scaffold, and opening the whole project to write it authorizes everything nobody reviewed.
#
# Every condition fails closed. The file must be readable (a corrupted gate can never open a
# window), active must read exactly "true", and allowedPaths must actually match this file: an
# active window with an empty list opens nothing, and so does one whose globs match nothing.
# A window narrows permission. It is not a bypass, and it does not authorize the project.
window_active=0
WINDOW_PATHS=()
if [ "$readable" -eq 1 ]; then
  win_flag="$(gov_read '.implementationWindow.active // empty' \
    'print(str(d.get("implementationWindow", {}).get("active", "")).lower())')"
  # Lowered string on both sides so a JSON boolean and the string "true" agree with the PowerShell
  # twin. Anything else -- null, 1, "yes" -- leaves the window shut.
  if [ "$win_flag" = "true" ]; then
    window_active=1
    # A JSON array or nothing: jq's [] filter yields nothing for a bare string, and the Python
    # branch says so explicitly rather than joining a string into single-character globs.
    # Malformed is closed, and identically so on both shells.
    mapfile -t WINDOW_PATHS < <(gov_read '.implementationWindow.allowedPaths[]?' \
      'w = d.get("implementationWindow") or {}; p = w.get("allowedPaths"); print("\n".join(p) if isinstance(p, list) else "")')
  fi
fi

if [ "$window_active" -eq 1 ]; then
  for g in ${WINDOW_PATHS[@]+"${WINDOW_PATHS[@]}"}; do
    [ -z "$g" ] && continue
    if glob_match "$g" "$relative"; then exit 0; fi
  done
fi

gates="$(gov_read '.blockedUntil[]?' 'print("\n".join(d.get("blockedUntil", [])))')"
[ "$readable" -eq 0 ] && gates='(governance file unreadable -- treated as closed)'
where="$(gov_read '.decidedIn // empty' 'print(d.get("decidedIn", ""))')"
[ -z "$where" ] && where='.ai/memory/decisions/'

{
  echo 'BLOCKED by project governance (scripts/hooks/guard-governance.sh).'
  echo ''
  echo "File       : $relative"
  echo 'Reason     : application code is not authorized for this project yet.'
  echo '             .ai/context/governance.json says codeAuthorized: false.'
  echo ''
  echo 'Open gates :'
  printf '%s\n' "$gates" | sed 's/^/  - /'
  # Naming the open window in the refusal is the difference between "you may not write code" and
  # "you may write code, in one place, and this is not it".
  if [ "$window_active" -eq 1 ]; then
    win_where="$(gov_read '.implementationWindow.decidedIn // empty' \
      'print(d.get("implementationWindow", {}).get("decidedIn", ""))')"
    [ -z "$win_where" ] && win_where="$where"
    echo ''
    echo 'An implementation window IS open, and this file is outside it:'
    if [ "${#WINDOW_PATHS[@]}" -eq 0 ]; then
      echo '  allowed : (none listed -- an empty window opens nothing)'
    else
      printf '  allowed : %s\n' "$(printf '%s, ' "${WINDOW_PATHS[@]}" | sed 's/, $//')"
    fi
    printf '  decided : %s\n' "$win_where"
    echo 'Widen the window only by recording that decision -- never by editing the file you were refused.'
  fi
  echo ''
  echo 'This is not the discovery gate. The project may be fully defined and still not cleared to write'
  echo 'code -- alignment, review, and approval happen first, and this file records where they stand.'
  echo ''
  echo "Where it is decided : $where"
  echo 'How it opens        : a human records the decision there, then sets codeAuthorized to true in'
  echo '                      .ai/context/governance.json. Nothing else opens it, and it never opens by default.'
  echo ''
  echo 'Until then, work in .ai/, docs/, scripts/, and templates/ -- those paths are never governed here.'
} >&2
exit 2
