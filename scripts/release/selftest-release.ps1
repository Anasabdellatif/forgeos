#requires -Version 5.1
<#
.SYNOPSIS
Self-test for the release artifact builder. SOURCE-ONLY, like the builder it tests.

.DESCRIPTION
scripts/hooks/selftest.ps1 cannot host these cases: it is portable, so it runs inside every
adopting project -- where scripts/release/ does not exist by design, and every case here would
fail for the right reason. Portable tests cover portable behaviour; this covers ours.

The two guarantees adopters DO depend on -- sync never copies a source-only path, and a fresh
register is seeded from the template -- live in the portable self-test where they belong.

Same cases, same labels, same order as selftest-release.sh.

Exit 0 all passed, 1 something failed.
#>

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$builder = Join-Path $repoRoot 'scripts/release/build-artifact.ps1'

$script:total = 0
$script:failed = 0
$script:failedCases = New-Object System.Collections.Generic.List[string]

function Assert-Count {
    param([string]$Case, [int]$Expected, [int]$Actual)
    $script:total++
    if ($Expected -eq $Actual) {
        Write-Output ("PASS  {0,-58} {1}/{2}" -f $Case, $Actual, $Expected)
    } else {
        $script:failed++
        $script:failedCases.Add("  - $Case (expected $Expected, got $Actual)")
        Write-Output ("FAIL  {0,-58} {1}/{2}" -f $Case, $Actual, $Expected)
    }
}

