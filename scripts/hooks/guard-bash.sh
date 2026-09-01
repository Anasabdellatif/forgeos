#!/usr/bin/env bash
# Claude Code PreToolUse hook for the Bash tool. Blocks destructive commands.
# POSIX counterpart of guard-bash.ps1. Exit 2 blocks; exit 0 allows.
#
# Safety net for accidental damage, not a security boundary.

set -uo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_json.sh
. "$HOOK_DIR/_json.sh"

payload="$(cat)"
[ -z "$payload" ] && exit 0

command_text="$(json_field "$payload" tool_input command)"
[ -z "$command_text" ] && exit 0

# Format: <extended-regex>|||<reason>
RULES=(
  'rm[[:space:]]+(-[a-z]*[rf][a-z]*[[:space:]]+)+(/|~|\$HOME|\*)[[:space:]]*$|||Recursive delete of a root, home, or wildcard target.'
  'rm[[:space:]]+-[a-z]*r[a-z]*f|rm[[:space:]]+-[a-z]*f[a-z]*r|||Recursive force delete. Confirm the exact target with the user first.'
  'git[[:space:]]+push[[:space:]]+.*--force([^-]|$)|||Force push rewrites shared history. Use --force-with-lease, and only with explicit authorization.'
  'git[[:space:]]+push[[:space:]]+(-f|.*[[:space:]]-f)([[:space:]]|$)|||Force push rewrites shared history. Requires explicit authorization.'
  'git[[:space:]]+reset[[:space:]]+--hard|||Discards working-tree and index changes irreversibly. Use git stash push instead.'
  'git[[:space:]]+clean[[:space:]]+-[a-z]*f|||Deletes untracked files irreversibly.'
  'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+\.|||Discards all working-tree changes irreversibly.'
  'git[[:space:]]+stash[[:space:]]+(drop|clear)|||Destroys stashed work irreversibly.'
  'git[[:space:]]+(filter-branch|filter-repo)|||Rewrites repository history.'
  'git[[:space:]]+branch[[:space:]]+-D[[:space:]]|||Force-deletes a branch, including unmerged work.'
  'git[[:space:]]+update-ref[[:space:]]+-d|||Deletes a Git reference directly.'
  '[Dd][Rr][Oo][Pp][[:space:]]+([Dd][Aa][Tt][Aa][Bb][Aa][Ss][Ee]|[Ss][Cc][Hh][Ee][Mm][Aa]|[Tt][Aa][Bb][Ll][Ee])[[:space:]]|||Destroys database objects and their data.'
  '[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee][[:space:]]+[Tt][Aa][Bb][Ll][Ee][[:space:]]|||Destroys all rows in a table.'
  '[Dd][Ee][Ll][Ee][Tt][Ee][[:space:]]+[Ff][Rr][Oo][Mm][[:space:]]+[a-zA-Z_]+[[:space:]]*(;|$)|||DELETE without a WHERE clause removes every row.'
  '(curl|wget)[[:space:]][^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh|||Piping a remote script into a shell executes unreviewed code.'
  'chmod[[:space:]]+(-R[[:space:]]+)?777|||World-writable permissions. Use the minimum required mode.'
  ':[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:|||Fork bomb.'
  'mkfs(\.|[[:space:]])|dd[[:space:]]+if=.*of=/dev/|||Destroys a filesystem or block device.'
  'terraform[[:space:]]+(destroy|apply[[:space:]]+.*-auto-approve)|||Destroys or mutates infrastructure without review.'
  'kubectl[[:space:]]+delete[[:space:]]+(namespace|ns|pv|all)[[:space:]]|||Deletes cluster-scoped resources.'
  'docker[[:space:]]+system[[:space:]]+prune[[:space:]]+.*-a|||Removes all unused images, containers, networks, and volumes.'
  'docker[[:space:]]+volume[[:space:]]+(rm|prune)|||Destroys container volumes and their data.'
  '(npm|pnpm|yarn)[[:space:]]+publish|||Publishes a package publicly and irreversibly.'
  '[Rr]emove-[Ii]tem[[:space:]]+.*-[Rr]ecurse.*-[Ff]orce|||Recursive force delete. Confirm the exact target with the user first.'
  '(rmdir|rd)[[:space:]]+/[sS]|||Recursive delete via cmd. Confirm the exact target with the user first.'
  'history[[:space:]]+-c|shred[[:space:]]|||Destroys history or file contents irrecoverably.'
)

# A read-only search is not an execution. An audit that looks for "rm -rf" across the tree was
# blocked by the rule meant to stop the deletion -- so the safest way to inspect a dangerous
# pattern was the one way the hook refused.
#
# The exception is deliberately narrow, because a wrapper that merely quotes the text still runs
# it: the WHOLE command must be one simple command whose program is a known search tool, with no
# metacharacter that could start a second command, and no option that makes a search tool run one
# (rg --pre, --pager). Anything ambiguous keeps its block.
is_readonly_search() {
  local cmd="$1"
  case "$cmd" in
    *';'*|*'|'*|*'&'*|*'`'*|*'$('*|*'('*|*')'*|*'{'*|*'}'*|*'<'*|*'>'*) return 1 ;;
    *'--pre'*|*'--pager'*|*'--hostname-bin'*) return 1 ;;
  esac
  # $'\n' and not "$(printf '\n')": command substitution strips trailing newlines, so the
  # latter is the empty string -- a pattern that matches everything and rejects every search.
  case "$cmd" in *$'\n'*|*$'\r'*) return 1 ;; esac
  printf '%s' "$cmd" | grep -Eq '^[[:space:]]*(grep|egrep|fgrep|rg|ag|ack|ack-grep|findstr|[Ss]elect-[Ss]tring|sls)[[:space:]]' && return 0
  printf '%s' "$cmd" | grep -Eq '^[[:space:]]*git[[:space:]]+grep[[:space:]]' && return 0
  return 1
}

is_readonly_search "$command_text" && exit 0

for rule in "${RULES[@]}"; do
  pattern="${rule%%|||*}"
  reason="${rule##*|||}"
  if printf '%s' "$command_text" | grep -Eq -- "$pattern"; then
    cat >&2 <<EOF
BLOCKED by blueprint safety hook (scripts/hooks/guard-bash.sh).

Command : $command_text
Reason  : $reason

This command class requires explicit authorization in the conversation
(.ai/contract/safety.md section 1, "Explicit authorization").

Do not retry it verbatim. Instead:
  1. Explain to the user the exact action, the exact target, and the blast radius.
  2. Propose the reversible alternative if one exists.
  3. Ask the user to run it themselves, or to authorize it explicitly.
EOF
    exit 2
  fi
done

exit 0
