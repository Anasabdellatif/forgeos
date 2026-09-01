#!/usr/bin/env bash
# Audits the public launch surface of THIS repository. POSIX counterpart of
# check-public-surface.ps1.
#
# Every other claim in this repository has a check behind it. The public page did not, and it
# rotted exactly as an unchecked claim does: at v1.15.1 the README still announced 1.13.4 and
# still described 132 policy controls. The file a stranger judges the project by was the least
# verified file in it. This check closes that hole.
#
# Advisory in v1.15.2, by deliberate sequence: the drift it reports is real and predates it, and a
# check introduced red would either block the branch or invite someone to soften it. It prints
# every finding and exits 0. --fail-on-drift turns findings into exit 1, which is how it will run
# once the public surface is written.
#
# It never fails the audit closed: only a missing manifest or an unreadable version file -- a
# tooling failure that makes the audit impossible -- exits 1, the same rule check-context-budget
# follows.
#
# SCOPE: the blueprint's own public surface, never an adopting project's. The required files here
# are ForgeOS's launch contract, not a product's; running them against someone else's repository
# would report our obligations as their defects. The check reads blueprint.version's role and
# reports "not applicable" in an adopted project.
#
# No network. No GitHub API. No gh. Nothing is written.
#
# Usage: check-public-surface.sh [--fail-on-drift] [--measured <check-all run log>]
# Exit 0 normally, including with drift; 1 with --fail-on-drift when drift is found, and 1 when
# the manifest or the version file cannot be read.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/lib/blueprint-manifest.json"
VERSION_FILE="$REPO_ROOT/blueprint.version"

FAIL_ON_DRIFT=0
MEASURED=''
while [ $# -gt 0 ]; do
  case "$1" in
    --fail-on-drift) FAIL_ON_DRIFT=1; shift ;;
    # A run log from check-all: every check has already printed the numbers this page claims, so
    # they are read from there rather than re-derived. Absent when the audit runs standalone, and
    # the affected claims then report UNCHECKED with the reason, exactly as before.
    --measured)      MEASURED="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

echo 'Public launch surface'

[ -f "$MANIFEST" ] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }
[ -f "$VERSION_FILE" ] || { echo "Version file not found: $VERSION_FILE" >&2; exit 1; }

# Capability, not presence -- the house rule. A Store stub named python3 sits on PATH in Git Bash
# and cannot run anything, so probe with a real parse before trusting it.
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
    echo "check-public-surface.sh requires jq or a working python3/python." >&2
    exit 1
  fi
}

mapfile -t REQUIRED < <(read_cfg '.policy.publicSurface.required[]?'  'print("\n".join(d["policy"]["publicSurface"]["required"]))')
mapfile -t EXPECTED < <(read_cfg '.policy.publicSurface.expected[]?'  'print("\n".join(d["policy"]["publicSurface"]["expected"]))')
mapfile -t SECTIONS < <(read_cfg '.policy.publicSurface.sections[]?'  'print("\n".join(d["policy"]["publicSurface"]["sections"]))')
CLAIM_FILE="$(read_cfg '.policy.publicSurface.claimFile // empty' 'print(d["policy"]["publicSurface"].get("claimFile",""))')"

# An unread manifest yields empty lists and an audit that reports nothing wrong -- a false
# all-clear, the one result a validation must never produce.
if [ "${#REQUIRED[@]}" -eq 0 ] || [ -z "$CLAIM_FILE" ]; then
  echo "Cannot read policy.publicSurface from the manifest. Install jq or python3." >&2
  echo "  manifest : $MANIFEST" >&2
  exit 1
fi

ROLE="$(grep -m1 '"role"' "$VERSION_FILE" | sed 's/.*: *"//; s/".*//')"
BP_VERSION="$(grep -m1 '"version"' "$VERSION_FILE" | sed 's/.*: *"//; s/".*//')"
[ -n "$BP_VERSION" ] || { echo "Could not read the version from $VERSION_FILE" >&2; exit 1; }

if [ "$ROLE" != 'source' ]; then
  printf '  role      %s -- this audit belongs to the blueprint, not to a project that adopted it\n' "${ROLE:-unknown}"
  echo 'Public surface NOT APPLICABLE  (an adopted project publishes its own surface, on its own terms)'
  exit 0
fi

