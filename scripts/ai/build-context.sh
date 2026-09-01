#!/usr/bin/env bash
# Builds a deterministic, self-contained context package for handoff to another agent or session.
# POSIX counterpart of build-context.ps1.
#
# Usage:
#   build-context.sh [--task <path>] [--plan <path>] [--output <path>] [--force]
#                    [--include-docs] [--minimal] [--max-bytes <n>]
#
# --minimal omits the contract and context files that every session in this project already loads.
# Use it for a handoff inside the same project; use full mode only when the receiving environment
# cannot be trusted to read CLAUDE.md, AGENTS.md, and .ai/context/ for itself.
#
# Refuses to include oversized files or files containing secret-like content.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TASK_PATH=""
PLAN_PATH=""
OUTPUT_PATH=""
FORCE=0
INCLUDE_DOCS=0
MINIMAL=0
MAX_BYTES=65536

while [ $# -gt 0 ]; do
  case "$1" in
    --task)         TASK_PATH="${2:-}"; shift 2 ;;
    --plan)         PLAN_PATH="${2:-}"; shift 2 ;;
    --output)       OUTPUT_PATH="${2:-}"; shift 2 ;;
    --force)        FORCE=1; shift ;;
    --include-docs) INCLUDE_DOCS=1; shift ;;
    --minimal)      MINIMAL=1; shift ;;
    --max-bytes)    MAX_BYTES="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ "$MAX_BYTES" -lt 1024 ] 2>/dev/null && { echo "--max-bytes must be at least 1024." >&2; exit 1; }

PLACEHOLDER='(example|placeholder|change[_-]?me|your[_-][a-z0-9_-]*|goes[_-]?here|xxx+|\.\.\.|<[^>]+>|\$\{[^}]+\}|\{\{[^}]+\}\}|dummy|redacted|sample|test[_-]?only|fake|TBD)'

SECRET_PATTERNS=(
  '-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----'
  '(AKIA|ASIA)[0-9A-Z]{16}'
  'aws_secret_access_key[[:space:]]*[:=][[:space:]]*[^[:space:]]{20,}'
  'gh[pousr]_[A-Za-z0-9]{30,}'
  'sk_(live|test)_[0-9A-Za-z]{20,}'
  '(api[_-]?key|secret|password|access[_-]?token|client[_-]?secret)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]]{12,}["'"'"']'
  '(postgres|postgresql|mysql|mongodb(\+srv)?|redis|amqp)://[^:[:space:]/]+:[^@[:space:]]{6,}@'
)

buffer=""
emit() { buffer="${buffer}$1"$'\n'; }

# A fence must outlast the longest backtick run inside the content, otherwise a fenced
# block in an included file terminates the wrapper early.
safe_fence() {
  local file="$1"
  local longest
  longest="$(grep -oE '`+' "$file" 2>/dev/null | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
  local n=$(( longest + 1 ))
  [ "$n" -lt 3 ] && n=3
  printf '%*s' "$n" '' | tr ' ' '`'
}

add_file() {
  local rel="$1"
  local full="$REPO_ROOT/$rel"

  if [ ! -f "$full" ]; then
    echo "Context file not found: $rel" >&2
    exit 1
  fi

  local size
  size="$(wc -c < "$full" | tr -d ' ')"
  if [ "$size" -gt "$MAX_BYTES" ]; then
    echo "Refusing to include large file ($size bytes): $rel" >&2
    exit 1
  fi

  for pattern in "${SECRET_PATTERNS[@]}"; do
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      local lineno="${hit%%:*}"
      local content
      content="$(sed -n "${lineno}p" "$full")"
      if printf '%s' "$content" | grep -Eqi -- "$PLACEHOLDER"; then continue; fi
      echo "Refusing to include file with secret-like content: $rel (line $lineno). Remove or parameterize the value, then retry." >&2
      exit 1
    done < <(grep -nEi -- "$pattern" "$full" 2>/dev/null)
  done

  local fence
  fence="$(safe_fence "$full")"
  emit ''
  emit "## $rel"
  emit ''
  emit "$fence markdown"
  buffer="${buffer}$(cat "$full")"$'\n'
  emit "$fence"
}

emit '# AI Context Package'
emit ''
emit "- Repository: $REPO_ROOT"
if [ "$MINIMAL" -eq 1 ]; then
  emit '- Scope: MINIMAL -- the work only. The receiving agent is expected to load the'
  emit '  contract and context itself, exactly as any session in this project does.'
else
  emit '- Scope: core contract, project context, active task, optional plan, and selected indexes'
fi

CORE_FILES=(
  '.ai/contract/core.md'
  '.ai/context/project.md'
  '.ai/context/constraints.md'
  '.ai/context/stack.md'
  '.ai/context/structure.md'
  '.ai/rules/README.md'
  '.ai/tasks/README.md'
  '.ai/plans/README.md'
)
# Full mode repeats what every session already loads. That is right for a transfer into an
# environment that cannot be trusted to read CLAUDE.md, and pure waste inside this project.
if [ "$MINIMAL" -eq 0 ]; then
  for f in "${CORE_FILES[@]}"; do add_file "$f"; done
fi

to_relative() {
  case "$1" in
    /*) printf '%s' "${1#"$REPO_ROOT"/}" ;;
    *)  printf '%s' "$1" ;;
  esac
}

[ -n "$TASK_PATH" ] && add_file "$(to_relative "$TASK_PATH")"
[ -n "$PLAN_PATH" ] && add_file "$(to_relative "$PLAN_PATH")"

if [ "$INCLUDE_DOCS" -eq 1 ]; then
  for f in docs/README.md docs/product/README.md docs/architecture/README.md \
           docs/domains/README.md docs/design/README.md docs/operations/README.md; do
    add_file "$f"
  done
fi

if [ -n "$OUTPUT_PATH" ]; then
  case "$OUTPUT_PATH" in
    /*) RESOLVED_OUT="$OUTPUT_PATH" ;;
    *)  RESOLVED_OUT="$REPO_ROOT/$OUTPUT_PATH" ;;
  esac
  OUT_DIR="$(dirname "$RESOLVED_OUT")"
  [ -d "$OUT_DIR" ] || { echo "Output directory not found: $OUT_DIR" >&2; exit 1; }
  if [ -e "$RESOLVED_OUT" ] && [ "$FORCE" -eq 0 ]; then
    echo "Refusing to overwrite existing context package: $RESOLVED_OUT. Pass --force to replace it." >&2
    exit 1
  fi
  printf '%s' "$buffer" > "$RESOLVED_OUT"
  echo "Wrote context package to ${RESOLVED_OUT#"$REPO_ROOT"/}"
else
  printf '%s' "$buffer"
fi

exit 0
