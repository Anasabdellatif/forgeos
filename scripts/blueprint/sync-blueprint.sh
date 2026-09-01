#!/usr/bin/env bash
# Syncs the portable part of the blueprint from a source repository into this project,
# without touching anything the project owns. POSIX counterpart of sync-blueprint.ps1.
#
# The split is declared in scripts/lib/blueprint-manifest.json under "distribution":
#   portable          .ai/contract .ai/rules .ai/skills .ai/workflows .ai/agents
#                     .claude scripts templates examples .github/workflows
#                     CLAUDE.md AGENTS.md .editorconfig
#   project-specific  .ai/context .ai/tasks .ai/plans .ai/memory docs
#                     README.md .gitignore blueprint.version
#
# Only the portable half is copied. A project's facts, work state, and history survive every
# upgrade untouched.
#
# LOCAL CUSTOMIZATION IS DETECTED, NOT DESTROYED. blueprint.version records a hash per synced
# file; a target file whose hash no longer matches was edited locally, and is skipped and
# reported rather than overwritten. Pass --force to overwrite anyway, having seen the list.
#
# Usage:
#   sync-blueprint.sh --source <blueprint-path> [--target <project-path>] [--apply] [--force]
#
# WITHOUT --apply THIS ONLY REPORTS. A tool that overwrites files must not do so by default.

set -uo pipefail

SOURCE=''
TARGET=''
APPLY=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --apply)  APPLY=1; shift ;;
    --force)  FORCE=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -z "$SOURCE" ] && { echo "--source is required." >&2; exit 1; }

SOURCE_ROOT="$(cd "$SOURCE" 2>/dev/null && pwd)" || { echo "Source not found: $SOURCE" >&2; exit 1; }
if [ -n "$TARGET" ]; then
  TARGET_ROOT="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "Target not found: $TARGET" >&2; exit 1; }
else
  TARGET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

[ "$SOURCE_ROOT" = "$TARGET_ROOT" ] && { echo "Source and target are the same repository: $SOURCE_ROOT" >&2; exit 1; }

MANIFEST="$SOURCE_ROOT/scripts/lib/blueprint-manifest.json"
[ -f "$MANIFEST" ] || { echo "Source does not look like a blueprint (no scripts/lib/blueprint-manifest.json): $SOURCE_ROOT" >&2; exit 1; }

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

cfg() {   # cfg <jq-filter> <python-expression over d = manifest["distribution"]>
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c "
import json,sys
d = json.load(open(sys.argv[1]))['distribution']
$2
" "$MANIFEST" | tr -d '\r'
  else
    echo "sync-blueprint.sh requires jq or a working python3/python." >&2; exit 1
  fi
}

VERSION_FILE="$(cfg '.distribution.versionFile' 'print(d["versionFile"])')"
mapfile -t PORTABLE_DIRS  < <(cfg '.distribution.portable[]'        'print("\n".join(d["portable"]))')
mapfile -t PORTABLE_FILES < <(cfg '.distribution.portableFiles[]'   'print("\n".join(d["portableFiles"]))')
mapfile -t PROTECTED      < <(cfg '.distribution.projectSpecific[]' 'print("\n".join(d["projectSpecific"]))')
mapfile -t SOURCE_ONLY    < <(cfg '.distribution.sourceOnly[]?'     'print("\n".join(d.get("sourceOnly",[])))')

# cfg runs inside a command or process substitution, so its `exit 1` ends that subshell only. An
# unread manifest leaves every list empty: nothing portable, nothing protected. This script fails
# closed on the next line either way, but it would blame the source repository for a missing
# parser. A sync that copies nothing must never be mistaken for a sync that had nothing to copy.
if [ -z "$VERSION_FILE" ] || [ "${#PORTABLE_DIRS[@]}" -eq 0 ] || [ "${#PROTECTED[@]}" -eq 0 ]; then
  echo "Cannot read blueprint manifest. Install jq or python3." >&2
  echo "  manifest : $MANIFEST" >&2
  echo "  jq       : $(command -v jq || echo MISSING)" >&2
  echo "  python3  : $(command -v python3 || echo MISSING)" >&2
  exit 1