printf '  audits    the blueprint source repository (blueprint.version role: source, v%s)\n' "$BP_VERSION"

drift=0
note() {  # note <label> <message>
  drift=$((drift + 1))
  printf '  %-9s %s\n' "$1" "$2"
}

# --- A. Files the launch contract requires ------------------------------------------------------
echo ''
echo '  Required now'
for f in "${REQUIRED[@]}"; do
  if [ -f "$REPO_ROOT/$f" ]; then
    printf '  %-9s %s\n' 'ok' "$f"
  else
    note 'MISSING' "$f  -- required by the public preview contract"
  fi
done

echo ''
echo '  Required before the repository goes public'
for f in "${EXPECTED[@]}"; do
  if [ -f "$REPO_ROOT/$f" ]; then
    printf '  %-9s %s\n' 'ok' "$f"
  else
    note 'MISSING' "$f"
  fi
done

# --- B and C. What the public page claims -------------------------------------------------------
#
# Parsing prose is where a check like this earns its keep or becomes a nuisance. The rule followed
# here: extract only claims written in a shape the repository itself controls, and when a claim is
# not found in that shape, say UNCHECKED and why. A claim reported as passing because the parser
# missed it is worse than no parser at all.
echo ''
echo '  Public claims'
CLAIM_PATH="$REPO_ROOT/$CLAIM_FILE"
if [ ! -f "$CLAIM_PATH" ]; then
  note 'MISSING' "$CLAIM_FILE -- no public page to audit"
