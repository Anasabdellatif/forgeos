#!/usr/bin/env bash
# Gates task closure on mechanical completion signals, then archives the task and its plan.
# POSIX counterpart of finish-task.ps1.
#
# This is a GATE, NOT A VERDICT. The Definition of Done in .ai/contract/lifecycle.md section 6
# has eleven conditions; this script checks four of them mechanically.
#
# Usage: finish-task.sh --task <path> [--check]
# Exit: 0 success, 1 error, 2 not ready to close.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TASK_PATH=""
CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --task)  TASK_PATH="${2:-}"; shift 2 ;;
    --check) CHECK_ONLY=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -z "$TASK_PATH" ] && { echo "--task is required." >&2; exit 1; }

case "$TASK_PATH" in
  /*) RESOLVED="$TASK_PATH" ;;
  *)  RESOLVED="$REPO_ROOT/$TASK_PATH" ;;
esac

[ -f "$RESOLVED" ] || { echo "Task not found: $RESOLVED" >&2; exit 1; }

# CONTAINMENT, before anything else reads the file. The task must be a record inside .ai/tasks/,
# resolved physically: a path may reach outside through `..` or through a link, and a file that is
# not a task must never be archived as one. `pwd -P` resolves both.
# The physical root, so every containment comparison has the same spelling on both sides: the
# same directory can arrive as a short 8.3 path and as its long form.
REPO_ROOT_REAL="$(cd "$REPO_ROOT" 2>/dev/null && pwd -P)"
TASKS_ROOT="$(cd "$REPO_ROOT/.ai/tasks" 2>/dev/null && pwd -P)"
task_dir="$(cd "$(dirname "$RESOLVED")" 2>/dev/null && pwd -P)"
RESOLVED_REAL="${task_dir:-}/$(basename "$RESOLVED")"
if [ -z "$TASKS_ROOT" ] || [ -z "$task_dir" ]; then
  echo "Cannot resolve the task or .ai/tasks/: $RESOLVED" >&2; exit 1
fi
case "$RESOLVED_REAL" in
  "$TASKS_ROOT"/*) RESOLVED="$RESOLVED_REAL" ;;
  *) echo "Refusing: the task resolves outside .ai/tasks/ -> $RESOLVED_REAL" >&2
     echo 'Only a record inside .ai/tasks/ can be closed.' >&2
     exit 1 ;;
esac

# A record can exist in BOTH active/ and completed/ when a closure was interrupted between writing
# the archive and removing the original. That is not "already closed", and it is not a plain
# refusal either: it is one of two states, and they are told apart by content, never by filename.
#
#   recoverable  the archive is this record, plus exactly the changes a closure makes
#                (first Status, first Updated, first Related plan, an appended gate note)
#   conflicting  anything else -- someone edited one of the copies, or they are different records
#
# Comparison normalises only those four intended changes and compares the rest verbatim.
normalize_record() {   # normalize_record <file>
  awk '
    /^##[[:space:]]+Discovery Gate Note[[:space:]]*$/ { gate = 1 }
    gate { next }
    !ds && /^[[:space:]]*-[[:space:]]*Status:/       { ds = 1; print "- Status: <closure>";       next }
    !du && /^[[:space:]]*-[[:space:]]*Updated:/      { du = 1; print "- Updated: <closure>";      next }
    !dp && /^[[:space:]]*-[[:space:]]*Related plan:/ { dp = 1; print "- Related plan: <closure>"; next }
    { print }
  ' "$1"
}

TASK_LEAF="$(basename "$RESOLVED")"
ACTIVE_TWIN="$REPO_ROOT/.ai/tasks/active/$TASK_LEAF"
ARCHIVED_TWIN="$REPO_ROOT/.ai/tasks/completed/$TASK_LEAF"

if [ -f "$ACTIVE_TWIN" ] && [ -f "$ARCHIVED_TWIN" ]; then
  if [ "$(normalize_record "$ACTIVE_TWIN")" = "$(normalize_record "$ARCHIVED_TWIN")" ]; then
    if [ "$CHECK_ONLY" -eq 1 ]; then
      echo "Interrupted closure: ${ACTIVE_TWIN#"$REPO_ROOT"/} and its archive are the same record."
      echo 'Running without --check would remove the active copy and finish the closure.'
      echo 'Nothing was moved or edited (--check).'
      exit 0
    fi
    if rm -f "$ACTIVE_TWIN"; then
      echo "Recovered an interrupted closure: removed ${ACTIVE_TWIN#"$REPO_ROOT"/}"
      echo "The archive at ${ARCHIVED_TWIN#"$REPO_ROOT"/} was already complete and was not touched."
      exit 0
    fi
    echo "Could not remove ${ACTIVE_TWIN#"$REPO_ROOT"/}; both copies remain." >&2
    exit 1
  fi
  echo "CONFLICT: two different records share the name $TASK_LEAF." >&2
  echo "  active:   ${ACTIVE_TWIN#"$REPO_ROOT"/}" >&2
  echo "  archived: ${ARCHIVED_TWIN#"$REPO_ROOT"/}" >&2
  echo 'They differ by more than a closure would change, so neither was touched.' >&2
  echo 'Compare them yourself, keep the one that is right, and remove the other.' >&2
  exit 2
fi

# Closing something already closed is a repeat, not an error: an interrupted session reruns the same
# command, and the archive must not be touched for it.
case "$RESOLVED" in
  */.ai/tasks/completed/*)
    echo "Already closed: ${RESOLVED#"$REPO_ROOT"/}"
    echo 'Nothing to do. The archive was not touched.'
    exit 0 ;;
esac

blockers=""
add_blocker() { blockers="${blockers}  - $1"$'\n'; }

# Gate 1 — no unchecked acceptance criteria or checklist items.
while IFS= read -r hit; do
  [ -n "$hit" ] && add_blocker "unchecked criterion   $hit"
done < <(grep -nE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]+' "$RESOLVED" 2>/dev/null | sed 's/^\([0-9]*\):[[:space:]]*/line \1: /')

