#!/usr/bin/env bash
# Verifies that repository-relative file paths referenced from Markdown actually resolve.
# POSIX counterpart of check-links.ps1.
#
# A reference to a file that does not exist sends an agent somewhere empty and costs it a whole
# turn to discover that. Broken references are the most common form of documentation rot, and they
# are entirely mechanical to catch.
#
# Checks markdown links [text](path) and backticked paths `path`. Only references containing a
# path separator are checked -- a bare filename is prose shorthand, not a claim about location.
#
# Also runs a PORTABILITY pass. Resolving here is not enough: a file in the portable half is copied
# into every adopting project, so a reference it makes to something sync never places resolves in
# this repository and breaks in all of them.
#
# Exit 0 when every reference resolves and every portable reference travels, 1 otherwise.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/lib/blueprint-manifest.json"

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

read_cfg() {   # read_cfg <jq-filter> <python-expression>
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c "
import json,sys
d = json.load(open(sys.argv[1]))['linkCheck']
$2
" "$MANIFEST" | tr -d '\r'
  else
    echo "check-links.sh requires jq or a working python3/python." >&2
    exit 1
  fi
}

mapfile -t ROOTS       < <(read_cfg '.linkCheck.roots[]'            'print("\n".join(d["roots"]))')
mapfile -t ROOT_FILES  < <(read_cfg '.linkCheck.includeRootFiles[]' 'print("\n".join(d["includeRootFiles"]))')
mapfile -t IGNORE_PRE  < <(read_cfg '.linkCheck.ignorePrefixes[]'   'print("\n".join(d["ignorePrefixes"]))')
mapfile -t IGNORE_PAT  < <(read_cfg '.linkCheck.ignorePathPatterns[]' 'print("\n".join(d["ignorePathPatterns"]))')

read_dist() {   # read_dist <jq-filter> <python-expression>
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c "
import json,sys
d = json.load(open(sys.argv[1]))['distribution']
$2
" "$MANIFEST" | tr -d '\r'
  else
    echo "check-links.sh requires jq or a working python3/python." >&2
    exit 1
  fi
}

# Portability sets: everything sync actually places in an adopting project -- the portable half,
# plus the scaffolding it seeds. A file that lands there and references something that does not
# resolves here and breaks there.
mapfile -t PORT_DIRS   < <(read_dist '.distribution.portable[]' 'print("\n".join(d["portable"]))')
mapfile -t OWNED       < <(read_dist '.distribution.projectSpecific[]' 'print("\n".join(d["projectSpecific"]))')
mapfile -t SRC_ONLY    < <(read_dist '.distribution.sourceOnly[]?' 'print("\n".join(d.get("sourceOnly",[])))')
mapfile -t AVAIL_FILES < <(read_dist '(.distribution.portableFiles + .distribution.seedFiles)[]' \
                                     'print("\n".join(d["portableFiles"] + d["seedFiles"]))')

# Fail loudly when the manifest could not be read. Every reader above runs inside a process
# substitution, so its `exit 1` ends that subshell and nothing else -- and an unread manifest
# yields empty arrays, zero files to scan, and a check that reports "passed" having verified
# nothing. A validation that fails open is worse than no validation: it is a false all-clear.
# This happens in practice wherever jq is absent and `python3` resolves to a stub rather than an
# interpreter -- Git Bash on Windows, and minimal containers.
if [ "${#ROOTS[@]}" -eq 0 ] || [ "${#ROOT_FILES[@]}" -eq 0 ] || [ "${#IGNORE_PRE[@]}" -eq 0 ] ||
   [ "${#PORT_DIRS[@]}" -eq 0 ] || [ "${#AVAIL_FILES[@]}" -eq 0 ]; then
  echo "Cannot read blueprint manifest. Install jq or python3." >&2
  echo "  manifest : $MANIFEST" >&2
  echo "  jq       : $(command -v jq || echo MISSING)" >&2
  echo "  python3  : $(command -v python3 || echo MISSING)" >&2
  exit 1
fi

