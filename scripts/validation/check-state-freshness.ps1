<#
.SYNOPSIS
    Reports how far the state ledger lags the repository.

.DESCRIPTION
    Windows counterpart of check-state-freshness.sh. The persistence gate
    (.ai/contract/reporting.md section 0) says no final report ships before durable state lands
    in its file. Nothing mechanical can read a conversation, but the ledger's lag behind HEAD is
    measurable: a ledger many commits old is either stale or the sessions since produced nothing
    durable -- and the second claim deserves to be made out loud.

    Advisory by design, and deliberately never a failure: a pre-v1.12 adoption has no ledger
    yet, an unborn repository has no history -- both are findings to report, not reasons to
    block a validation run on an old project. Always exits 0.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$ledgerRel = '.ai/context/current-state.md'
$ledger = Join-Path -Path $repoRoot -ChildPath ($ledgerRel -replace '/', '\')

Write-Output 'State ledger freshness'
Write-Output "  ledger    $ledgerRel"

if (-not (Test-Path -LiteralPath $ledger -PathType Leaf)) {
    Write-Output 'State freshness NOTE  (no state ledger -- pre-v1.12 adoption; sync from the blueprint to seed it)'
    exit 0
}

& git -C $repoRoot rev-parse --git-dir 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'State freshness NOTE  (not a git repository -- freshness cannot be measured here)'
    exit 0
}

# A truncated history cannot answer this question, and answering it anyway produces the one
# result a validation must never produce: a false all-clear. `git log -1 -- <ledger>` walks only
# the commits that were fetched, so under actions/checkout's default fetch-depth of 1 it returns
# HEAD for ANY ledger -- a ledger untouched for a hundred commits reads as "updated by the latest
# commit". Measured against this repository at 987f907: full clone reported NOTE (1 commit behind),
# a depth-1 clone of the same commit reported OK. A check that cannot see the evidence says so.
$shallow = (& git -C $repoRoot rev-parse --is-shallow-repository 2>$null | Select-Object -First 1)
if ($shallow -ne 'true') {
    # --is-shallow-repository arrived in git 2.15. Older git answers nothing, so ask the file that
    # makes a repository shallow in the first place.
    $gitDir = (& git -C $repoRoot rev-parse --absolute-git-dir 2>$null | Select-Object -First 1)
    if ($gitDir -and (Test-Path -LiteralPath (Join-Path $gitDir 'shallow'))) { $shallow = 'true' }
}
if ($shallow -eq 'true') {
    Write-Output 'State freshness NOTE  (shallow history -- the ledger lag cannot be measured here; fetch full history to measure it)'
    exit 0
}

$lastCommit = (& git -C $repoRoot log -1 --format='%h %cs' -- $ledgerRel 2>$null | Select-Object -First 1)
if (-not $lastCommit) {
    Write-Output 'State freshness NOTE  (the ledger exists but was never committed -- commit it with the work it describes)'
    exit 0
}
Write-Output "  last touched   $lastCommit"

$dirty = (& git -C $repoRoot status --porcelain -- $ledgerRel 2>$null | Select-Object -First 1)
if ($dirty) {
    Write-Output 'State freshness OK  (the ledger is modified in the working tree -- being refreshed now)'
    exit 0
}

$lastHash = ($lastCommit -split ' ')[0]
$behind = (& git -C $repoRoot rev-list --count "$lastHash..HEAD" 2>$null | Select-Object -First 1)
if (-not $behind) { $behind = 0 }
Write-Output "  behind HEAD    $behind commit(s)"

if ([int]$behind -eq 0) {
    Write-Output 'State freshness OK  (the ledger was updated by the latest commit)'
} else {
    Write-Output "State freshness NOTE  ($behind commit(s) since the last ledger update -- refresh it, or the report must say why the state is unchanged)"
}
exit 0