# Gate 2 — no pending completion evidence.
while IFS= read -r hit; do
  [ -n "$hit" ] && add_blocker "pending evidence      $hit"
done < <(grep -niE '`\[?pending\]?`' "$RESOLVED" 2>/dev/null | sed 's/^\([0-9]*\):[[:space:]]*/line \1: /')

# Gate 3 — the task is not blocked.
if grep -qiE '^[[:space:]]*-[[:space:]]*Status:[[:space:]]*`?(yes|blocked)`?[[:space:]]*$' "$RESOLVED"; then
  add_blocker 'active blocker        the Blocked section reports Status: yes'
fi

# Gate 4 — no unreplaced template placeholders.
while IFS= read -r hit; do
  [ -n "$hit" ] && add_blocker "template placeholder  $hit"
done < <(grep -nE '\[(Observable criterion [0-9]|Title|Verified fact|Required work)\]' "$RESOLVED" 2>/dev/null | sed 's/^\([0-9]*\):[[:space:]]*/line \1: /')

# Gate 5 — profile compliance. Enforcement is the intersection of two declarations: the task says
# what it touches, the profile says which of those areas demand a role. A task that touches nothing
# sensitive owes nothing, and a role with nothing to examine is never demanded.
PROFILE_NOTE=""
MANIFEST="$REPO_ROOT/scripts/lib/blueprint-manifest.json"

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

