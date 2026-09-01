#requires -Version 5.1
<#
.SYNOPSIS
    Audits the public launch surface of THIS repository.

.DESCRIPTION
    Windows counterpart of check-public-surface.sh, case for case and message for message.

    Every other claim in this repository has a check behind it. The public page did not, and it
    rotted exactly as an unchecked claim does: at v1.15.1 the README still announced 1.13.4 and
    still described 132 policy controls. The file a stranger judges the project by was the least
    verified file in it. This check closes that hole.

    Advisory in v1.15.2, by deliberate sequence: the drift it reports is real and predates it, and
    a check introduced red would either block the branch or invite someone to soften it. It prints
    every finding and exits 0. -FailOnDrift turns findings into exit 1, which is how it will run
    once the public surface is written.

    It never fails the audit closed: only a missing manifest or an unreadable version file -- a
    tooling failure that makes the audit impossible -- exits 1, the same rule check-context-budget
    follows.

    SCOPE: the blueprint's own public surface, never an adopting project's. The required files here
    are ForgeOS's launch contract, not a product's; running them against someone else's repository
    would report our obligations as their defects. The check reads blueprint.version's role and
    reports "not applicable" in an adopted project.

    No network. No GitHub API. No gh. Nothing is written.

.PARAMETER FailOnDrift
    Exit 1 when drift is found, instead of reporting it and exiting 0.
#>
[CmdletBinding()]
param(
    [switch]$FailOnDrift,
    # A run log from check-all: every check has already printed the numbers this page claims, so
    # they are read from there rather than re-derived. Absent when the audit runs standalone, and
    # the affected claims then report UNCHECKED with the reason, exactly as before.
    [string]$Measured
)

$ErrorActionPreference = 'Continue'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$manifestPath = Join-Path $repoRoot 'scripts/lib/blueprint-manifest.json'
$versionPath = Join-Path $repoRoot 'blueprint.version'

Write-Output 'Public launch surface'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Error "Manifest not found: $manifestPath" -ErrorAction Continue; exit 1
}
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    Write-Error "Version file not found: $versionPath" -ErrorAction Continue; exit 1
}

# -Encoding UTF8 is not optional: PowerShell 5.1 reads a BOM-less file as CP1252 otherwise, and
# both files carry non-ASCII prose (v1.12.2).
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ps = $manifest.policy.publicSurface
if (-not $ps -or -not $ps.claimFile -or @($ps.required).Count -eq 0) {
    Write-Error "Cannot read policy.publicSurface from the manifest: $manifestPath" -ErrorAction Continue
    exit 1
}
$required = @($ps.required)
$expected = @($ps.expected)
$sections = @($ps.sections)
$claimFile = $ps.claimFile

$versionText = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8
$roleMatch = [regex]::Match($versionText, '"role"[ \t]*:[ \t]*"([^"]+)"')
$verMatch = [regex]::Match($versionText, '"version"[ \t]*:[ \t]*"([^"]+)"')
if (-not $verMatch.Success) {
    Write-Error "Could not read the version from $versionPath" -ErrorAction Continue; exit 1
}
$role = if ($roleMatch.Success) { $roleMatch.Groups[1].Value } else { 'unknown' }
$bpVersion = $verMatch.Groups[1].Value

if ($role -ne 'source') {
    Write-Output ("  role      {0} -- this audit belongs to the blueprint, not to a project that adopted it" -f $role)
    Write-Output 'Public surface NOT APPLICABLE  (an adopted project publishes its own surface, on its own terms)'
    exit 0
}

Write-Output ("  audits    the blueprint source repository (blueprint.version role: source, v{0})" -f $bpVersion)

$script:drift = 0
function Write-Row { param([string]$Label, [string]$Message) Write-Output ("  {0,-9} {1}" -f $Label, $Message) }
function Write-Note { param([string]$Label, [string]$Message) $script:drift++; Write-Row $Label $Message }