function Invoke-Builder {
    param([string[]]$BuilderArgs)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $builder @BuilderArgs 2>&1
    return [pscustomobject]@{ Output = ($out -join "`n"); Code = $LASTEXITCODE }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error 'git is required for the release self-test.'; exit 1
}
git -C $repoRoot rev-parse --git-dir > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error 'Not a git repository; the builder reads tracked state, so there is nothing to test.'
    exit 1
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("forgeos-release-selftest-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

# An untracked file must never reach an artifact. Create one so its absence proves something.
$probe = Join-Path $repoRoot '.ai/rules/RELEASE-SELFTEST-PROBE.md'
Set-Content -LiteralPath $probe -Value '# untracked probe' -Encoding UTF8

try {
    # --- 1. List mode reports the set and writes nothing -------------------------------------
    $neverDir = Join-Path $tmp 'never'
    $r = Invoke-Builder @('-List', '-Out', $neverDir)
    $ok = 0
    if ($r.Code -eq 0) { $ok++ }
    if ($r.Output -match 'Nothing was written') { $ok++ }
    if (-not (Test-Path -LiteralPath $neverDir)) { $ok++ }
    Assert-Count -Case 'release: list mode reports the set and writes nothing' -Expected 3 -Actual $ok

    # --- 2. A build produces an archive and a checksum that verifies -------------------------
    $distDir = Join-Path $tmp 'dist'
    $r = Invoke-Builder @('-Out', $distDir, '-Name', 'selftest-artifact')
    $archive = Join-Path $distDir 'selftest-artifact.tar.gz'
    $sumFile = "$archive.sha256"
    $ok = 0
    if ($r.Code -eq 0) { $ok++ }
    if (Test-Path -LiteralPath $archive) { $ok++ }
    if (Test-Path -LiteralPath $sumFile) { $ok++ }
    Assert-Count -Case 'release: a build writes an archive and a checksum' -Expected 3 -Actual $ok

    $ok = 0
    if ((Test-Path -LiteralPath $sumFile) -and (Test-Path -LiteralPath $archive)) {
        $recorded = ((Get-Content -LiteralPath $sumFile -Raw) -split '\s+')[0]
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLower()
        if ($recorded -eq $actual) { $ok = 1 }
    }
    Assert-Count -Case 'release: the checksum verifies the archive it names' -Expected 1 -Actual $ok

    # A checksum file that only its author can read is not a checksum. sha256sum -c rejects a
    # line with a carriage return, and this half is the one running on Windows.
    $ok = 0
    if (Test-Path -LiteralPath $sumFile) {
        $bytes = [System.IO.File]::ReadAllBytes($sumFile)
        if (($bytes | Where-Object { $_ -eq 13 }).Count -eq 0) { $ok = 1 }
    }
    Assert-Count -Case 'release: the checksum file carries no carriage return' -Expected 1 -Actual $ok

    # --- 3. The boundary ---------------------------------------------------------------------
    $entries = @()
    if (Test-Path -LiteralPath $archive) {
        $entries = @(& tar -tzf $archive 2>$null |
            ForEach-Object { $_ -replace '^selftest-artifact/', '' } |
            Where-Object { $_ -and -not $_.EndsWith('/') })
    }
    $entrySet = @{}
    foreach ($e in $entries) { $entrySet[$e] = $true }
    function Test-Entry { param([string]$Path) return $entrySet.ContainsKey($Path) }
    function Test-AnyEntry { param([string]$Pattern) return @($entries | Where-Object { $_ -match $Pattern }).Count -gt 0 }

    $ok = 0
    if (Test-Entry 'scripts/lib/blueprint-manifest.json') { $ok++ }
    if (Test-Entry 'blueprint.version') { $ok++ }
    if (Test-Entry 'CLAUDE.md') { $ok++ }
    if (Test-Entry 'scripts/blueprint/sync-blueprint.sh') { $ok++ }
    Assert-Count -Case 'release: the artifact carries what sync needs to run' -Expected 4 -Actual $ok

    $ok = 0
    if (-not (Test-AnyEntry '^scripts/release/')) { $ok++ }
    if (-not (Test-AnyEntry '^\.git/')) { $ok++ }
    if (-not (Test-AnyEntry 'RELEASE-SELFTEST-PROBE')) { $ok++ }
    Assert-Count -Case 'release: no source-only tooling, git internals, or untracked file' -Expected 3 -Actual $ok

    # Every seed target backed by a template holds THIS repository's answers -- identity,
    # constraints, governance (codeAuthorized true), the ledger, the register. Shipping one would
    # hand a new project our answers, which is the failure seedTemplates exists to prevent.
    $ok = 0
    foreach ($f in @('.ai/context/project.md', '.ai/context/constraints.md',
                     '.ai/context/governance.json', '.ai/context/current-state.md',
                     '.ai/memory/open-questions.md')) {
        if (-not (Test-Entry $f)) { $ok++ }
    }
    Assert-Count -Case 'release: the artifact carries none of our own answers' -Expected 5 -Actual $ok

    $ok = 0
    if (-not (Test-AnyEntry '^\.ai/memory/decisions/2026-')) { $ok++ }
    if (-not (Test-AnyEntry '^\.ai/memory/lessons/2026-'))   { $ok++ }
    if (-not (Test-AnyEntry '^\.ai/tasks/completed/2026-'))  { $ok++ }
    if (Test-Entry '.ai/memory/decisions/README.md') { $ok++ }
    Assert-Count -Case 'release: history stays home but its scaffolding travels' -Expected 4 -Actual $ok

    # --- 4. Same commit, same bytes -----------------------------------------------------------
    $dist2 = Join-Path $tmp 'dist2'
    Invoke-Builder @('-Out', $dist2, '-Name', 'selftest-artifact') | Out-Null
    $archive2 = Join-Path $dist2 'selftest-artifact.tar.gz'
    $ok = 0
    if ((Test-Path -LiteralPath $archive) -and (Test-Path -LiteralPath $archive2)) {
        $h1 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        $h2 = (Get-FileHash -LiteralPath $archive2 -Algorithm SHA256).Hash
        if ($h1 -eq $h2) { $ok = 1 }
    }
    Assert-Count -Case 'release: the same commit builds the same bytes' -Expected 1 -Actual $ok

    # --- 5. ...and a different platform builds the same bytes too ------------------------------
    # The case above proves determinism within one shell, which is the easy half. `* text=auto`
    # pins a file's content but not its line ending, and git archive then converts using the
    # BUILDER's platform -- CRLF on Windows, LF on POSIX. Five paths matched nothing more specific
    # until v1.15.7, so one tag produced two archives: 282,144 bytes here, 281,685 there, differing
    # in exactly those five entries and identical once CR was stripped.
    #
    # Two operating systems cannot be compared inside one shell, but the property that makes them
    # agree can be: every text file the artifact carries must have an explicit eol, because an
    # explicit eol is the only thing git archive resolves without asking the platform.
    # `attr/text=auto` means unpinned; `i/-text` means binary, which has no endings to convert.
    $unpinned = @()
    if ($entries.Count -gt 0) {
        foreach ($line in (& git -C $repoRoot ls-files --eol)) {
            $parts = $line -split "`t", 2
            if ($parts.Count -lt 2) { continue }
            $attrs = $parts[0]
            $path = $parts[1]
            if (-not $entrySet.ContainsKey($path)) { continue }
            if ($attrs -match 'i/-text' -or $attrs -match 'eol=') { continue }
            $unpinned += $path
        }
    }
    foreach ($p in $unpinned) { Write-Output ("      follows the platform: {0}" -f $p) }
    Assert-Count -Case 'release: no artifact file inherits the builder line endings' -Expected 0 -Actual $unpinned.Count

    # --- 6. The release workflow ---------------------------------------------------------------
    # The workflow is the one file here that can act on the outside world: it holds contents: write
    # and publishes. Nothing downstream re-reads it, so its safety properties are asserted from its
    # text.
    $wf = Join-Path $repoRoot '.github/workflows/release.yml'
    $man = Join-Path $repoRoot 'scripts/lib/blueprint-manifest.json'
    $wfLines = @()
    if (Test-Path -LiteralPath $wf) { $wfLines = @(Get-Content -LiteralPath $wf) }
    $wfText = ($wfLines -join "`n")
    $manText = ''
    if (Test-Path -LiteralPath $man) { $manText = (Get-Content -LiteralPath $man -Raw) }

    # A release workflow that reaches an adopting project tries to release THEIR repository from
    # THEIR tags. .github/workflows is portable, so only the declaration keeps this file home.
    $ok = 0
    if (Test-Path -LiteralPath $wf) { $ok++ }
    if ($manText -match '"\.github/workflows/release\.yml"') { $ok++ }
    if ($manText -match '(?s)"sourceOnly"\s*:\s*\[[^\]]*\.github/workflows/release\.yml') { $ok++ }
    Assert-Count -Case 'release: the workflow exists and is declared source-only' -Expected 3 -Actual $ok

    # Publishing must be reachable only by naming a version, never by pushing code. A branch push
    # that could publish would make every merge a release.
    $ok = 0
    if ($wfLines -match "^\s*tags: \['v\*'\]") { $ok++ }
    if (-not ($wfLines -match '^\s*branches:')) { $ok++ }
    if (-not ($wfLines -match '^\s*pull_request:')) { $ok++ }
    if ($wfText.Contains('v[0-9]+\.[0-9]+\.[0-9]+')) { $ok++ }
    Assert-Count -Case 'release: the workflow publishes only from a version tag' -Expected 4 -Actual $ok

    # contents: write is the least GitHub offers for creating a release. Read-only at the top means
    # a step added later cannot quietly inherit write, and no other scope may appear at all.
    $ok = 0
    if (($wfLines -match '^permissions:') -and ($wfLines -match '^\s*contents: read')) { $ok++ }
    if ($wfLines -match '^\s*contents: write') { $ok++ }
    if (-not ($wfLines -match '^\s*(actions|packages|id-token|deployments|issues|pull-requests|security-events): ')) { $ok++ }
    Assert-Count -Case 'release: the workflow asks for no scope beyond contents' -Expected 3 -Actual $ok

    # What it builds, what it proves, and what it uploads. A release whose checksum nobody verified
    # is a checksum nobody can trust, and a remote pipe is what this repository's own hook refuses.
    $ok = 0
    if ($wfText.Contains('build-artifact.sh --ref')) { $ok++ }
    if ($wfText.Contains('sha256sum -c')) { $ok++ }
    if ($wfText.Contains('forgeos-$VERSION.tar.gz')) { $ok++ }
    if ($wfText.Contains('forgeos-$VERSION.tar.gz.sha256') -or $wfText.Contains('$archive.sha256')) { $ok++ }
    if (-not ($wfText -match '(curl|wget|iwr|Invoke-WebRequest)[^|]*\|[^|]*(sh|bash|iex)')) { $ok++ }
    $usesAll = @($wfLines | Where-Object { $_ -match '^\s*- uses: ' }).Count
    $usesOfficial = @($wfLines | Where-Object { $_ -match '^\s*- uses: actions/' }).Count
    if ($usesAll -eq $usesOfficial) { $ok++ }
    Assert-Count -Case 'release: the workflow builds from the ref, verifies, and uploads the artifact' -Expected 6 -Actual $ok
}
finally {
    if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe }
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse }
}

Write-Output ''
Write-Output ("Total: {0}   Passed: {1}   Failed: {2}" -f $script:total, ($script:total - $script:failed), $script:failed)
if ($script:failed -gt 0) {
    Write-Output ''
    Write-Output 'Failed cases:'
    $script:failedCases | ForEach-Object { Write-Output $_ }
    exit 1
}
Write-Output 'Release self-test passed.'
exit 0
