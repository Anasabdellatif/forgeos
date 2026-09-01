<#
.SYNOPSIS
    Claude Code PreToolUse hook for Write, Edit, and NotebookEdit. Blocks writes to protected
    application paths until the project has explicitly authorized code.

.DESCRIPTION
    This is NOT the discovery gate. Discovery asks "is the project defined?" and answers it from
    TBD markers in always-loaded context. That gate opens the moment the documents are filled --
    and then nothing stood between a defined project and its first source file, even when the
    humans running it had three open decision gates and had authorized no code at all. A real
    adoption stayed safe only because a stray TBD in a documentation sentence kept discovery
    shut by accident. Protection by accident is not protection.

    This hook reads the project's own governance file, .ai/context/governance.json:

      codeAuthorized  false until a human flips it. There is no default that opens it.
      blockedUntil    the named gates still open -- printed so the agent can say which one.
      protectedPaths  globs for application code, manifests, migrations, infrastructure.
      decidedIn       where the authorization is recorded when it happens.
      implementationWindow
                      optional and closed by default: { active, allowedPaths, decidedIn }. While
                      the project stays closed, an ACTIVE window makes only the paths it lists
                      writable -- one approved slice, not the project.

    While codeAuthorized is false, a write to any protected path exits 2 and says exactly: which
    gates are open, which file was attempted, and where the decision is made. Writes anywhere else
    -- .ai/, docs/, scripts/, templates/ -- are never governed here, because alignment work must
    always be possible.

.NOTES
    Exit 2 blocks the write. Exit 0 allows it.

    Missing governance file = not governed. This is deliberate and it is the one place the default
    is permissive: the file is seeded into every adopted project by sync-blueprint, so its absence
    means a project that predates this hook, and a hook that suddenly blocks every write in an
    older project is a hook that gets switched off. An UNREADABLE file -- present but not JSON,
    or codeAuthorized missing -- fails CLOSED for protected paths: a corrupted gate must not read
    as an open one.

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

