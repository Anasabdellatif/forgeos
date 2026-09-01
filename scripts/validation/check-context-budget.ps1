<#
.SYNOPSIS
    Reports the always-loaded context against its recorded budget.

.DESCRIPTION
    Windows counterpart of check-context-budget.sh. The file set and the budget are data --
    policy.contextBudget in scripts/lib/blueprint-manifest.json -- so the meter and the contract
    cannot drift apart. Since v1.12.3 the set is split: platformFiles is the floor the blueprint
    imposes and a project cannot reduce; projectFiles is what the project owns and can trim. The
    project's allowance is derived -- the target minus the measured platform floor -- so an
    overrun is attributed to its owner: a bloated ledger is the project's to fix, a grown core.md
    is the blueprint's, and the verdict says which.

    Informational by design: it warns, it does not gate. -FailOnOver turns either OVER verdict
    into exit 1 for projects that want the budget enforced. Exit 1 also whenever the manifest or
    a budgeted file is missing -- a meter that cannot read its inputs must not report clean.
#>
[CmdletBinding()]
param(
    [switch]$FailOnOver
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'scripts\lib\blueprint-manifest.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Output 'Context budget check FAILED'
    Write-Output '  Manifest not found: scripts/lib/blueprint-manifest.json'
    exit 1
}

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Output 'Context budget check FAILED'
    Write-Output "  Manifest is not valid JSON: $($_.Exception.Message)"
    exit 1
}

$budget = $manifest.policy.contextBudget
if ($null -eq $budget -or
    $null -eq $budget.platformFiles -or $budget.platformFiles.Count -eq 0 -or
    $null -eq $budget.projectFiles -or $budget.projectFiles.Count -eq 0 -or
    -not $budget.charsPerToken -or -not $budget.targetTokens -or -not $budget.warnTokens) {
    Write-Output 'Context budget check FAILED'
    Write-Output '  policy.contextBudget is missing or incomplete in the manifest.'
    exit 1
}

$charsPerToken = [int]$budget.charsPerToken
$target = [int]$budget.targetTokens
$warn = [int]$budget.warnTokens

$script:missing = 0
$script:groupChars = 0
function Measure-Group {
    # Writes the group's lines and leaves the char sum in $script:groupChars. A pipeline return
    # would be polluted by the Write-Output lines on Windows PowerShell 5.1 -- the caller would
    # receive an array, not a number.
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Files
    )

    Write-Output "  $Label"
    $script:groupChars = 0
    foreach ($rel in $Files) {
        $full = Join-Path -Path $repoRoot -ChildPath ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            Write-Output ('    {0,-36} MISSING' -f $rel)
            $script:missing++
            continue
        }
        $size = (Get-Item -LiteralPath $full).Length
        $script:groupChars += $size
        Write-Output ('    {0,-36} {1,6} chars  ~{2,5} tokens' -f $rel, $size, [math]::Floor($size / $charsPerToken))
    }
}

Write-Output 'Context budget -- always-loaded files'
Measure-Group -Label 'platform (the blueprint floor -- a project cannot reduce these):' -Files $budget.platformFiles
$platformChars = $script:groupChars
Measure-Group -Label 'project (project-owned -- trim here when over):' -Files $budget.projectFiles
$projectChars = $script:groupChars

$platformTk = [math]::Floor($platformChars / $charsPerToken)
$projectTk = [math]::Floor($projectChars / $charsPerToken)
$totalChars = $platformChars + $projectChars
$totalTk = [math]::Floor($totalChars / $charsPerToken)
$allowTarget = $target - $platformTk
$allowWarn = $warn - $platformTk

Write-Output '  --------------------------------------------------------------'
Write-Output ('  {0,-38} {1,6} chars  ~{2,5} tokens' -f 'platform subtotal', $platformChars, $platformTk)
Write-Output ('  {0,-38} {1,6} chars  ~{2,5} tokens' -f 'project subtotal', $projectChars, $projectTk)
Write-Output ('  {0,-38} {1,6} chars  ~{2,5} tokens' -f 'always-loaded total', $totalChars, $totalTk)
Write-Output ('  budget: target {0} tokens, warn {1} (chars/token: {2})' -f $target, $warn, $charsPerToken)
Write-Output ('  project allowance: ~{0} tokens to target, ~{1} to warn (target minus the platform floor)' -f $allowTarget, $allowWarn)

if ($script:missing -gt 0) {
    Write-Output "Context budget check FAILED  ($script:missing budgeted file(s) missing -- seed or sync the project first)"
    exit 1
}

# Attribution order: a floor that exceeds the budget on its own is the blueprint's problem and
# must be named before any advice to trim project files -- which could not help anyway.
if ($platformTk -gt $target) {
    Write-Output "Context budget PLATFORM OVER  (the blueprint floor alone ~$platformTk > target $target -- a blueprint problem, not this project's)"
    if ($FailOnOver) { exit 1 }
} elseif ($projectTk -gt $allowTarget) {
    Write-Output "Context budget PROJECT OVER  (project files ~$projectTk > their ~$allowTarget allowance -- trim the project files listed above)"
    if ($FailOnOver) { exit 1 }
} elseif ($platformTk -gt $warn) {
    Write-Output "Context budget PLATFORM WARN  (the blueprint floor alone ~$platformTk > warn $warn -- the next trim is the blueprint's, not this project's)"
} elseif ($projectTk -gt $allowWarn) {
    Write-Output "Context budget PROJECT WARN  (project files ~$projectTk of ~$allowTarget, past the ~$allowWarn warn room -- the next trim belongs to the project files)"
} else {
    Write-Output "Context budget OK  (total ~$totalTk of $target tokens; project ~$projectTk of ~$allowTarget)"
}
exit 0
