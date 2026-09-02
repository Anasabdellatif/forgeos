#!/usr/bin/env bash
# Reports where this project is, from its own files. POSIX counterpart of project-status.ps1.
#
# READ-ONLY BY CONSTRUCTION. It creates, modifies and deletes nothing; it runs no git command that
# changes state; it touches the network never. The contract and the reasoning are in README.md
# beside this file, and the self-test asserts the three safety flags below are false.
#
# The one rule that shapes everything here: a field with no source is reported as missing, never
# guessed. A string becomes "unknown", a number becomes null -- because zero tasks and no task
# directory are different facts -- and the source is named in missingSources.
#
# Usage: project-status.sh [--json] [--section all|next|prompt]
# Exit 0 reported; 1 the repository is unreadable, or --section prompt refuses to invent facts.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --section exists so the wrapper can ask for a subset instead of re-parsing this command's output.
# One emitter, one place: a consumer that had to slice JSON back apart would be a second grammar for
# the same document, and this repository has paid for that mistake before.
JSON=0; SECTION='all'
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --section) shift; SECTION="${1:-}" ;;
    --section=*) SECTION="${1#--section=}" ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    '') ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done
case "$SECTION" in
  all|next|prompt) ;;
  *) echo "Unknown section: $SECTION (expected 'all', 'next' or 'prompt')" >&2; exit 1 ;;
esac

[ -d "$REPO_ROOT" ] || { echo "Cannot read the repository root: $REPO_ROOT" >&2; exit 1; }

missing=()
note_missing() { missing+=("$1"); }

# --- git, read-only -----------------------------------------------------------------------------
git_ok=0
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 && git_ok=1

branch='unknown'; commit='unknown'; repo_name='unknown'
# latest_tag starts EMPTY, not the text "null": jnul emits a bare JSON null only for an empty
# string, so seeding it with the word produced the string "null" in the JSON -- a value that parses
# but lies. tag_count is a number field and carries the literal null for "no source".
tag_count='null'; latest_tag=''
if [ "$git_ok" -eq 1 ]; then
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  # A remote URL is only a good name source when it looks like one. Stripping to the last path
  # segment turned a local remote of "." into the repository name "." -- a value that is not wrong
  # so much as useless. Take the name from a host-style URL; otherwise use the directory, which is
  # always meaningful; and say "unknown" only when neither yields a usable word.
  remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  repo_name=''
  if printf '%s' "$remote" | grep -qE '^([a-z]+://|[^/]+@[^/]+:)'; then
    repo_name="$(printf '%s' "$remote" | sed 's|/$||; s|\.git$||; s|.*[/:]||')"
  fi
  case "$repo_name" in
    ''|.|..) repo_name='' ;;
  esac
  printf '%s' "$repo_name" | grep -q '[A-Za-z0-9]' || repo_name=''
  if [ -z "$repo_name" ]; then
    repo_name="$(basename "$REPO_ROOT")"
    case "$repo_name" in
      ''|.|..|/) repo_name='unknown' ;;
    esac
  fi
  tag_count="$(git -C "$REPO_ROOT" tag 2>/dev/null | grep -c . )"
  tag_count="${tag_count:-0}"
  lt="$(git -C "$REPO_ROOT" tag --sort=-v:refname 2>/dev/null | head -1)"
  [ -n "$lt" ] && latest_tag="$lt"
else
  note_missing 'git metadata'
  repo_name="$(basename "$REPO_ROOT")"
fi

# --- blueprint.version --------------------------------------------------------------------------
bp_version='unknown'; bp_role='unknown'
if [ -f "$REPO_ROOT/blueprint.version" ]; then
  v="$(grep -m1 '"version"' "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
  r="$(grep -m1 '"role"'    "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
  [ -n "$v" ] && bp_version="$v"
  [ -n "$r" ] && bp_role="$r"
else
  note_missing 'blueprint.version'
fi

# --- the state ledger ---------------------------------------------------------------------------
LEDGER="$REPO_ROOT/.ai/context/current-state.md"
ledger_present='false'; s_now=''; s_next=''; s_blocked=''
if [ -f "$LEDGER" ]; then
  ledger_present='true'
  # A ledger bullet wraps across indented continuation lines; reading only the first line cuts the
  # sentence mid-clause. Take the bullet and fold its continuations into one line.
  bullet() {   # bullet <label>
    awk -v lab="- $1:" '
      index($0, lab) == 1 { found = 1; sub(/^- [^:]*: */, ""); buf = $0; next }
      found && /^  [^ -]/ { sub(/^  */, " "); buf = buf $0; next }
      found { print buf; exit }
      END { if (found) print buf }
    ' "$LEDGER" | head -1
  }
  s_now="$(bullet 'Now')"
  s_next="$(bullet 'Next')"
  s_blocked="$(bullet 'Blocked by')"
else
  note_missing '.ai/context/current-state.md'
fi

# --- work in flight -----------------------------------------------------------------------------
count_md() {   # count_md <dir> -> a count, or 'null' when the directory does not exist
  # `grep -c` exits 1 on zero matches, so a `|| printf 0` fallback prints a SECOND number and the
  # field becomes two lines. Count into a variable and normalise instead.
  [ -d "$1" ] || { printf 'null'; return; }
  local n
  n="$(find "$1" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -v '/README\.md$' | grep -c . )"
  printf '%s' "${n:-0}"
}
t_inbox="$(count_md "$REPO_ROOT/.ai/tasks/inbox")"
t_active="$(count_md "$REPO_ROOT/.ai/tasks/active")"
t_done="$(count_md "$REPO_ROOT/.ai/tasks/completed")"
p_active="$(count_md "$REPO_ROOT/.ai/plans/active")"
[ "$t_active" = 'null' ] && note_missing '.ai/tasks/'
[ "$p_active" = 'null' ] && note_missing '.ai/plans/'

# --- the open-questions register ----------------------------------------------------------------
QUESTIONS="$REPO_ROOT/.ai/memory/open-questions.md"
q_open='null'; q_answered='null'
if [ -f "$QUESTIONS" ]; then
  q_open="$(awk -F'|' '/^\| [0-9]{3} /{gsub(/ /,"",$6); if($6=="open") n++} END{print n+0}' "$QUESTIONS")"
  q_answered="$(awk -F'|' '/^\| [0-9]{3} /{gsub(/ /,"",$6); if($6=="answered") n++} END{print n+0}' "$QUESTIONS")"
else
  note_missing '.ai/memory/open-questions.md'
fi

# --- the validation surface ---------------------------------------------------------------------
# Counted from check-all's own table, never from a number typed into a document.
CHECKALL="$REPO_ROOT/scripts/validation/check-all.sh"
checkall_present='false'; gating='null'; informational='null'
if [ -f "$CHECKALL" ]; then
  checkall_present='true'
  # The same grammar check-public-surface uses, deliberately -- one place decides what a row is.
  # Leading whitespace is allowed because `placeholders` is declared inside the --strict if/else and
  # is indented; an anchored ^run_check drops it and undercounts by one. A name declared both ways
  # counts as informational, because the default run is what a reader sees.
  g=0; i=0
  while IFS= read -r cname; do
    [ -z "$cname" ] && continue
    flags="$(grep -oE "run_check +'$cname' +'[^']+' +[01]" "$CHECKALL" | grep -oE '[01]$' | sort -u | tr -d '\n')"
    case "$flags" in
      1) g=$((g + 1)) ;;
      *) i=$((i + 1)) ;;
    esac
  done < <(grep -oE "^[[:space:]]*run_check +'[a-z-]+'" "$CHECKALL" | grep -oE "'[a-z-]+'" | tr -d "'" | sort -u)
  gating="$g"; informational="$i"
else
  note_missing 'scripts/validation/check-all.sh'
fi

# --- maturity, read from the decision that defines it --------------------------------------------
# Never computed here. The decision defines each track as criteria met over criteria declared, and
# an adopting project has no such record -- .ai/memory is project-owned and never synced -- so all
# three are null there rather than inherited from this repository.
DECISION_REL='docs/roadmap.md'
DECISION="$REPO_ROOT/$DECISION_REL"
m_install='null'; m_pcc='null'; m_e2e='null'; m_source='missing'
if [ -f "$DECISION" ]; then
  m_source="$DECISION_REL"
  pct() { grep -m1 "^| $1 " "$DECISION" | grep -oE '~[0-9]+%' | head -1 | tr -cd '0-9'; }
  vi="$(pct 'Installability')"
  vp="$(pct 'Project Command Center')"
  ve="$(pct 'Driving a real project end to end')"
  [ -n "$vi" ] && m_install="$vi"
  [ -n "$vp" ] && m_pcc="$vp"
  [ -n "$ve" ] && m_e2e="$ve"
else
  note_missing "$DECISION_REL"
fi