files=()
for name in "${ROOT_FILES[@]}"; do
  [ -f "$REPO_ROOT/$name" ] && files+=("$REPO_ROOT/$name")
done
for root in "${ROOTS[@]}"; do
  [ -d "$REPO_ROOT/$root" ] || continue
  while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$REPO_ROOT/$root" -type f -name '*.md' -print0)
done

is_ignored() {
  local target="$1" p
  for p in "${IGNORE_PRE[@]}"; do
    case "$target" in "$p"*) return 0 ;; esac
  done
  for p in "${IGNORE_PAT[@]}"; do
    [[ "$target" =~ $p ]] && return 0
  done
  return 1
}

is_portable() {
  local target="$1" p
  # Source-only first: release tooling sits inside a portable directory but is dropped by sync, so
  # requiring its references to travel would fail on paths no adopter ever receives.
  for p in ${SRC_ONLY[@]+"${SRC_ONLY[@]}"}; do
    [ -z "$p" ] && continue
    [ "$target" = "$p" ] && return 1
    case "$target" in "$p"/*) return 1 ;; esac
  done
  for p in "${AVAIL_FILES[@]}"; do
    [ "$target" = "$p" ] && return 0
  done
  for p in "${PORT_DIRS[@]}"; do
    case "$target" in "$p"/*) return 0 ;; esac
  done
  return 1
}

# A seeded file can still be the PROJECT'S. sync places docs/README.md and .ai/context/project.md
# once, and from that moment they belong to the project: it fills them with references to its own
# documentation, which the blueprint neither knows nor distributes. Judging those references by the
# portability rule fails every real adoption -- found by a dry run against a project whose
# docs/README.md points at docs/Client/, docs/Developer/, docs/data/.
#
# So projectSpecific decides who OWNS a file, and ownership decides whether the portability rule
# applies to what it references. It does not exempt the file from link checking: a broken link in a
# project's own index is still broken, and is still reported.
is_project_owned() {
  local target="$1" p
  for p in ${OWNED[@]+"${OWNED[@]}"}; do
    [ "$target" = "$p" ] && return 0
    case "$target" in "$p"/*) return 0 ;; esac
  done
  return 1
}

broken=''
unportable=''
checked=0

# PERFORMANCE. The first version of this loop spawned three to five processes per markdown LINE
# (grep, sed, tr, a grep per ignore pattern, a cd/dirname/basename per reference). On this
# repository that is invisible; on a real adopting project with ninety thousand markdown lines it
# took twenty minutes -- a correct answer nobody will wait for, which is a check that gets skipped.
#
# So extraction is one awk pass per FILE, and every per-reference decision below is a bash
# builtin: case/glob for the path shape and prefixes, a pure-string path normaliser instead of
# cd/pwd, and [[ =~ ]] only for the handful of ignore patterns. Nothing forks inside the loop.

# Emits "lineno<TAB>reference" for every markdown link target and backticked path in a file.
extract_refs() {
  awk '
    {
      line = $0
      # [text](target) -- target runs to the first ")" or whitespace
      while (match(line, /\[[^]]*\]\([^)[:space:]]+\)/)) {
        m = substr(line, RSTART, RLENGTH)
        sub(/.*\(/, "", m); sub(/\)$/, "", m)
        print NR "\t" m
        line = substr(line, RSTART + RLENGTH)
      }
      line = $0
      # `path` -- no whitespace inside
      while (match(line, /`[^`[:space:]]+`/)) {
        m = substr(line, RSTART + 1, RLENGTH - 2)
        print NR "\t" m
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$1"
}

# Collapses "a/b/../c" and "./x" without touching the filesystem. Used to turn a reference that
# resolved relative to its file into the repository-relative form the portability pass needs.
normalise_path() {
  local input="$1" out='' part
  local IFS='/'
  # shellcheck disable=SC2086
  set -- $input
  for part in "$@"; do
    case "$part" in
      ''|'.') ;;
      # ${out%/*} strips the last segment only when a slash remains; on a single segment the
      # pattern cannot match and the segment survived, so docs/architecture/../../x collapsed to
      # docs/x instead of x -- a valid reference reported broken, found by a real adoption.
      '..')   case "$out" in */*) out="${out%/*}" ;; *) out='' ;; esac ;;
      *)      out="${out:+$out/}$part" ;;
    esac
  done
  printf '%s' "$out"
}