pc_read() {   # pc_read <jq-filter> <python-expression-over-d>
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

if [ -f "$MANIFEST" ]; then
  PC_SECTION="$(pc_read '.policy.profileCompliance.taskSection // empty' 'print(d["policy"].get("profileCompliance", {}).get("taskSection", ""))')"
  PC_SCOPE_FIELD="$(pc_read '.policy.profileCompliance.scopeField // empty' 'print(d["policy"].get("profileCompliance", {}).get("scopeField", ""))')"
  PC_EVIDENCE_FIELD="$(pc_read '.policy.profileCompliance.evidenceField // empty' 'print(d["policy"].get("profileCompliance", {}).get("evidenceField", ""))')"
  PC_PROMOTED_FIELD="$(pc_read '.policy.profileCompliance.promotedField // empty' 'print(d["policy"].get("profileCompliance", {}).get("promotedField", ""))')"
  PC_NONE="$(pc_read '.policy.profileCompliance.noneTag // empty' 'print(d["policy"].get("profileCompliance", {}).get("noneTag", ""))')"
  mapfile -t PC_MAP < <(pc_read '.policy.profileCompliance.scopeRoles[]? | "\(.tag) \(.role)"' \
    'print("\n".join(t["tag"] + " " + t["role"] for t in d["policy"]["profileCompliance"]["scopeRoles"]))')

  if [ -n "$PC_SECTION" ] && [ "${#PC_MAP[@]}" -gt 0 ]; then
    if ! grep -qxF "$PC_SECTION" "$RESOLVED"; then
      # The task predates this rule. Record it at closure rather than blocking work that was
      # opened before the requirement existed -- same principle as the discovery gate note.
      PROFILE_NOTE="no Profile Compliance section"
    else
      scope_line="$(grep -E "^[[:space:]]*-[[:space:]]*$PC_SCOPE_FIELD" "$RESOLVED" | head -1)"
      mapfile -t TAGS < <(printf '%s' "$scope_line" | grep -oE '`[^`]+`' | tr -d '`' | grep -v "^${PC_NONE}$")

      known_tags=""
      for entry in "${PC_MAP[@]}"; do known_tags="$known_tags ${entry%% *}"; done

      # An unrecognized tag must fail. A typo would otherwise disable the check silently.
      for tag in ${TAGS[@]+"${TAGS[@]}"}; do
        case " $known_tags " in
          *" $tag "*) ;;
          *) add_blocker "unknown scope tag     '$tag' is not one of:$known_tags $PC_NONE" ;;
        esac
      done

      # Which roles this project actually enforces: the profile's required set, plus any the
      # project promoted in .ai/context/project.md.
      enforced=""
      CONTEXT="$REPO_ROOT/.ai/context/project.md"
      profile_name=""
      if [ -f "$CONTEXT" ]; then
        profile_name="$(grep -E '^[[:space:]]*-[[:space:]]*Profile:' "$CONTEXT" | head -1 | grep -oE '`[^`]+`' | head -1 | tr -d '`')"
        # Structured first: a "- Promoted roles: `role`" line. The prose form is still read as a
        # fallback, but only for names that are actually roles -- the old scan took every backticked
        # token on any line mentioning "promoted", so a profile name beside the role became a role.
        role_names=""
        for entry in "${PC_MAP[@]}"; do role_names="$role_names ${entry##* }"; done

        promoted_line="$(grep -E "^[[:space:]]*-[[:space:]]*$PC_PROMOTED_FIELD" "$CONTEXT" | head -1)"
        while IFS= read -r r; do
          [ -n "$r" ] && [ "$r" != "none" ] && enforced="$enforced $r"
        done < <(printf '%s' "$promoted_line" | grep -oE '`[a-z-]+`' | tr -d '`')

        while IFS= read -r r; do
          [ -z "$r" ] && continue
          case " $role_names " in *" $r "*) enforced="$enforced $r" ;; esac
        done < <(grep -iE 'promoted' "$CONTEXT" | grep -oE '`[a-z-]+`' | tr -d '`')
      fi
      if [ -n "$profile_name" ] && [ "$profile_name" != "none" ]; then
        PROFILE_FILE="$REPO_ROOT/.ai/profiles/$profile_name.md"
        if [ -f "$PROFILE_FILE" ]; then
          while IFS= read -r r; do enforced="$enforced $r"; done < <(
            grep -E '^requiredRoles:' "$PROFILE_FILE" | head -1 | sed -e 's/^requiredRoles:[[:space:]]*\[//' -e 's/\].*$//' | tr ',' '\n' | tr -d ' ')
        fi
      fi

      # Evidence lines: "- `role`: what was examined". A placeholder is not evidence.
      #
      # Presence was not enough. A real adoption closed a task whose only evidence was
      # "(يُملأ: review later)" -- the field was filled, the reviews were not, and by the time they
      # happened the task sat in completed/, where it is immutable and could not be reopened. The
      # gate now reads the text, not just the field.
      #
      # Three shapes, all seen in the field: a bracketed prompt copied from the template, an
      # English "not yet" word, and its Arabic equivalents. The bracket form is this repository's
      # own convention from check-placeholders.sh -- five characters or more, starting with a
      # letter, and not a markdown link, so `[the upload path](src/upload.ts)` still counts as
      # evidence. Handed to grep -E and never to awk: mawk supports neither the interval nor \b.
      EV_BRACKET='\[[A-Za-z][^]]{4,}\]([^(]|$)'
      EV_WORDS='(^|[^A-Za-z])(TBD|TODO|FIXME)([^A-Za-z]|$)|to be (filled|completed|done)|fill (in )?later|placeholder|يُملأ|يملأ|لاحقا'

      is_placeholder_evidence() {   # is_placeholder_evidence <detail>
        printf '%s' "$1" | grep -qE '^`?\[.*\]`?$' && return 0
        printf '%s' "$1" | grep -qE -- "$EV_BRACKET" && return 0
        printf '%s' "$1" | grep -qiE -- "$EV_WORDS" && return 0
        return 1
      }

      evidence=""
      placeholder_roles=""
      while IFS= read -r line; do
        role="$(printf '%s' "$line" | grep -oE '`[a-z-]+`' | head -1 | tr -d '`')"
        detail="$(printf '%s' "$line" | sed -e 's/^[^:]*:[[:space:]]*//')"
        [ -z "$role" ] && continue
        if is_placeholder_evidence "$detail"; then
          placeholder_roles="$placeholder_roles $role"
          continue
        fi
        [ -n "$detail" ] && evidence="$evidence $role"
      done < <(grep -E '^[[:space:]]*-[[:space:]]*`[a-z-]+`[[:space:]]*:' "$RESOLVED")

      for tag in ${TAGS[@]+"${TAGS[@]}"}; do
        role=""
        for entry in "${PC_MAP[@]}"; do
          [ "${entry%% *}" = "$tag" ] && role="${entry##* }"
        done
        [ -z "$role" ] && continue
        case " $enforced " in *" $role "*) ;; *) continue ;; esac
        # "Missing" and "still a placeholder" are different problems, and telling an agent its
        # evidence is missing while it is looking at a filled line teaches it to distrust the gate.
        case " $evidence " in
          *" $role "*) ;;
          *)
            case " $placeholder_roles " in
              *" $role "*) add_blocker "placeholder role evidence scope tag '$tag' needs real evidence from \`$role\` under '$PC_EVIDENCE_FIELD' -- say what was reviewed and what came of it; template text does not satisfy the gate" ;;
              *)           add_blocker "missing role evidence scope tag '$tag' requires evidence from \`$role\` under '$PC_EVIDENCE_FIELD'" ;;
            esac
            ;;
        esac
      done
    fi
  fi