# --- next phase, from the roadmap ----------------------------------------------------------------
ROADMAP="$REPO_ROOT/docs/roadmap.md"
next_phase=''
if [ -f "$ROADMAP" ]; then
  next_phase="$(grep -m1 -E '^## M-[0-9]+' "$ROADMAP" | sed 's/^## *//')"
else
  note_missing 'docs/roadmap.md'
fi

# --- project state --------------------------------------------------------------------------------
# Order matters: undefined outranks blocked and active. A project that has not been defined cannot
# have meaningful work in flight, and saying so is more useful than reporting the work.
project_state='ready'
blocking_markers='null'
PLACEHOLDERS="$REPO_ROOT/scripts/validation/check-placeholders.sh"
if [ -f "$PLACEHOLDERS" ]; then
  ph_out="$(bash "$PLACEHOLDERS" 2>/dev/null)"
  bm="$(printf '%s' "$ph_out" | grep -oE '\(blocking: [0-9]+\)' | grep -oE '[0-9]+' | head -1)"
  [ -n "$bm" ] && blocking_markers="$bm"
fi
if [ "$bp_version" = 'unknown' ] || [ "$git_ok" -eq 0 ]; then
  project_state='unknown'
elif [ "$blocking_markers" != 'null' ] && [ "${blocking_markers:-0}" -gt 0 ]; then
  project_state='undefined'
elif [ -n "$s_blocked" ] && [ "$s_blocked" != 'none' ]; then
  project_state='blocked'
elif { [ "$t_active" != 'null' ] && [ "${t_active:-0}" -gt 0 ]; } ||
     { [ "$p_active" != 'null' ] && [ "${p_active:-0}" -gt 0 ]; }; then
  project_state='active'
fi

# --- the project map ------------------------------------------------------------------------------
# Ten sections, each answering the same three questions: does this surface exist, what was read, and
# how much is there. The state vocabulary is deliberately small -- present, partial, missing,
# unknown -- because a map that hedges in ten different ways is a map nobody can act on.
#
# "partial" means the documents exist and still carry TBD markers. That is a plainer measure than
# the one check-placeholders applies, and it is named plainly for that reason: unfilledDocuments,
# not "blocking". The gate's number is reported once, under requirements, and comes from the
# checker itself rather than from a fourth grammar invented here.
count_docs() {   # count_docs <dir> -> count, or 'null' when the directory is absent
  [ -d "$1" ] || { printf 'null'; return; }
  local n
  n="$(find "$1" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -v '/README\.md$' | grep -c .)"
  printf '%s' "${n:-0}"
}
count_unfilled() {   # count_unfilled <dir> -> documents containing a TBD marker, or 'null'
  [ -d "$1" ] || { printf 'null'; return; }
  local n
  n="$(grep -rl 'TBD' "$1" --include='*.md' 2>/dev/null | grep -v '/README\.md$' | grep -c .)"
  printf '%s' "${n:-0}"
}
doc_state() {   # doc_state <count> <unfilled>
  if [ "$1" = 'null' ] || [ "${1:-0}" -eq 0 ] 2>/dev/null; then printf 'missing'; return; fi
  if [ "$2" != 'null' ] && [ "${2:-0}" -gt 0 ]; then printf 'partial'; return; fi
  printf 'present'
}
list_docs() {   # list_docs <dir> -> newline-separated basenames
  [ -d "$1" ] || return 0
  find "$1" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -v '/README\.md$' | sed 's|.*/||' | sort
}

prod_n="$(count_docs "$REPO_ROOT/docs/product")";       prod_u="$(count_unfilled "$REPO_ROOT/docs/product")"
arch_n="$(count_docs "$REPO_ROOT/docs/architecture")";  arch_u="$(count_unfilled "$REPO_ROOT/docs/architecture")"
dom_n="$(count_docs "$REPO_ROOT/docs/domains")";        dom_u="$(count_unfilled "$REPO_ROOT/docs/domains")"
dec_n="$(count_docs "$REPO_ROOT/.ai/memory/decisions")"
dec_recent="$(list_docs "$REPO_ROOT/.ai/memory/decisions" | tail -1)"
arch_recent="$dec_recent"

# Migrations: only conventional locations, and null rather than 0 when none exists -- a project
# with no database is not a project with an empty migrations directory.
mig_n='null'; mig_dir=''
for d in migrations db/migrations database/migrations supabase/migrations prisma/migrations; do
  if [ -d "$REPO_ROOT/$d" ]; then
    mig_dir="$d"
    mig_n="$(find "$REPO_ROOT/$d" -type f 2>/dev/null | grep -c .)"
    mig_n="${mig_n:-0}"
    break
  fi
done

t_active_names="$(list_docs "$REPO_ROOT/.ai/tasks/active")"
t_recent_done="$(list_docs "$REPO_ROOT/.ai/tasks/completed" | tail -1)"
next_slice_active='false'
[ "$t_active" != 'null' ] && [ "${t_active:-0}" -gt 0 ] && next_slice_active='true'

# Slice age. "Which slices are open and closed" was only half the criterion -- the other half is
# SINCE WHEN, and a name with no age cannot tell a week-old slice from a stalled one.
#
# Read from git and from nothing else. Filesystem mtime was considered and rejected: in a fresh
# clone it is the checkout time, so every task would report as brand new -- an answer to a different
# question than the one asked, which is exactly the invention this command refuses. When git cannot
# answer, the age is null and ageSource says unknown.
#
# A shallow clone is treated as no answer at all. `git log` there walks only the fetched commits and
# happily returns the boundary commit for any path, which is how check-state-freshness once reported
# a stale ledger as fresh (1.15.1). A cheap rev-parse settles it before anything is measured.
age_source='unknown'
if [ "$git_ok" -eq 1 ]; then
  shallow="$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)"
  [ "$shallow" = 'false' ] && age_source='git'
fi
now_epoch="$(date +%s 2>/dev/null)"
[ -n "$now_epoch" ] || age_source='unknown'

days_since() {   # days_since <iso-8601 timestamp> -> whole days, or empty
  [ -n "$1" ] || return 0
  local t
  t="$(date -d "$1" +%s 2>/dev/null)" || return 0
  [ -n "$t" ] || return 0
  printf '%s' "$(( (now_epoch - t) / 86400 ))"
}
added_age() {   # added_age <path> -> days since the commit that ADDED it
  [ "$age_source" = 'git' ] || return 0
  days_since "$(git -C "$REPO_ROOT" log --diff-filter=A --format=%cI -- "$1" 2>/dev/null | tail -1)"
}
touched_age() {   # touched_age <path> -> days since the commit that LAST touched it
  [ "$age_source" = 'git' ] || return 0
  days_since "$(git -C "$REPO_ROOT" log -1 --format=%cI -- "$1" 2>/dev/null)"
}

# activeAge answers how long work has been open, so it is the OLDEST active task -- the one that has
# been waiting longest, not the one touched most recently. mostRecentCompletedAge answers how
# recently something was finished, so it is the last touch on the newest completed file: moving a
# task into completed/ is itself a commit against that path.
t_active_age=''
if [ -n "$t_active_names" ]; then
  while IFS= read -r tn; do
    [ -z "$tn" ] && continue
    a="$(added_age "$REPO_ROOT/.ai/tasks/active/$tn")"
    [ -z "$a" ] && continue
    if [ -z "$t_active_age" ] || [ "$a" -gt "$t_active_age" ]; then t_active_age="$a"; fi
  done <<< "$t_active_names"
fi
t_done_age=''
[ -n "$t_recent_done" ] && t_done_age="$(touched_age "$REPO_ROOT/.ai/tasks/completed/$t_recent_done")"
# A source that produced no usable age for anything present is not a working source.
if [ "$age_source" = 'git' ] && [ -z "$t_active_age" ] && [ -z "$t_done_age" ] &&
   { [ -n "$t_active_names" ] || [ -n "$t_recent_done" ]; }; then
  age_source='unknown'
fi