fi

SRC_VERSION_PATH="$SOURCE_ROOT/$VERSION_FILE"
[ -f "$SRC_VERSION_PATH" ] || { echo "Source has no $VERSION_FILE. It cannot be identified, so it will not be synced from." >&2; exit 1; }

read_version() {   # read_version <file>
  if command -v jq >/dev/null 2>&1; then jq -r '.version // "unknown"' "$1" 2>/dev/null
  elif [ -n "$JSON_PY" ]; then "$JSON_PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","unknown"))' "$1" 2>/dev/null | tr -d '\r'
  else echo unknown; fi
}

SRC_VERSION="$(read_version "$SRC_VERSION_PATH")"
TGT_VERSION_PATH="$TARGET_ROOT/$VERSION_FILE"
TGT_VERSION='(none)'
declare -A RECORDED=()

if [ -f "$TGT_VERSION_PATH" ]; then
  TGT_VERSION="$(read_version "$TGT_VERSION_PATH")"
  while IFS=$'\t' read -r p h; do
    [ -n "$p" ] && RECORDED["$p"]="$h"
  done < <(
    if command -v jq >/dev/null 2>&1; then
      jq -r '(.files // {}) | to_entries[] | [.key, .value] | @tsv' "$TGT_VERSION_PATH" 2>/dev/null
    elif [ -n "$JSON_PY" ]; then
      "$JSON_PY" -c '
import json,sys
for k,v in json.load(open(sys.argv[1])).get("files",{}).items(): print(k+"\t"+v)
' "$TGT_VERSION_PATH" 2>/dev/null | tr -d '\r'
    fi
  )
fi

hash_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