else
  # Version. [ \t] and not \s: in .NET \s matches a newline, and the two halves must agree.
  claimed_version="$(grep -m1 -oE 'Current version:[ \t]*\*\*`?[0-9]+\.[0-9]+\.[0-9]+`?\*\*' "$CLAIM_PATH" \
                     | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -z "$claimed_version" ]; then
    printf '  %-9s %s\n' 'UNCHECKED' "version claim -- no 'Current version: **x.y.z**' line in $CLAIM_FILE"
  elif [ "$claimed_version" = "$BP_VERSION" ]; then
    printf '  %-9s %s\n' 'ok' "version claim $claimed_version matches blueprint.version"
  else
    note 'DRIFT' "$CLAIM_FILE says version $claimed_version; blueprint.version says $BP_VERSION"
  fi

  # Check-all's own row counts, read from check-all.sh -- a stable local file, no run required.
  # placeholders is declared twice (gating under --strict, informational by default); the default
  # run is what the page describes, so a name declared both ways counts as informational.
  ca="$REPO_ROOT/scripts/validation/check-all.sh"
  gating_n=0; info_n=0
  if [ -f "$ca" ]; then
    while IFS= read -r name; do
      flags="$(grep -oE "run_check +'$name' +'[^']+' +[01]" "$ca" | grep -oE '[01]$' | sort -u | tr -d '\n')"
      case "$flags" in
        1)  gating_n=$((gating_n + 1)) ;;
        *)  info_n=$((info_n + 1)) ;;
      esac
    # Leading whitespace allowed, because placeholders is declared inside the --strict if/else and
    # is indented: an anchored ^run_check dropped it silently and undercounted the row by one.
    done < <(grep -oE "^[[:space:]]*run_check +'[a-z-]+'" "$ca" | grep -oE "'[a-z-]+'" | tr -d "'" | sort -u)
  fi

  # Number words, because the page is written for people. An unmapped word is UNCHECKED, never a
  # pass: a reworded sentence must not read as agreement.
  word_to_n() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
      one) echo 1 ;; two) echo 2 ;; three) echo 3 ;; four) echo 4 ;; five) echo 5 ;; six) echo 6 ;;
      seven) echo 7 ;; eight) echo 8 ;; nine) echo 9 ;; ten) echo 10 ;; eleven) echo 11 ;;
      twelve) echo 12 ;; [0-9]*) echo "$1" ;; *) echo '' ;;
    esac
  }

  claim_line="$(grep -m1 -oE '\*\*[A-Za-z0-9]+ gating checks and [A-Za-z0-9]+ informational reports\*\*' "$CLAIM_PATH")"
  if [ -z "$claim_line" ]; then
    printf '  %-9s %s\n' 'UNCHECKED' "check-count claim -- the 'N gating checks and M informational reports' sentence was not found"
  else
    cg="$(word_to_n "$(printf '%s' "$claim_line" | awk '{print $1}' | tr -d '*')")"
    ci="$(printf '%s' "$claim_line" | sed -E 's/.*checks and ([A-Za-z0-9]+) informational.*/\1/')"
    ci="$(word_to_n "$ci")"
    if [ -z "$cg" ] || [ -z "$ci" ]; then
      printf '  %-9s %s\n' 'UNCHECKED' 'check-count claim -- the counts are not written as numbers this check can read'
    else
      [ "$cg" = "$gating_n" ] && printf '  %-9s %s\n' 'ok' "gating check claim $cg matches check-all" \
                              || note 'DRIFT' "$CLAIM_FILE claims $cg gating checks; check-all declares $gating_n"
      [ "$ci" = "$info_n" ]   && printf '  %-9s %s\n' 'ok' "informational claim $ci matches check-all" \
                              || note 'DRIFT' "$CLAIM_FILE claims $ci informational reports; check-all declares $info_n"
    fi
  fi

  # CI jobs, counted from the workflow rather than from a run: no network, no gh, no invention.
  wf="$REPO_ROOT/.github/workflows/validate.yml"
  if [ -f "$wf" ]; then
    jobs_n="$(awk '/^jobs:/{f=1;next} f && /^  [a-z0-9_-]+:[ \t]*$/{n++} END{print n+0}' "$wf")"
    job_claim="$(grep -m1 -oE '\*\*CI\.\*\* [A-Za-z0-9]+ jobs' "$CLAIM_PATH" | awk '{print $2}')"
    [ -z "$job_claim" ] && job_claim="$(grep -m1 -oE '(^|[^A-Za-z])[A-Za-z0-9]+ jobs, green' "$CLAIM_PATH" | awk '{print $1}')"
    cj="$(word_to_n "${job_claim:-}")"
    if [ -z "$cj" ]; then
      printf '  %-9s %s\n' 'UNCHECKED' 'CI job claim -- no readable "N jobs" statement on the public page'
    elif [ "$cj" = "$jobs_n" ]; then
      printf '  %-9s %s\n' 'ok' "CI job claim $cj matches the workflow"
    else
      note 'DRIFT' "$CLAIM_FILE claims $cj CI jobs; the workflow declares $jobs_n"
    fi
  fi

  # Numbers that exist only at run time. Re-deriving them here would duplicate a gating check, and
  # running the self-test from inside a check the self-test itself invokes would recurse. So they
  # are read from check-all's run log when there is one, and reported UNCHECKED with the reason
  # when there is not -- never passed silently.
  measured_claim() {   # measured_claim <label> <claimed> <measured>
    if [ -z "$3" ]; then
      printf '  %-9s %s\n' 'UNCHECKED' "$1 -- not measured in this run (no --measured log)"
    elif [ -z "$2" ]; then
      printf '  %-9s %s\n' 'UNCHECKED' "$1 -- the page states no number this check can read"
    elif [ "$2" = "$3" ]; then
      printf '  %-9s %s\n' 'ok' "$1 claim $2 matches what the tools reported"
    else
      note 'DRIFT' "$CLAIM_FILE claims $1 $2; the tools reported $3"
    fi
  }

  m_selftest=''; m_policy=''; m_refs=''; m_files=''; m_broken=''; m_unportable=''
  if [ -n "$MEASURED" ] && [ -f "$MEASURED" ]; then
    m_selftest="$(grep -oE '^Total: +[0-9]+ +Passed:' "$MEASURED" | grep -oE '[0-9]+' | head -1)"
    m_policy="$(grep -oE 'Policy check passed +\([0-9]+ control' "$MEASURED" | grep -oE '[0-9]+' | head -1)"
    link_line="$(grep -m1 -oE 'Link check passed +\([0-9]+ reference\(s\) checked across [0-9]+ file\(s\), [0-9]+ broken, [0-9]+ unportable' "$MEASURED")"
    if [ -n "$link_line" ]; then
      m_refs="$(printf '%s' "$link_line" | grep -oE '[0-9]+' | sed -n 1p)"
      m_files="$(printf '%s' "$link_line" | grep -oE '[0-9]+' | sed -n 2p)"
      m_broken="$(printf '%s' "$link_line" | grep -oE '[0-9]+' | sed -n 3p)"
      m_unportable="$(printf '%s' "$link_line" | grep -oE '[0-9]+' | sed -n 4p)"
    fi
  fi

  c_selftest="$(grep -m1 -oE '[0-9]+ cases per shell' "$CLAIM_PATH" | grep -oE '[0-9]+')"
  c_policy="$(grep -m1 -oE '\| [0-9]+ policy controls \|' "$CLAIM_PATH" | grep -oE '[0-9]+')"
  c_link="$(grep -m1 -oE '[0-9]+ references across [0-9]+ files, [0-9]+ broken, [0-9]+ unportable' "$CLAIM_PATH")"
  c_refs=''; c_files=''; c_broken=''; c_unportable=''
  if [ -n "$c_link" ]; then
    c_refs="$(printf '%s' "$c_link" | grep -oE '[0-9]+' | sed -n 1p)"
    c_files="$(printf '%s' "$c_link" | grep -oE '[0-9]+' | sed -n 2p)"
    c_broken="$(printf '%s' "$c_link" | grep -oE '[0-9]+' | sed -n 3p)"
    c_unportable="$(printf '%s' "$c_link" | grep -oE '[0-9]+' | sed -n 4p)"
  fi

  measured_claim 'self-test case count' "$c_selftest"   "$m_selftest"
  measured_claim 'policy control count' "$c_policy"     "$m_policy"
  measured_claim 'link reference count' "$c_refs"       "$m_refs"
  measured_claim 'link file count'      "$c_files"      "$m_files"
  measured_claim 'broken link count'    "$c_broken"     "$m_broken"
  measured_claim 'unportable count'     "$c_unportable" "$m_unportable"

  # --- D. The two tables ------------------------------------------------------------------------
  echo ''
  echo '  Proof tables'
  for sec in ${SECTIONS[@]+"${SECTIONS[@]}"}; do
    if grep -qF -- "$sec" "$CLAIM_PATH"; then
      printf '  %-9s %s\n' 'ok' "section present: $sec"
    else
      note 'MISSING' "section: $sec"
    fi
  done

  # One staleness rule, and only one that can be decided mechanically: a claim about what this
  # repository contains, which this repository can contradict. The page says memory holds no
  # lesson; the moment a lesson exists, the page is wrong and says so with confidence.
  lessons="$(find "$REPO_ROOT/.ai/memory/lessons" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
  if grep -qE 'carries no handoff, lesson, or incident' "$CLAIM_PATH" && [ "${lessons:-0}" -gt 0 ]; then
    note 'DRIFT' "$CLAIM_FILE says memory carries no lesson; $lessons lesson(s) are on record"
  fi
