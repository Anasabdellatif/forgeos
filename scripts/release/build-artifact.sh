#!/usr/bin/env bash
# Builds a ForgeOS release artifact and its SHA-256 checksum from TRACKED repository state.
# POSIX counterpart of build-artifact.ps1. Source-only: this directory is never distributed.
#
# Usage:
#   bash scripts/release/build-artifact.sh              # build dist/forgeos-<version>.tar.gz
#   bash scripts/release/build-artifact.sh --list       # print the file list, write nothing
#   bash scripts/release/build-artifact.sh --ref v1.14.2 --out /tmp/rel
#
# The artifact is a SYNC SOURCE, not a product bundle. Its contents are derived from the manifest,
# never hand-listed: everything sync can place -- the portable half, the portable root files, and
# the seed files it copies from source paths -- plus blueprint.version so the copy can identify
# itself, plus README.md and LICENSE so whoever downloads it knows what they have and under what
# terms. Sync never places those last two; a person reading a tarball needs them.
#
# What it must never carry: this repository's own answers (every seed target backed by a template),
# its history (memory, tasks, plans), its release tooling (distribution.sourceOnly), and anything
# untracked. git archive gives the last one for free -- it reads a commit, not a directory.
#
# Exit 0 built or listed, 1 could not run, 2 refused.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/lib/blueprint-manifest.json"

REF='HEAD'
OUT="$REPO_ROOT/dist"
LIST=0
NAME=''

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)     REF="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}"; shift 2 ;;
    --name)    NAME="${2:-}"; shift 2 ;;
    --list)    LIST=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo "git is required." >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "Not a git repository: $REPO_ROOT" >&2; exit 1; }

COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify "$REF^{commit}" 2>/dev/null)" || {
  echo "Not a commit: $REF" >&2; exit 1; }

# Capability, not presence -- the house rule from check-links.sh. A Store stub named python3 sits
# on PATH in Git Bash and cannot run anything, so probe with a real parse before trusting it.
JSON_PY=''
if ! command -v jq >/dev/null 2>&1; then
  for _py in python3 python; do
    if command -v "$_py" >/dev/null 2>&1 && "$_py" -c 'import json' >/dev/null 2>&1; then
      JSON_PY="$_py"; break
    fi
  done
fi

read_cfg() {   # read_cfg <jq-filter> <python-expression>
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c "
import json,sys
d = json.load(open(sys.argv[1]))
$2
" "$MANIFEST" | tr -d '\r'
  else
    echo "build-artifact.sh requires jq or a working python3/python." >&2
    exit 1
  fi
}

mapfile -t PORTABLE    < <(read_cfg '.distribution.portable[]'      'print("\n".join(d["distribution"]["portable"]))')
mapfile -t PORT_FILES  < <(read_cfg '.distribution.portableFiles[]' 'print("\n".join(d["distribution"]["portableFiles"]))')
mapfile -t SEED_FILES  < <(read_cfg '.distribution.seedFiles[]'     'print("\n".join(d["distribution"]["seedFiles"]))')
mapfile -t TEMPLATED   < <(read_cfg '.distribution.seedTemplates | keys[]' 'print("\n".join(sorted(d["distribution"]["seedTemplates"])))')
mapfile -t SOURCE_ONLY < <(read_cfg '.distribution.sourceOnly[]?'   'print("\n".join(d["distribution"].get("sourceOnly",[])))')
VERSION_FILE="$(read_cfg '.distribution.versionFile' 'print(d["distribution"]["versionFile"])')"
VERSION="$(read_cfg '.version' 'print(d["version"])')"

# An unread manifest yields empty lists, an empty include set, and an artifact that looks built and
# carries nothing. Fail loudly instead -- the check-links.sh lesson, one directory over.
if [ "${#PORTABLE[@]}" -eq 0 ] || [ "${#PORT_FILES[@]}" -eq 0 ] || [ "${#SEED_FILES[@]}" -eq 0 ] ||
   [ -z "$VERSION" ] || [ -z "$VERSION_FILE" ]; then
  echo "Cannot read blueprint manifest. Install jq or python3." >&2
  echo "  manifest : $MANIFEST" >&2
  exit 1
fi

# Read the version from the artifact's own commit, not from the working tree: building v1.14.2
# must not stamp it with today's edits.
BP_JSON="$(git -C "$REPO_ROOT" show "$COMMIT:$VERSION_FILE" 2>/dev/null)" || BP_JSON=''
if [ -n "$BP_JSON" ]; then
  V="$(printf '%s' "$BP_JSON" | grep -m1 '"version"' | sed 's/.*: *"//; s/".*//')"
  [ -n "$V" ] && VERSION="$V"
fi
[ -n "$NAME" ] || NAME="forgeos-$VERSION"