# --- A. Files the launch contract requires ------------------------------------------------------
Write-Output ''
Write-Output '  Required now'
foreach ($f in $required) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $f) -PathType Leaf) { Write-Row 'ok' $f }
    else { Write-Note 'MISSING' "$f  -- required by the public preview contract" }
}

Write-Output ''
Write-Output '  Required before the repository goes public'
foreach ($f in $expected) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $f) -PathType Leaf) { Write-Row 'ok' $f }
    else { Write-Note 'MISSING' $f }
}

# --- B and C. What the public page claims -------------------------------------------------------
#
# Parsing prose is where a check like this earns its keep or becomes a nuisance. The rule followed
# here: extract only claims written in a shape the repository itself controls, and when a claim is
# not found in that shape, say UNCHECKED and why. A claim reported as passing because the parser
# missed it is worse than no parser at all.
Write-Output ''
Write-Output '  Public claims'
$claimPath = Join-Path $repoRoot $claimFile
if (-not (Test-Path -LiteralPath $claimPath -PathType Leaf)) {
    Write-Note 'MISSING' "$claimFile -- no public page to audit"
} else {
    $claimText = Get-Content -LiteralPath $claimPath -Raw -Encoding UTF8

    # [ \t] and not \s: in .NET \s matches a newline, so a broad pattern runs past its own line
    # and captures the next one (v1.14.2). The two halves must agree, so both write it out.
    $m = [regex]::Match($claimText, 'Current version:[ \t]*\*\*`?([0-9]+\.[0-9]+\.[0-9]+)`?\*\*')
    if (-not $m.Success) {
        Write-Row 'UNCHECKED' "version claim -- no 'Current version: **x.y.z**' line in $claimFile"
    } elseif ($m.Groups[1].Value -eq $bpVersion) {
        Write-Row 'ok' ("version claim {0} matches blueprint.version" -f $m.Groups[1].Value)
    } else {
        Write-Note 'DRIFT' ("{0} says version {1}; blueprint.version says {2}" -f $claimFile, $m.Groups[1].Value, $bpVersion)
    }

    # Check-all's own row counts, read from check-all.sh -- a stable local file, no run required.
    # placeholders is declared twice (gating under --strict, informational by default); the default
    # run is what the page describes, so a name declared both ways counts as informational.
    $gatingN = 0; $infoN = 0
    $caPath = Join-Path $repoRoot 'scripts/validation/check-all.sh'
    if (Test-Path -LiteralPath $caPath -PathType Leaf) {
        $caText = Get-Content -LiteralPath $caPath -Raw -Encoding UTF8
        $rows = @{}
        foreach ($rm in [regex]::Matches($caText, "(?m)^[ \t]*run_check +'([a-z-]+)' +'[^']+' +([01])")) {
            $n = $rm.Groups[1].Value
            $g = $rm.Groups[2].Value
            if ($rows.ContainsKey($n)) { if ($rows[$n] -ne $g) { $rows[$n] = '0' } }
            else { $rows[$n] = $g }
        }
        foreach ($k in $rows.Keys) { if ($rows[$k] -eq '1') { $gatingN++ } else { $infoN++ } }
    }

    # Number words, because the page is written for people. An unmapped word is UNCHECKED, never a
    # pass: a reworded sentence must not read as agreement.
    $words = @{ one = 1; two = 2; three = 3; four = 4; five = 5; six = 6; seven = 7; eight = 8;
                nine = 9; ten = 10; eleven = 11; twelve = 12 }
    function ConvertTo-Number {
        param([string]$Word)
        if (-not $Word) { return $null }
        $w = $Word.ToLower().Trim('*', ' ')
        if ($w -match '^[0-9]+$') { return [int]$w }
        if ($words.ContainsKey($w)) { return [int]$words[$w] }
        return $null
    }

    $cm = [regex]::Match($claimText, '\*\*([A-Za-z0-9]+) gating checks and ([A-Za-z0-9]+) informational reports\*\*')
    if (-not $cm.Success) {
        Write-Row 'UNCHECKED' "check-count claim -- the 'N gating checks and M informational reports' sentence was not found"
    } else {
        $cg = ConvertTo-Number $cm.Groups[1].Value
        $ci = ConvertTo-Number $cm.Groups[2].Value
        if ($null -eq $cg -or $null -eq $ci) {
            Write-Row 'UNCHECKED' 'check-count claim -- the counts are not written as numbers this check can read'
        } else {
            if ($cg -eq $gatingN) { Write-Row 'ok' ("gating check claim {0} matches check-all" -f $cg) }
            else { Write-Note 'DRIFT' ("{0} claims {1} gating checks; check-all declares {2}" -f $claimFile, $cg, $gatingN) }
            if ($ci -eq $infoN) { Write-Row 'ok' ("informational claim {0} matches check-all" -f $ci) }
            else { Write-Note 'DRIFT' ("{0} claims {1} informational reports; check-all declares {2}" -f $claimFile, $ci, $infoN) }
        }
    }

    # CI jobs, counted from the workflow rather than from a run: no network, no gh, no invention.
    $wfPath = Join-Path $repoRoot '.github/workflows/validate.yml'
    if (Test-Path -LiteralPath $wfPath -PathType Leaf) {
        $jobsN = 0; $inJobs = $false
        foreach ($line in (Get-Content -LiteralPath $wfPath -Encoding UTF8)) {
            if ($line -match '^jobs:') { $inJobs = $true; continue }
            if ($inJobs -and $line -match '^  [a-z0-9_-]+:[ \t]*$') { $jobsN++ }
        }
        $jm = [regex]::Match($claimText, '\*\*CI\.\*\*[ \t]+([A-Za-z0-9]+) jobs')
        $cj = $null
        if ($jm.Success) { $cj = ConvertTo-Number $jm.Groups[1].Value }
        if ($null -eq $cj) {
            Write-Row 'UNCHECKED' 'CI job claim -- no readable "N jobs" statement on the public page'
        } elseif ($cj -eq $jobsN) {
            Write-Row 'ok' ("CI job claim {0} matches the workflow" -f $cj)
        } else {
            Write-Note 'DRIFT' ("{0} claims {1} CI jobs; the workflow declares {2}" -f $claimFile, $cj, $jobsN)
        }
    }

    # Numbers that exist only at run time. Re-deriving them here would duplicate a gating check,
    # and running the self-test from inside a check the self-test itself invokes would recurse. So
    # they are read from check-all's run log when there is one, and reported UNCHECKED with the
    # reason when there is not -- never passed silently.
    function Test-MeasuredClaim {
        param([string]$Label, [string]$Claimed, [string]$MeasuredValue)
        if (-not $MeasuredValue) {
            Write-Row 'UNCHECKED' "$Label -- not measured in this run (no -Measured log)"
        } elseif (-not $Claimed) {
            Write-Row 'UNCHECKED' "$Label -- the page states no number this check can read"
        } elseif ($Claimed -eq $MeasuredValue) {
            Write-Row 'ok' "$Label claim $Claimed matches what the tools reported"
        } else {
            Write-Note 'DRIFT' "$claimFile claims $Label $Claimed; the tools reported $MeasuredValue"
        }
    }

    $mSelftest = ''; $mPolicy = ''; $mRefs = ''; $mFiles = ''; $mBroken = ''; $mUnportable = ''
    if ($Measured -and (Test-Path -LiteralPath $Measured)) {
        $logText = Get-Content -LiteralPath $Measured -Raw -Encoding UTF8
        $mm = [regex]::Match($logText, '(?m)^Total: +([0-9]+) +Passed:')
        if ($mm.Success) { $mSelftest = $mm.Groups[1].Value }
        $mm = [regex]::Match($logText, 'Policy check passed +\(([0-9]+) control')
        if ($mm.Success) { $mPolicy = $mm.Groups[1].Value }
        $mm = [regex]::Match($logText, 'Link check passed +\(([0-9]+) reference\(s\) checked across ([0-9]+) file\(s\), ([0-9]+) broken, ([0-9]+) unportable')
        if ($mm.Success) {
            $mRefs = $mm.Groups[1].Value; $mFiles = $mm.Groups[2].Value
            $mBroken = $mm.Groups[3].Value; $mUnportable = $mm.Groups[4].Value
        }
    }

    $cSelftest = ''; $cPolicy = ''; $cRefs = ''; $cFiles = ''; $cBroken = ''; $cUnportable = ''
    $cm2 = [regex]::Match($claimText, '([0-9]+) cases per shell')
    if ($cm2.Success) { $cSelftest = $cm2.Groups[1].Value }
    $cm2 = [regex]::Match($claimText, '\| ([0-9]+) policy controls \|')
    if ($cm2.Success) { $cPolicy = $cm2.Groups[1].Value }
    $cm2 = [regex]::Match($claimText, '([0-9]+) references across ([0-9]+) files, ([0-9]+) broken, ([0-9]+) unportable')
    if ($cm2.Success) {
        $cRefs = $cm2.Groups[1].Value; $cFiles = $cm2.Groups[2].Value
        $cBroken = $cm2.Groups[3].Value; $cUnportable = $cm2.Groups[4].Value
    }

    Test-MeasuredClaim 'self-test case count' $cSelftest   $mSelftest
    Test-MeasuredClaim 'policy control count' $cPolicy     $mPolicy
    Test-MeasuredClaim 'link reference count' $cRefs       $mRefs
    Test-MeasuredClaim 'link file count'      $cFiles      $mFiles
    Test-MeasuredClaim 'broken link count'    $cBroken     $mBroken
    Test-MeasuredClaim 'unportable count'     $cUnportable $mUnportable

    # --- D. The two tables ----------------------------------------------------------------------
    Write-Output ''
    Write-Output '  Proof tables'
    foreach ($sec in $sections) {
        if ($claimText.Contains($sec)) { Write-Row 'ok' "section present: $sec" }
        else { Write-Note 'MISSING' "section: $sec" }
    }

    # One staleness rule, and only one that can be decided mechanically: a claim about what this
    # repository contains, which this repository can contradict. The page says memory holds no
    # lesson; the moment a lesson exists, the page is wrong and says so with confidence.
    $lessonDir = Join-Path $repoRoot '.ai/memory/lessons'
    $lessons = 0
    if (Test-Path -LiteralPath $lessonDir -PathType Container) {
        $lessons = @(Get-ChildItem -LiteralPath $lessonDir -Filter '*.md' -File |
                     Where-Object { $_.Name -ne 'README.md' }).Count
    }
    if (($claimText -match 'carries no handoff, lesson, or incident') -and $lessons -gt 0) {
        Write-Note 'DRIFT' ("{0} says memory carries no lesson; {1} lesson(s) are on record" -f $claimFile, $lessons)
    }
}

