#!/usr/bin/env bash
# Creates the project's directory structure from .ai/context/scaffold.json.
# POSIX counterpart of scaffold.ps1.
#
# The last mechanical step of discovery. Creates directories only -- never source files: a file
# with invented content is a decision nobody made, which is what discovery exists to prevent.
# Files arrive through tasks, with acceptance criteria.
#
# Refuses to run while any entry still says TBD.
#
# Usage: scaffold.sh [--apply] [--spec <path>]
# Exit: 0 success, 1 error, 2 spec not ready.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APPLY=0
SPEC="$REPO_ROOT/.ai/context/scaffold.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --spec)  SPEC="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ ! -f "$SPEC" ]; then
  echo "Scaffold spec not found: $SPEC"
  echo 'It is written at the end of discovery phase 5. Run /discovery first.'
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

read_spec() {   # read_spec <jq-filter> <python-expression>
  if command -v jq >/dev/null 2>&1; then jq -r "$1" "$SPEC" 2>/dev/null
  elif [ -n "$JSON_PY" ]; then "$JSON_PY" -c "
import json,sys
d = json.load(open(sys.argv[1]))
$2
" "$SPEC" 2>/dev/null | tr -d '\r'
  else echo "scaffold.sh requires jq or a working python3/python." >&2; exit 1; fi
}

ARCHITECTURE="$(read_spec '.architecture // ""' 'print(d.get("architecture",""))')"
GITKEEP="$(read_spec '.gitkeep // true' 'print(str(d.get("gitkeep",True)).lower())')"

entries="$(read_spec '.directories[] | [.path, .purpose] | @tsv' '
for x in d.get("directories", []):
    print("\t".join([x.get("path",""), x.get("purpose","")]))
')"

if [ -z "$entries" ]; then
  echo 'Scaffold spec declares no directories. Nothing to do.'
  exit 2
fi

# --- Readiness ---------------------------------------------------------------------------------

unresolved=''
printf '%s' "$ARCHITECTURE" | grep -qiE '\bTBD\b' && unresolved="${unresolved}  - architecture: ${ARCHITECTURE}"$'\n'

while IFS=$'\t' read -r p purpose; do
  [ -z "$p" ] && continue
  printf '%s' "$p"       | grep -qiE '\bTBD\b' && unresolved="${unresolved}  - path: ${p}"$'\n'
  printf '%s' "$purpose" | grep -qiE '\bTBD\b' && unresolved="${unresolved}  - purpose of '${p}': ${purpose}"$'\n'
done <<< "$entries"

if [ -n "$unresolved" ]; then
  echo "Scaffold spec is NOT ready: $SPEC"
  echo ''
  printf '%s' "$unresolved"
  echo ''
  echo 'Discovery phase 5 has not produced a real structure yet. Complete it first;'
  echo 'a directory tree built from an unfinished architecture is worse than none.'
  exit 2
fi

# --- Validate ----------------------------------------------------------------------------------

rejected=''
to_create=(); to_create_purpose=(); already=()

while IFS=$'\t' read -r p purpose; do
  [ -z "$p" ] && continue
  rel="$(printf '%s' "$p" | tr '\\' '/' | sed -e 's#^/*##' -e 's#/*$##')"

  if [ -z "$rel" ]; then rejected="${rejected}  ! empty path"$'\n'; continue; fi
  case "$rel" in
    ../*|*/../*|*/..) rejected="${rejected}  ! ${rel}  (escapes the repository)"$'\n'; continue ;;
    /*)               rejected="${rejected}  ! ${rel}  (absolute path)"$'\n'; continue ;;
    .ai|.ai/*|.claude|.claude/*|.git|.git/*|scripts|scripts/*|templates|templates/*|examples|examples/*)
                      rejected="${rejected}  ! ${rel}  (reserved by the blueprint)"$'\n'; continue ;;
  esac

  if [ -d "$REPO_ROOT/$rel" ]; then
    already+=("$rel")
  else
    to_create+=("$rel"); to_create_purpose+=("$purpose")
  fi
done <<< "$entries"

if [ -n "$rejected" ]; then
  echo 'Rejected entries:'
  printf '%s' "$rejected"
  echo ''
  echo 'Fix them in the spec. Nothing was created.'
  exit 1
fi

# --- Report ------------------------------------------------------------------------------------

MODE='DRY RUN -- nothing will be created'
[ "$APPLY" -eq 1 ] && MODE='APPLY'

echo ''
echo "Scaffold  [$MODE]"
printf '  architecture   %s\n' "$ARCHITECTURE"
printf '  spec           %s\n' "${SPEC#"$REPO_ROOT"/}"
echo ''
printf '  to create      %s\n' "${#to_create[@]}"
printf '  already exist  %s\n' "${#already[@]}"

if [ "${#to_create[@]}" -gt 0 ]; then
  echo ''
  for i in "${!to_create[@]}"; do printf '    + %-40s %s\n' "${to_create[$i]}" "${to_create_purpose[$i]}"; done
fi
if [ "${#already[@]}" -gt 0 ]; then
  echo ''
  for d in "${already[@]}"; do printf '    = %-40s (exists, untouched)\n' "$d"; done
fi

if [ "$APPLY" -eq 0 ]; then
  echo ''
  echo 'Dry run complete. Re-run with --apply to create these directories.'
  exit 0
fi

# --- Apply -------------------------------------------------------------------------------------

created=0
for i in "${!to_create[@]}"; do
  full="$REPO_ROOT/${to_create[$i]}"
  mkdir -p "$full"
  created=$((created + 1))
  if [ "$GITKEEP" = "true" ] && [ ! -f "$full/.gitkeep" ]; then
    {
      echo '# Keeps this directory tracked by Git until it holds real files.'
      printf '# Purpose: %s\n' "${to_create_purpose[$i]}"
    } > "$full/.gitkeep"
  fi
done

echo ''
printf 'Created %s directory(ies).\n' "$created"
echo ''
echo 'Next, and not optional:'
echo '  1. Fill .ai/context/structure.md from what now exists.'
echo '  2. Write the initial backlog into .ai/tasks/inbox/, each task independently shippable.'
echo '  3. No source file is created by this script. Files arrive through tasks, with criteria.'
exit 0
