#!/usr/bin/env bash
# Creates a task or bug record from a template without overwriting an existing file.
# POSIX counterpart of new-task.ps1.
#
# Usage:
#   new-task.sh --title "Fix invoice rounding" [--type task|bug] [--status inbox|active]
#               [--priority critical|high|medium|low] [--owner <name>]
#               [--acknowledge-discovery-gate --override-reason "<why>"]
#
# .ai/contract/discovery.md section 1 forbids opening a task in .ai/tasks/active/ while the project
# is still undefined. Nothing measured that, so the rule was bypassable by accident. The override
# exists because a human may legitimately decide otherwise -- but it is never silent: it demands a
# reason and writes the whole circumstance into the task file.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TITLE=""
TYPE="task"
STATUS="inbox"
PRIORITY="medium"
OWNER="unassigned"
ACK_GATE=0
OVERRIDE_REASON=""

while [ $# -gt 0 ]; do
  case "$1" in
    --title)    TITLE="${2:-}"; shift 2 ;;
    --type)     TYPE="${2:-}"; shift 2 ;;
    --status)   STATUS="${2:-}"; shift 2 ;;
    --priority) PRIORITY="${2:-}"; shift 2 ;;
    --owner)    OWNER="${2:-}"; shift 2 ;;
    --acknowledge-discovery-gate) ACK_GATE=1; shift ;;
    --override-reason) OVERRIDE_REASON="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -z "$TITLE" ] && { echo "--title is required." >&2; exit 1; }

case "$TYPE"     in task|bug) ;;                        *) echo "--type must be task or bug." >&2; exit 1 ;; esac
case "$STATUS"   in inbox|active) ;;                    *) echo "--status must be inbox or active." >&2; exit 1 ;; esac
case "$PRIORITY" in critical|high|medium|low) ;;        *) echo "--priority must be critical, high, medium, or low." >&2; exit 1 ;; esac

TEMPLATE_NAME="task-template.md"
[ "$TYPE" = "bug" ] && TEMPLATE_NAME="bug-template.md"
TEMPLATE_PATH="$REPO_ROOT/.ai/tasks/templates/$TEMPLATE_NAME"
TARGET_DIR="$REPO_ROOT/.ai/tasks/$STATUS"

[ -f "$TEMPLATE_PATH" ] || { echo "Template not found: $TEMPLATE_PATH" >&2; exit 1; }
[ -d "$TARGET_DIR" ]    || { echo "Target task directory not found: $TARGET_DIR" >&2; exit 1; }

# --- Discovery gate ----------------------------------------------------------------------------
# Only 'active' is gated. 'inbox' is the correct destination for work captured before discovery
# finishes -- the contract wants requests recorded, not lost, it just forbids starting them.
GATE_BLOCKING=0
GATE_OVERRIDDEN=0

if [ "$STATUS" = "active" ]; then
  CHECKER="$REPO_ROOT/scripts/validation/check-placeholders.sh"
  if [ ! -f "$CHECKER" ]; then
    # Refuse rather than guess. Opening an active task is deliberate and infrequent, so the safe
    # direction is closed -- unlike a per-write hook, where that would be intolerable.
    echo 'Cannot measure the discovery gate: scripts/validation/check-placeholders.sh not found.'
    echo 'Refusing to open an active task without knowing whether the project is defined.'
    exit 2
  fi

  gate_output="$(bash "$CHECKER" --fail-on-blocking 2>&1)"
  gate_code=$?
  if [ "$gate_code" -eq 0 ]; then
    GATE_BLOCKING=0
  else
    GATE_BLOCKING="$(printf '%s' "$gate_output" | grep -oE '[0-9]+ blocking marker' | head -1 | grep -oE '^[0-9]+')"
    [ -z "$GATE_BLOCKING" ] && GATE_BLOCKING=-1
  fi

  if [ "$GATE_BLOCKING" -ne 0 ]; then
    if [ "$ACK_GATE" -eq 0 ]; then
      echo "REFUSED: this project is still undefined -- $GATE_BLOCKING blocking placeholder marker(s) remain."
      echo ''
      echo '.ai/contract/discovery.md section 1: while the project is undefined, opening a task in'
      echo '.ai/tasks/active/ is forbidden. The interview is the only permitted activity.'
      echo ''
      echo 'Do one of these:'
      echo '  1. Capture it without starting it:  --status inbox'
      echo '  2. Finish discovery, then open it:  .ai/contract/discovery.md'
      echo '  3. Override deliberately, with a reason recorded in the task file:'
      echo '       --status active --acknowledge-discovery-gate --override-reason "<why>"'
      exit 2
    fi

    if [ -z "$OVERRIDE_REASON" ]; then
      echo 'REFUSED: --acknowledge-discovery-gate requires --override-reason.'
      echo 'An override with no stated reason is a silent override, which is the thing this check exists to prevent.'
      exit 2
    fi

    GATE_OVERRIDDEN=1
  fi
fi

# Slug: lowercase, non-alphanumeric collapsed to a hyphen, trimmed, capped at 80 characters.
slug="$(printf '%s' "$TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-//' -e 's/-$//' \
  | cut -c1-80 | sed -e 's/-$//')"
[ -z "$slug" ] && slug="untitled"

DATE="$(date +%Y-%m-%d)"
TARGET_PATH="$TARGET_DIR/$DATE-$slug.md"

if [ -e "$TARGET_PATH" ]; then
  echo "Refusing to overwrite existing task: $TARGET_PATH" >&2
  exit 1
fi

# sed replacement needs & and / escaped in the substituted values.
esc() { printf '%s' "$1" | sed -e 's/[&/\]/\\&/g'; }

sed \
  -e "s/\[Title\]/$(esc "$TITLE")/" \
  -e "s/Status: \`inbox\`/Status: \`$(esc "$STATUS")\`/" \
  -e "s/Priority: \`\[critical \/ high \/ medium \/ low\]\`/Priority: \`$(esc "$PRIORITY")\`/" \
  -e "s/Owner: \`\[person or agent\]\`/Owner: \`$(esc "$OWNER")\`/" \
  -e "s/Created: \`\[YYYY-MM-DD\]\`/Created: \`$DATE\`/" \
  -e "s/Updated: \`\[YYYY-MM-DD\]\`/Updated: \`$DATE\`/" \
  -e "s/Reported: \`\[YYYY-MM-DD\]\`/Reported: \`$DATE\`/" \
  "$TEMPLATE_PATH" > "$TARGET_PATH"

if [ "$GATE_OVERRIDDEN" -eq 1 ]; then
  cat >> "$TARGET_PATH" <<EOF

## Discovery Gate Override

**This task was opened while the project was still undefined.** When it was created on \`$DATE\`,
$GATE_BLOCKING blocking placeholder marker(s) remained in always-loaded context.

\`.ai/contract/discovery.md\` section 1 forbids opening a task in \`.ai/tasks/active/\` before
discovery completes. That rule was overridden deliberately, with human authorization, by passing
\`--acknowledge-discovery-gate\`.

**Reason given:** $OVERRIDE_REASON

Anyone reviewing this task should read its acceptance criteria knowing they were written against a
project whose requirements were not yet fully defined. If the criteria and the finished discovery
disagree, discovery wins.
EOF
fi

echo "Created $TYPE at ${TARGET_PATH#"$REPO_ROOT"/}"
if [ "$GATE_OVERRIDDEN" -eq 1 ]; then
  echo "DISCOVERY GATE OVERRIDDEN: $GATE_BLOCKING blocking marker(s). The reason is recorded in the task file."
fi
exit 0