# --- E. None of this may travel -----------------------------------------------------------------
#
# Every file above is ForgeOS's, not a blueprint's. An adopting project that inherited the security
# policy would publish our disclosure address as theirs. They stay home today because no list names
# them -- and M-18 established what safety by omission is worth. This says it out loud each run.
Write-Output ''
Write-Output '  Distribution safety'
$dist = $manifest.distribution
$portDirs = @($dist.portable)
$portFiles = @($dist.portableFiles)
$seedFiles = @($dist.seedFiles)
# seedTemplates was NOT consulted here until M-23.0a. A key there is only a REDIRECT -- it changes
# which file a seed is copied FROM, and sync seeds nothing that is not also in seedFiles -- so a
# seedTemplates-only entry cannot travel today and this is a superset guard, not a closed hole.
# It is worth reading anyway: the two lists are edited together, and a check that watched only one
# of them would go quiet the moment the seed loop learned to iterate the other.
$seedTmpl = @()
if ($dist.PSObject.Properties.Name -contains 'seedTemplates') {
    $seedTmpl = @($dist.seedTemplates.PSObject.Properties.Name)
}
$srcOnly = @()
if ($dist.PSObject.Properties.Name -contains 'sourceOnly') { $srcOnly = @($dist.sourceOnly) }

function Get-TravelReason {
    param([string]$Path)
    foreach ($q in $portFiles) { if ($Path -eq $q) { return 'listed as a portable file' } }
    foreach ($q in $seedFiles) { if ($Path -eq $q) { return 'listed as a seed file' } }
    foreach ($q in $seedTmpl)  { if ($Path -eq $q) { return 'seeded from a template' } }
    foreach ($q in $portDirs) { if ($Path.StartsWith("$q/")) { return "inside the portable directory $q" } }
    return ''
}