# Governance: read, never touched. codeAuthorized and the window are facts about the project's own
# gate; this command reports them and has no path that could change either.
GOV="$REPO_ROOT/.ai/context/governance.json"
gov_state='missing'; gov_authorized='null'; gov_allowed='null'; gov_window='null'
if [ -f "$GOV" ]; then
  gov_state='present'
  ga="$(grep -m1 '"codeAuthorized"' "$GOV" | grep -o 'true\|false')"
  [ -n "$ga" ] && gov_authorized="$ga"
  gw="$(awk '/"implementationWindow"/{f=1} f && /"active"/{print; exit}' "$GOV" | grep -o 'true\|false')"
  [ -n "$gw" ] && gov_window="$gw"
  blk="$(awk '/"allowedPaths"/{f=1} f{printf "%s", $0; if (index($0, "]")) exit}' "$GOV")"
  blk="${blk#*[}"; blk="${blk%%]*}"
  gov_allowed="$(printf '%s' "$blk" | grep -o '"[^"]*"' | grep -c .)"
  gov_allowed="${gov_allowed:-0}"
else
  note_missing '.ai/context/governance.json'
fi

# The next capability that does not exist yet, read from the roadmap's own criteria table rather
# than decided here. First row still marked "not built" wins.
next_capability=''
if [ -f "$ROADMAP" ]; then
  next_capability="$(grep -E '^\| [0-9]+ \|.*\| not built \|' "$ROADMAP" | head -1 | awk -F'|' '{gsub(/^ | $/,"",$3); print $3}')"
fi

# --- the recommendation, the two drafts, and the generated prompt ----------------------------------
# Derived from what was already read above, and none of it decides anything: the recommendation names
# a row the roadmap already carries, the governance draft is a suggestion a person applies, the
# validation plan is a list of commands nobody here has run, and the prompt is assembled from those
# three. No new source is opened for any of it.

# Choosing the next slice. "The first incomplete row" was a placeholder for this: it answered which
# row comes first in the table, not which one is smallest or whether it can actually be started.
#
# Every qualifying row is normalised once -- number, status, name, the rest of its cells, and the
# section that owns it -- and a table qualifies only when it carries a status column. A two-column
# criteria list has no status to read, and inferring one from the criterion's wording would be
# invention.
rec_rows=''
if [ -f "$ROADMAP" ]; then
  rec_rows="$(awk '
    /^## / { sec = $0; sub(/^## */, "", sec) }
    /^\| *[0-9]+ *\|/ {
      n = split($0, c, "|")
      if (n < 6) next
      num = c[2]; gsub(/ /, "", num)
      name = c[3]; gsub(/^ +| +$/, "", name)
      # The verdict LEADS the cell and the rest is detail, so the match is anchored. Scanning the
      # whole cell read "**done** -- partial rows before unstarted ones" as partial: a row was
      # reclassified by a word in its own explanation, and the command then recommended a criterion
      # it had just been told was finished.
      st = c[n - 1]
      gsub(/\*/, "", st)
      gsub(/^[ \t]+|[ \t]+$/, "", st)
      s = "unknown"
      if (st ~ /^not built/) s = "not built"
      else if (st ~ /^partial/) s = "partial"
      else if (st ~ /^done/) s = "done"
      rest = ""
      for (i = 4; i <= n - 1; i++) rest = rest " " c[i]
      gsub(/\|/, " ", rest)
      print num "|" s "|" name "|" rest "|" sec
    }' "$ROADMAP")"
fi
# The rows already complete, for the prerequisite test below, keyed by SECTION and number. Row
# numbers restart in every criteria table, so a global set of numbers let one phase's "#4 is done"
# satisfy another phase's "requires #4" -- a prerequisite marked met by a coincidence of numbering.
rec_done_keys="$(printf '%s\n' "$rec_rows" | awk -F'|' '$2 == "done" { print $5 "#" $1 }')"

# Two orderings decide "smallest", and both are read from the table rather than judged here:
# a partial row is less remaining work than an unstarted one, because part of it already exists; and
# within a status, the lower number comes first because that is the order the project declared.
#
# A prerequisite counts only when the row DECLARES it, as "requires #N". Absence of a declaration
# means no prerequisite -- a prerequisite this command inferred would be one nobody agreed to. A row
# whose declared prerequisite is unmet is skipped, and every skip is reported: silently dropping a
# row is how a recommendation starts lying about what it considered.
rec_capability=''; next_section=''; rec_selected_status='unknown'; rec_selected_number=''
rec_skipped=''; rec_incomplete=0
best_partial=''; best_unstarted=''
while IFS='|' read -r r_num r_stat r_name r_rest r_sec; do
  [ -z "$r_num" ] && continue
  case "$r_stat" in
    partial|'not built') ;;
    *) continue ;;
  esac
  rec_incomplete=$((rec_incomplete + 1))
  unmet=''
  for req in $(printf '%s' "$r_rest" | grep -oE 'requires #[0-9]+' | grep -oE '[0-9]+'); do
    printf '%s\n' "$rec_done_keys" | grep -qxF "$r_sec#$req" ||
      unmet="${unmet:+$unmet, }#$req"
  done
  if [ -n "$unmet" ]; then
    rec_skipped="${rec_skipped:+$rec_skipped
}#$r_num $r_name -- declares requires $unmet, which is not complete"
    continue
  fi
  if [ "$r_stat" = 'partial' ] && [ -z "$best_partial" ]; then
    best_partial="$r_num|$r_name|$r_sec"
  elif [ "$r_stat" = 'not built' ] && [ -z "$best_unstarted" ]; then
    best_unstarted="$r_num|$r_name|$r_sec"
  fi
done <<< "$rec_rows"

sel=''
if [ -n "$best_partial" ]; then
  sel="$best_partial"; rec_selected_status='partial'
elif [ -n "$best_unstarted" ]; then
  sel="$best_unstarted"; rec_selected_status='not built'
fi
if [ -n "$sel" ]; then
  rec_selected_number="$(printf '%s' "$sel" | cut -d'|' -f1)"
  rec_capability="$(printf '%s' "$sel" | cut -d'|' -f2)"
  next_section="$(printf '%s' "$sel" | cut -d'|' -f3)"
fi

# nextPhase was the FIRST phase heading, which stops being the next one the moment that phase is
# finished: a prompt would then be titled with a phase the roadmap itself calls complete. A phase is
# skipped only when it owns a status-bearing table and every row in it is done -- a phase whose
# criteria are prose has nothing to be complete by, so it is never skipped on a guess.
if [ -n "$rec_rows" ]; then
  complete_sections="$(printf '%s\n' "$rec_rows" | awk -F'|' '
    { tbl[$5] = 1; if ($2 == "partial" || $2 == "not built") inc[$5] = 1 }
    END { for (s in tbl) if (!(s in inc)) print s }')"
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    skip=0
    while IFS= read -r cs; do
      [ -n "$cs" ] && [ "$cs" = "$h" ] && skip=1
    done <<< "$complete_sections"
    if [ "$skip" -eq 0 ]; then next_phase="$h"; break; fi
  done <<< "$(grep -E '^## M-[0-9]+' "$ROADMAP" | sed 's/^## *//')"
fi

rec_source='missing'
[ -f "$ROADMAP" ] && rec_source='docs/roadmap.md'
rec_ineligible='false'
if [ -n "$rec_capability" ]; then
  if [ "$rec_selected_status" = 'partial' ]; then
    rec_reason="the smallest eligible incomplete criterion, #$rec_selected_number: a partial row, which is less remaining work than an unstarted one"
  else
    rec_reason="the smallest eligible incomplete criterion, #$rec_selected_number: no partial row was eligible, so the lowest-numbered unstarted one"
  fi
  if [ "$ledger_present" = 'true' ] && [ "$gov_state" = 'present' ]; then
    rec_confidence='high'
  else
    rec_confidence='medium'
  fi
elif [ "$rec_incomplete" -gt 0 ]; then
  # Rows remain, and every one of them was skipped. That is a blocked recommendation, not an absent
  # one, and the reasons are already in rec_skipped.
  rec_capability='unknown'
  rec_reason="every incomplete criterion declares a prerequisite that is not complete: $rec_incomplete considered, $rec_incomplete skipped"
  rec_confidence='unknown'
  rec_ineligible='true'
elif [ -n "$rec_rows" ]; then
  rec_capability='unknown'
  rec_reason='every criterion in the roadmap criteria table is complete, so there is no incomplete row to name'
  rec_confidence='unknown'
else
  rec_capability='unknown'
  rec_reason='no roadmap criteria table with a status column could be read, so no capability is named'
  rec_confidence='unknown'
fi

# A blocker is a fact read from a file, never a judgement. Each one names where it came from.
rec_blockers=''
add_blocker() {
  if [ -z "$rec_blockers" ]; then rec_blockers="$1"; else rec_blockers="$rec_blockers
$1"; fi
}
if [ -n "$s_blocked" ] && [ "$s_blocked" != 'none' ]; then
  add_blocker "the state ledger names a blocker: $s_blocked"
fi
if [ "$gov_authorized" = 'false' ]; then
  add_blocker 'code writes are not authorized in .ai/context/governance.json'
fi
if [ "$t_active" != 'null' ] && [ "${t_active:-0}" -gt 0 ]; then
  add_blocker "a task is already active: $(printf '%s' "$t_active_names" | tr '\n' ' ' | sed 's/ *$//')"
fi
# Every skipped row becomes a blocker too when nothing was left to select. A recommendation that
# says "unknown" without saying what it rejected is a recommendation nobody can check.
if [ "$rec_ineligible" = 'true' ] && [ -n "$rec_skipped" ]; then
  while IFS= read -r sk; do
    [ -n "$sk" ] && add_blocker "$sk"
  done <<< "$rec_skipped"
fi
rec_blocked='false'
[ -n "$rec_blockers" ] && rec_blocked='true'

