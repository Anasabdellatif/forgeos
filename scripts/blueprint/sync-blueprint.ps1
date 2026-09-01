<#
.SYNOPSIS
    Syncs the portable part of the blueprint from a source repository into this project,
    without touching anything the project owns.

.DESCRIPTION
    The blueprint splits into two halves, declared in scripts/lib/blueprint-manifest.json:

      portable         .ai/contract .ai/rules .ai/skills .ai/workflows .ai/agents
                       .claude scripts templates examples .github/workflows
                       CLAUDE.md AGENTS.md .editorconfig

      project-specific .ai/context .ai/tasks .ai/plans .ai/memory docs
                       README.md .gitignore blueprint.version

    Only the portable half is copied. The project-specific half is never read, never written,
    and never compared. That is the whole point: a project's facts, work state, and history
    must survive every upgrade untouched.

    LOCAL CUSTOMIZATION IS DETECTED, NOT DESTROYED. blueprint.version records a hash per synced
    file. On the next sync, a target file whose hash no longer matches the recorded one has been
    edited locally -- a project-specific guard-bash rule, for example -- and is skipped and
    reported rather than overwritten. Pass -Force to overwrite anyway, having seen the list.

.PARAMETER Source
    Path to the blueprint repository to sync from. Required.

.PARAMETER Target
    Project to sync into. Defaults to the repository this script lives in.

.PARAMETER Apply
    Actually write. WITHOUT THIS THE SCRIPT ONLY REPORTS. A tool that overwrites files must not
    do so by default.

.PARAMETER Force
    Overwrite locally modified files too. Review the dry run first.

.EXAMPLE
    ./sync-blueprint.ps1 -Source ../forgeos
    ./sync-blueprint.ps1 -Source ../forgeos -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Target,
    [switch]$Apply,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Resolve-Root {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLowerInvariant()
        } finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
}