$projectRoot = $env:CLAUDE_PROJECT_DIR
if ([string]::IsNullOrWhiteSpace($projectRoot) -or -not (Test-Path -LiteralPath $projectRoot)) {
    $projectRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
}
# GetFullPath expands 8.3 short names; apply it to the root as well as the file, or a project opened
# from a short path fails the StartsWith comparison and this hook exits 0 as "outside the project".
$projectRoot = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd('\', '/')

$govPath = Join-Path -Path $projectRoot -ChildPath '.ai\context\governance.json'
if (-not (Test-Path -LiteralPath $govPath -PathType Leaf)) { exit 0 }

# Relative path, forward slashes. A file outside the project is not this gate's business.
try {
    if ([System.IO.Path]::IsPathRooted($filePath)) {
        $full = [System.IO.Path]::GetFullPath($filePath)
    } else {
        $full = [System.IO.Path]::GetFullPath((Join-Path -Path $projectRoot -ChildPath $filePath))
    }
} catch { exit 0 }
if (-not $full.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) { exit 0 }
$relative = $full.Substring($projectRoot.Length).TrimStart('\', '/').Replace('\', '/')
if ([string]::IsNullOrWhiteSpace($relative)) { exit 0 }

# Glob -> regex. ** crosses directories, * stays within one segment. Anchored both ends.
function ConvertTo-GlobRegex {
    param([string]$Glob)
    $escaped = [regex]::Escape($Glob)
    $escaped = $escaped.Replace('\*\*/', '(?:.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*').Replace('\?', '[^/]')
    return '^' + $escaped + '$'
}

$gov = $null
$readable = $true
try {
    $gov = Get-Content -LiteralPath $govPath -Raw | ConvertFrom-Json
    if ($null -eq $gov.codeAuthorized) { $readable = $false }
} catch { $readable = $false }

$patterns = @()
if ($readable -and $gov.protectedPaths) { $patterns = @($gov.protectedPaths) }

# With an unreadable file we cannot know the project's own list, so fall back to the template's
# defaults for the decision -- closed is the safe direction for a corrupted gate.
if (-not $readable) {
    $tpl = Join-Path -Path $projectRoot -ChildPath 'templates\governance-template.json'
    try { $patterns = @((Get-Content -LiteralPath $tpl -Raw | ConvertFrom-Json).protectedPaths) } catch { $patterns = @('src/**', 'app/**', 'migrations/**', 'package.json') }
}

$protected = $false
foreach ($g in $patterns) {
    if ([regex]::IsMatch($relative, (ConvertTo-GlobRegex -Glob $g), 'IgnoreCase')) { $protected = $true; break }
}
if (-not $protected) { exit 0 }

if ($readable -and $gov.codeAuthorized -eq $true) { exit 0 }

# A narrow implementation window. The project stays closed -- codeAuthorized is still false -- while
# ONE approved slice becomes writable, because the first implementation of anything is a migration
# or a scaffold, and opening the whole project to write it authorizes everything nobody reviewed.
#
# Every condition fails closed. The file must be readable (a corrupted gate can never open a
# window), active must read exactly "true", and allowedPaths must actually match this file: an
# active window with an empty list opens nothing, and so does one whose globs match nothing.
# A window narrows permission. It is not a bypass, and it does not authorize the project.
$windowPaths = @()
$windowActive = $false
if ($readable -and $gov.implementationWindow) {
    $w = $gov.implementationWindow
    # Compared as a lowered string so a JSON boolean and the string "true" agree here and in the
    # POSIX twin, where jq prints both identically. Anything else -- null, 1, "yes" -- stays closed.
    if (("$($w.active)").ToLowerInvariant() -eq 'true') {
        $windowActive = $true
        # An ARRAY or nothing. "allowedPaths": "src/**" is malformed, and treating a bare string as
        # a one-element list opened a window here that the POSIX twin kept shut -- caught by probing
        # the malformed shapes against both. Malformed is closed, on both sides.
        if ($w.allowedPaths -is [System.Array]) { $windowPaths = @($w.allowedPaths) }
    }
}

if ($windowActive) {
    foreach ($g in $windowPaths) {
        if ([string]::IsNullOrWhiteSpace($g)) { continue }
        if ([regex]::IsMatch($relative, (ConvertTo-GlobRegex -Glob $g), 'IgnoreCase')) { exit 0 }
    }
}

$gates = if ($readable -and $gov.blockedUntil) { @($gov.blockedUntil) } else { @('(governance file unreadable -- treated as closed)') }
$where = if ($readable -and $gov.decidedIn) { $gov.decidedIn } else { '.ai/memory/decisions/' }

# Naming the open window in the refusal is the difference between "you may not write code" and
# "you may write code, in one place, and this is not it".
$windowNote = ''
if ($windowActive) {
    $listed = if ($windowPaths.Count -gt 0) { ($windowPaths -join ', ') } else { '(none listed -- an empty window opens nothing)' }
    $windowWhere = if ($gov.implementationWindow.decidedIn) { $gov.implementationWindow.decidedIn } else { $where }
    $windowNote = @"

An implementation window IS open, and this file is outside it:
  allowed : $listed
  decided : $windowWhere
Widen the window only by recording that decision -- never by editing the file you were refused.
"@
}

$message = @"
BLOCKED by project governance (scripts/hooks/guard-governance.ps1).

File       : $relative
Reason     : application code is not authorized for this project yet.
             .ai/context/governance.json says codeAuthorized: false.

Open gates :
$(($gates | ForEach-Object { "  - $_" }) -join "`n")
$windowNote
This is not the discovery gate. The project may be fully defined and still not cleared to write
code -- alignment, review, and approval happen first, and this file records where they stand.

Where it is decided : $where
How it opens        : a human records the decision there, then sets codeAuthorized to true in
                      .ai/context/governance.json. Nothing else opens it, and it never opens by default.

Until then, work in .ai/, docs/, scripts/, and templates/ -- those paths are never governed here.
"@
[Console]::Error.WriteLine($message)
exit 2