is_protected() {
  local rel="$1" p
  for p in "${PROTECTED[@]}"; do
    [ "$rel" = "$p" ] && return 0
    case "$rel" in "$p"/*) return 0 ;; esac
  done
  return 1
}

# Source-only paths belong to the SOURCE repository's own maintenance -- release tooling, and
# later a release workflow. They sit inside a portable directory because the discovery gate
# permits writes nowhere else, so being portable is an accident of location, not an intent to
# distribute. Dropping them here is a strengthening: fewer files reach a project, never more.
# An absent or empty list changes nothing, which is what an older manifest must mean.
is_source_only() {
  local rel="$1" p
  for p in ${SOURCE_ONLY[@]+"${SOURCE_ONLY[@]}"}; do
    [ -z "$p" ] && continue
    [ "$rel" = "$p" ] && return 0
    case "$rel" in "$p"/*) return 0 ;; esac
  done
  return 1
}

# --- Enumerate the portable file set from the source -------------------------------------------

source_files=()
for dir in "${PORTABLE_DIRS[@]}"; do
  [ -d "$SOURCE_ROOT/$dir" ] || continue
  while IFS= read -r -d '' f; do
    source_files+=("${f#"$SOURCE_ROOT"/}")
  done < <(find "$SOURCE_ROOT/$dir" -type f -print0)
done
for f in "${PORTABLE_FILES[@]}"; do
  [ -f "$SOURCE_ROOT/$f" ] && source_files+=("$f")
done
mapfile -t source_files < <(printf '%s\n' "${source_files[@]}" | sort -u)

kept=()
for rel in ${source_files[@]+"${source_files[@]}"}; do
  is_source_only "$rel" && continue
  kept+=("$rel")
done
source_files=(${kept[@]+"${kept[@]}"})

# --- Classify ----------------------------------------------------------------------------------

new=(); updated=(); unchanged=(); localmods=(); preexisting=(); protected_skipped=()

for rel in "${source_files[@]}"; do
  if is_protected "$rel"; then protected_skipped+=("$rel"); continue; fi

  src="$SOURCE_ROOT/$rel"; dst="$TARGET_ROOT/$rel"
  src_hash="$(hash_of "$src")"

  if [ ! -f "$dst" ]; then new+=("$rel"); continue; fi

  dst_hash="$(hash_of "$dst")"
  if [ "$dst_hash" = "$src_hash" ]; then unchanged+=("$rel"); continue; fi

  # Target differs from source. Three possibilities, only one safe to overwrite.
  if [ -z "${RECORDED[$rel]:-}" ]; then
    # Never placed here by sync, yet it exists and differs. It is the project's own file.
    # Overwriting it would destroy work sync did not create.
    preexisting+=("$rel")
  elif [ "${RECORDED[$rel]}" != "$dst_hash" ]; then
    # Sync placed it, the project edited it since. A deliberate customization.
    localmods+=("$rel")
  else
    # Sync placed it, the project left it alone, the blueprint moved on. Safe to update.
    updated+=("$rel")
  fi
done

removed=()
for rel in "${!RECORDED[@]}"; do
  found=0
  for s in "${source_files[@]}"; do [ "$s" = "$rel" ] && { found=1; break; }; done
  [ "$found" -eq 0 ] && removed+=("$rel")
done

# --- Report ------------------------------------------------------------------------------------

MODE='DRY RUN -- nothing will be written'
[ "$APPLY" -eq 1 ] && MODE='APPLY'

echo ''
echo "Blueprint sync  [$MODE]"
printf '  source   %s  (v%s)\n' "$SOURCE_ROOT" "$SRC_VERSION"
printf '  target   %s  (v%s)\n' "$TARGET_ROOT" "$TGT_VERSION"
echo ''
printf '  new                %s\n' "${#new[@]}"
printf '  updated            %s\n' "${#updated[@]}"
printf '  unchanged          %s\n' "${#unchanged[@]}"
printf '  pre-existing       %s   <- YOUR files, never placed by sync; skipped unless --force\n' "${#preexisting[@]}"
printf '  locally modified   %s   <- skipped unless --force\n' "${#localmods[@]}"
printf '  removed in source  %s   <- not deleted; remove by hand if intended\n' "${#removed[@]}"
printf '  project-owned      %s   <- never touched\n' "${#protected_skipped[@]}"

[ "${#new[@]}" -gt 0 ]     && { echo ''; echo '  NEW:';     printf '    + %s\n' "${new[@]}"; }
[ "${#updated[@]}" -gt 0 ] && { echo ''; echo '  UPDATED:'; printf '    ~ %s\n' "${updated[@]}"; }
if [ "${#preexisting[@]}" -gt 0 ]; then
  echo ''
  echo '  PRE-EXISTING (already in this project before the blueprint arrived):'
  printf '    # %s\n' "${preexisting[@]}"
  echo ''
  echo '  Sync did not put these here and will not overwrite them. They may be the'
  echo "  project's own work -- an existing AGENTS.md, README, or scripts directory."
  echo '  Read each one, merge what you want from the blueprint version by hand, and'
  echo '  only then re-run with --force if you genuinely want the blueprint copy.'
fi
if [ "${#localmods[@]}" -gt 0 ]; then
  echo ''
  echo '  LOCALLY MODIFIED (your edits -- review before deciding):'
  printf '    ! %s\n' "${localmods[@]}"
  echo ''
  echo '  These differ from both the source and the version this project recorded.'
  echo '  That means the project edited them deliberately. Diff each against the source,'
  echo '  decide whether the customization still applies, then re-run with --force.'
fi
if [ "${#removed[@]}" -gt 0 ]; then
  echo ''
  echo '  REMOVED IN SOURCE (still present here):'
  printf '    - %s\n' "${removed[@]}"
fi

# --- Seeding: project-specific scaffolding, only when absent ------------------------------------
#
# A brand-new project has none of the project-specific half. Without seeding, the discovery gate
# would find no .ai/context/project.md, check-placeholders would report 0 blocking, and the gate
# would fail open on the exact case it exists for.
#
# Seeded once. An existing file is never compared, never overwritten, never reported.

mapfile -t SEED_FILES < <(cfg '.distribution.seedFiles[]?'       'print("\n".join(d.get("seedFiles", [])))')
mapfile -t SEED_DIRS  < <(cfg '.distribution.seedDirectories[]?' 'print("\n".join(d.get("seedDirectories", [])))')

# A seed target may be sourced from a template instead of the path of the same name. This
# repository fills .ai/context/project.md with the blueprint's own identity; an adopting project
# must start undefined, not inherit it. See seedTemplates in the manifest.
declare -A SEED_TEMPLATES=()
while IFS=$'\t' read -r k v; do
  [ -n "$k" ] && SEED_TEMPLATES["$k"]="$v"
done < <(cfg '(.distribution.seedTemplates // {}) | to_entries[] | [.key, .value] | @tsv' \
             'print("\n".join(k + "\t" + v for k, v in d.get("seedTemplates", {}).items()))')

seed_files=(); seed_dirs=()
for rel in ${SEED_FILES[@]+"${SEED_FILES[@]}"}; do
  [ -z "$rel" ] && continue
  # Ask whether the file this seed is COPIED FROM exists, which is the template when one is
  # mapped -- not the target path. The two are the same in a clone, so the difference was
  # invisible until a release artifact was used as the source: an artifact deliberately omits
  # every template-backed target, so this test skipped exactly the five files a new project
  # cannot start without -- identity, constraints, governance, the ledger and the register.
  seed_src="$rel"
  tpl_probe="${SEED_TEMPLATES[$rel]:-}"
  [ -n "$tpl_probe" ] && [ -f "$SOURCE_ROOT/$tpl_probe" ] && seed_src="$tpl_probe"
  [ -f "$SOURCE_ROOT/$seed_src" ] || continue
  [ -e "$TARGET_ROOT/$rel" ] && continue
  seed_files+=("$rel")
done
for rel in ${SEED_DIRS[@]+"${SEED_DIRS[@]}"}; do
  [ -z "$rel" ] && continue
  [ -d "$TARGET_ROOT/$rel" ] && continue
  seed_dirs+=("$rel")
done

if [ "${#seed_files[@]}" -gt 0 ] || [ "${#seed_dirs[@]}" -gt 0 ]; then
  echo ''
  printf '  seeded             %s file(s), %s directory(ies)   <- only because absent; never overwritten\n' "${#seed_files[@]}" "${#seed_dirs[@]}"
  if [ "${#seed_files[@]}" -gt 0 ]; then
    echo ''
    echo '  SEED (project-specific scaffolding, first time only):'
    printf '    * %s\n' "${seed_files[@]}"
  fi
  [ "${#seed_dirs[@]}" -gt 0 ] && printf '    * %s/\n' "${seed_dirs[@]}"
fi

if [ "$APPLY" -eq 0 ]; then
  echo ''
  echo 'Dry run complete. Re-run with --apply to write these changes.'
  exit 0
fi


for rel in ${seed_files[@]+"${seed_files[@]}"}; do
  mkdir -p "$(dirname "$TARGET_ROOT/$rel")"
  src_rel="$rel"
  tpl="${SEED_TEMPLATES[$rel]:-}"
  [ -n "$tpl" ] && [ -f "$SOURCE_ROOT/$tpl" ] && src_rel="$tpl"
  cp -p "$SOURCE_ROOT/$src_rel" "$TARGET_ROOT/$rel"
done

for rel in ${seed_dirs[@]+"${seed_dirs[@]}"}; do
  mkdir -p "$TARGET_ROOT/$rel"
  if [ ! -f "$TARGET_ROOT/$rel/.gitkeep" ]; then
    {
      echo '# Keeps this required directory tracked by Git until it holds records.'
      echo '# Created by sync-blueprint when this project was seeded.'
    } > "$TARGET_ROOT/$rel/.gitkeep"
  fi
done

# --- Apply -------------------------------------------------------------------------------------

to_write=(${new[@]+"${new[@]}"} ${updated[@]+"${updated[@]}"})
if [ "$FORCE" -eq 1 ]; then
  to_write+=(${localmods[@]+"${localmods[@]}"} ${preexisting[@]+"${preexisting[@]}"})
fi

written=0
for rel in ${to_write[@]+"${to_write[@]}"}; do
  is_protected "$rel" && continue   # unreachable by construction; kept as a hard stop
  mkdir -p "$(dirname "$TARGET_ROOT/$rel")"
  src_rel="$rel"
  tpl="${SEED_TEMPLATES[$rel]:-}"
  [ -n "$tpl" ] && [ -f "$SOURCE_ROOT/$tpl" ] && src_rel="$tpl"
  cp -p "$SOURCE_ROOT/$src_rel" "$TARGET_ROOT/$rel"
  written=$((written + 1))
done

# Record what this project now has, so the next sync can tell an upgrade from a customization.
#
# THE RULE: record the hash of what THIS TOOL WROTE, never the hash of what it found. The first
# version re-read every target file after apply, including the ones it had just skipped as locally
# modified -- which silently replaced the recorded blueprint hash with the hash of the user's
# customization. On the next sync recorded == target, the file classified as a plain upgrade, and
# the customization was overwritten in silence. A local change survived exactly one sync.
#
# So: a file written now records the hash it was written with. A file skipped -- locally modified,
# or pre-existing -- keeps whatever hash was recorded before, so it is still reported as modified
# next time, every time, until a human resolves it. Unchanged files are re-read only to cover a
# hash that was never stored. Pre-existing and never recorded stays unrecorded.
declare -A WRITTEN_SET=()
for rel in ${to_write[@]+"${to_write[@]}"}; do WRITTEN_SET["$rel"]=1; done
declare -A UNCHANGED_SET=()
for rel in ${unchanged[@]+"${unchanged[@]}"}; do UNCHANGED_SET["$rel"]=1; done

{
  echo '{'
  echo '  "$comment": "Written by scripts/blueprint/sync-blueprint. Do not edit by hand: the hashes are how the next sync distinguishes a blueprint upgrade from a local customization.",'
  echo '  "role": "adopted",'
  printf '  "version": "%s",\n' "$SRC_VERSION"
  printf '  "syncedAt": "%s",\n' "$(date +%Y-%m-%d)"
  printf '  "source": "%s",\n' "$SOURCE_ROOT"
  echo '  "files": {'
  first=1
  recorded_count=0
  for rel in "${source_files[@]}"; do
    is_protected "$rel" && continue
    [ -f "$TARGET_ROOT/$rel" ] || continue
    h=''
    if [ -n "${WRITTEN_SET[$rel]:-}" ]; then
      h="$(hash_of "$TARGET_ROOT/$rel")"          # written this run: record what was written
    elif [ -n "${RECORDED[$rel]:-}" ]; then
      h="${RECORDED[$rel]}"                        # skipped with a prior record: KEEP the prior record
    elif [ -n "${UNCHANGED_SET[$rel]:-}" ]; then
      h="$(hash_of "$TARGET_ROOT/$rel")"          # identical to source, never recorded: safe to record
    fi
    [ -z "$h" ] && continue                        # pre-existing, never recorded: stays unrecorded
    [ "$first" -eq 0 ] && echo ','
    first=0
    printf '    "%s": "%s"' "$rel" "$h"
    recorded_count=$((recorded_count + 1))
  done
  echo ''
  echo '  }'
  echo '}'
} > "$TGT_VERSION_PATH"

echo ''
printf 'Applied. %s file(s) written, recorded in %s.\n' "$written" "$VERSION_FILE"
[ "${#localmods[@]}" -gt 0 ] && [ "$FORCE" -eq 0 ] && printf '%s locally modified file(s) were left alone.\n' "${#localmods[@]}"
echo ''
# The secret scan reads the git-tracked tree, so validation cannot pass in a folder that is not a
# repository yet. Say it here, at the moment it becomes true, rather than letting the next command
# fail and leave the reason to be guessed.
if [ ! -e "$TARGET_ROOT/.git" ]; then
  echo 'This target is not a git repository yet. Validation scans the git-tracked tree, so run first:'
  echo '  git init -b main'
  echo '  git add -A'
  echo ''
fi
echo 'Now run the validation suite. A sync that leaves the project failing its own checks is not done:'
echo '  bash scripts/validation/check-all.sh'
exit 0
