<#
.SYNOPSIS
    Creates the project's directory structure from .ai/context/scaffold.json.

.DESCRIPTION
    The last mechanical step of discovery. The architect writes scaffold.json at the end of
    phase 5; this creates what it declares, and nothing else.

    Creates directories only. It does not generate source files: a file with invented content is
    a decision nobody made, which is exactly what discovery exists to prevent. Files arrive
    through tasks, with acceptance criteria.

    Refuses to run while any entry still says TBD. A structure built from an unfinished
    architecture is worse than no structure.

.PARAMETER Apply
    Actually create. WITHOUT THIS THE SCRIPT ONLY REPORTS.

.PARAMETER SpecPath
    Alternate spec file. Defaults to .ai/context/scaffold.json.

.OUTPUTS
    Exit 0 on success, 1 on error, 2 when the spec is not ready.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$SpecPath
)

$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    $root = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    return $root.Path
}

$repoRoot = Get-RepositoryRoot
if (-not $SpecPath) { $SpecPath = Join-Path -Path $repoRoot -ChildPath '.ai\context\scaffold.json' }

if (-not (Test-Path -LiteralPath $SpecPath -PathType Leaf)) {
    Write-Output "Scaffold spec not found: $SpecPath"
    Write-Output 'It is written at the end of discovery phase 5. Run /discovery first.'
    exit 1
}

try {
    $spec = Get-Content -LiteralPath $SpecPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Scaffold spec is not valid JSON: $SpecPath"
    exit 1
}

if (-not $spec.directories -or @($spec.directories).Count -eq 0) {
    Write-Output 'Scaffold spec declares no directories. Nothing to do.'
    exit 2
}

# --- Readiness ---------------------------------------------------------------------------------

$unresolved = [System.Collections.Generic.List[string]]::new()
if ("$($spec.architecture)" -match '(?i)\bTBD\b') { $unresolved.Add("architecture: $($spec.architecture)") }
foreach ($d in $spec.directories) {
    if ("$($d.path)" -match '(?i)\bTBD\b')    { $unresolved.Add("path: $($d.path)") }
    if ("$($d.purpose)" -match '(?i)\bTBD\b') { $unresolved.Add("purpose of '$($d.path)': $($d.purpose)") }
}

if ($unresolved.Count -gt 0) {
    Write-Output "Scaffold spec is NOT ready: $SpecPath"
    Write-Output ''
    $unresolved | ForEach-Object { Write-Output "  - $_" }
    Write-Output ''
    Write-Output 'Discovery phase 5 has not produced a real structure yet. Complete it first;'
    Write-Output 'a directory tree built from an unfinished architecture is worse than none.'
    exit 2
}

# --- Validate paths ----------------------------------------------------------------------------

$rejected = [System.Collections.Generic.List[string]]::new()
$planned = [System.Collections.Generic.List[psobject]]::new()

foreach ($d in $spec.directories) {
    $rel = "$($d.path)".Trim().Replace('\', '/').Trim('/')

    if ([string]::IsNullOrWhiteSpace($rel))          { $rejected.Add("empty path"); continue }
    if ($rel -match '(^|/)\.\.(/|$)')                { $rejected.Add("$rel  (escapes the repository)"); continue }
    if ([System.IO.Path]::IsPathRooted($rel))        { $rejected.Add("$rel  (absolute path)"); continue }
    if ($rel -match '^(\.ai|\.claude|\.git|scripts|templates|examples)(/|$)') {
        $rejected.Add("$rel  (reserved by the blueprint)"); continue
    }

    $full = Join-Path -Path $repoRoot -ChildPath ($rel -replace '/', '\')
    $planned.Add([pscustomobject]@{
        Relative = $rel
        Full     = $full
        Purpose  = "$($d.purpose)"
        Exists   = (Test-Path -LiteralPath $full -PathType Container)
    })
}

if ($rejected.Count -gt 0) {
    Write-Output 'Rejected entries:'
    $rejected | ForEach-Object { Write-Output "  ! $_" }
    Write-Output ''
    Write-Output 'Fix them in the spec. Nothing was created.'
    exit 1
}

# --- Report ------------------------------------------------------------------------------------

$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN -- nothing will be created' }
$toCreate = @($planned | Where-Object { -not $_.Exists })
$already = @($planned | Where-Object { $_.Exists })

Write-Output ''
Write-Output "Scaffold  [$mode]"
Write-Output ("  architecture   {0}" -f $spec.architecture)
Write-Output ("  spec           {0}" -f $SpecPath.Substring($repoRoot.Length + 1))
Write-Output ''
Write-Output ("  to create      {0}" -f $toCreate.Count)
Write-Output ("  already exist  {0}" -f $already.Count)

if ($toCreate.Count -gt 0) {
    Write-Output ''
    foreach ($p in $toCreate) { Write-Output ("    + {0,-40} {1}" -f $p.Relative, $p.Purpose) }
}
if ($already.Count -gt 0) {
    Write-Output ''
    foreach ($p in $already) { Write-Output ("    = {0,-40} (exists, untouched)" -f $p.Relative) }
}

if (-not $Apply) {
    Write-Output ''
    Write-Output 'Dry run complete. Re-run with -Apply to create these directories.'
    exit 0
}

# --- Apply -------------------------------------------------------------------------------------

$created = 0
$gitkeep = $true
if ($null -ne $spec.gitkeep) { $gitkeep = [bool]$spec.gitkeep }

foreach ($p in $toCreate) {
    New-Item -ItemType Directory -Path $p.Full -Force | Out-Null
    $created++

    if ($gitkeep) {
        $keep = Join-Path -Path $p.Full -ChildPath '.gitkeep'
        if (-not (Test-Path -LiteralPath $keep)) {
            $text = "# Keeps this directory tracked by Git until it holds real files.`n# Purpose: $($p.Purpose)`n"
            [System.IO.File]::WriteAllText($keep, $text, (New-Object System.Text.UTF8Encoding($false)))
        }
    }
}

Write-Output ''
Write-Output ("Created {0} directory(ies)." -f $created)
Write-Output ''
Write-Output 'Next, and not optional:'
Write-Output '  1. Fill .ai/context/structure.md from what now exists.'
Write-Output '  2. Write the initial backlog into .ai/tasks/inbox/, each task independently shippable.'
Write-Output '  3. No source file is created by this script. Files arrive through tasks, with criteria.'
exit 0
