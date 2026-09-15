<#
.SYNOPSIS
    Reports whether a project has turned its governing documents into compact product intelligence.

.DESCRIPTION
    Windows counterpart of check-project-ingestion.sh. M-25 Project Ingestion Layer, slice 1.

    A project that already carries governing documents -- a client specification, developer
    documents, a data model -- is expected to build seven compact, cited maps in .ai/product/
    before implementation. A project with none is expected to prepare six discovery records there
    instead. The procedure that fills them is .ai/workflows/ingest-project.md.

    Informational by design, and never a failure: a project that adopted before this layer existed
    has no maps yet, and that is a finding to report, not a reason to fail validation. Gating is
    slice 3, once the layer is proven on adopters. Always exits 0.

    Cheap by construction: it checks directory and file PRESENCE only. It never opens a governing
    document, never reads a PDF, and never scans content.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$productRel = '.ai/product'
$productDir = Join-Path -Path $repoRoot -ChildPath '.ai\product'

function Show-Row {
    param([string]$Label, [string]$Value)
    Write-Output ('  {0,-13} {1}' -f $Label, $Value)
}

$role = 'unknown'
$versionFile = Join-Path -Path $repoRoot -ChildPath 'blueprint.version'
if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
    $roleLine = Select-String -LiteralPath $versionFile -Pattern '"role"' | Select-Object -First 1
    if ($roleLine) {
        $roleValue = ($roleLine.Line -replace '.*:\s*"', '') -replace '".*', ''
        if ($roleValue) { $role = $roleValue }
    }
}

Write-Output 'Project ingestion'
Show-Row -Label 'role' -Value $role

if ($role -eq 'source') {
    Show-Row -Label 'mode' -Value 'NOT_APPLICABLE'
    Write-Output 'Project ingestion N/A  (source role -- the blueprint has no product of its own to ingest; adopting projects are checked)'
    exit 0
}

# Governing document directories, as a first guess. Each entry is one logical place in up to two
# common spellings; the first that exists is reported, so a case-insensitive filesystem answers once
# and both shells print the same name. A directory counts only when it holds at least one file, and
# the enumeration stops at the first file it sees -- the contents are never read.
$candidatePairs = @('docs/Client:docs/client', 'docs/Developer:docs/developer', 'docs/data:docs/Data',
                    'docs/specifications:', 'docs/specs:')
$governing = New-Object System.Collections.Generic.List[string]
foreach ($pair in $candidatePairs) {
    foreach ($cand in ($pair -split ':')) {
        if (-not $cand) { continue }
        $full = Join-Path -Path $repoRoot -ChildPath ($cand -replace '/', '\')
        if (Test-Path -LiteralPath $full -PathType Container) {
            $firstFile = Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($firstFile) {
                $governing.Add($cand)
                break
            }
        }
    }
}

# A map counts only when it is non-empty: an empty file is a placeholder, not a map.
function Test-Map {
    param([string]$Name)
    $path = Join-Path -Path $productDir -ChildPath "$Name.md"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    return ((Get-Item -LiteralPath $path).Length -gt 0)
}

$intelNames = @('authority-map', 'source-index', 'project-concept', 'module-map', 'requirement-matrix',
                'implementation-roadmap', 'open-decisions')
$discNames = @('project-brief', 'stakeholders', 'module-map-draft', 'questions', 'assumptions', 'phase-roadmap')

$intelCount = 0
$intelMissing = New-Object System.Collections.Generic.List[string]
foreach ($name in $intelNames) {
    if (Test-Map -Name $name) { $intelCount++ } else { $intelMissing.Add("$productRel/$name.md") }
}

$discCount = 0
$discMissing = New-Object System.Collections.Generic.List[string]
foreach ($name in $discNames) {
    if (Test-Map -Name $name) { $discCount++ } else { $discMissing.Add("$productRel/$name.md") }
}

# The authority map is the declaration: a project that has written one says its governing documents
# exist, wherever they live -- the directory list above is only the first guess.
$mode = 'PROJECT_DISCOVERY_REQUIRED'
$governingText = 'none found'
if ($governing.Count -gt 0) {
    $mode = 'PROJECT_WITH_GOVERNING_DOCS'
    $governingText = ($governing -join ', ')
} elseif (Test-Map -Name 'authority-map') {
    $mode = 'PROJECT_WITH_GOVERNING_DOCS'
    $governingText = "declared in $productRel/authority-map.md"
}

Show-Row -Label 'mode' -Value $mode
Show-Row -Label 'governing' -Value $governingText
Show-Row -Label 'intelligence' -Value "$intelCount of 7 in $productRel"
Show-Row -Label 'discovery' -Value "$discCount of 6 in $productRel"

if ($mode -eq 'PROJECT_WITH_GOVERNING_DOCS') {
    if ($intelCount -eq 7) {
        Write-Output 'Project ingestion OK  (governing documents found; the product intelligence layer is complete, 7 of 7 maps)'
    } else {
        Show-Row -Label 'missing' -Value ($intelMissing -join ', ')
        Write-Output "Project ingestion NOTE  (governing documents found; $intelCount of 7 product intelligence maps -- run .ai/workflows/ingest-project.md before implementation)"
    }
} else {
    if ($discCount -eq 6) {
        Write-Output 'Project ingestion OK  (no governing documents found; the discovery layer is complete, 6 of 6 records)'
    } else {
        Show-Row -Label 'missing' -Value ($discMissing -join ', ')
        Write-Output "Project ingestion NOTE  (no governing documents found; $discCount of 6 discovery records -- run .ai/workflows/ingest-project.md in discovery mode before implementation)"
    }
}

exit 0
