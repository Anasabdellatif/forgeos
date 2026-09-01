<#
.SYNOPSIS
    Reports which blueprint version this repository carries, and which synced files have
    drifted from it.

.DESCRIPTION
    Needs no access to the source blueprint. It compares the file hashes recorded in
    blueprint.version against the files on disk, so it answers two questions offline:

      - Which blueprint version did this project adopt?
      - Which portable files has this project since edited?

    A local edit is not a failure. It is a fact the next sync must know, because sync-blueprint
    skips locally modified files rather than overwriting them. This check makes that set visible
    before the sync, not during it.

    In the source blueprint (role "source") it only validates the version file, since there is
    nothing to have drifted from.

.PARAMETER FailOnDrift
    Exit 1 when any synced file has been locally modified. Off by default: customization is
    expected and legitimate.
#>
[CmdletBinding()]
param(
    [switch]$FailOnDrift
)

$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    $root = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    return $root.Path
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

$repoRoot = Get-RepositoryRoot
$manifest = Get-Content -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'scripts\lib\blueprint-manifest.json') -Raw | ConvertFrom-Json
$versionFile = $manifest.distribution.versionFile
$versionPath = Join-Path -Path $repoRoot -ChildPath $versionFile

if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    Write-Output "Blueprint version check FAILED"
    Write-Output "  $versionFile is missing."
    Write-Output ''
    Write-Output 'Without it, this repository cannot say which blueprint it carries, and'
    Write-Output 'sync-blueprint cannot tell a local customization from an upstream change.'
    exit 1
}

try {
    $version = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json
} catch {
    Write-Output "Blueprint version check FAILED"
    Write-Output "  $versionFile is not valid JSON."
    exit 1
}

$role = if ($version.role) { $version.role } else { 'unknown' }
Write-Output "Blueprint version"
Write-Output ("  version   {0}" -f $version.version)
Write-Output ("  role      {0}" -f $role)
if ($version.syncedAt) { Write-Output ("  synced    {0}  from  {1}" -f $version.syncedAt, $version.source) }
if ($version.releasedAt) { Write-Output ("  released  {0}" -f $version.releasedAt) }

if ($role -eq 'source') {
    Write-Output ''
    Write-Output 'This is the source blueprint. Nothing to compare against.'
    exit 0
}

if (-not $version.files) {
    Write-Output ''
    Write-Output "No file hashes recorded in $versionFile. Drift cannot be detected."
    Write-Output 'Re-run scripts/blueprint/sync-blueprint.ps1 -Apply to record them.'
    exit 1
}

$drifted = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()
$intact = 0

foreach ($entry in $version.files.PSObject.Properties) {
    $path = Join-Path -Path $repoRoot -ChildPath ($entry.Name -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $missing.Add($entry.Name)
        continue
    }
    if ((Get-Sha256 -Path $path) -ne $entry.Value) { $drifted.Add($entry.Name) } else { $intact++ }
}

Write-Output ''
Write-Output ("  intact             {0}" -f $intact)
Write-Output ("  locally modified   {0}" -f $drifted.Count)
Write-Output ("  missing            {0}" -f $missing.Count)

if ($drifted.Count -gt 0) {
    Write-Output ''
    Write-Output '  LOCALLY MODIFIED since the last sync:'
    $drifted | Sort-Object | ForEach-Object { Write-Output "    ! $_" }
    Write-Output ''
    Write-Output '  sync-blueprint will skip these rather than overwrite them. That is deliberate.'
    Write-Output '  If a change here is generally useful, contribute it back to the source blueprint'
    Write-Output '  instead of maintaining a fork of it in this project.'
}

if ($missing.Count -gt 0) {
    Write-Output ''
    Write-Output '  MISSING (recorded but no longer present):'
    $missing | Sort-Object | ForEach-Object { Write-Output "    - $_" }
}

if ($FailOnDrift -and ($drifted.Count -gt 0 -or $missing.Count -gt 0)) {
    Write-Output ''
    Write-Output 'FAILED: -FailOnDrift was requested and the synced set has drifted.'
    exit 1
}

exit 0
