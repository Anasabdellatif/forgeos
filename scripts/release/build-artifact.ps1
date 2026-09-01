#requires -Version 5.1
<#
.SYNOPSIS
Builds a ForgeOS release artifact and its SHA-256 checksum from TRACKED repository state.

.DESCRIPTION
Windows counterpart of build-artifact.sh. Source-only: this directory is never distributed.

The artifact is a SYNC SOURCE, not a product bundle. Its contents are derived from the manifest,
never hand-listed: everything sync can place -- the portable half, the portable root files, and
the seed files it copies from source paths -- plus blueprint.version so the copy can identify
itself, plus README.md and LICENSE so whoever downloads it knows what they have and under what
terms. Sync never places those last two; a person reading a tarball needs them.

What it must never carry: this repository's own answers (every seed target backed by a template),
its history (memory, tasks, plans), its release tooling (distribution.sourceOnly), and anything
untracked. git archive gives the last one for free -- it reads a commit, not a directory.

Exit 0 built or listed, 1 could not run, 2 refused.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release/build-artifact.ps1 -List
#>
param(
    [string]$Ref = 'HEAD',
    [string]$Out,
    [string]$Name,
    [switch]$List
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifestPath = Join-Path $repoRoot 'scripts/lib/blueprint-manifest.json'
if (-not $Out) { $Out = Join-Path $repoRoot 'dist' }

function Fail([string]$message, [int]$code = 1) {
    Write-Error $message -ErrorAction Continue
    exit $code
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git is required.' }
if (-not (Test-Path -LiteralPath $manifestPath)) { Fail "Manifest not found: $manifestPath" }

git -C $repoRoot rev-parse --git-dir > $null 2>&1
if ($LASTEXITCODE -ne 0) { Fail "Not a git repository: $repoRoot" }

$commit = (git -C $repoRoot rev-parse --verify "$Ref^{commit}" 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $commit) { Fail "Not a commit: $Ref" }
$commit = $commit.Trim()

# -Encoding UTF8 is not optional: PowerShell 5.1 reads a BOM-less file as CP1252 otherwise, and
# the manifest carries non-ASCII prose in its comments (v1.12.2).
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$dist = $manifest.distribution

$portable    = @($dist.portable)
$portFiles   = @($dist.portableFiles)
$seedFiles   = @($dist.seedFiles)
$templated   = @($dist.seedTemplates.PSObject.Properties.Name)
$sourceOnly  = @()
if ($dist.PSObject.Properties.Name -contains 'sourceOnly') { $sourceOnly = @($dist.sourceOnly) }
$versionFile = $dist.versionFile
$version     = $manifest.version

if ($portable.Count -eq 0 -or $portFiles.Count -eq 0 -or $seedFiles.Count -eq 0 -or
    -not $version -or -not $versionFile) {
    Fail "Cannot read blueprint manifest: $manifestPath"
}

# Read the version from the artifact's own commit, not from the working tree: building v1.14.2
# must not stamp it with today's edits.
$bpJson = (git -C $repoRoot show "${commit}:$versionFile" 2>$null) -join "`n"
if ($LASTEXITCODE -eq 0 -and $bpJson) {
    $m = [regex]::Match($bpJson, '"version"[ \t]*:[ \t]*"([^"]+)"')
    if ($m.Success) { $version = $m.Groups[1].Value }
}
if (-not $Name) { $Name = "forgeos-$version" }

function Test-SourceOnly([string]$path) {
    foreach ($q in $sourceOnly) {
        if (-not $q) { continue }
        if ($path -eq $q -or $path.StartsWith("$q/")) { return $true }
    }
    return $false
}

function Test-Templated([string]$path) {
    foreach ($q in $templated) { if ($path -eq $q) { return $true } }
    return $false
}

# --- The include list, derived from the manifest ------------------------------------------------
$include = New-Object System.Collections.Generic.List[string]
foreach ($p in $portable)  { if (-not (Test-SourceOnly $p)) { $include.Add($p) } }
foreach ($p in $portFiles) { if (-not (Test-SourceOnly $p)) { $include.Add($p) } }
foreach ($p in $seedFiles) {
    if (Test-Templated $p)   { continue }
    if (Test-SourceOnly $p)  { continue }
    $include.Add($p)
}
$include.Add($versionFile)
foreach ($p in @('README.md', 'LICENSE')) {
    git -C $repoRoot cat-file -e "${commit}:$p" 2>$null
    if ($LASTEXITCODE -eq 0) { $include.Add($p) }
}

# A portable directory can CONTAIN a source-only subtree, so the pathspec above is not enough:
# ask git what it resolves, then subtract. One place, visible, testable.
$listed = @(git -C $repoRoot ls-tree -r --name-only $commit -- $include.ToArray())
$resolved = New-Object System.Collections.Generic.List[string]
foreach ($f in ($listed | Sort-Object)) {
    if (-not $f) { continue }
    if (Test-SourceOnly $f) { continue }
    if (Test-Templated $f)  { continue }
    $resolved.Add($f)
}

if ($resolved.Count -eq 0) {
    Fail "The include list resolved to no files at $Ref. Refusing to build an empty artifact." 2
}

# Belt and braces: prove the resolved list carries none of what it must never carry, rather than
# trusting that the derivation above was right. A boundary nobody re-checks is a boundary by hope.
$historyPattern = '^\.ai/(memory/[^/]+|tasks/completed|plans/completed)/'
$seedSet = @{}
foreach ($p in $seedFiles) { $seedSet[$p] = $true }
$leaks = New-Object System.Collections.Generic.List[string]
foreach ($f in $resolved) {
    if (Test-SourceOnly $f) { $leaks.Add("source-only: $f") }
    if (Test-Templated $f)  { $leaks.Add("template-backed: $f") }
    # A declared seed file inside one of those directories is the README that explains what the
    # directory is for -- a new project needs it. Anything else there is this repository's record.
    if (($f -match $historyPattern) -and -not $seedSet.ContainsKey($f)) {
        $leaks.Add("project history: $f")
    }
}
if ($leaks.Count -gt 0) {
    Write-Host 'Refusing to build: the include list reaches paths the artifact must not carry.'
    foreach ($l in $leaks) { Write-Host "  - $l" }
    exit 2
}

$dirty = 'clean'
if ((git -C $repoRoot status --porcelain) -ne $null -and (git -C $repoRoot status --porcelain).Length -gt 0) {
    $dirty = 'dirty (ignored -- the artifact is built from the commit, not the working tree)'
}

$mode = 'BUILD'
if ($List) { $mode = 'LIST -- writes nothing' }

Write-Host ''
Write-Host "ForgeOS release artifact  [$mode]"
Write-Host ("  version    {0}" -f $version)
Write-Host ("  ref        {0}  ({1})" -f $Ref, $commit)
Write-Host ("  tree       {0}" -f $dirty)
Write-Host ("  files      {0}" -f $resolved.Count)
Write-Host ("  excluded   {0} source-only path(s), {1} template-backed seed target(s)" -f `
    $sourceOnly.Count, $templated.Count)

if ($List) {
    Write-Host ''
    foreach ($f in $resolved) { Write-Host "  $f" }
    Write-Host ''
    Write-Host '  Nothing was written.'
    exit 0
}

if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Path $Out | Out-Null }
$Out = (Resolve-Path -LiteralPath $Out).Path
$archive = Join-Path $Out "$Name.tar.gz"

git -C $repoRoot archive --format=tar.gz --prefix="$Name/" -o $archive $commit -- $resolved.ToArray()
if ($LASTEXITCODE -ne 0) { Fail 'git archive failed.' }

# sha256sum -c reads "<hash>  <name>" and rejects a line with a carriage return, so write LF and
# lowercase -- the file has to be verifiable on the platform that did not build it.
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLower()
$sumPath = "$archive.sha256"
[System.IO.File]::WriteAllText($sumPath, "$hash  $Name.tar.gz`n",
    (New-Object System.Text.UTF8Encoding($false)))

$size = (Get-Item -LiteralPath $archive).Length
Write-Host ''
Write-Host ("  archive    {0}  ({1} bytes)" -f $archive, $size)
Write-Host ("  checksum   {0}" -f $sumPath)
Write-Host ("             {0}" -f $hash)
Write-Host ''
Write-Host "  Verify with:  sha256sum -c $Name.tar.gz.sha256"
Write-Host "  Inspect with: tar -tzf $Name.tar.gz"
Write-Host ''
Write-Host '  Nothing was published. Publishing a release is a separate, authorized act.'
exit 0
