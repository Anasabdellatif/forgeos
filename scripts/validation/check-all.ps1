<#
.SYNOPSIS
    Runs the full blueprint validation suite and reports each check's observed result.

.DESCRIPTION
    Runs, in order: structure, empty files, hook self-test, and placeholder readiness.
    Exit 0 only when every gating check passed.

    The placeholder check is informational by default: a fresh blueprint is expected to report
    findings. Pass -Strict to gate on it, which is the right setting for an adopted project.

.PARAMETER Strict
    Also fail when blocking placeholders remain in always-loaded context.
#>
[CmdletBinding()]
param(
    [switch]$Strict
)

$ErrorActionPreference = 'Continue'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $scriptDir -ChildPath '..\..')).Path
$results = [System.Collections.Generic.List[psobject]]::new()

# Every check prints the number the public page claims -- the self-test total, the policy control
# count, the link counts. Until now the audit could not see them and reported them UNCHECKED, and
# they drifted twice in two phases. Tee each check into a run log and hand it to public-surface,
# which runs last: measured once, verified once, no check run twice.
$runLog = Join-Path ([System.IO.Path]::GetTempPath()) ('blueprint-check-all-' + [guid]::NewGuid().ToString('N') + '.log')

function Invoke-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @(),
        [switch]$Gating
    )

    Write-Output ''
    Write-Output ('=' * 78)
    Write-Output "CHECK: $Name"
    Write-Output ('=' * 78)

    $fullPath = Join-Path -Path $repoRoot -ChildPath $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Write-Output "SKIPPED: script not found at $Path"
        $results.Add([pscustomobject]@{ Name = $Name; Code = -1; Gating = [bool]$Gating; Status = 'missing' })
        return
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullPath @Arguments | Tee-Object -FilePath $runLog -Append
    $code = $LASTEXITCODE

    $status = if ($code -eq 0) { 'passed' } else { 'failed' }
    $results.Add([pscustomobject]@{ Name = $Name; Code = $code; Gating = [bool]$Gating; Status = $status })
}

Invoke-Check -Name 'structure'     -Path 'scripts\validation\check-structure.ps1'    -Arguments @('-Quiet') -Gating
Invoke-Check -Name 'empty-files'   -Path 'scripts\validation\check-empty-files.ps1'  -Gating
Invoke-Check -Name 'policy'        -Path 'scripts\validation\check-policy.ps1'       -Gating
Invoke-Check -Name 'links'         -Path 'scripts\validation\check-links.ps1'        -Gating
Invoke-Check -Name 'bp-version'    -Path 'scripts\validation\check-blueprint-version.ps1' -Gating
Invoke-Check -Name 'secrets'       -Path 'scripts\hooks\scan-secrets.ps1'  -Arguments @('-ScanTree') -Gating
Invoke-Check -Name 'hook-selftest' -Path 'scripts\hooks\selftest.ps1'                -Gating

if ($Strict) {
    Invoke-Check -Name 'placeholders' -Path 'scripts\validation\check-placeholders.ps1' -Arguments @('-FailOnBlocking') -Gating
} else {
    Invoke-Check -Name 'placeholders' -Path 'scripts\validation\check-placeholders.ps1'
}

Invoke-Check -Name 'context-budget' -Path 'scripts\validation\check-context-budget.ps1'
Invoke-Check -Name 'state-freshness' -Path 'scripts\validation\check-state-freshness.ps1'
Invoke-Check -Name 'public-surface'  -Path 'scripts\validation\check-public-surface.ps1' -Arguments @('-FailOnDrift', '-Measured', $runLog) -Gating

Write-Output ''
Write-Output ('=' * 78)
if (Test-Path -LiteralPath $runLog) { Remove-Item -LiteralPath $runLog -ErrorAction SilentlyContinue }

Write-Output 'SUMMARY'
Write-Output ('=' * 78)

foreach ($r in $results) {
    $gate = if ($r.Gating) { 'gating' } else { 'info  ' }
    Write-Output ("  {0,-14}  {1,-8}  exit={2,-3}  {3}" -f $r.Name, $r.Status, $r.Code, $gate)
}

$blocking = @($results | Where-Object { $_.Gating -and $_.Code -ne 0 })

Write-Output ''
if ($blocking.Count -gt 0) {
    Write-Output "VALIDATION FAILED: $($blocking.Count) gating check(s) did not pass."
    $blocking | ForEach-Object { Write-Output ("  - {0} (exit {1})" -f $_.Name, $_.Code) }
    exit 1
}

Write-Output 'VALIDATION PASSED: every gating check exited 0.'
exit 0