fi

# --- E. None of this may travel -----------------------------------------------------------------
#
# Every file above is ForgeOS's, not a blueprint's. An adopting project that inherited the security
# policy would publish our disclosure address as theirs. They stay home today because no list names
# them -- and M-18 established what safety by omission is worth. This says it out loud each run.
echo ''
echo '  Distribution safety'
mapfile -t PORT_DIRS  < <(read_cfg '.distribution.portable[]'      'print("\n".join(d["distribution"]["portable"]))')
mapfile -t PORT_FILES < <(read_cfg '.distribution.portableFiles[]' 'print("\n".join(d["distribution"]["portableFiles"]))')
mapfile -t SEED_FILES < <(read_cfg '.distribution.seedFiles[]'     'print("\n".join(d["distribution"]["seedFiles"]))')
# seedTemplates was NOT consulted here until M-23.0a. A key there is only a REDIRECT -- it changes
# which file a seed is copied FROM, and sync seeds nothing that is not also in seedFiles -- so a
# seedTemplates-only entry cannot travel today and this is a superset guard, not a closed hole.
# It is worth reading anyway: the two lists are edited together, and a check that watched only one
# of them would go quiet the moment the seed loop learned to iterate the other.
# `? // {}` and not a bare `.seedTemplates | keys[]`: jq errors on `null | keys`, so a manifest
# without the key would fail the audit closed -- the one outcome this check must never produce.
# The python branch already defaulted; the two halves must both tolerate the absence.
mapfile -t SEED_TMPL  < <(read_cfg '(.distribution.seedTemplates? // {}) | keys[]' 'print("\n".join(d["distribution"].get("seedTemplates",{}).keys()))')
mapfile -t SRC_ONLY < <(read_cfg '.distribution.sourceOnly[]?' 'print(chr(10).join(d["distribution"].get("sourceOnly",[])))')

