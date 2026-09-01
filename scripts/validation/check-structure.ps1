<#
.SYNOPSIS
    Verifies that every required blueprint directory and file exists and is non-empty.

.DESCRIPTION
    Reads the required paths from scripts/lib/blueprint-manifest.json. The path list lives in the
    manifest, as data, so it is declared once and shared with check-structure.sh instead of being
    duplicated in two scripts.

    Exit 0 when the structure is intact, 1 otherwise.

.PARAMETER Quiet
    Print only failures and the final summary.
#>
[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    $root = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    return $root.Path
}

$repoRoot = Get-RepositoryRoot
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'scripts\lib\blueprint-manifest.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Error "Manifest not found: $manifestPath"
    exit 1
}

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Manifest is not valid JSON: $manifestPath`n$($_.Exception.Message)"
    exit 1
}

$failures = [System.Collections.Generic.List[string]]::new()
$okCount = 0

# Valid JSON is not a readable manifest. A truncated write, a bad merge, or a renamed key leaves
# an object that parses cleanly and carries nothing -- and the loops below would then verify zero
# paths and report "Structure validation passed (0 paths verified)". A false all-clear is worse
# than no check, so require the data before trusting a clean result.
if (-not $manifest.requiredDirectories -or -not $manifest.requiredFiles) {
    Write-Output 'Cannot read blueprint manifest. Install jq or python3.'
    Write-Output "  manifest : $manifestPath"
    Write-Output '  The file parsed, but requiredDirectories or requiredFiles is missing or empty.'
    exit 1
}

foreach ($relative in $manifest.requiredDirectories) {
    $path = Join-Path -Path $repoRoot -ChildPath ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (Test-Path -LiteralPath $path -PathType Container) {
        $okCount++
        if (-not $Quiet) { Write-Output "OK  dir   $relative" }
    } else {
        $failures.Add("Missing directory: $relative")
    }
}

# A source-only path exists in the source repository and NOWHERE ELSE -- that is what the
# classification means. Requiring it everywhere made this check fail in every project that
# adopted v1.15.0 or later: five release-tooling files declared required, correctly never copied,
# and reported missing. Read the role and require them only where they belong; in an adopted
# project their PRESENCE is the finding, and check-policy is where that is asserted.
$structRole = ''
$structVersionPath = Join-Path $repoRoot 'blueprint.version'
if (Test-Path -LiteralPath $structVersionPath) {
    $structVerText = Get-Content -LiteralPath $structVersionPath -Raw -Encoding UTF8
    $structRoleMatch = [regex]::Match($structVerText, '"role"[ 	]*:[ 	]*"([^"]+)"')
    if ($structRoleMatch.Success) { $structRole = $structRoleMatch.Groups[1].Value }
}
$structSourceOnly = @()
if ($manifest.distribution -and ($manifest.distribution.PSObject.Properties.Name -contains 'sourceOnly')) {
    $structSourceOnly = @($manifest.distribution.sourceOnly)
}
function Test-StructSourceOnly {
    param([string]$Path)
    foreach ($q in $structSourceOnly) {
        if (-not $q) { continue }
        if ($Path -eq $q -or $Path.StartsWith("$q/")) { return $true }
    }
    return $false
}

foreach ($relative in $manifest.requiredFiles) {
    if ($structRole -ne 'source' -and (Test-StructSourceOnly -Path $relative)) { continue }
    $path = Join-Path -Path $repoRoot -ChildPath ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Missing file: $relative")
        continue
    }

    $item = Get-Item -LiteralPath $path
    if ($item.Length -eq 0) {
        $failures.Add("Empty file: $relative")
        continue
    }

    $okCount++
    if (-not $Quiet) { Write-Output "OK  file  $relative" }
}

# Orphan detection: a required-looking path that exists but is not declared in the manifest.
$declared = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($f in $manifest.requiredFiles) { [void]$declared.Add($f) }

$scanRoots = @('.ai', '.claude', 'scripts', 'templates', 'examples')
$undeclared = [System.Collections.Generic.List[string]]::new()
foreach ($scanRoot in $scanRoots) {
    $full = Join-Path -Path $repoRoot -ChildPath $scanRoot
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
    Get-ChildItem -LiteralPath $full -Recurse -File -Include '*.md', '*.ps1', '*.sh', '*.json' |
        Where-Object { $_.FullName -notmatch '[\\/](tasks|plans)[\\/](inbox|active|completed|abandoned)[\\/]' } |
        Where-Object { $_.FullName -notmatch '[\\/]memory[\\/](decisions|lessons|incidents|handoffs)[\\/](?!README\.md)' } |
        ForEach-Object {
            $rel = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
            if (-not $declared.Contains($rel)) { $undeclared.Add($rel) }
        }
}

Write-Output ''
if ($undeclared.Count -gt 0) {
    Write-Output "Undeclared files (exist but not in the manifest -- add them or remove them):"
    $undeclared | Sort-Object | ForEach-Object { Write-Output "  ? $_" }
    Write-Output ''
}

if ($failures.Count -gt 0) {
    Write-Output "Structure validation FAILED  ($okCount ok, $($failures.Count) failed)"
    $failures | ForEach-Object { Write-Output "  - $_" }
    exit 1
}

Write-Output "Structure validation passed  ($okCount paths verified, $($undeclared.Count) undeclared)"
exit 0