fi

# Gate 6 -- validation evidence must be observed. Pending or unknown is not success.
# The archive is read later as proof that something ran; a field reading "unknown" or "not run" is
# proof of nothing. It must carry a result, or be waived deliberately and in writing.
ev_section=0
while IFS= read -r line; do
  case "$line" in
    '## Completion Evidence'*) ev_section=1; continue ;;
    '## '*) ev_section=0 ;;
  esac
  [ "$ev_section" -eq 1 ] || continue
  case "$line" in
    -\ Commands\ executed:*|-\ Results:*|-\ Final\ diff\ reviewed:*)
      ev_field="${line%%:*}"
      ev_value="$(printf '%s' "${line#*:}" | tr -d '`' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr 'A-Z' 'a-z')"
      # A waiver is an exception someone wrote down, not a word that switches the gate off. It must
      # say WHY, in its own words: `waived: <reason>`. A bare marker, or one whose reason is itself
      # a pending word, is the disguised pending evidence this gate exists to catch. Text cannot
      # authenticate who allowed it, and this script never claims to -- it checks that a human
      # sentence is there to review, nothing more.
      case "$ev_value" in
        waived:*)
          # A waiver is the contract's "a check that could not be run is documented with the reason
          # and the residual risk" (lifecycle.md section 6), written in a shape a script can check:
          #   waived: scope=<this field>; reason=<why>; risk=<what may bite>; ref=<a file here>
          # Every part is mandatory, the scope must be the field the waiver sits on, and the
          # reference must resolve to a file inside this repository -- nothing is fetched. The tool
          # verifies STRUCTURE and RESOLUTION; it cannot authenticate who allowed the exception and
          # it cannot prove a command ran. One waiver covers its own field and nothing else.
          ev_body="$(printf '%s' "${ev_value#waived:}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
          w_scope=''; w_reason=''; w_risk=''; w_ref=''
          old_ifs="$IFS"; IFS=';'
          for part in $ev_body; do
            key="$(printf '%s' "${part%%=*}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr 'A-Z' 'a-z')"
            val="$(printf '%s' "${part#*=}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
            [ "$part" = "$key" ] && continue
            case "$key" in
              scope) w_scope="$val" ;; reason) w_reason="$val" ;; risk) w_risk="$val" ;; ref) w_ref="$val" ;;
            esac
          done
          IFS="$old_ifs"
          ev_name="$(printf '%s' "${ev_field#- }" | tr 'A-Z' 'a-z')"
          if [ -z "$w_scope" ] || [ -z "$w_reason" ] || [ -z "$w_risk" ] || [ -z "$w_ref" ]; then
            add_blocker "waiver is malformed    ${ev_field#- }: expected 'waived: scope=...; reason=...; risk=...; ref=...'"
          elif [ "$(printf '%s' "$w_scope" | tr 'A-Z' 'a-z')" != "$ev_name" ]; then
            add_blocker "waiver scope mismatch  ${ev_field#- }: the waiver names scope '$w_scope', not this field"
          elif [ "${#w_reason}" -lt 12 ]; then
            add_blocker "waiver without a reason ${ev_field#- }: the reason must say why, in at least 12 characters"
          elif [ "${#w_risk}" -lt 6 ]; then
            add_blocker "waiver without a risk  ${ev_field#- }: the residual risk must be stated"
          else
            case "$(printf '%s' "$w_reason" | tr 'A-Z' 'a-z')" in
              pending*|unknown*|tbd*|todo*|later*|'not run'*|'not yet'*|n/a*)
                add_blocker "waiver restates pending ${ev_field#- }: '$w_reason' is pending evidence wearing a waiver" ;;
              *)
                ref_dir="$(cd "$(dirname "$REPO_ROOT/$w_ref")" 2>/dev/null && pwd -P)"
                ref_real="${ref_dir:-}/$(basename "$w_ref")"
                if [ -z "$ref_dir" ] || [ ! -f "$ref_real" ]; then
                  add_blocker "waiver reference missing ${ev_field#- }: ref '$w_ref' does not resolve to a file in this repository"
                else
                  case "$ref_real" in
                    "$REPO_ROOT_REAL"/*) ;;
                    *) add_blocker "waiver reference escapes ${ev_field#- }: ref '$w_ref' resolves outside the repository" ;;
                  esac
                fi
                ;;
            esac
          fi
          ;;
        ''|unknown|'not run'|'not yet'|none|n/a|tbd|pending|no)
          add_blocker "unobserved evidence   ${ev_field#- }: '$ev_value' is not an observed result" ;;
      esac
      ;;
  esac
done < "$RESOLVED"

# --- The related plan, resolved structurally rather than guessed ---------------------------------
# A task names its plan in ONE metadata line; everything else on that line is prose. The rules: one
# line only, `none` (with or without an explanation after it) means no plan, a path is the single
# backticked token, and it must live under .ai/plans/. Anything ambiguous refuses instead of
# guessing. The defect this replaces: a line reading "Related plan: `docs/roadmap.md` section M-0"
# resolved to the project's roadmap, and closing that task archived the ROADMAP as a plan.
PLAN_REF=''; PLAN_REL=''; PLAN_NOTE=''
plan_line_count="$(grep -cE '^[[:space:]]*-[[:space:]]*Related plan:' "$RESOLVED")"
if [ "$plan_line_count" -gt 1 ]; then
  add_blocker "ambiguous related plan  $plan_line_count 'Related plan:' lines; exactly one is allowed"
elif [ "$plan_line_count" -eq 1 ]; then
  plan_value="$(grep -m1 -E '^[[:space:]]*-[[:space:]]*Related plan:' "$RESOLVED" | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//')"
  plan_lower="$(printf '%s' "$plan_value" | tr -d '`' | tr 'A-Z' 'a-z')"
  case "$plan_lower" in
    none|none[!a-z0-9]*|'[path or none]') ;;
    *)
      ticks="$(printf '%s' "$plan_value" | awk -F'`' '{print NF - 1}')"
      if [ "$ticks" -ge 4 ]; then
        add_blocker "ambiguous related plan  more than one quoted path on the line"
      elif [ "$ticks" -ge 2 ]; then
        PLAN_REF="$(printf '%s' "$plan_value" | sed 's/^[^`]*`//; s/`.*$//')"
      else
        candidate="$(printf '%s' "$plan_value" | awk '{print $1}')"
        case "$candidate" in
          *.md) PLAN_REF="$candidate" ;;
          *) PLAN_NOTE="the Related plan line is prose, not a path; no plan was archived" ;;
        esac
      fi
      ;;
  esac
fi

if [ -n "$PLAN_REF" ]; then
  case "$PLAN_REF" in
    "$REPO_ROOT"/*) PLAN_REL="${PLAN_REF#"$REPO_ROOT"/}" ;;
    /*) PLAN_REL='' ;;
    *) PLAN_REL="${PLAN_REF#./}" ;;
  esac
  case "$PLAN_REL" in
    .ai/plans/*) ;;
    *) add_blocker "out-of-scope plan       '$PLAN_REF' is not under .ai/plans/; refusing to archive it"
       PLAN_REF=''; PLAN_REL='' ;;
  esac
  # The prefix above is the text. This is the FACT: resolve the path and require the result to sit
  # inside .ai/plans/. `.ai/plans/../../docs/roadmap.md` passes any prefix test and is the roadmap.
  if [ -n "$PLAN_REL" ]; then
    PLANS_ROOT="$(cd "$REPO_ROOT/.ai/plans" 2>/dev/null && pwd -P)"
    plan_dir="$(cd "$(dirname "$REPO_ROOT/$PLAN_REL")" 2>/dev/null && pwd -P)"
    if [ -n "$plan_dir" ]; then
      plan_real="$plan_dir/$(basename "$PLAN_REL")"
      case "${PLANS_ROOT:-/nonexistent}" in
        '') ;;
      esac
      case "$plan_real" in
        # Contained: nothing to record. The check acts through its refusal branch, and the closure
        # goes on to use the declared relative path it just validated.
        "$PLANS_ROOT"/*) ;;
        *) add_blocker "out-of-scope plan       '$PLAN_REF' resolves outside .ai/plans/ -> $plan_real"
           PLAN_REF=''; PLAN_REL='' ;;
      esac
    fi
  fi
fi

if [ -n "$blockers" ]; then
  echo "Task is NOT ready to close: $RESOLVED"
  echo ''
  printf '%s' "$blockers"
  echo ''
  echo 'Nothing was moved and nothing was edited.'
  echo 'Fix these, or keep the task active and record the blocker honestly.'
  echo 'See .ai/contract/lifecycle.md section 6 for the full Definition of Done.'
  exit 2
fi

# --- Discovery awareness: records, never blocks --------------------------------------------------
# new-task refuses to OPEN an active task while the project is undefined. Closing is different:
# .ai/contract/discovery.md section 1 forbids starting work, not finishing work already started.
# Blocking closure here would strand every task the override legitimately created, and would push
# people to archive by hand -- which destroys the record this directory exists to keep.
GATE_BLOCKING=0
GATE_CHECKER="$REPO_ROOT/scripts/validation/check-placeholders.sh"
if [ -f "$GATE_CHECKER" ]; then
  gate_output="$(bash "$GATE_CHECKER" --fail-on-blocking 2>&1)"
  if [ $? -ne 0 ]; then
    GATE_BLOCKING="$(printf '%s' "$gate_output" | grep -oE '[0-9]+ blocking marker' | head -1 | grep -oE '^[0-9]+')"
    [ -z "$GATE_BLOCKING" ] && GATE_BLOCKING=-1
  fi
fi

HAS_OVERRIDE=0
grep -qE '^##[[:space:]]+Discovery Gate Override[[:space:]]*$' "$RESOLVED" && HAS_OVERRIDE=1

NEEDS_GATE_NOTE=0
[ "$GATE_BLOCKING" -ne 0 ] && [ "$HAS_OVERRIDE" -eq 0 ] && NEEDS_GATE_NOTE=1

# Where each record is going, decided before anything moves. A plan that is missing, or that another
# active task still names, is reported rather than archived: one task's closure does not retire a
# plan its siblings are still working from.
PLAN_FULL=''
if [ -n "$PLAN_REL" ]; then
  PLAN_FULL="$REPO_ROOT/$PLAN_REL"
  if [ ! -f "$PLAN_FULL" ]; then
    PLAN_NOTE="the related plan $PLAN_REL does not exist, so nothing was archived for it"
    PLAN_FULL=''
  else
    shared=0
    for other in "$REPO_ROOT"/.ai/tasks/active/*.md; do
      [ -f "$other" ] || continue
      # By leaf, not by full path: the same file can arrive by two spellings, and a task that
      # counted ITSELF as a sibling would never archive its own plan.
      [ "$(basename "$other")" = "$(basename "$RESOLVED")" ] && continue
      grep -qF "$(basename "$PLAN_REL")" "$other" 2>/dev/null && shared=$((shared + 1))
    done
    # A forwarding record is not a plan. If the task points at one, the plan it names was archived
    # when its last active task closed; there is nothing left to archive here.
    if grep -qxF -- '- Status: `moved`' "$PLAN_FULL" 2>/dev/null; then
      PLAN_NOTE="$PLAN_REL is a forwarding record; its plan was archived earlier and was not touched"
      PLAN_FULL=''
    elif [ "$shared" -gt 0 ]; then
      PLAN_NOTE="the related plan $PLAN_REL is still named by $shared other active task(s), so it stays active"
      PLAN_FULL=''
    elif grep -qE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]+' "$PLAN_FULL" 2>/dev/null; then
      # No other task names it, which says nothing about whether the PLAN is finished. Its own
      # unchecked items decide that, and the person closing the task decides what to do about them.
      PLAN_NOTE="the related plan $PLAN_REL still has unchecked items, so it stays active"
      PLAN_FULL=''
    fi
  fi
fi

COMPLETED_TASK_DIR="$REPO_ROOT/.ai/tasks/completed"
[ -d "$COMPLETED_TASK_DIR" ] || { echo "Completed task directory not found: $COMPLETED_TASK_DIR" >&2; exit 1; }
TASK_DEST="$COMPLETED_TASK_DIR/$(basename "$RESOLVED")"
[ -e "$TASK_DEST" ] && { echo "Refusing to overwrite completed task: $TASK_DEST" >&2; exit 1; }

PLAN_DEST=''
if [ -n "$PLAN_FULL" ]; then
  COMPLETED_PLAN_DIR="$REPO_ROOT/.ai/plans/completed"
  [ -d "$COMPLETED_PLAN_DIR" ] || { echo "Completed plan directory not found: $COMPLETED_PLAN_DIR" >&2; exit 1; }
  PLAN_DEST="$COMPLETED_PLAN_DIR/$(basename "$PLAN_FULL")"
  [ -e "$PLAN_DEST" ] && { echo "Refusing to overwrite completed plan: $PLAN_DEST" >&2; exit 1; }
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "Task passes the mechanical completion gates: $RESOLVED"
  if [ "$GATE_BLOCKING" -ne 0 ]; then
    if [ "$HAS_OVERRIDE" -eq 1 ]; then
      echo "Note: the project is still undefined ($GATE_BLOCKING blocking marker(s)). This task carries a Discovery Gate Override."
    else
      echo "Note: the project is still undefined ($GATE_BLOCKING blocking marker(s)) and this task carries no Discovery Gate Override."
      echo '      Closing it will append a Discovery Gate Note recording that. Closure is not blocked.'
    fi
  fi
  [ -n "$PROFILE_NOTE" ] && echo "Note: this task has $PROFILE_NOTE, so profile role evidence was not checked."
  [ -n "$PLAN_NOTE" ] && echo "Note: $PLAN_NOTE."
  echo "Would set Status to completed and archive -> ${TASK_DEST#"$REPO_ROOT"/}"
  [ -n "$PLAN_DEST" ] && echo "Would archive the plan -> ${PLAN_DEST#"$REPO_ROOT"/}"
  echo 'Nothing was moved or edited (--check). The remaining Definition of Done conditions are yours to verify.'
  exit 0
fi

# --- Writing starts here -------------------------------------------------------------------------
# ORDER IS THE GUARANTEE. Both archives are written from staged copies FIRST; the originals keep
# their original bytes until both destinations exist. A failure therefore leaves the records exactly
# as they were, never an active record marked completed, and never a link to a plan that was not
# archived. This is recoverable-failure safety, not crash atomicity: a process killed between two
# file operations can still leave a copy in completed/ and the original in active/, which the
# already-closed answer and the refuse-to-overwrite check make safe to re-run and easy to see.
TODAY="$(date +%Y-%m-%d)"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forgeos-close-XXXXXX")"
stage_cleanup() { rm -f "$STAGE_DIR/task.md" "$STAGE_DIR/plan.md" 2>/dev/null; rmdir "$STAGE_DIR" 2>/dev/null; }

# The FIRST Status and Updated lines only: the task template carries a second Status inside its
# Blocked section, and that one answers a different question.
set_record_state() {   # set_record_state <file> <status>
  awk -v st="$2" -v today="$TODAY" '
    !ds && /^[[:space:]]*-[[:space:]]*Status:/  { sub(/:.*/, ": `" st "`");    ds = 1; print; next }
    !du && /^[[:space:]]*-[[:space:]]*Updated:/ { sub(/:.*/, ": `" today "`"); du = 1; print; next }
    { print }
  ' "$1" > "$1.closing" && mv "$1.closing" "$1"
}

