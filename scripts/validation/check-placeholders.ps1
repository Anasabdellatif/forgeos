<#
.SYNOPSIS
    Reports unfilled placeholder markers, weighted by how much they degrade agent behavior.

.DESCRIPTION
    A fresh blueprint is full of TBD markers by design. Each one is a project fact the adopting
    project must supply. This script turns that into an adoption-readiness score so the gap is
    visible instead of silently inherited.

    check-structure verifies that files exist. This verifies that they say something.

.PARAMETER FailOnBlocking
    Exit 1 when any target with weight "blocking" still has unfilled markers. Use in CI for a
    real project; leave off for the blueprint repository itself.

.PARAMETER Detailed
    List every finding rather than the top files per target.
#>
[CmdletBinding()]
param(
    [switch]$FailOnBlocking,
    [switch]$Detailed
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

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

# Valid JSON is not a readable manifest. With no scan targets this script reports "0 blocking" and
# "This project is fully adopted" about a project it never looked at -- and that answer is what the
# discovery gate in .ai/contract/core.md consults. A false clean here opens the gate on an
# undefined project, which is the single failure the gate exists to prevent.
if (-not $manifest.placeholderScan -or -not $manifest.placeholderScan.targets -or -not $manifest.placeholderScan.markers) {
    Write-Output 'Cannot read blueprint manifest. Install jq or python3.'
    Write-Output "  manifest : $manifestPath"
    Write-Output '  The file parsed, but placeholderScan.targets or .markers is missing or empty.'
    exit 1
}
# Whole-word matching so "TBD", "TBD:", "TBD." and "TBD," all count.
$markers = $manifest.placeholderScan.markers
$markerPattern = '\b(' + (($markers | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'

# The templates use a second convention: bracketed prompts such as [requirements and approach].
# A document written entirely in that style has zero TBD and would otherwise report as ready.
$bracketPattern = $manifest.placeholderScan.bracketPattern

$totalFindings = 0
$blockingFindings = 0
$summary = [System.Collections.Generic.List[psobject]]::new()

Write-Output 'Blueprint adoption readiness'
Write-Output '============================'
Write-Output ''

foreach ($target in $manifest.placeholderScan.targets) {
    $dir = Join-Path -Path $repoRoot -ChildPath ($target.path -replace '/', [System.IO.Path]::DirectorySeparatorChar)

    # A missing target is not "ready" -- it is the most unfilled a project can be. Treating it as
    # ready would let the discovery gate fail open on a brand-new project, which is the one case
    # the gate exists for.
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        $penalty = 1
        $totalFindings += $penalty
        if ($target.weight -eq 'blocking') { $blockingFindings += $penalty }
        Write-Output ("MISSING   [{0,-8}]  {1,-24}  directory does not exist" -f $target.weight, $target.path)
        Write-Output ("            {0}" -f $target.note)
        Write-Output '            Run sync-blueprint to seed the project-specific scaffolding.'
        Write-Output ''
        $summary.Add([pscustomobject]@{ Path = $target.path; Weight = $target.weight; Count = $penalty })
        continue
    }

    $findings = [System.Collections.Generic.List[psobject]]::new()
    Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.md' | ForEach-Object {
        $file = $_
        $lineNumber = 0
        $inFence = $false
        foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
            $lineNumber++

            # Skip fenced code blocks: array[index] in a sample is code, not an unfilled gap.
            if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
            if ($inFence) { continue }

            # A marker inside backticks is a MENTION of the marker, not a gap -- ".ai/context/README.md"
            # says "While any `TBD` remains..." as documentation. Counting it kept the discovery gate
            # closed on a defined project by accident, which is a false positive holding the line.
            $prose = [regex]::Replace($line, '`[^`]*`', '')
            $isMarker = $prose -match $markerPattern
            $isBracket = $bracketPattern -and ($line -match $bracketPattern)

            if ($isMarker -or $isBracket) {
                $findings.Add([pscustomobject]@{
                    File = $file.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
                    Line = $lineNumber
                    Kind = if ($isMarker) { 'marker' } else { 'bracket' }
                    Text = $line.Trim()
                })
            }
        }
    }

    $count = $findings.Count
    $totalFindings += $count
    if ($target.weight -eq 'blocking') { $blockingFindings += $count }

    $status = if ($count -eq 0) { 'READY  ' } else { 'UNFILLED' }
    $brk = @($findings | Where-Object { $_.Kind -eq 'bracket' }).Count
    $detail = if ($brk -gt 0) { "$count line(s)  ($($count - $brk) marker, $brk bracket)" } else { "$count line(s)" }
    Write-Output ("{0}  [{1,-8}]  {2,-24}  {3}" -f $status, $target.weight, $target.path, $detail)

    if ($count -gt 0) {
        Write-Output ("            {0}" -f $target.note)
        if ($Detailed) {
            $findings | ForEach-Object { Write-Output ("            {0}:{1}  {2}" -f $_.File, $_.Line, $_.Text) }
        } else {
            $findings | Group-Object File | Sort-Object Count -Descending | Select-Object -First 4 | ForEach-Object {
                Write-Output ("            {0}  ({1})" -f $_.Name, $_.Count)
            }
        }
        Write-Output ''
    }

    $summary.Add([pscustomobject]@{ Path = $target.path; Weight = $target.weight; Count = $count })
}

Write-Output ''
Write-Output ("Total unfilled markers: {0}   (blocking: {1})" -f $totalFindings, $blockingFindings)

if ($totalFindings -eq 0) {
    Write-Output 'This project is fully adopted. Every context and documentation fact is supplied.'
    exit 0
}

Write-Output ''
Write-Output 'These are not defects in a fresh blueprint. They are the facts the adopting project'
Write-Output 'must supply. Run the /adopt command, or fill them from real evidence -- never by guessing.'

if ($FailOnBlocking -and $blockingFindings -gt 0) {
    Write-Output ''
    Write-Output "FAILED: $blockingFindings blocking marker(s) remain in always-loaded context."
    exit 1
}

exit 0