function Test-DeclaredSourceOnly {
    param([string]$Path)
    foreach ($q in $srcOnly) {
        if (-not $q) { continue }
        if ($Path -eq $q -or $Path.StartsWith("$q/")) { return $true }
    }
    # A seedTemplates redirect is the same promise by a different route, and check-policy REFUSES
    # the other one: a source-only path may not also be a seed file, because "never copied" and
    # "copied when absent" cannot both be true of one path. When an adopter must have a file at this
    # path -- docs/roadmap.md, or forgeos next is blind -- the redirect is what keeps OUR copy home:
    # the seed is filled from templates/, so this repository's content is never the thing that
    # travels. That is a written declaration, not an accident, which is all this check insists on.
    foreach ($q in $seedTmpl) {
        if ($Path -eq $q) { return $true }
    }
    return $false
}

$travellers = 0
foreach ($f in ($required + $expected)) {
    $reason = Get-TravelReason -Path $f
    if ($reason) {
        # README.md and the guides are the project's own and are handled by the distribution split;
        # only a PUBLIC-SURFACE file that reaches an adopter is a finding.
        # docs/roadmap.md is seeded from templates/roadmap-template.md, never from the copy below
        # it. forgeos next reads a roadmap to recommend anything, so an adopter without one is
        # blind -- but THIS repository's roadmap is a public trust file and must not travel. A
        # neutral template settles both: the path is filled, the content is not ours.
        if ($f -eq 'README.md' -or $f -eq 'LICENSE' -or $f -eq 'docs/adoption.md' -or
            $f -eq 'docs/roadmap.md' -or $f -like 'scripts/*') {
            Write-Row 'ok' "$f is distributed by design ($reason)"
        } else {
            Write-Note 'LEAK' "$f would reach an adopting project -- $reason"
            $travellers++
        }
    }
}