function ConvertTo-Relative {
    param([string]$Root, [string]$Full)
    return $Full.Substring($Root.Length + 1).Replace('\', '/')
}

# --- Resolve roots -----------------------------------------------------------------------------

$sourceRoot = Resolve-Root -Path $Source
if ($Target) {
    $targetRoot = Resolve-Root -Path $Target
} else {
    $targetRoot = Resolve-Root -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
}

if ($sourceRoot -eq $targetRoot) {
    Write-Error "Source and target are the same repository: $sourceRoot"
    exit 1
}

$manifestPath = Join-Path -Path $sourceRoot -ChildPath 'scripts\lib\blueprint-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Error "Source does not look like a blueprint (no scripts/lib/blueprint-manifest.json): $sourceRoot"
    exit 1
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$dist = $manifest.distribution

$sourceVersionPath = Join-Path -Path $sourceRoot -ChildPath $dist.versionFile
if (-not (Test-Path -LiteralPath $sourceVersionPath -PathType Leaf)) {
    Write-Error "Source has no $($dist.versionFile). It cannot be identified, so it will not be synced from."
    exit 1
}
$sourceVersion = Get-Content -LiteralPath $sourceVersionPath -Raw | ConvertFrom-Json

# --- Recorded state of the target --------------------------------------------------------------

$targetVersionPath = Join-Path -Path $targetRoot -ChildPath $dist.versionFile
$recorded = @{}
$previousVersion = '(none)'
if (Test-Path -LiteralPath $targetVersionPath -PathType Leaf) {
    try {
        $tv = Get-Content -LiteralPath $targetVersionPath -Raw | ConvertFrom-Json
        if ($tv.version) { $previousVersion = $tv.version }
        if ($tv.files) {
            foreach ($p in $tv.files.PSObject.Properties) { $recorded[$p.Name] = $p.Value }
        }
    } catch {
        Write-Output "Warning: target $($dist.versionFile) is unreadable; every file will be treated as locally modified."
    }
}

# --- Enumerate the portable file set from the source -------------------------------------------

$sourceFiles = [System.Collections.Generic.List[string]]::new()

foreach ($dir in $dist.portable) {
    $full = Join-Path -Path $sourceRoot -ChildPath ($dir -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
    Get-ChildItem -LiteralPath $full -Recurse -File -Force | ForEach-Object {
        $sourceFiles.Add((ConvertTo-Relative -Root $sourceRoot -Full $_.FullName))
    }
}
foreach ($file in $dist.portableFiles) {
    $full = Join-Path -Path $sourceRoot -ChildPath ($file -replace '/', '\')
    if (Test-Path -LiteralPath $full -PathType Leaf) { $sourceFiles.Add($file) }
}

# Source-only paths belong to the SOURCE repository's own maintenance -- release tooling, and
# later a release workflow. They sit inside a portable directory because the discovery gate
# permits writes nowhere else, so being portable is an accident of location, not an intent to
# distribute. Dropping them here is a strengthening: fewer files reach a project, never more.
# An absent or empty list changes nothing, which is what an older manifest must mean.
$sourceOnly = @()
if ($dist.PSObject.Properties.Name -contains 'sourceOnly') { $sourceOnly = @($dist.sourceOnly) }
function Test-SourceOnly {
    param([string]$Relative)
    foreach ($p in $sourceOnly) {
        if (-not $p) { continue }
        if ($Relative -eq $p -or $Relative.StartsWith("$p/")) { return $true }
    }
    return $false
}

# Belt and braces: a path that is somehow in both lists must never be written.
$protected = @($dist.projectSpecific)
function Test-Protected {
    param([string]$Relative)
    foreach ($p in $protected) {
        if ($Relative -eq $p -or $Relative.StartsWith("$p/")) { return $true }
    }
    return $false
}

# --- Classify ----------------------------------------------------------------------------------

$new = [System.Collections.Generic.List[string]]::new()
$updated = [System.Collections.Generic.List[string]]::new()
$unchanged = [System.Collections.Generic.List[string]]::new()
$localMods = [System.Collections.Generic.List[string]]::new()
$preExisting = [System.Collections.Generic.List[string]]::new()
$skippedProtected = [System.Collections.Generic.List[string]]::new()

foreach ($rel in ($sourceFiles | Sort-Object -Unique)) {
    if (Test-Protected -Relative $rel) { $skippedProtected.Add($rel); continue }
    if (Test-SourceOnly -Relative $rel) { continue }

    $src = Join-Path -Path $sourceRoot -ChildPath ($rel -replace '/', '\')
    $dst = Join-Path -Path $targetRoot -ChildPath ($rel -replace '/', '\')
    $srcHash = Get-Sha256 -Path $src

    if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) {
        $new.Add($rel)
        continue
    }

    $dstHash = Get-Sha256 -Path $dst
    if ($dstHash -eq $srcHash) { $unchanged.Add($rel); continue }

    # Target differs from source. Three possibilities, and only one of them is safe to overwrite.
    if (-not $recorded.ContainsKey($rel)) {
        # Never placed here by sync, yet it exists and differs. It is the project's own file --
        # a pre-existing AGENTS.md, a README, a scripts/ directory that was already there.
        # Overwriting it would destroy work sync did not create. Skip and report.
        $preExisting.Add($rel)
    } elseif ($recorded[$rel] -ne $dstHash) {
        # Sync placed it, the project edited it since. A deliberate customization.
        $localMods.Add($rel)
    } else {
        # Sync placed it, the project left it alone, the blueprint moved on. Safe to update.
        $updated.Add($rel)
    }
}

# Files the source no longer has, but that we previously placed there.
$sourceSet = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($f in $sourceFiles) { [void]$sourceSet.Add($f) }
$removedInSource = @($recorded.Keys | Where-Object { -not $sourceSet.Contains($_) } | Sort-Object)

# --- Report ------------------------------------------------------------------------------------

$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN -- nothing will be written' }

Write-Output ''
Write-Output "Blueprint sync  [$mode]"
Write-Output ("  source   {0}  (v{1})" -f $sourceRoot, $sourceVersion.version)
Write-Output ("  target   {0}  (v{1})" -f $targetRoot, $previousVersion)
Write-Output ''
Write-Output ("  new                {0}" -f $new.Count)
Write-Output ("  updated            {0}" -f $updated.Count)
Write-Output ("  unchanged          {0}" -f $unchanged.Count)
Write-Output ("  pre-existing       {0}   <- YOUR files, never placed by sync; skipped unless -Force" -f $preExisting.Count)
Write-Output ("  locally modified   {0}   <- skipped unless -Force" -f $localMods.Count)
Write-Output ("  removed in source  {0}   <- not deleted; remove by hand if intended" -f $removedInSource.Count)
Write-Output ("  project-owned      {0}   <- never touched" -f $skippedProtected.Count)

if ($new.Count -gt 0)     { Write-Output ''; Write-Output '  NEW:';     $new     | ForEach-Object { Write-Output "    + $_" } }
if ($updated.Count -gt 0) { Write-Output ''; Write-Output '  UPDATED:'; $updated | ForEach-Object { Write-Output "    ~ $_" } }
if ($preExisting.Count -gt 0) {
    Write-Output ''
    Write-Output '  PRE-EXISTING (already in this project before the blueprint arrived):'
    $preExisting | ForEach-Object { Write-Output "    # $_" }
    Write-Output ''
    Write-Output '  Sync did not put these here and will not overwrite them. They may be the'
    Write-Output '  project''s own work -- an existing AGENTS.md, README, or scripts directory.'
    Write-Output '  Read each one, merge what you want from the blueprint version by hand, and'
    Write-Output '  only then re-run with -Force if you genuinely want the blueprint copy.'
}
if ($localMods.Count -gt 0) {
    Write-Output ''
    Write-Output '  LOCALLY MODIFIED (your edits -- review before deciding):'
    $localMods | ForEach-Object { Write-Output "    ! $_" }
    Write-Output ''
    Write-Output '  These differ from both the source and the version this project recorded.'
    Write-Output '  That means the project edited them deliberately. Diff each against the source,'
    Write-Output '  decide whether the customization still applies, then re-run with -Force.'
}
if ($removedInSource.Count -gt 0) {
    Write-Output ''
    Write-Output '  REMOVED IN SOURCE (still present here):'
    $removedInSource | ForEach-Object { Write-Output "    - $_" }
}

# --- Seeding: project-specific scaffolding, only when absent ------------------------------------
#
# A brand-new project has none of the project-specific half. Without seeding, the discovery gate
# would find no .ai/context/project.md, check-placeholders would report 0 blocking, and the gate
# would fail open on the exact case it exists for.
#
# Seeded once. An existing file is never compared, never overwritten, never reported.

# A seed target may be sourced from a template instead of the path of the same name. This
# repository fills .ai/context/project.md with the blueprint's own identity; an adopting
# project must start undefined, not inherit it. See seedTemplates in the manifest.
$seedTemplates = @{}
if ($dist.seedTemplates) {
    foreach ($p in $dist.seedTemplates.PSObject.Properties) { $seedTemplates[$p.Name] = $p.Value }
}

$seedFiles = [System.Collections.Generic.List[string]]::new()
foreach ($rel in @($dist.seedFiles)) {
    # Ask whether the file this seed is COPIED FROM exists, which is the template when one is
    # mapped -- not the target path. The two are the same in a clone, so the difference was
    # invisible until a release artifact was used as the source: an artifact deliberately omits
    # every template-backed target, so this test skipped exactly the five files a new project
    # cannot start without -- identity, constraints, governance, the ledger and the register.
    $seedSrcRel = $rel
    if ($seedTemplates.ContainsKey($rel)) {
        $tplProbe = Join-Path -Path $sourceRoot -ChildPath ($seedTemplates[$rel] -replace '/', [char]92)
        if (Test-Path -LiteralPath $tplProbe -PathType Leaf) { $seedSrcRel = $seedTemplates[$rel] }
    }
    $srcFile = Join-Path -Path $sourceRoot -ChildPath ($seedSrcRel -replace '/', [char]92)
    $dstFile = Join-Path -Path $targetRoot -ChildPath ($rel -replace '/', [char]92)
    if ((Test-Path -LiteralPath $srcFile -PathType Leaf) -and -not (Test-Path -LiteralPath $dstFile)) {
        $seedFiles.Add($rel)
    }
}

$seedDirs = [System.Collections.Generic.List[string]]::new()
foreach ($rel in @($dist.seedDirectories)) {
    $dstDir = Join-Path -Path $targetRoot -ChildPath ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $dstDir -PathType Container)) { $seedDirs.Add($rel) }
}

if ($seedFiles.Count -gt 0 -or $seedDirs.Count -gt 0) {
    Write-Output ''
    Write-Output ("  seeded             {0} file(s), {1} directory(ies)   <- only because absent; never overwritten" -f $seedFiles.Count, $seedDirs.Count)
    if ($seedFiles.Count -gt 0) {
        Write-Output ''
        Write-Output '  SEED (project-specific scaffolding, first time only):'
        $seedFiles | ForEach-Object { Write-Output "    * $_" }
    }
    if ($seedDirs.Count -gt 0) {
        $seedDirs | ForEach-Object { Write-Output "    * $_/" }
    }
}

if (-not $Apply) {
    Write-Output ''
    Write-Output 'Dry run complete. Re-run with -Apply to write these changes.'
    exit 0
}


foreach ($rel in $seedFiles) {
    $srcFile = Join-Path -Path $sourceRoot -ChildPath ($rel -replace '/', '\')
    $dstFile = Join-Path -Path $targetRoot -ChildPath ($rel -replace '/', '\')
    $dstDir = Split-Path -Path $dstFile -Parent
    if (-not (Test-Path -LiteralPath $dstDir -PathType Container)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    if ($seedTemplates.ContainsKey($rel)) {
        $tpl = Join-Path -Path $sourceRoot -ChildPath ($seedTemplates[$rel] -replace "/", [char]92)
        if (Test-Path -LiteralPath $tpl -PathType Leaf) { $srcFile = $tpl }
    }
    Copy-Item -LiteralPath $srcFile -Destination $dstFile
}

foreach ($rel in $seedDirs) {
    $dstDir = Join-Path -Path $targetRoot -ChildPath ($rel -replace '/', '\')
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    $keep = Join-Path -Path $dstDir -ChildPath '.gitkeep'
    if (-not (Test-Path -LiteralPath $keep)) {
        $text = "# Keeps this required directory tracked by Git until it holds records.`n# Created by sync-blueprint when this project was seeded.`n"
        [System.IO.File]::WriteAllText($keep, $text, (New-Object System.Text.UTF8Encoding($false)))
    }
}

# --- Apply -------------------------------------------------------------------------------------

$toWrite = [System.Collections.Generic.List[string]]::new()
foreach ($r in $new)     { $toWrite.Add($r) }
foreach ($r in $updated) { $toWrite.Add($r) }
if ($Force) {
    foreach ($r in $localMods)   { $toWrite.Add($r) }
    foreach ($r in $preExisting) { $toWrite.Add($r) }
}

$written = 0
foreach ($rel in $toWrite) {
    if (Test-Protected -Relative $rel) { continue }   # unreachable by construction; kept as a hard stop
    if (Test-SourceOnly -Relative $rel) { continue }
    $src = Join-Path -Path $sourceRoot -ChildPath ($rel -replace '/', '\')
    $dst = Join-Path -Path $targetRoot -ChildPath ($rel -replace '/', '\')
    $dstDir = Split-Path -Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dstDir -PathType Container)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $written++
}

# Record what this project now has, so the next sync can tell an upgrade from a customization.
#
# THE RULE: record the hash of what THIS TOOL WROTE, never the hash of what it found. The first
# version re-read every target file after apply, including the ones it had just skipped as locally
# modified -- which silently replaced the recorded blueprint hash with the hash of the user's
# customization. On the next sync recorded == target, the file classified as a plain upgrade, and
# the customization was overwritten in silence. A local change survived exactly one sync. That is
# the opposite of the promise on the tin.
#
# So: a file written now records the hash it was written with. A file skipped -- locally modified,
# or pre-existing -- keeps whatever hash was recorded before, so it is still reported as modified
# next time, every time, until a human resolves it. A file never recorded and never written stays
# unrecorded. Unchanged files are re-read only to be safe against a hash that was never stored.
$fileHashes = [ordered]@{}
$writtenSet = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($r in $toWrite) { [void]$writtenSet.Add($r) }

foreach ($rel in ($sourceFiles | Sort-Object -Unique)) {
    if (Test-Protected -Relative $rel) { continue }
    if (Test-SourceOnly -Relative $rel) { continue }
    $dst = Join-Path -Path $targetRoot -ChildPath ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) { continue }

    if ($writtenSet.Contains($rel)) {
        # Written this run: the target now carries the source content, so its hash IS the
        # source hash. Read it back rather than trusting the copy -- the read is what we record.
        $fileHashes[$rel] = Get-Sha256 -Path $dst
    } elseif ($recorded.ContainsKey($rel)) {
        # Skipped with a prior record: keep the prior record. This is the whole fix.
        $fileHashes[$rel] = $recorded[$rel]
    } elseif ($unchanged.Contains($rel)) {
        # Identical to source and never recorded (first sync with a pre-placed identical file):
        # recording it is safe, because target == source by definition here.
        $fileHashes[$rel] = Get-Sha256 -Path $dst
    }
    # Pre-existing and never recorded: leave unrecorded. It is the project's file; the next sync
    # will report it pre-existing again, exactly as it should.
}

$record = [ordered]@{
    '$comment' = 'Written by scripts/blueprint/sync-blueprint. Do not edit by hand: the hashes are how the next sync distinguishes a blueprint upgrade from a local customization.'
    role       = 'adopted'
    version    = $sourceVersion.version
    syncedAt   = (Get-Date -Format 'yyyy-MM-dd')
    source     = $sourceRoot.Replace('\', '/')
    files      = $fileHashes
}

$json = $record | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($targetVersionPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Output ''
Write-Output ("Applied. {0} file(s) written, {1} recorded in {2}." -f $written, $fileHashes.Count, $dist.versionFile)
if ($localMods.Count -gt 0 -and -not $Force) {
    Write-Output ("{0} locally modified file(s) were left alone." -f $localMods.Count)
}
Write-Output ''
# The secret scan reads the git-tracked tree, so validation cannot pass in a folder that is not a
# repository yet. Say it here, at the moment it becomes true, rather than letting the next command
# fail and leave the reason to be guessed.
if (-not (Test-Path -LiteralPath (Join-Path -Path $targetRoot -ChildPath '.git'))) {
    Write-Output 'This target is not a git repository yet. Validation scans the git-tracked tree, so run first:'
    Write-Output '  git init -b main'
    Write-Output '  git add -A'
    Write-Output ''
}
Write-Output 'Now run the validation suite. A sync that leaves the project failing its own checks is not done:'
Write-Output '  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1'
exit 0