is_source_only() {   # is_source_only <path>
  local q
  for q in ${SOURCE_ONLY[@]+"${SOURCE_ONLY[@]}"}; do
    [ -z "$q" ] && continue
    [ "$1" = "$q" ] && return 0
    case "$1" in "$q"/*) return 0 ;; esac
  done
  return 1
}

is_seed_file() {     # is_seed_file <path> -- declared scaffolding, not our own record
  local q
  for q in "${SEED_FILES[@]}"; do
    [ "$1" = "$q" ] && return 0
  done
  return 1
}

is_templated() {     # is_templated <path> -- seeded from templates/, so the source copy stays home
  local q
  for q in ${TEMPLATED[@]+"${TEMPLATED[@]}"}; do
    [ "$1" = "$q" ] && return 0
  done
  return 1
}

# --- The include list, derived from the manifest ------------------------------------------------
include=()
for p in "${PORTABLE[@]}";   do is_source_only "$p" || include+=("$p"); done
for p in "${PORT_FILES[@]}"; do is_source_only "$p" || include+=("$p"); done
for p in "${SEED_FILES[@]}"; do
  is_templated   "$p" && continue
  is_source_only "$p" && continue
  include+=("$p")
done
include+=("$VERSION_FILE")
for p in README.md LICENSE; do
  git -C "$REPO_ROOT" cat-file -e "$COMMIT:$p" 2>/dev/null && include+=("$p")
done

# A portable directory can CONTAIN a source-only subtree, so the pathspec above is not enough:
# ask git what it resolves, then subtract. :(exclude) needs a pathspec magic every git honours,
# so filter the resolved list instead -- one place, visible, testable.
resolved=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  is_source_only "$f" && continue
  is_templated   "$f" && continue
  resolved+=("$f")
done < <(git -C "$REPO_ROOT" ls-tree -r --name-only "$COMMIT" -- "${include[@]}" | sort)

if [ "${#resolved[@]}" -eq 0 ]; then
  echo "The include list resolved to no files at $REF. Refusing to build an empty artifact." >&2
  exit 2
fi

# Belt and braces: prove the resolved list carries none of what it must never carry, rather than
# trusting that the derivation above was right. A boundary nobody re-checks is a boundary by hope.
leaks=()
for f in "${resolved[@]}"; do
  is_source_only "$f" && leaks+=("source-only: $f")
  is_templated   "$f" && leaks+=("template-backed: $f")
  case "$f" in
    .ai/memory/*/*|.ai/tasks/completed/*|.ai/plans/completed/*)
      # A declared seed file inside one of those directories is the README that explains
      # what the directory is for -- a new project needs it. Anything else there is this
      # repository's own record.
      is_seed_file "$f" || leaks+=("project history: $f") ;;
  esac
done
if [ "${#leaks[@]}" -gt 0 ]; then
  echo "Refusing to build: the include list reaches paths the artifact must not carry." >&2
  printf '  - %s\n' "${leaks[@]}" >&2
  exit 2
fi

DIRTY='clean'
[ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ] &&
  DIRTY='dirty (ignored -- the artifact is built from the commit, not the working tree)'

MODE='BUILD'
[ "$LIST" -eq 1 ] && MODE='LIST -- writes nothing'

echo ''
echo "ForgeOS release artifact  [$MODE]"
printf '  version    %s\n' "$VERSION"
printf '  ref        %s  (%s)\n' "$REF" "$COMMIT"
printf '  tree       %s\n' "$DIRTY"
printf '  files      %s\n' "${#resolved[@]}"
printf '  excluded   %s source-only path(s), %s template-backed seed target(s)\n' \
       "${#SOURCE_ONLY[@]}" "${#TEMPLATED[@]}"

if [ "$LIST" -eq 1 ]; then
  echo ''
  printf '  %s\n' "${resolved[@]}"
  echo ''
  echo '  Nothing was written.'
  exit 0
fi

mkdir -p "$OUT" || { echo "Cannot create output directory: $OUT" >&2; exit 1; }
OUT="$(cd "$OUT" && pwd)"
ARCHIVE="$OUT/$NAME.tar.gz"

git -C "$REPO_ROOT" archive --format=tar.gz --prefix="$NAME/" -o "$ARCHIVE" "$COMMIT" \
    -- "${resolved[@]}" || { echo "git archive failed." >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then
  ( cd "$OUT" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256" )
elif command -v shasum >/dev/null 2>&1; then
  ( cd "$OUT" && shasum -a 256 "$NAME.tar.gz" > "$NAME.tar.gz.sha256" )
else
  echo "No sha256sum or shasum available; refusing to ship an artifact nobody can verify." >&2
  rm -f "$ARCHIVE"
  exit 1
fi

echo ''
printf '  archive    %s  (%s bytes)\n' "$ARCHIVE" "$(wc -c < "$ARCHIVE" | tr -d ' ')"
printf '  checksum   %s\n' "$ARCHIVE.sha256"
printf '             %s\n' "$(cut -d' ' -f1 < "$ARCHIVE.sha256")"
echo ''
echo "  Verify with:  sha256sum -c $NAME.tar.gz.sha256"
echo "  Inspect with: tar -tzf $NAME.tar.gz"
echo ''
echo '  Nothing was published. Publishing a release is a separate, authorized act.'
exit 0