for file in "${files[@]}"; do
  file_rel="${file#"$REPO_ROOT"/}"
  file_dir_rel="${file_rel%/*}"
  [ "$file_dir_rel" = "$file_rel" ] && file_dir_rel=''
  file_portable=0
  if is_portable "$file_rel" && ! is_project_owned "$file_rel"; then file_portable=1; fi

  while IFS=$'\t' read -r lineno ref; do
    [ -z "$ref" ] && continue
    target="${ref%%#*}"
    [ -z "$target" ] && continue
    is_ignored "$target" && continue
    # Path shape, as a glob: has a separator, ends in a known extension, starts sanely.
    case "$target" in
      */*.md|*/*.ps1|*/*.sh|*/*.json|*/*.yml|*/*.yaml|*/*.txt) ;;
      *) continue ;;
    esac
    case "$target" in
      [A-Za-z0-9_.]*) ;;
      *) continue ;;
    esac
    # Reject anything outside the character set the old regex allowed, e.g. spaces or ")".
    case "$target" in
      *[!A-Za-z0-9_./-]*) continue ;;
    esac

    checked=$((checked + 1))

    # Resolve relative to the referencing file first, then to the repository root. The portability
    # pass needs the repository-relative form, not the reference as written: architecture/decisions.md
    # inside docs/ is docs/architecture/decisions.md.
    target_rel=''
    candidate="$(normalise_path "${file_dir_rel:+$file_dir_rel/}$target")"
    if [ -n "$candidate" ] && [ -e "$REPO_ROOT/$candidate" ]; then
      target_rel="$candidate"
    elif [ -e "$REPO_ROOT/$target" ]; then
      target_rel="$(normalise_path "$target")"
    fi

    if [ -z "$target_rel" ]; then
      broken="${broken}  ${file_rel}:${lineno}  ->  ${target}"$'\n'
      continue
    fi

    # Portability: a file that lands in an adopting project may reference only what also lands
    # there. Anything else resolves here -- where the whole repository exists -- and breaks on the
    # first adoption, which is the one place nobody was looking.
    if [ "$file_portable" -eq 1 ] && ! is_portable "$target_rel"; then
      unportable="${unportable}  ${file_rel}:${lineno}  ->  ${target_rel}"$'\n'
    fi
  done < <(extract_refs "$file")
done

failed=0

if [ -n "$broken" ]; then
  failed=1
  broken_count="$(printf '%s' "$broken" | grep -c '' || true)"
  printf 'Link check FAILED  (%s reference(s) checked, %s broken)\n\n' "$checked" "$broken_count"
  printf '%s' "$broken" | sort
  echo ''
  echo 'Fix the path, create the file, or add the pattern to linkCheck.ignorePathPatterns'
  echo 'in scripts/lib/blueprint-manifest.json if the reference is deliberately illustrative.'
fi

if [ -n "$unportable" ]; then
  [ "$failed" -eq 1 ] && echo ''
  failed=1
  unportable_count="$(printf '%s' "$unportable" | grep -c '' || true)"
  printf 'Portability check FAILED  (%s portable file reference(s) that sync does not place)\n\n' "$unportable_count"
  printf '%s' "$unportable" | sort
  echo ''
  echo 'These resolve in this repository and break in every adopting project. State the'
  echo 'fact inline, or point at a portable file or a seeded one -- see distribution in'
  echo 'scripts/lib/blueprint-manifest.json.'
fi

[ "$failed" -eq 1 ] && exit 1

printf 'Link check passed  (%s reference(s) checked across %s file(s), 0 broken, 0 unportable)\n' \
       "$checked" "${#files[@]}"
exit 0
