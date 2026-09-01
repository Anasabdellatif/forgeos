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

if [ -n "$blockers" ]; then
  echo "Task is NOT ready to close: $RESOLVED"
  echo ''
  printf '%s' "$blockers"
  echo ''
  echo 'Fix these, or keep the task active and record the blocker honestly.'
  echo 'See .ai/contract/lifecycle.md section 6 for the full Definition of Done.'
  exit 2
fi

# --- Discovery awareness: records, never blocks --------------------------------------------------
# new-task refuses to OPEN an active task while the project is undefined. Closing is different:
# .ai/contract/discovery.md section 1 forbids starting work, not finishing work already started.
# Blocking closure here would strand every task the override legitimately created, and would push
# people to archive by hand -- which destroys the record this directory exists to keep.
#
# So closure proceeds, and the circumstance is written down. The rule about what counts as
# "undefined" is not restated here; check-placeholders is asked, exactly as new-task asks it.
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
  echo 'Nothing was moved (--check). The remaining Definition of Done conditions are yours to verify.'
  exit 0
fi

COMPLETED_TASK_DIR="$REPO_ROOT/.ai/tasks/completed"
[ -d "$COMPLETED_TASK_DIR" ] || { echo "Completed task directory not found: $COMPLETED_TASK_DIR" >&2; exit 1; }

TASK_DEST="$COMPLETED_TASK_DIR/$(basename "$RESOLVED")"
[ -e "$TASK_DEST" ] && { echo "Refusing to overwrite completed task: $TASK_DEST" >&2; exit 1; }

# Related plan, if the task declares one.
PLAN_DEST=""
RELATED_PLAN="$(grep -oE '^[[:space:]]*-[[:space:]]*Related plan:[[:space:]]*`?[^`]+`?' "$RESOLVED" 2>/dev/null \
  | head -n1 | sed -e 's/.*Related plan:[[:space:]]*//' -e 's/`//g' -e 's/[[:space:]]*$//')"

if [ -n "$RELATED_PLAN" ] && [ "$RELATED_PLAN" != "none" ] && [ "$RELATED_PLAN" != "[path or none]" ]; then
  case "$RELATED_PLAN" in
    /*) PLAN_FULL="$RELATED_PLAN" ;;
    *)  PLAN_FULL="$REPO_ROOT/$RELATED_PLAN" ;;
  esac
  if [ -f "$PLAN_FULL" ]; then
    COMPLETED_PLAN_DIR="$REPO_ROOT/.ai/plans/completed"
    [ -d "$COMPLETED_PLAN_DIR" ] || { echo "Completed plan directory not found: $COMPLETED_PLAN_DIR" >&2; exit 1; }
    PLAN_DEST="$COMPLETED_PLAN_DIR/$(basename "$PLAN_FULL")"
    [ -e "$PLAN_DEST" ] && { echo "Refusing to overwrite completed plan: $PLAN_DEST" >&2; exit 1; }
  fi
fi

if [ "$NEEDS_GATE_NOTE" -eq 1 ]; then
  # Written while the task is still in active/ -- completed/ is an immutable archive, denied to the
  # write tools by .claude/settings.json, and it should stay that way.
  cat >> "$RESOLVED" <<EOF

## Discovery Gate Note

Recorded automatically by \`scripts/ai/finish-task\` at closure on \`$(date +%Y-%m-%d)\`.

This task was closed while the project was still undefined: $GATE_BLOCKING blocking placeholder
marker(s) remained in always-loaded context, and the task carried no \`Discovery Gate Override\`.
It was therefore opened either before the gate existed or outside it.

\`.ai/contract/discovery.md\` section 1 governs *opening* work, not closing it, so closure was not
blocked. This note exists so the archive does not imply the project was defined at the time.
EOF
fi

mv "$RESOLVED" "$TASK_DEST"
echo "Archived task -> ${TASK_DEST#"$REPO_ROOT"/}"

if [ -n "$PLAN_DEST" ]; then
  mv "$PLAN_FULL" "$PLAN_DEST"
  echo "Archived plan -> ${PLAN_DEST#"$REPO_ROOT"/}"
fi

echo ''
[ -n "$PROFILE_NOTE" ] && echo "Note: this task has $PROFILE_NOTE, so profile role evidence was not checked."
if [ "$NEEDS_GATE_NOTE" -eq 1 ]; then
  echo "DISCOVERY GATE NOTE appended: closed with $GATE_BLOCKING blocking marker(s) and no override."
elif [ "$GATE_BLOCKING" -ne 0 ] && [ "$HAS_OVERRIDE" -eq 1 ]; then
  echo "Closed under a recorded Discovery Gate Override ($GATE_BLOCKING blocking marker(s) remain)."
fi
echo 'Reminder: this script checked 5 mechanical gates. The Definition of Done has 11'
echo 'conditions. Confirm the other 6 in your final report, with evidence.'
exit 0