# The governance draft. One declared rule, for the one surface this repository actually has; a
# capability from a section with no rule gets an empty draft and says so. Guessing a path list for a
# surface that does not exist yet is exactly the invention this command refuses. Every drafted path
# is also required to exist, so a draft can never name a file the project does not have.
gd_paths=''; gd_rationale=''
add_draft_path() {   # add_draft_path <path> <why>
  [ -e "$REPO_ROOT/${1%/}" ] || return 0
  if [ -z "$gd_paths" ]; then gd_paths="$1"; else gd_paths="$gd_paths
$1"; fi
  if [ -z "$gd_rationale" ]; then gd_rationale="$1 -- $2"; else gd_rationale="$gd_rationale
$1 -- $2"; fi
}
if printf '%s' "$next_section" | grep -qiE 'command cent(er|re)'; then
  add_draft_path 'scripts/command/'           'the surface the capability extends'
  add_draft_path 'scripts/hooks/selftest.sh'  'the contract requires a permanent case for each behaviour'
  add_draft_path 'scripts/hooks/selftest.ps1' 'the same case, on the other shell'
  add_draft_path 'docs/roadmap.md'            'the criteria table records the status this slice changes'
  add_draft_path 'blueprint.version'          'scripts/command is portable, so adopting projects receive the change'
fi

# Required is answered conservatively: a gate that cannot be read is assumed closed, never open.
gd_required='false'
[ "$gov_authorized" != 'true' ] && gd_required='true'
if [ "$gov_authorized" = 'null' ]; then
  gd_note='.ai/context/governance.json -- the gate could not be read, so a window is assumed necessary'
  if [ -z "$gd_rationale" ]; then gd_rationale="$gd_note"; else gd_rationale="$gd_rationale
$gd_note"; fi
fi
if [ -f "$GOV" ] && [ -n "$gd_paths" ]; then
  prot="$(awk '/"protectedPaths"/{f=1} f{printf "%s", $0; if (index($0, "]")) exit}' "$GOV" \
          | sed 's/.*\[//; s/\].*//' | grep -o '"[^"]*"' | tr -d '"')"
  while IFS= read -r pp; do
    [ -z "$pp" ] && continue
    root="${pp%%\**}"
    [ -z "$root" ] && continue
    while IFS= read -r dp; do
      [ -z "$dp" ] && continue
      case "$dp" in "$root"*) gd_required='true' ;; esac
    done <<< "$gd_paths"
  done <<< "$prot"
fi

# The validation plan. Every entry names a script that exists, so an adopting project is never told
# to run something it does not have. Nothing here has been executed -- that is the first note.
shell_slice='false'
printf '%s' "$gd_paths" | grep -q 'scripts/' && shell_slice='true'
vp_narrow=''; vp_full=''; vp_notes=''
add_plan() {   # add_plan <narrow|full> <command> <the script that must exist>
  [ -f "$REPO_ROOT/$3" ] || return 0
  case "$1" in
    narrow) if [ -z "$vp_narrow" ]; then vp_narrow="$2"; else vp_narrow="$vp_narrow
$2"; fi ;;
    full)   if [ -z "$vp_full" ]; then vp_full="$2"; else vp_full="$vp_full
$2"; fi ;;
  esac
}
add_note() { if [ -z "$vp_notes" ]; then vp_notes="$1"; else vp_notes="$vp_notes
$1"; fi; }
if [ "$rec_capability" != 'unknown' ]; then
  add_plan narrow 'bash scripts/command/project-status.sh --json' 'scripts/command/project-status.sh'
  add_plan narrow 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/project-status.ps1 -Json' 'scripts/command/project-status.ps1'
  add_plan narrow 'bash scripts/hooks/selftest.sh' 'scripts/hooks/selftest.sh'
  add_plan narrow 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/selftest.ps1' 'scripts/hooks/selftest.ps1'
fi
add_plan full 'bash scripts/validation/check-all.sh' 'scripts/validation/check-all.sh'
add_plan full 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1' 'scripts/validation/check-all.ps1'
add_plan full 'bash scripts/release/selftest-release.sh' 'scripts/release/selftest-release.sh'
vp_ci='false'
if [ "$shell_slice" = 'true' ] && ! command -v shellcheck >/dev/null 2>&1; then vp_ci='true'; fi
add_note 'No check in this plan has been run.'
if [ "$vp_ci" = 'true' ]; then
  add_note 'ShellCheck is not installed here and this slice changes shell files, so CI is the only place its result can come from.'
fi
if [ "$rec_capability" = 'unknown' ]; then
  add_note 'No capability could be read, so this plan lists the repository gates rather than a slice-specific narrow set.'
fi

# The generated prompt, assembled from the fields above and from nothing else, so re-running the
# command on an unchanged repository produces the same text. A prohibition is dropped only when the
# roadmap section is itself about that subject -- a phase about the CLI may not be told to avoid the
# CLI.
# Matched against whatever the prompt is actually ABOUT. With no row selected there is no owning
# section, and reading the empty string kept every prohibition -- so a prompt titled with the CLI
# phase also told its reader not to start CLI work. The subject is the phase in that case.
sect_l="$(printf '%s' "${next_section:-$next_phase}" | tr 'A-Z' 'a-z')"
sect_has() { printf '%s' "$sect_l" | grep -qE "$1"; }
dn=''
add_dn() { if [ -z "$dn" ]; then dn="$1"; else dn="$dn
$1"; fi; }

# WHERE THIS LIST COMES FROM, and why it is not written here any more. These entries used to be
# hardcoded above, and this file is portable -- so every adopting project's generated prompt named
# the private repositories of the project this engine was written in, and forbade a visibility
# change that was never that project's business. Those belong to whoever owns them.
#
# They now live in .ai/context/constraints.md, which is project-specific: sync never copies it, so
# a source repository keeps its own list while an adopter's copy is seeded from
# templates/constraints-template.md with generic entries instead. Note that this comment names no
# repository either: a comment in a portable file travels just as far as the code under it.
#
# Two forms, and nothing else is read:
#   - when-not `regex`: text     emitted unless the named slice is about that subject
#   - text                       always emitted
CONSTRAINTS="$REPO_ROOT/.ai/context/constraints.md"
dn_found=0
if [ -r "$CONSTRAINTS" ]; then
  # Read only the "## Prompt Prohibitions" section: awk holds a flag between that heading and the
  # next same-level heading, so a bullet elsewhere in the file can never be mistaken for one here.
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    dn_found=1
    case "$line" in
      'when-not '*)
        # Split on the FIRST ": " after the closing backtick, so a regex may contain anything.
        cond="$(printf '%s' "$line" | sed -n 's/^when-not `\(.*\)`: .*$/\1/p')"
        text="$(printf '%s' "$line" | sed -n 's/^when-not `.*`: \(.*\)$/\1/p')"
        if [ -n "$cond" ] && [ -n "$text" ]; then
          sect_has "$cond" || add_dn "- $text"
        else
          # A malformed line is still a prohibition someone meant. Emit it verbatim rather than
          # dropping it silently: losing a "do not" is the one failure mode worth being loud about.
          add_dn "- $line"
        fi
        ;;
      *) add_dn "- $line" ;;
    esac
  done <<EOF
$(awk '
  /^## Prompt Prohibitions[ \t]*$/ { inside = 1; sub_on = 0; next }
  inside && /^## / { inside = 0 }
  # Only bullets inside a ### subsection are entries. The prose above the first one explains the
  # format using bullets of its own, and reading those emitted the documentation as prohibitions --
  # found by running it. The subsections are what make the section both readable and parseable.
  inside && /^### / { sub_on = 1; next }
  inside && sub_on && /^- / { sub(/^- /, ""); print }
' "$CONSTRAINTS")
EOF
fi

# FAILS SAFE, NEVER SILENT. With no section to read, a prompt with no "Do not" list would be a
# prompt that quietly dropped its guardrails. The fallback restates the contract's own
# non-negotiable rules, which are true of every project, and names nothing specific to any.
if [ "$dn_found" -eq 0 ]; then
  add_dn '- expand the scope beyond the capability named above'
  add_dn '- weaken, skip, or delete a test to obtain a passing result'
  add_dn '- disable or bypass a security control'
  add_dn '- commit secrets, credentials, tokens, or personal data'
  add_dn '- push'
  add_note 'No "## Prompt Prohibitions" section was found in .ai/context/constraints.md, so the generated prompt carries the built-in default. Add that section to make the prompt name your own constraints.'
fi

if [ "$gd_required" = 'true' ]; then
  gov_line='A governance window is required before this slice may write. The draft is in this report; a person opens it, never the command.'
else
  gov_line='No governance window is required: the drafted paths are not protected and code writes are already authorized.'
fi
# A prompt titled "unknown" is a defect in the artifact, not a fact about the project. When no row
# can be named -- every criterion complete, or none eligible -- the phase the roadmap already names
# is the honest subject, and the capability line still says unknown so nothing is dressed up.
prompt_subject="$rec_capability"
if [ "$rec_capability" = 'unknown' ] && [ -n "$next_phase" ]; then
  prompt_subject="$next_phase"
fi
vp_first_narrow="$(printf '%s' "$vp_narrow" | head -1)"
vp_first_full="$(printf '%s' "$vp_full" | head -1)"
[ -z "$vp_first_narrow" ] && vp_first_narrow='none derived -- no capability was named'
[ -z "$vp_first_full" ] && vp_first_full='none derived -- no gate script was found'

generated_prompt="$(cat <<PROMPTEOF
# ForgeOS -- $prompt_subject

You are working in:

$REPO_ROOT

Current state:

- Repository: $repo_name
- Branch: $branch
- HEAD: $commit
- Version: $bp_version
- Project state: $project_state
- Next capability: $rec_capability
- Read its wording from: $rec_source

Goal:

Implement the capability named above. Its acceptance criteria are the row that names it in the
source above. Read that row before writing anything, and do not restate it from this prompt.

Pre-checks:

- confirm the branch, and that the working tree is clean
- confirm HEAD is $commit
- confirm the version is $bp_version
- read the authoritative files before editing anything
- reproduce any defect before fixing it

Governance:

$gov_line

Validation:

- narrow: $vp_first_narrow
- full: $vp_first_full
- ShellCheck must come from CI: $vp_ci

Do not:

$dn

Stop after the local commit and report. Do not push.
PROMPTEOF
)"