# Keep the forward link pointing at where the record actually went. A trailing annotation, if the
# line carries one, is preserved: it is the author's, not this script's.
point_link() {   # point_link <file> <field> <new path>
  awk -v field="$2" -v new="$3" '
    !dn && $0 ~ "^[[:space:]]*-[[:space:]]*" field ":" {
      n = split($0, part, "`")
      tail = (n >= 3) ? part[3] : ""
      print "- " field ": `" new "`" tail
      dn = 1; next
    }
    { print }
  ' "$1" > "$1.link" && mv "$1.link" "$1"
}

STAGE_TASK="$STAGE_DIR/task.md"
cp "$RESOLVED" "$STAGE_TASK" || { echo 'Could not stage the task; nothing was changed.' >&2; stage_cleanup; exit 1; }
set_record_state "$STAGE_TASK" 'completed'
[ -n "$PLAN_DEST" ] && point_link "$STAGE_TASK" 'Related plan' ".ai/plans/completed/$(basename "$PLAN_FULL")"

if [ "$NEEDS_GATE_NOTE" -eq 1 ]; then
  cat >> "$STAGE_TASK" <<GATENOTE

## Discovery Gate Note

Recorded automatically by \`scripts/ai/finish-task\` at closure on \`$TODAY\`.

This task was closed while the project was still undefined: $GATE_BLOCKING blocking placeholder
marker(s) remained in always-loaded context, and the task carried no \`Discovery Gate Override\`.
It was therefore opened either before the gate existed or outside it.

\`.ai/contract/discovery.md\` section 1 governs *opening* work, not closing it, so closure was not
blocked. This note exists so the archive does not imply the project was defined at the time.
GATENOTE
fi

STAGE_PLAN=''
if [ -n "$PLAN_DEST" ]; then
  STAGE_PLAN="$STAGE_DIR/plan.md"
  cp "$PLAN_FULL" "$STAGE_PLAN" || { echo 'Could not stage the plan; nothing was changed.' >&2; stage_cleanup; exit 1; }
  set_record_state "$STAGE_PLAN" 'completed'
  point_link "$STAGE_PLAN" 'Related task' ".ai/tasks/completed/$(basename "$RESOLVED")"
fi

# Publish. Destinations first, originals afterwards.
if ! cp "$STAGE_TASK" "$TASK_DEST"; then
  echo "Could not write $TASK_DEST; nothing was closed and both records are unchanged." >&2
  rm -f "$TASK_DEST" 2>/dev/null
  stage_cleanup; exit 1
fi
if [ -n "$PLAN_DEST" ] && ! cp "$STAGE_PLAN" "$PLAN_DEST"; then
  rm -f "$TASK_DEST" 2>/dev/null
  echo "Could not write $PLAN_DEST; nothing was closed and both records are unchanged." >&2
  stage_cleanup; exit 1
fi

INCOMPLETE=0
if ! rm -f "$RESOLVED"; then
  echo "WARNING: the task was archived to ${TASK_DEST#"$REPO_ROOT"/} but the original could not be removed." >&2
  echo "         Both copies now exist. Remove ${RESOLVED#"$REPO_ROOT"/} yourself to finish the closure." >&2
  INCOMPLETE=1
fi
# Historical references keep resolving. Completed tasks named this plan at its ACTIVE path, and a
# completed record is immutable -- so instead of rewriting somebody's archive, the old path keeps a
# forwarding record that says where the plan went. It carries `Status: moved`, which the status
# readers skip, so it never counts as an active plan.
PLAN_FORWARD=''
if [ -n "$PLAN_DEST" ]; then
  fwd_refs=0
  for past in "$REPO_ROOT"/.ai/tasks/completed/*.md; do
    [ -f "$past" ] || continue
    grep -qF "$PLAN_REL" "$past" 2>/dev/null && fwd_refs=$((fwd_refs + 1))
  done
  if [ "$fwd_refs" -gt 0 ]; then
    PLAN_FORWARD="$PLAN_FULL"
    cat > "$PLAN_FORWARD" <<FORWARD
# Moved: $(basename "$PLAN_REL" .md)

- Status: \`moved\`
- Moved: \`$TODAY\`
- Now at: \`.ai/plans/completed/$(basename "$PLAN_FULL")\`

This file is a **forwarding record, not a plan**. The plan that lived here was archived when its
last active task closed. $fwd_refs completed task record(s) still name this path, and a completed
record is never rewritten, so this note keeps those references resolving.

Read the plan at its archived path above. Nothing should be added here.
FORWARD
  fi
fi

if [ -n "$PLAN_DEST" ] && [ -z "$PLAN_FORWARD" ] && ! rm -f "$PLAN_FULL"; then
  echo "WARNING: the plan was archived to ${PLAN_DEST#"$REPO_ROOT"/} but the original could not be removed." >&2
  echo "         Both copies now exist. Remove ${PLAN_FULL#"$REPO_ROOT"/} yourself to finish the closure." >&2
  INCOMPLETE=1
fi
stage_cleanup

echo "Archived task -> ${TASK_DEST#"$REPO_ROOT"/}"
[ -n "$PLAN_DEST" ] && echo "Archived plan -> ${PLAN_DEST#"$REPO_ROOT"/}"
[ -n "$PLAN_FORWARD" ] && echo "Left a forwarding record -> ${PLAN_FORWARD#"$REPO_ROOT"/}"

echo ''
[ -n "$PROFILE_NOTE" ] && echo "Note: this task has $PROFILE_NOTE, so profile role evidence was not checked."
[ -n "$PLAN_NOTE" ] && echo "Note: $PLAN_NOTE."
if [ "$NEEDS_GATE_NOTE" -eq 1 ]; then
  echo "DISCOVERY GATE NOTE appended: closed with $GATE_BLOCKING blocking marker(s) and no override."
elif [ "$GATE_BLOCKING" -ne 0 ] && [ "$HAS_OVERRIDE" -eq 1 ]; then
  echo "Closed under a recorded Discovery Gate Override ($GATE_BLOCKING blocking marker(s) remain)."
fi
echo 'Status set to completed. This script checked 6 mechanical gates; the Definition of Done has 11'
echo 'conditions. Confirm the other 5 in your final report, with evidence.'
[ "$INCOMPLETE" -eq 1 ] && exit 1
exit 0
