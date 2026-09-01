<#
.SYNOPSIS
    Claude Code PreToolUse hook for the Bash tool. Blocks destructive commands.

.DESCRIPTION
    Reads the hook payload from stdin, inspects tool_input.command, and exits 2 to block
    when the command matches a destructive pattern. Exit 0 allows the command.

    This is a safety net for accidental damage, not a security boundary. It reduces the
    blast radius of a mistaken command; it does not contain a determined actor.

.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
    Wire up in .claude/settings.json under hooks.PreToolUse with matcher "Bash".
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Destructive patterns. Each entry: Pattern (regex, case-insensitive) and Reason.
$rules = @(
    @{ Pattern = 'rm\s+(-[a-z]*[rf][a-z]*\s+)+(/|~|\$HOME|\*)\s*$'; Reason = 'Recursive delete of a root, home, or wildcard target.' }
    @{ Pattern = 'rm\s+-[a-z]*r[a-z]*f|rm\s+-[a-z]*f[a-z]*r';        Reason = 'Recursive force delete. Confirm the exact target with the user first.' }
    @{ Pattern = 'git\s+push\s+.*--force(?!-with-lease)';            Reason = 'Force push rewrites shared history. Use --force-with-lease, and only with explicit authorization.' }
    @{ Pattern = 'git\s+push\s+(-f|.*\s-f)(\s|$)';                   Reason = 'Force push rewrites shared history. Requires explicit authorization.' }
    @{ Pattern = 'git\s+reset\s+--hard';                             Reason = 'Discards working-tree and index changes irreversibly. Use git stash push instead.' }
    @{ Pattern = 'git\s+clean\s+-[a-z]*f';                           Reason = 'Deletes untracked files irreversibly.' }
    @{ Pattern = 'git\s+checkout\s+--\s+\.';                         Reason = 'Discards all working-tree changes irreversibly.' }
    @{ Pattern = 'git\s+stash\s+(drop|clear)';                       Reason = 'Destroys stashed work irreversibly.' }
    @{ Pattern = 'git\s+(filter-branch|filter-repo)';                Reason = 'Rewrites repository history.' }
    @{ Pattern = 'git\s+branch\s+-D\s';                              Reason = 'Force-deletes a branch, including unmerged work.' }
    @{ Pattern = 'git\s+update-ref\s+-d';                            Reason = 'Deletes a Git reference directly.' }
    @{ Pattern = '(?s)drop\s+(database|schema|table)\s';             Reason = 'Destroys database objects and their data.' }
    @{ Pattern = 'truncate\s+table\s';                               Reason = 'Destroys all rows in a table.' }
    @{ Pattern = 'delete\s+from\s+\w+\s*(;|$)';                      Reason = 'DELETE without a WHERE clause removes every row.' }
    @{ Pattern = '(curl|wget)\s[^|]*\|\s*(sudo\s+)?(ba)?sh';         Reason = 'Piping a remote script into a shell executes unreviewed code.' }
    @{ Pattern = 'chmod\s+(-R\s+)?777';                              Reason = 'World-writable permissions. Use the minimum required mode.' }
    @{ Pattern = ':\s*\(\s*\)\s*\{\s*:\s*\|\s*:';                    Reason = 'Fork bomb.' }
    @{ Pattern = 'mkfs(\.|\s)|dd\s+if=.*of=/dev/';                   Reason = 'Destroys a filesystem or block device.' }
    @{ Pattern = 'terraform\s+(destroy|apply\s+.*-auto-approve)';    Reason = 'Destroys or mutates infrastructure without review.' }
    @{ Pattern = 'kubectl\s+delete\s+(namespace|ns|pv|all)\s';       Reason = 'Deletes cluster-scoped resources.' }
    @{ Pattern = 'docker\s+system\s+prune\s+.*-a';                   Reason = 'Removes all unused images, containers, networks, and volumes.' }
    @{ Pattern = 'docker\s+volume\s+rm|docker\s+volume\s+prune';     Reason = 'Destroys container volumes and their data.' }
    @{ Pattern = 'npm\s+publish|pnpm\s+publish|yarn\s+publish';      Reason = 'Publishes a package publicly and irreversibly.' }
    @{ Pattern = 'Remove-Item\s+.*-Recurse.*-Force';                 Reason = 'Recursive force delete. Confirm the exact target with the user first.' }
    @{ Pattern = '(rmdir|rd)\s+/s';                                  Reason = 'Recursive delete via cmd. Confirm the exact target with the user first.' }
    @{ Pattern = 'history\s+-c|shred\s+';                            Reason = 'Destroys history or file contents irrecoverably.' }
)

# A read-only search is not an execution. An audit that looks for "rm -rf" across the tree was
# blocked by the rule meant to stop the deletion -- so the safest way to inspect a dangerous
# pattern was the one way the hook refused.
#
# The exception is deliberately narrow, because a wrapper that merely quotes the text still runs
# it: the WHOLE command must be one simple command whose program is a known search tool, with no
# metacharacter that could start a second command, and no option that makes a search tool run one
# (rg --pre, --pager). Anything ambiguous keeps its block.
function Test-ReadOnlySearch {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Command)

    if ($Command -match '[;|&`(){}<>]') { return $false }
    if ($Command -match '\r|\n') { return $false }
    if ($Command -match '--pre|--pager|--hostname-bin') { return $false }
    if ($Command -match '^\s*(grep|egrep|fgrep|rg|ag|ack|ack-grep|findstr|Select-String|sls)\s') { return $true }
    if ($Command -match '^\s*git\s+grep\s') { return $true }
    return $false
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $payload = $raw | ConvertFrom-Json
    $command = $payload.tool_input.command
} catch {
    # Never block on a parsing failure. The hook is a safety net, not a gate.
    exit 0
}

if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

if (Test-ReadOnlySearch -Command $command) { exit 0 }

foreach ($rule in $rules) {
    if ([regex]::IsMatch($command, $rule.Pattern, 'IgnoreCase')) {
        $message = @"
BLOCKED by blueprint safety hook (scripts/hooks/guard-bash.ps1).

Command : $command
Reason  : $($rule.Reason)

This command class requires explicit authorization in the conversation
(.ai/contract/safety.md section 1, "Explicit authorization").

Do not retry it verbatim. Instead:
  1. Explain to the user the exact action, the exact target, and the blast radius.
  2. Propose the reversible alternative if one exists.
  3. Ask the user to run it themselves, or to authorize it explicitly.
"@
        [Console]::Error.WriteLine($message)
        exit 2
    }
}

exit 0
