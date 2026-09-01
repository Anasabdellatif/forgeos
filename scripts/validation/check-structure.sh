#!/usr/bin/env bash
# Verifies that every required blueprint directory and file exists and is non-empty.
# POSIX counterpart of check-structure.ps1. Both read scripts/lib/blueprint-manifest.json,
# so the required-path list is declared once, as data.
#
# Usage: check-structure.sh [--quiet]
# Exit 0 when the structure is intact, 1 otherwise.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/lib/blueprint-manifest.json"

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

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

# Emits the entries of a top-level manifest array, one per line.
manifest_array() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k][]' "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c 'import json,sys; print(chr(10).join(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$MANIFEST" "$key" | tr -d '\r'
  else
    echo "check-structure.sh requires jq or a working python3/python to read the manifest." >&2
    exit 1
  fi
}

mapfile -t REQUIRED_DIRS  < <(manifest_array requiredDirectories)
mapfile -t REQUIRED_FILES < <(manifest_array requiredFiles)

# manifest_array runs inside a process substitution, so its `exit 1` ends that subshell and
# nothing else. An unread manifest therefore yields no paths, no failures, and the sentence
# "Structure validation passed (0 paths verified)" -- a false all-clear, which is worse than no
# check at all. Verify the read produced something before trusting a clean result.
if [ "${#REQUIRED_DIRS[@]}" -eq 0 ] || [ "${#REQUIRED_FILES[@]}" -eq 0 ]; then
  echo "Cannot read blueprint manifest. Install jq or python3." >&2
  echo "  manifest : $MANIFEST" >&2
  echo "  jq       : $(command -v jq || echo MISSING)" >&2
  echo "  python3  : $(command -v python3 || echo MISSING)" >&2
  exit 1
fi


# A source-only path exists in the source repository and NOWHERE ELSE -- that is what the
# classification means. Requiring it everywhere made check-structure fail in every project that
# adopted v1.15.0 or later: five release-tooling files declared required, correctly never copied,
# and reported missing. Read the role and require them only where they belong. In an adopted
# project their PRESENCE would be the finding, and check-policy is where that is asserted.
ROLE=''
[ -f "$REPO_ROOT/blueprint.version" ] &&
  ROLE="$(grep -m1 '"role"' "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
# manifest_array reads top-level keys only, and a nested key would have returned nothing at all --
# an empty list, a skip that never fires, and a fix that looks applied. Read it explicitly.
source_only_array() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.distribution.sourceOnly[]?' "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c 'import json,sys; d = json.load(open(sys.argv[1])); print(chr(10).join(d.get("distribution",{}).get("sourceOnly",[])))' "$MANIFEST" | tr -d '\r'
  fi
}
mapfile -t SRC_ONLY < <(source_only_array)

is_source_only() {
  local rel="$1" p
  for p in ${SRC_ONLY[@]+"${SRC_ONLY[@]}"}; do
    [ -z "$p" ] && continue
    [ "$rel" = "$p" ] && return 0
    case "$rel" in "$p"/*) return 0 ;; esac
  done
  return 1
}

failures=()
ok_count=0

for rel in "${REQUIRED_DIRS[@]}"; do
  [ -z "$rel" ] && continue
  if [ -d "$REPO_ROOT/$rel" ]; then
    ok_count=$((ok_count + 1))
    [ "$QUIET" -eq 0 ] && printf 'OK  dir   %s\n' "$rel"
  else
    failures+=("Missing directory: $rel")
  fi
done

for rel in "${REQUIRED_FILES[@]}"; do
  [ -z "$rel" ] && continue
  if [ "$ROLE" != "source" ] && is_source_only "$rel"; then continue; fi
  if [ ! -f "$REPO_ROOT/$rel" ]; then
    failures+=("Missing file: $rel")
  elif [ ! -s "$REPO_ROOT/$rel" ]; then
    failures+=("Empty file: $rel")
  else
    ok_count=$((ok_count + 1))
    [ "$QUIET" -eq 0 ] && printf 'OK  file  %s\n' "$rel"
  fi
done

# Orphan detection: a required-looking path that exists but is nothing in the manifest declares.
# The PowerShell half has reported these since it was written; this half never did, so a POSIX-only
# run -- which is what CI runs twice and what anyone maintaining from Linux runs -- could not see an
# undeclared file at all (open question 008). Same roots, same extensions, same exclusions, and the
# same non-gating verdict: reported, counted in the summary line, never a failure. Raising it to a
# failure here would gate on POSIX something Windows only reports, which is a different change.
declared_list="$(printf '%s\n' ${REQUIRED_FILES[@]+"${REQUIRED_FILES[@]}"})"
undeclared=()
for scan_root in .ai .claude scripts templates examples; do
  [ -d "$REPO_ROOT/$scan_root" ] || continue
  while IFS= read -r found; do
    [ -z "$found" ] && continue
    rel="${found#"$REPO_ROOT/"}"
    case "$rel" in
      */tasks/inbox/*|*/tasks/active/*|*/tasks/completed/*|*/tasks/abandoned/*) continue ;;
      */plans/inbox/*|*/plans/active/*|*/plans/completed/*|*/plans/abandoned/*) continue ;;
    esac
    case "$rel" in
      */memory/decisions/*|*/memory/lessons/*|*/memory/incidents/*|*/memory/handoffs/*)
        case "$rel" in */README.md) ;; *) continue ;; esac ;;
    esac
    printf '%s\n' "$declared_list" | grep -qxF "$rel" || undeclared+=("$rel")
  done < <(find "$REPO_ROOT/$scan_root" -type f \( -name '*.md' -o -name '*.ps1' -o -name '*.sh' -o -name '*.json' \) 2>/dev/null)
done

echo ''
if [ "${#undeclared[@]}" -gt 0 ]; then
  echo 'Undeclared files (exist but not in the manifest -- add them or remove them):'
  printf '%s\n' "${undeclared[@]}" | sort | sed 's/^/  ? /'
  echo ''
fi

if [ "${#failures[@]}" -gt 0 ]; then
  printf 'Structure validation FAILED  (%s ok, %s failed)\n' "$ok_count" "${#failures[@]}"
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi

printf 'Structure validation passed  (%s paths verified, %s undeclared)\n' "$ok_count" "${#undeclared[@]}"
exit 0
