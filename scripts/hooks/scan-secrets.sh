#!/usr/bin/env bash
# Detects secret-like content in files changed during the session.
# POSIX counterpart of scan-secrets.ps1.
#
# Runs as a Stop hook: once per turn, over every file Git reports as modified, added, or
# untracked. Runs once per turn instead of once per write; coverage is identical because every
# written file appears in git status, and the per-call process startup cost is paid once.
#
# Also accepts a PostToolUse payload with tool_input.file_path, scanning only that file.
#
# --scan-tree scans every git-tracked file instead, reads no stdin, and exits 1 on findings.
# That mode exists because the hook modes are useless in CI: a fresh checkout has nothing in
# `git status`, so a Stop-mode run would scan zero files and pass. A security check that passes
# because it examined nothing is worse than no check. The patterns live here once and all three
# modes share them -- a second copy in scripts/validation/ would be a second home for the one
# fact that matters most.
#
# Never prints the matched value -- file, line number, and pattern name only.

set -uo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_json.sh
. "$HOOK_DIR/_json.sh"

SCAN_TREE=0
[ "${1:-}" = "--scan-tree" ] && SCAN_TREE=1

# Only read stdin in hook mode. In tree mode there is no payload and cat would block.
payload=''
if [ "$SCAN_TREE" -eq 0 ]; then
  payload="$(cat)"

  # A Stop hook that exits 2 makes Claude continue. Without this guard that is an infinite loop.
  if printf '%s' "$payload" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    exit 0
  fi
fi

PLACEHOLDER='(example|placeholder|change[_-]?me|your[_-][a-z0-9_-]*|goes[_-]?here|insert[_-]?[a-z]*[_-]?here|xxx+|\.\.\.|<[^>]+>|\$\{[^}]+\}|\{\{[^}]+\}\}|dummy|redacted|sample|test[_-]?only|fake|noop|TBD)'

SKIP='/scripts/hooks/|/scripts/validation/|/\.ai/rules/(security|ai-safety)\.md$|/examples/'

SCAN_EXT='\.(md|txt|json|yml|yaml|toml|ini|cfg|conf|xml|js|mjs|cjs|ts|tsx|jsx|py|rb|go|rs|java|kt|cs|php|sh|ps1|sql|env|tf|tfvars|properties)$'

PATTERNS=(
  '-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----|||Private key block'
  '(AKIA|ASIA)[0-9A-Z]{16}|||AWS access key id'
  'aws_secret_access_key[[:space:]]*[:=][[:space:]]*[^[:space:]]{20,}|||AWS secret access key'
  'gh[pousr]_[A-Za-z0-9]{30,}|||GitHub token'
  'xox[abposr]-[A-Za-z0-9-]{10,}|||Slack token'
  'AIza[0-9A-Za-z_-]{35}|||Google API key'
  'sk_(live|test)_[0-9A-Za-z]{20,}|||Stripe secret key'
  'ey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|||JSON Web Token'
  '(api[_-]?key|secret|passwd|password|access[_-]?token|auth[_-]?token|client[_-]?secret)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]]{12,}["'"'"']|||Generic assigned secret'
  '(postgres|postgresql|mysql|mongodb(\+srv)?|redis|amqp)://[^:[:space:]/]+:[^@[:space:]]{6,}@|||Database URL with password'
)

findings=''

scan_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  printf '%s' "$file" | grep -Eq -- "$SKIP" && return 0
  printf '%s' "$file" | grep -Eq -- "$SCAN_EXT" || return 0
  [ "$(wc -c < "$file" 2>/dev/null || echo 0)" -gt 2097152 ] && return 0

  local entry pattern name lineno line_content
  for entry in "${PATTERNS[@]}"; do
    pattern="${entry%%|||*}"
    name="${entry##*|||}"
    while IFS= read -r lineno; do
      [ -z "$lineno" ] && continue
      line_content="$(sed -n "${lineno}p" "$file" 2>/dev/null)"
      printf '%s' "$line_content" | grep -Eqi -- "$PLACEHOLDER" && continue
      findings="${findings}  ${file}:${lineno}  ${name}"$'\n'
    done < <(grep -nEi -- "$pattern" "$file" 2>/dev/null | cut -d: -f1)
  done
}

single_file=''
[ "$SCAN_TREE" -eq 0 ] && single_file="$(json_field "$payload" tool_input file_path)"

if [ "$SCAN_TREE" -eq 1 ]; then
  # Validation mode: every git-tracked file in the committed tree.
  project_dir="$(cd "$HOOK_DIR/../.." && pwd)"
  cd "$project_dir" 2>/dev/null || { echo "Cannot enter repository root." >&2; exit 1; }
  # A freshly synced project is not a repository yet, and this is the first command an adopting
  # project runs. Say what to do, not just what is wrong.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "This check requires a git repository: it scans the git-tracked tree." >&2
    echo "Run 'git init' in the project root, commit or stage the files, then re-run validation." >&2
    exit 1
  fi

  scanned=0
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    scanned=$((scanned + 1))
    scan_file "$project_dir/$rel"
  done < <(git ls-files)

elif [ -n "$single_file" ]; then
  # PostToolUse mode: a single file.
  scan_file "$single_file"
else
  # Stop mode: every file Git reports as changed or untracked.
  project_dir="${CLAUDE_PROJECT_DIR:-}"
  [ -z "$project_dir" ] && project_dir="$(cd "$HOOK_DIR/../.." && pwd)"
  cd "$project_dir" 2>/dev/null || exit 0

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

  while IFS= read -r line; do
    [ ${#line} -lt 4 ] && continue
    state="${line:0:2}"
    case "$state" in 'D '|' D') continue ;; esac
    rel="${line:3}"
    rel="${rel%\"}"; rel="${rel#\"}"
    case "$rel" in *' -> '*) rel="${rel##* -> }" ;; esac
    scan_file "$project_dir/$rel"
  done < <(git status --porcelain --untracked-files=all 2>/dev/null)
fi

if [ -n "$findings" ]; then
  cat >&2 <<EOF
SECRET-LIKE CONTENT DETECTED by blueprint hook (scripts/hooks/scan-secrets.sh).

$findings
Required action, per .ai/rules/security.md section 1:
  1. Remove the value from the file now. Do not commit it.
  2. Do not print or echo the value anywhere.
  3. Replace it with an environment variable or a secret-manager reference.
  4. If the value is real and was ever committed, tell the user it must be rotated.

If this is a false positive (a documented placeholder), say so explicitly and continue.
EOF
  # Validation semantics are exit 1; hook semantics are exit 2.
  [ "$SCAN_TREE" -eq 1 ] && exit 1
  exit 2
fi

if [ "$SCAN_TREE" -eq 1 ]; then
  printf 'Secret scan passed  (%s tracked file(s) considered, 0 findings)\n' "${scanned:-0}"
fi

exit 0