# Absence from the portable lists is not a guarantee; it is an accident waiting to be undone by
# whoever next adds a file to portableFiles. Every trust file must be DECLARED source-only, so
# check-policy fails the moment the declaration is contradicted. This is the M-18 rule applied to
# the public surface: safety by omission is worth nothing until it is written down.
$undeclared = 0
foreach ($f in $expected) {
    if (-not (Test-DeclaredSourceOnly -Path $f)) {
        Write-Note 'UNDECLARED' "$f is not in distribution.sourceOnly -- it stays home by accident, not by rule"
        $undeclared++
    }
}

if ($travellers -eq 0 -and $undeclared -eq 0) {
    Write-Row 'ok' 'every public trust file is declared source-only, and none travels except by design above'
}

# --- Verdict ------------------------------------------------------------------------------------
Write-Output ''
if ($script:drift -eq 0) {
    Write-Output 'PUBLIC SURFACE OK  (every public claim matches what the repository reports)'
    exit 0
}

Write-Output ("PUBLIC SURFACE DRIFT  ({0} finding(s))" -f $script:drift)
if ($FailOnDrift) {
    Write-Output 'Reported as a failure because -FailOnDrift was passed.'
    exit 1
}
Write-Output 'Advisory for now: the findings above predate this check and are the work of the public'
Write-Output 'surface slices. Nothing here is hidden, softened, or excused -- and nothing is gated on it'
Write-Output 'until the surface is written. Then this check runs with -FailOnDrift and stays green.'
exit 0