# --- the session package (--section prompt) -------------------------------------------------------
# Everything the person starting the next session would otherwise ask a coordinator for: session,
# model, effort, scope, policy, reading order, report shape, and the paste-ready prompt. Model and
# effort come from scripts/lib/session-policy.json -- a data table, first matching category wins --
# never from this file. The package REFUSES rather than invents: each fact below is read from a
# file, and a missing file becomes a named refusal instead of a plausible guess.
POLICY_FILE="$REPO_ROOT/scripts/lib/session-policy.json"
pkg_model=''; pkg_effort=''; pkg_model_reason=''; pkg_category=''
if [ -f "$POLICY_FILE" ]; then
  # One category per line by contract (the file's own $comment says so), so a dependency-free read
  # works on every platform: no jq, no python, exactly like governance.json above. The contract is
  # ENFORCED, and on both shells: a "key" line that does not also carry its model and effort means
  # the table was reformatted -- an editor's format-on-save is enough -- and a parser that shrugged
  # here once picked a category with an empty model and exit 0, failing OPEN on the one file this
  # feature tells projects to edit. Malformed means refuse, on this shell and the other one alike.
  # Matched against the capability text ALONE, not its phase heading: a heading names the theme of
  # a whole phase, and one domain word in it would drag every row under it into the same category
  # -- found by running this against a real roadmap, where a phase about adoption made an
  # implementation row recommend the adoption tier.
  pkg_policy_ok=1
  while IFS= read -r pline; do
    printf '%s' "$pline" | grep -q '"model"' && printf '%s' "$pline" | grep -q '"effort"' || pkg_policy_ok=0
  done <<PKGCHKEOF