would_travel() {   # would_travel <path> -> echoes the reason, or nothing
  local p="$1" q
  for q in "${PORT_FILES[@]}"; do [ "$p" = "$q" ] && { echo 'listed as a portable file'; return; }; done
  for q in "${SEED_FILES[@]}"; do [ "$p" = "$q" ] && { echo 'listed as a seed file'; return; }; done
  for q in ${SEED_TMPL[@]+"${SEED_TMPL[@]}"}; do [ "$p" = "$q" ] && { echo 'seeded from a template'; return; }; done
  for q in "${PORT_DIRS[@]}";  do case "$p" in "$q"/*) echo "inside the portable directory $q"; return ;; esac; done
}

is_declared_source_only() {   # is_declared_source_only <path>
  local q
  for q in ${SRC_ONLY[@]+"${SRC_ONLY[@]}"}; do
    [ -z "$q" ] && continue
    [ "$1" = "$q" ] && return 0
    case "$1" in "$q"/*) return 0 ;; esac
  done
  # A seedTemplates redirect is the same promise by a different route, and check-policy REFUSES the
  # other one: a source-only path may not also be a seed file, because "never copied" and "copied
  # when absent" cannot both be true of one path. When an adopter must have a file at this path --
  # docs/roadmap.md, or forgeos next is blind -- the redirect is what keeps OUR copy home: the seed
  # is filled from templates/, so this repository's content is never the thing that travels. That is
  # a written declaration, not an accident, which is all this check exists to insist on.
  for q in ${SEED_TMPL[@]+"${SEED_TMPL[@]}"}; do
    [ "$1" = "$q" ] && return 0
  done
  return 1
}

travellers=0
for f in ${REQUIRED[@]+"${REQUIRED[@]}"} ${EXPECTED[@]+"${EXPECTED[@]}"}; do
  reason="$(would_travel "$f")"
  if [ -n "$reason" ]; then
    # README.md and the guides are the project's own and are handled by the distribution split;
    # only a PUBLIC-SURFACE file that reaches an adopter is a finding.
    case "$f" in
      # docs/roadmap.md is seeded from templates/roadmap-template.md, never from the copy below it.
      # forgeos next reads a roadmap to recommend anything, so an adopter without one is blind --
      # but THIS repository's roadmap is a public trust file and must not travel. A neutral template
      # settles both: the path is filled, the content is not ours.
      README.md|LICENSE|docs/adoption.md|docs/roadmap.md|scripts/*) printf '  %-9s %s\n' 'ok' "$f is distributed by design ($reason)" ;;
      *) note 'LEAK' "$f would reach an adopting project -- $reason"; travellers=$((travellers + 1)) ;;
    esac
  fi
done

# Absence from the portable lists is not a guarantee; it is an accident waiting to be undone by
# whoever next adds a file to portableFiles. Every trust file must be DECLARED source-only, so
# check-policy fails the moment the declaration is contradicted. This is the M-18 rule applied to
# the public surface: safety by omission is worth nothing until it is written down.
undeclared=0
for f in ${EXPECTED[@]+"${EXPECTED[@]}"}; do
  if ! is_declared_source_only "$f"; then
    note 'UNDECLARED' "$f is not in distribution.sourceOnly -- it stays home by accident, not by rule"
    undeclared=$((undeclared + 1))
  fi
done

if [ "$travellers" -eq 0 ] && [ "$undeclared" -eq 0 ]; then
  printf '  %-9s %s
' 'ok' 'every public trust file is declared source-only, and none travels except by design above'
fi

# --- Verdict ------------------------------------------------------------------------------------
echo ''
if [ "$drift" -eq 0 ]; then
  echo 'PUBLIC SURFACE OK  (every public claim matches what the repository reports)'
  exit 0
fi

printf 'PUBLIC SURFACE DRIFT  (%s finding(s))\n' "$drift"
if [ "$FAIL_ON_DRIFT" -eq 1 ]; then
  echo 'Reported as a failure because --fail-on-drift was passed.'
  exit 1
fi
echo 'Advisory for now: the findings above predate this check and are the work of the public'
echo 'surface slices. Nothing here is hidden, softened, or excused -- and nothing is gated on it'
echo 'until the surface is written. Then this check runs with --fail-on-drift and stays green.'
exit 0
