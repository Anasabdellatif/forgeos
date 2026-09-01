<#
.SYNOPSIS
    Claude Code PreToolUse hook for Write, Edit, and NotebookEdit. Blocks code changes while
    the project is still undefined.

.DESCRIPTION
    .ai/contract/core.md section 0 and .ai/contract/discovery.md section 1 state the rule: a
    project whose always-loaded context still carries blocking TBD markers is undefined, and the
    only permitted activity is the discovery interview.

    Until now that rule was prose. Nothing enforced it, and prose does not stop a write. This hook
    turns it into an exit code.

    Allowed while undefined: everything discovery and adoption legitimately write -- .ai/, docs/,
    and the blueprint's own surfaces. Blocked: everything else, which is where a project's source,
    manifests, and scaffolding would land.

    The blocking targets come from placeholderScan in the manifest, so "what counts as undefined"
    has one home shared with check-placeholders. Only the word markers are counted, not the
    bracketed prompts: .ai/context is written entirely in the TBD style, so markers alone answer
    the question, and duplicating the bracket regex here would create a second home for the
    trickiest pattern in the repository.

.NOTES
    Exit 2 blocks the write. Exit 0 allows it.

    Fails OPEN when the manifest cannot be read. That is deliberate and consistent with
    scripts/hooks/_json.sh: a hook is a safety net, not a security boundary, and a hook that
    blocks every write on a machine with no JSON parser is a hook that gets switched off. The
    fail-CLOSED half of this control is check-placeholders -FailOnBlocking, which since 1.7.2
    refuses to report a clean result it did not compute.

    Honors CLAUDE_PROJECT_DIR so the self-test can point it at a throwaway project.
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $payload = $raw | ConvertFrom-Json
    $filePath = $payload.tool_input.file_path
} catch {
    exit 0
}

if ([string]::IsNullOrWhiteSpace($filePath)) { exit 0 }

# Project root: the harness sets CLAUDE_PROJECT_DIR; fall back to this script's repository.
$projectRoot = $env:CLAUDE_PROJECT_DIR
if ([string]::IsNullOrWhiteSpace($projectRoot) -or -not (Test-Path -LiteralPath $projectRoot)) {
    $projectRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
}
# GetFullPath expands 8.3 short names (LONGNA~1 -> its long form). It is applied to the file below,
# so it must be applied to the root too, or a project opened from a short path compares a long
# file path against a short root, fails StartsWith, and this hook exits 0 as "outside the project".
$projectRoot = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd('\', '/')

$manifestPath = Join-Path -Path $projectRoot -ChildPath 'scripts\lib\blueprint-manifest.json'
try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $gate = $manifest.policy.discoveryGate
    $markers = @($manifest.placeholderScan.markers)
    $blockingTargets = @($manifest.placeholderScan.targets | Where-Object { $_.weight -eq 'blocking' } | ForEach-Object { $_.path })
    if (-not $gate -or $markers.Count -eq 0 -or $blockingTargets.Count -eq 0) { throw 'incomplete manifest' }
} catch {
    [Console]::Error.WriteLine('guard-discovery: manifest unreadable, allowing the write. Run check-placeholders -FailOnBlocking to check the gate properly.')
    exit 0
}

# Relative path, forward slashes. A file outside the project is not this gate's business.
# Test rootedness FIRST. Join-Path with an already-absolute child yields "C:\root\C:\abs", and
# GetFullPath throws on it -- which would send this hook down the catch and allow every write.
try {
    if ([System.IO.Path]::IsPathRooted($filePath)) {
        $full = [System.IO.Path]::GetFullPath($filePath)
    } else {
        $full = [System.IO.Path]::GetFullPath((Join-Path -Path $projectRoot -ChildPath $filePath))
    }
} catch {
    exit 0
}
if (-not $full.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) { exit 0 }
$relative = $full.Substring($projectRoot.Length).TrimStart('\', '/').Replace('\', '/')
if ([string]::IsNullOrWhiteSpace($relative)) { exit 0 }

foreach ($allowed in @($gate.allowedFiles)) {
    if ($relative -eq $allowed) { exit 0 }
}
foreach ($prefix in @($gate.allowedPrefixes)) {
    if ($relative.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { exit 0 }
}

# Sharing the RULES was not enough; the answer is to share the DETECTOR. This hook used to count
# markers itself, copying three rules from check-placeholders -- and it still counted something
# different, because the checker also treats bracketed prompts like [the project name] as
# placeholders and this hook never did. A project whose context was written entirely in bracket
# style therefore opened the gate while the checker called it blocking: reporter and enforcer
# disagreeing again, one layer down from the last time (open question 013).
#
# So ask the checker instead of imitating it. It owns the grammar, and there is now exactly one
# place where "undefined" is defined. The cost lands only here: every permitted prefix returned
# above, so this runs only when something wants to write code.
#
# The PROJECT's checker, not this repository's: check-placeholders resolves its scan root from its
# own location, so the copy shipped with the project under audit is the only one that can answer
# for it. Every adopting project has one -- it is portable.
$checker = Join-Path -Path $projectRoot -ChildPath 'scripts\validation\check-placeholders.ps1'
if (-not (Test-Path -LiteralPath $checker)) {
    [Console]::Error.WriteLine(@"
BLOCKED by the discovery gate (scripts/hooks/guard-discovery.ps1).

File    : $relative
Reason  : the gate cannot confirm this project is defined. Its placeholder checker is missing:
          $checker

This refuses rather than allows: a gate that cannot see is not a gate. Restore the file from the
blueprint, or run a sync, then try again.
"@)
    exit 2
}

$checkerOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $checker -FailOnBlocking 2>&1 | Out-String
$checkerCode = $LASTEXITCODE
if ($checkerCode -eq 0) { exit 0 }

$blockingCount = $null
if ($checkerOut -match '\(blocking:\s*(\d+)\)') { $blockingCount = $Matches[1] }
if ($null -eq $blockingCount) {
    [Console]::Error.WriteLine(@"
BLOCKED by the discovery gate (scripts/hooks/guard-discovery.ps1).

File    : $relative
Reason  : the gate cannot confirm this project is defined. check-placeholders exited $checkerCode
          without reporting a blocking count.

Run it directly to see why:
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validation\check-placeholders.ps1 -FailOnBlocking
"@)
    exit 2
}

$message = @"
BLOCKED by the discovery gate (scripts/hooks/guard-discovery.ps1).

File    : $relative
Reason  : this project is still undefined. $blockingCount blocking marker(s) remain in
          $($blockingTargets -join ', ').

.ai/contract/core.md section 0: in an undefined project the only permitted activity is the
discovery interview. No code, no scaffolding, no dependency, no technology choice -- regardless
of what was asked, and not overridable by a request to "just start".

Permitted right now: $($gate.allowedPrefixes -join ' ')

Do this instead:
  1. Run the discovery interview -- .ai/contract/discovery.md, six phases, in order.
  2. Write each phase's answers to the document that phase owns.
  3. Confirm with check-placeholders -FailOnBlocking. Zero blocking markers opens the gate.

If the user insists on code first, say what is still undefined and ask the next question.
A starting point built on invented requirements is the most expensive artifact in software.
"@
[Console]::Error.WriteLine($message)
exit 2