$(grep '"key"' "$POLICY_FILE")
PKGCHKEOF
  if [ "$pkg_policy_ok" -eq 1 ]; then
    pkg_target="$(printf '%s' "$prompt_subject" | tr 'A-Z' 'a-z')"
    while IFS= read -r pline; do
      pkey="$(printf '%s' "$pline" | sed -n 's/.*"key": *"\([^"]*\)".*/\1/p')"
      pmodel="$(printf '%s' "$pline" | sed -n 's/.*"model": *"\([^"]*\)".*/\1/p')"
      peffort="$(printf '%s' "$pline" | sed -n 's/.*"effort": *"\([^"]*\)".*/\1/p')"
      [ -n "$pkey" ] && [ -n "$pmodel" ] && [ -n "$peffort" ] || continue
      pmatch="$(printf '%s' "$pline" | sed -n 's/.*"match": *"\([^"]*\)".*/\1/p')"
      if [ -z "$pmatch" ] || printf '%s' "$pkg_target" | grep -qiE "$pmatch"; then
        pkg_category="$pkey"
        pkg_model="$pmodel"
        pkg_effort="$peffort"
        pkg_model_reason="$(printf '%s' "$pline" | sed -n 's/.*"reason": *"\([^"]*\)".*/\1/p')"
        break
      fi
    done <<PKGPOLEOF
$(grep '"key"' "$POLICY_FILE")
PKGPOLEOF
  fi
fi

# What the package cannot say without inventing. Each entry names the file and the way out.
pkg_missing=''
add_pkg_missing() { if [ -z "$pkg_missing" ]; then pkg_missing="$1"; else pkg_missing="$pkg_missing
$1"; fi; }
if [ "$rec_source" = 'missing' ]; then
  add_pkg_missing 'docs/roadmap.md -- the roadmap is missing, so no capability can be named; seed it from templates/roadmap-template.md'
elif [ "$rec_capability" = 'unknown' ]; then
  add_pkg_missing "docs/roadmap.md -- $rec_reason; give the next phase a criteria table with a Status column, or mark a row incomplete"
fi
if [ "$ledger_present" != 'true' ]; then
  add_pkg_missing '.ai/context/current-state.md -- the state ledger is missing, so the package cannot say where the project is; seed it from templates/state-ledger-template.md'
fi
if [ "$gov_state" != 'present' ]; then
  add_pkg_missing '.ai/context/governance.json -- the gate cannot be read, so scope and authorization cannot be stated; seed it from templates/governance-template.json'
fi
if [ -z "$pkg_category" ]; then
  add_pkg_missing 'scripts/lib/session-policy.json -- the model policy table is missing or matched nothing, so model and effort cannot be recommended; restore it from the blueprint source'
fi

# Same session or a new one -- decided by the work in flight, not by preference.
if [ "$t_active" != 'null' ] && [ "${t_active:-0}" -gt 0 ]; then
  pkg_new_session='false'
  pkg_session_reason="a task is already active ($(printf '%s' "$t_active_names" | tr '\n' ' ' | sed 's/ *$//')); continue the session that owns it, or resume from its file"
else
  pkg_new_session='true'
  pkg_session_reason='no task is active, so the slice starts clean with only this package as context'
fi
pkg_session_name="$repo_name - $prompt_subject"

# Reading order: only files that exist are listed, in the order a cold session should open them.
pkg_read=''
add_read() {   # add_read <relative path> <why>
  [ -f "$REPO_ROOT/$1" ] || return 0
  if [ -z "$pkg_read" ]; then pkg_read="$1 -- $2"; else pkg_read="$pkg_read
$1 -- $2"; fi
}
add_read 'CLAUDE.md'                        'the entry point; it loads the operating contract'
add_read 'AGENTS.md'                        'the same contract, for tools that read this entry point'
add_read '.ai/context/project.md'           'what this project is'
add_read '.ai/context/constraints.md'       'the hard constraints and the prompt prohibitions'
add_read '.ai/context/current-state.md'     'where the work stands right now'
add_read '.ai/memory/open-questions.md'     'what is deliberately unresolved'
add_read 'docs/roadmap.md'                  'the criteria row that defines this capability'
if [ -n "$t_active_names" ]; then
  while IFS= read -r tn; do
    [ -n "$tn" ] && add_read ".ai/tasks/active/$tn" 'the active task this session continues'
  done <<< "$t_active_names"
fi

# Scope. Allowed comes from the governance draft when one exists; forbidden is read from the
# project's own protected paths, never composed here.
if [ -n "$gd_paths" ]; then
  pkg_allowed="$(printf '%s' "$gd_paths" | tr '\n' ' ' | sed 's/ *$//; s/ /, /g')"
else
  pkg_allowed='only the files the capability acceptance criteria require -- read the criteria row first'
fi
pkg_forbidden=''
add_forbidden() { if [ -z "$pkg_forbidden" ]; then pkg_forbidden="$1"; else pkg_forbidden="$pkg_forbidden
$1"; fi; }
if [ -f "$GOV" ]; then
  gov_prot="$(awk '/"protectedPaths"/{f=1} f{printf "%s", $0; if (index($0, "]")) exit}' "$GOV" \
              | sed 's/.*\[//; s/\].*//' | grep -o '"[^"]*"' | tr -d '"')"
  while IFS= read -r pp; do
    [ -n "$pp" ] && add_forbidden "$pp -- protected by .ai/context/governance.json"
  done <<< "$gov_prot"
fi
add_forbidden 'anything a "Do not" entry below names'

# Commit, push, tag, deploy. This package can authorize NOTHING; it only reports what the project
# itself already refuses, and sends everything else to the owner. Even the commit line is
# governance-aware: behind a closed gate it points at the owner, because "allowed" printed into a
# project whose own governance file says no would be this package overriding the gate it reports.
if [ "$gov_authorized" = 'true' ]; then
  pkg_policy_commit='allowed after the validation plan passes -- local only'
else
  pkg_policy_commit='not authorized by this package -- the governance gate is closed; ask the owner'
fi
if printf '%s' "$dn" | grep -qiE '(^|- )push'; then
  pkg_policy_push="refused by the project's own prohibitions"
else
  pkg_policy_push='not authorized by this package -- ask the owner'
fi
if printf '%s' "$dn" | grep -qiE '(^|[^a-z])tag([^a-z]|$)|release'; then
  pkg_policy_tag="refused by the project's own prohibitions"
else
  pkg_policy_tag='not authorized by this package -- ask the owner'
fi
if printf '%s' "$dn" | grep -qiE 'deploy'; then
  pkg_policy_deploy="refused by the project's own prohibitions"
else
  pkg_policy_deploy='not authorized by this package -- ask the owner'
fi

# The report shape, from the contract's own closing section -- restated as a checklist so the next
# session ends the way every session here is required to end.
pkg_report='Summary -- what was asked and what actually happened
Files Changed -- every file, with why
Validation -- each command run, with its observed result, never its expected one
Acceptance Criteria -- each criterion from the roadmap row, verified individually
Risks and Limitations -- what was not checked, and what that leaves open
Decisions -- anything decided along the way, recorded where decisions live
Next Action -- the next safe step, or none
State -- the state ledger refreshed before this report, so the report summarizes the repository'

pkg_gov_authorized="$gov_authorized"
[ "$pkg_gov_authorized" = 'null' ] && pkg_gov_authorized='unknown'

package_prompt="$(cat <<PKGPROMPTEOF
# ForgeOS session -- $prompt_subject

Session:

- Name: $pkg_session_name
- New session: $pkg_new_session
- Model: $pkg_model
- Effort: $pkg_effort
- Why: $pkg_model_reason

You are working in:

$REPO_ROOT

Current state:

- Repository: $repo_name
- Branch: $branch
- HEAD: $commit
- Version: $bp_version
- Project state: $project_state
- Next capability: $rec_capability
- Read its wording from: $rec_source

Read first, in this order:

$(printf '%s\n' "$pkg_read" | sed 's/^/- /')

Goal:

Implement the capability named above. Its acceptance criteria are the row that names it in the
source above. Read that row before writing anything, and do not restate it from this prompt.

Pre-checks:

- confirm the branch, and that the working tree is clean
- confirm HEAD is $commit
- confirm the version is $bp_version
- read the authoritative files before editing anything
- reproduce any defect before fixing it

Governance:

$gov_line

Scope:

- Allowed: $pkg_allowed
- Forbidden:
$(printf '%s\n' "$pkg_forbidden" | sed 's/^/  - /')

Validation:

- narrow: $vp_first_narrow
- full: $vp_first_full
- ShellCheck must come from CI: $vp_ci

Do not:

$dn

Final report -- include every item:

$(printf '%s\n' "$pkg_report" | sed 's/^/- /')

Stop after the local commit and report. Do not push.
PKGPROMPTEOF
)"

# --- output ---------------------------------------------------------------------------------------
jesc() {   # minimal JSON string escaping: backslash, quote, and the control characters
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\010\013\014\016-\037'
}
jstr() { printf '"%s"' "$(jesc "$1")"; }
jnul() { if [ -z "$1" ]; then printf 'null'; else jstr "$1"; fi; }
jarr() {   # jarr <newline-separated items> -> a JSON array of strings
  local out='' item
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    [ -n "$out" ] && out="$out, "
    out="$out$(jstr "$item")"
  done <<< "${1:-}"
  printf '[%s]' "$out"
}
jmul() {   # a multi-line value as one JSON string: real newlines become the two characters \n
  # Escaping is jesc's job and stays there -- one place decides what a JSON string may contain.
  # jesc keeps CR, which is invalid raw inside a JSON string, so that goes here; then the surviving
  # newlines are folded into an explicit two-character escape.
  jesc "$1" | tr -d '\015' | awk 'BEGIN { ORS = "" } NR > 1 { printf "%s", "\\n" } { print }'
}

# The next-section subset. It carries its own schema id rather than reusing the status one: it is a
# different document with a different shape, and a consumer that trusted "forgeos.project-status/1"
# and then found half the keys missing would be right to complain.
if [ "$JSON" -eq 1 ] && [ "$SECTION" = 'next' ]; then
  cat <<NEXTJSONEOF
{
  "schema": "forgeos.project-next/1",
  "generatedFrom": "repository files only",
  "nextRecommendation": {
    "capability": $(jstr "$rec_capability"),
    "reason": $(jstr "$rec_reason"),
    "source": $(jstr "$rec_source"),
    "confidence": $(jstr "$rec_confidence"),
    "selectedStatus": $(jstr "$rec_selected_status"),
    "blocked": $rec_blocked,
    "blockers": $(jarr "$rec_blockers"),
    "skipped": $(jarr "$rec_skipped")
  },
  "governanceDraft": {
    "required": $gd_required,
    "allowedPaths": $(jarr "$gd_paths"),
    "rationale": $(jarr "$gd_rationale"),
    "canApplyAutomatically": false
  },
  "validationPlan": {
    "narrow": $(jarr "$vp_narrow"),
    "full": $(jarr "$vp_full"),
    "ciRequired": $vp_ci,
    "notes": $(jarr "$vp_notes")
  },
  "generatedPrompt": "$(jmul "$generated_prompt")",
  "safety": {
    "canModifyFiles": false,
    "canAuthorizeCode": false,
    "canOpenGovernanceWindow": false
  }
}
NEXTJSONEOF
  exit 0
fi

# The session-package subset. Like the next subset it carries its own schema id -- and unlike every
# other emitter it can refuse: a package with invented facts would be worse than no package, so a
# missing source turns the whole document into a named refusal with exit 1.
if [ "$JSON" -eq 1 ] && [ "$SECTION" = 'prompt' ]; then
  if [ -n "$pkg_missing" ]; then
    cat <<PKGREFUSEEOF
{
  "schema": "forgeos.project-prompt/1",
  "generatedFrom": "repository files only",
  "generated": false,
  "missing": $(jarr "$pkg_missing"),
  "safety": {
    "canModifyFiles": false,
    "canAuthorizeCode": false,
    "canOpenGovernanceWindow": false
  }
}
PKGREFUSEEOF
    exit 1
  fi
  cat <<PKGJSONEOF
{
  "schema": "forgeos.project-prompt/1",
  "generatedFrom": "repository files only",
  "generated": true,
  "project": {
    "identity": $(jstr "$repo_name"),
    "version": $(jstr "$bp_version"),
    "branch": $(jstr "$branch"),
    "state": $(jstr "$project_state")
  },
  "stateSummary": {
    "now": $(jnul "$s_now"),
    "next": $(jnul "$s_next"),
    "blockedBy": $(jnul "$s_blocked")
  },
  "nextRecommendation": {
    "capability": $(jstr "$rec_capability"),
    "reason": $(jstr "$rec_reason"),
    "source": $(jstr "$rec_source"),
    "confidence": $(jstr "$rec_confidence"),
    "blocked": $rec_blocked,
    "blockers": $(jarr "$rec_blockers")
  },
  "session": {
    "newSession": $pkg_new_session,
    "reason": $(jstr "$pkg_session_reason"),
    "name": $(jstr "$pkg_session_name"),
    "model": $(jstr "$pkg_model"),
    "effort": $(jstr "$pkg_effort"),
    "modelReason": $(jstr "$pkg_model_reason"),
    "category": $(jstr "$pkg_category")
  },
  "governance": {
    "windowRequired": $gd_required,
    "codeAuthorized": $(jstr "$pkg_gov_authorized"),
    "draftedPaths": $(jarr "$gd_paths")
  },
  "scope": {
    "allowed": $(jstr "$pkg_allowed"),
    "forbidden": $(jarr "$pkg_forbidden")
  },
  "policy": {
    "commit": $(jstr "$pkg_policy_commit"),
    "push": $(jstr "$pkg_policy_push"),
    "tag": $(jstr "$pkg_policy_tag"),
    "deploy": $(jstr "$pkg_policy_deploy")
  },
  "readFirst": $(jarr "$pkg_read"),
  "validationPlan": {
    "narrow": $(jarr "$vp_narrow"),
    "full": $(jarr "$vp_full"),
    "ciRequired": $vp_ci,
    "notes": $(jarr "$vp_notes")
  },
  "reportChecklist": $(jarr "$pkg_report"),
  "generatedPrompt": "$(jmul "$package_prompt")",
  "safety": {
    "canModifyFiles": false,
    "canAuthorizeCode": false,
    "canOpenGovernanceWindow": false
  }
}
PKGJSONEOF
  exit 0
fi

if [ "$JSON" -eq 1 ]; then
  ms=''
  for m in ${missing[@]+"${missing[@]}"}; do
    [ -n "$ms" ] && ms="$ms, "
    ms="$ms$(jstr "$m")"
  done
  cat <<JSONEOF
{
  "schema": "forgeos.project-status/1",
  "generatedFrom": "repository files only",
  "projectState": $(jstr "$project_state"),
  "repository": {
    "name": $(jstr "$repo_name"),
    "branch": $(jstr "$branch"),
    "commit": $(jstr "$commit"),
    "visibility": "unknown"
  },
  "blueprint": {
    "version": $(jstr "$bp_version"),
    "role": $(jstr "$bp_role")
  },
  "state": {
    "ledgerPresent": $ledger_present,
    "now": $(jnul "$s_now"),
    "next": $(jnul "$s_next"),
    "blockedBy": $(jnul "$s_blocked")
  },
  "work": {
    "tasksInbox": $t_inbox,
    "tasksActive": $t_active,
    "tasksCompleted": $t_done,
    "plansActive": $p_active,
    "openQuestions": $q_open,
    "answeredQuestions": $q_answered
  },
  "validation": {
    "checkAllPresent": $checkall_present,
    "gatingChecks": $gating,
    "informationalChecks": $informational,
    "blockingMarkers": $blocking_markers
  },
  "release": {
    "tagCount": $tag_count,
    "latestTag": $(jnul "$latest_tag")
  },
  "maturity": {
    "installability": $m_install,
    "projectCommandCenter": $m_pcc,
    "endToEndProjectDriving": $m_e2e,
    "source": $(jstr "$m_source")
  },
  "map": {
    "product": {
      "state": $(jstr "$(doc_state "$prod_n" "$prod_u")"),
      "sources": $(jarr "docs/product"),
      "documentCount": $prod_n,
      "unfilledDocuments": $prod_u
    },
    "architecture": {
      "state": $(jstr "$(doc_state "$arch_n" "$arch_u")"),
      "sources": $(jarr "$(printf 'docs/architecture\n.ai/memory/decisions')"),
      "documentCount": $arch_n,
      "unfilledDocuments": $arch_u,
      "decisionCount": $dec_n,
      "mostRecentDecision": $(jnul "$arch_recent")
    },
    "dataModel": {
      "state": $(jstr "$(doc_state "$dom_n" "$dom_u")"),
      "sources": $(jarr "$(printf 'docs/domains\n%s' "$mig_dir")"),
      "documentCount": $dom_n,
      "unfilledDocuments": $dom_u,
      "migrationCount": $mig_n
    },
    "requirements": {
      "state": $(jstr "$(doc_state "$prod_n" "$prod_u")"),
      "sources": $(jarr "$(printf 'docs/product\n.ai/context/project.md')"),
      "documentCount": $prod_n,
      "blockingMarkers": $blocking_markers,
      "discoveryClosed": $([ "$blocking_markers" != 'null' ] && [ "${blocking_markers:-0}" -gt 0 ] && printf 'true' || printf 'false')
    },
    "tasks": {
      "state": $(jstr "$([ "$t_active" = 'null' ] && printf 'missing' || printf 'present')"),
      "sources": $(jarr "$(printf '.ai/tasks\n.ai/plans')"),
      "inbox": $t_inbox,
      "active": $t_active,
      "completed": $t_done,
      "activeNames": $(jarr "$t_active_names"),
      "mostRecentCompleted": $(jnul "$t_recent_done"),
      "activeAge": ${t_active_age:-null},
      "mostRecentCompletedAge": ${t_done_age:-null},
      "ageSource": $(jstr "$age_source"),
      "nextSliceActive": $next_slice_active
    },
    "decisions": {
      "state": $(jstr "$([ "$dec_n" = 'null' ] && printf 'missing' || printf 'present')"),
      "sources": $(jarr ".ai/memory/decisions"),
      "count": $dec_n,
      "mostRecent": $(jnul "$dec_recent")
    },
    "openQuestions": {
      "state": $(jstr "$([ "$q_open" = 'null' ] && printf 'missing' || printf 'present')"),
      "sources": $(jarr ".ai/memory/open-questions.md"),
      "open": $q_open,
      "answered": $q_answered
    },
    "validation": {
      "state": $(jstr "$([ "$checkall_present" = 'true' ] && printf 'present' || printf 'missing')"),
      "sources": $(jarr "scripts/validation/check-all.sh"),
      "gatingChecks": $gating,
      "informationalChecks": $informational,
      "blockingMarkers": $blocking_markers
    },
    "release": {
      "state": $(jstr "$([ -n "$latest_tag" ] && printf 'present' || printf 'missing')"),
      "sources": $(jarr "git tags"),
      "tagCount": $tag_count,
      "latestTag": $(jnul "$latest_tag")
    },
    "governance": {
      "state": $(jstr "$gov_state"),
      "sources": $(jarr ".ai/context/governance.json"),
      "codeAuthorized": $gov_authorized,
      "allowedPathCount": $gov_allowed,
      "windowOpen": $gov_window
    }
  },
  "nextPhase": $(jnul "$next_phase"),
  "nextCapability": $(jnul "$next_capability"),
  "nextRecommendation": {
    "capability": $(jstr "$rec_capability"),
    "reason": $(jstr "$rec_reason"),
    "source": $(jstr "$rec_source"),
    "confidence": $(jstr "$rec_confidence"),
    "selectedStatus": $(jstr "$rec_selected_status"),
    "blocked": $rec_blocked,
    "blockers": $(jarr "$rec_blockers"),
    "skipped": $(jarr "$rec_skipped")
  },
  "governanceDraft": {
    "required": $gd_required,
    "allowedPaths": $(jarr "$gd_paths"),
    "rationale": $(jarr "$gd_rationale"),
    "canApplyAutomatically": false
  },
  "validationPlan": {
    "narrow": $(jarr "$vp_narrow"),
    "full": $(jarr "$vp_full"),
    "ciRequired": $vp_ci,
    "notes": $(jarr "$vp_notes")
  },
  "generatedPrompt": "$(jmul "$generated_prompt")",
  "safety": {
    "canModifyFiles": false,
    "canAuthorizeCode": false,
    "canOpenGovernanceWindow": false
  },
  "missingSources": [$ms]
}
JSONEOF
  exit 0
fi

show() { printf '  %-22s %s\n' "$1" "$2"; }
nz()   { if [ -z "$1" ] || [ "$1" = 'null' ]; then printf 'unknown'; else printf '%s' "$1"; fi; }

# The human half of --section prompt: the whole package, self-contained, then out. It refuses with
# exit 1 rather than print a prompt that guesses -- the refusal names every missing file and the
# way to supply it, which is the useful half of a coordinator's answer anyway.
if [ "$SECTION" = 'prompt' ]; then
  echo ''
  echo "ForgeOS session package  [$project_state]"
  if [ -n "$pkg_missing" ]; then
    echo ''
    echo '  cannot generate: a package would have to invent facts, and this command refuses to.'
    echo ''
    echo '  missing:'
    while IFS= read -r pm; do [ -n "$pm" ] && printf '    - %s\n' "$pm"; done <<< "$pkg_missing"
    echo ''
    echo '  This command reads. It writes nothing, authorizes nothing, and opens no governance window.'
    echo ''
    exit 1
  fi
  echo ''
  echo '  project:'
  printf '    %-14s %s\n' 'identity' "$repo_name"
  printf '    %-14s %s\n' 'version' "$bp_version"
  printf '    %-14s %s\n' 'branch' "$branch"
  printf '    %-14s %s\n' 'state' "$project_state"
  [ -n "$s_now" ] && printf '    %-14s %s\n' 'now' "$s_now"
  echo ''
  echo '  next capability:'
  printf '    %-14s %s\n' 'capability' "$rec_capability"
  printf '    %-14s %s\n' 'source' "$rec_source"
  printf '    %-14s %s\n' 'confidence' "$rec_confidence"
  printf '    %-14s %s\n' 'blocked' "$rec_blocked"
  if [ -n "$rec_blockers" ]; then
    while IFS= read -r b; do [ -n "$b" ] && printf '      - %s\n' "$b"; done <<< "$rec_blockers"
  fi
  echo ''
  echo '  session:'
  printf '    %-14s %s\n' 'new session' "$pkg_new_session"
  printf '    %-14s %s\n' 'reason' "$pkg_session_reason"
  printf '    %-14s %s\n' 'name' "$pkg_session_name"
  printf '    %-14s %s\n' 'model' "$pkg_model"
  printf '    %-14s %s\n' 'effort' "$pkg_effort"
  printf '    %-14s %s\n' 'why' "$pkg_model_reason"
  printf '    %-14s %s\n' 'category' "$pkg_category"
  echo ''
  echo '  governance:'
  printf '    %-14s %s\n' 'window needed' "$gd_required"
  printf '    %-14s %s\n' 'codeAuthorized' "$pkg_gov_authorized"
  if [ -n "$gd_rationale" ]; then
    while IFS= read -r r; do [ -n "$r" ] && printf '      - %s\n' "$r"; done <<< "$gd_rationale"
  fi
  echo ''
  echo '  scope:'
  printf '    %-14s %s\n' 'allowed' "$pkg_allowed"
  echo '    forbidden:'
  while IFS= read -r fb; do [ -n "$fb" ] && printf '      - %s\n' "$fb"; done <<< "$pkg_forbidden"
  echo ''
  echo '  policy:'
  printf '    %-8s %s\n' 'commit' "$pkg_policy_commit"
  printf '    %-8s %s\n' 'push' "$pkg_policy_push"
  printf '    %-8s %s\n' 'tag' "$pkg_policy_tag"
  printf '    %-8s %s\n' 'deploy' "$pkg_policy_deploy"
  echo ''
  echo '  read first:'
  while IFS= read -r rf; do [ -n "$rf" ] && printf '    - %s\n' "$rf"; done <<< "$pkg_read"
  echo ''
  echo '  validation plan -- a plan; nothing in it has been run:'
  if [ -n "$vp_narrow" ]; then
    while IFS= read -r c; do [ -n "$c" ] && printf '    narrow   %s\n' "$c"; done <<< "$vp_narrow"
  fi
  if [ -n "$vp_full" ]; then
    while IFS= read -r c; do [ -n "$c" ] && printf '    full     %s\n' "$c"; done <<< "$vp_full"
  fi
  printf '    %-8s %s\n' 'from CI' "ShellCheck required: $vp_ci"
  echo ''
  echo '  final report checklist:'
  while IFS= read -r rp; do [ -n "$rp" ] && printf '    - %s\n' "$rp"; done <<< "$pkg_report"
  echo ''
  echo '  session prompt -- copy everything between the two rules:'
  echo '--------------------------------------------------------------------------------'
  printf '%s\n' "$package_prompt"
  echo '--------------------------------------------------------------------------------'
  echo ''
  echo '  This command reads. It writes nothing, authorizes nothing, and opens no governance window.'
  echo ''
  exit 0
fi

# The human half of --section next. The blocks themselves are printed by the same code further down,
# so this skips the report header and the map rather than reprinting anything.
if [ "$SECTION" = 'next' ]; then
  echo ''
  echo "ForgeOS next step  [$project_state]"
  SKIP_STATUS_BODY=1
else
  SKIP_STATUS_BODY=0
fi

if [ "$SKIP_STATUS_BODY" -eq 0 ]; then
echo ''
echo "ForgeOS project status  [$project_state]"
echo ''
show 'repository' "$repo_name"
show 'branch' "$branch"
show 'commit' "$commit"
show 'blueprint' "$bp_version  (role: $bp_role)"
show 'latest tag' "$(nz "$latest_tag")  of $(nz "$tag_count")"
echo ''
if [ "$ledger_present" = 'true' ]; then
  [ -n "$s_now" ]     && printf '  now        %s\n' "$s_now"
  [ -n "$s_next" ]    && printf '  next       %s\n' "$s_next"
  [ -n "$s_blocked" ] && printf '  blocked by %s\n' "$s_blocked"
else
  echo '  state ledger missing -- .ai/context/current-state.md'
fi
echo ''
show 'tasks' "inbox $(nz "$t_inbox") - active $(nz "$t_active") - completed $(nz "$t_done")"
show 'plans active' "$(nz "$p_active")"
show 'open questions' "$(nz "$q_open") open, $(nz "$q_answered") answered"
show 'validation' "$(nz "$gating") gating, $(nz "$informational") informational"
show 'blocking markers' "$(nz "$blocking_markers")"
echo ''
echo '  maturity toward the public launch bar (95% each):'
show '  installability' "$(nz "$m_install")$([ "$m_install" != 'null' ] && printf '%%')"
show '  command centre' "$(nz "$m_pcc")$([ "$m_pcc" != 'null' ] && printf '%%')"
show '  end-to-end driving' "$(nz "$m_e2e")$([ "$m_e2e" != 'null' ] && printf '%%')"
show '  source' "$m_source"
echo ''
echo '  project map:'
mapline() { printf '    %-14s %-8s %s\n' "$1" "$2" "$3"; }
mapline 'product'       "$(doc_state "$prod_n" "$prod_u")" "$(nz "$prod_n") doc(s), $(nz "$prod_u") unfilled"
mapline 'architecture'  "$(doc_state "$arch_n" "$arch_u")" "$(nz "$arch_n") doc(s), $(nz "$dec_n") decision(s)"
mapline 'dataModel'     "$(doc_state "$dom_n" "$dom_u")"   "$(nz "$dom_n") doc(s), migrations $(nz "$mig_n")"
mapline 'requirements'  "$(doc_state "$prod_n" "$prod_u")" "$(nz "$blocking_markers") blocking marker(s)"
mapline 'tasks'         "$([ "$t_active" = 'null' ] && printf 'missing' || printf 'present')" "active $(nz "$t_active") (age $(nz "$t_active_age")), completed $(nz "$t_done") (last $(nz "$t_done_age")), age from $age_source"
mapline 'decisions'     "$([ "$dec_n" = 'null' ] && printf 'missing' || printf 'present')" "$(nz "$dec_n"), latest $(nz "$dec_recent")"
mapline 'openQuestions' "$([ "$q_open" = 'null' ] && printf 'missing' || printf 'present')" "$(nz "$q_open") open, $(nz "$q_answered") answered"
mapline 'validation'    "$([ "$checkall_present" = 'true' ] && printf 'present' || printf 'missing')" "$(nz "$gating") gating, $(nz "$informational") informational"
mapline 'release'       "$([ -n "$latest_tag" ] && printf 'present' || printf 'missing')" "$(nz "$latest_tag") of $(nz "$tag_count")"
mapline 'governance'    "$gov_state" "codeAuthorized $(nz "$gov_authorized"), window open $(nz "$gov_window"), $(nz "$gov_allowed") allowed path(s)"
echo ''
[ -n "$next_phase" ] && show 'next phase' "$next_phase"
[ -n "$next_capability" ] && show 'next capability' "$next_capability"
if [ "${#missing[@]}" -gt 0 ]; then
  echo ''
  echo "  missing sources (${#missing[@]}) -- reported, not guessed:"
  printf '    - %s\n' "${missing[@]}"
fi
fi   # end of the status body that --section next skips
echo ''
echo '  next recommendation:'
printf '    %-14s %s\n' 'capability' "$rec_capability"
printf '    %-14s %s\n' 'reason' "$rec_reason"
printf '    %-14s %s\n' 'source' "$rec_source"
printf '    %-14s %s\n' 'confidence' "$rec_confidence"
printf '    %-14s %s\n' 'row status' "$rec_selected_status"
printf '    %-14s %s\n' 'blocked' "$rec_blocked"
if [ -n "$rec_blockers" ]; then
  while IFS= read -r b; do [ -n "$b" ] && printf '      - %s\n' "$b"; done <<< "$rec_blockers"
fi
if [ -n "$rec_skipped" ]; then
  printf '    %-14s %s\n' 'skipped' "$(printf '%s' "$rec_skipped" | grep -c .)"
  while IFS= read -r sk; do [ -n "$sk" ] && printf '      - %s\n' "$sk"; done <<< "$rec_skipped"
fi
echo ''
echo '  governance window draft -- a draft only; this command cannot open a window:'
printf '    %-22s %s\n' 'required' "$gd_required"
printf '    %-22s %s\n' 'canApplyAutomatically' 'false'
if [ -n "$gd_rationale" ]; then
  while IFS= read -r r; do [ -n "$r" ] && printf '      - %s\n' "$r"; done <<< "$gd_rationale"
else
  echo '      - no rule covers this section, so no path is drafted'
fi
echo ''
echo '  validation plan -- a plan; nothing in it has been run:'
if [ -n "$vp_narrow" ]; then
  while IFS= read -r c; do [ -n "$c" ] && printf '    narrow   %s\n' "$c"; done <<< "$vp_narrow"
fi
if [ -n "$vp_full" ]; then
  while IFS= read -r c; do [ -n "$c" ] && printf '    full     %s\n' "$c"; done <<< "$vp_full"
fi
printf '    %-8s %s\n' 'from CI' "ShellCheck required: $vp_ci"
while IFS= read -r nte; do [ -n "$nte" ] && printf '    note     %s\n' "$nte"; done <<< "$vp_notes"
echo ''
echo '  generated prompt -- copy everything between the two rules:'
echo '--------------------------------------------------------------------------------'
printf '%s\n' "$generated_prompt"
echo '--------------------------------------------------------------------------------'

echo ''
echo '  This command reads. It writes nothing, authorizes nothing, and opens no governance window.'
echo ''
exit 0
