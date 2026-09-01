<#
.SYNOPSIS
    Reports where this project is, from its own files. Windows counterpart of project-status.sh.

.DESCRIPTION
    READ-ONLY BY CONSTRUCTION. It creates, modifies and deletes nothing; it runs no git command that
    changes state; it touches the network never. The contract and the reasoning are in README.md
    beside this file, and the self-test asserts the three safety flags are false.

    The one rule that shapes everything here: a field with no source is reported as missing, never
    guessed. A string becomes "unknown", a number becomes $null -- because zero tasks and no task
    directory are different facts -- and the source is named in missingSources.

.PARAMETER Json
    Emit JSON on stdout and nothing else. Any human commentary goes to stderr, so a caller piping
    stdout into a parser never has to strip a banner first.

.NOTES
    Exit 0 reported (including undefined, blocked, or missing sources); 1 the repository is
    unreadable.
#>
# -Section exists so the wrapper can ask for a subset instead of re-parsing this command's output.
# One emitter, one place: a consumer that had to slice JSON back apart would be a second grammar for
# the same document, and this repository has paid for that mistake before.
param(
    [switch]$Json,
    [ValidateSet('all', 'next')]
    [string]$Section = 'all'
)

Set-StrictMode -Version 2.0
# -Encoding UTF8 on every read and a UTF-8 console are both load-bearing on Windows PowerShell 5.1:
# without them a BOM-less UTF-8 file is read as CP1252 and an em-dash prints as mojibake.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path -LiteralPath $repoRoot)) {
    [Console]::Error.WriteLine("Cannot read the repository root: $repoRoot")
    exit 1
}

$missing = New-Object System.Collections.Generic.List[string]

# Windows PowerShell 5.1 turns a native command's stderr into an ErrorRecord, and with
# $ErrorActionPreference = 'Stop' that becomes terminating. `git` outside a repository writes
# "not a git repository" to stderr, so the reporter would THROW exactly where it is supposed to
# report the source as missing. Every external call goes through here instead.
function Invoke-External {
    param([string]$Exe, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $out = & $Exe @Arguments 2>$null
        return @($out | Where-Object { $null -ne $_ -and "$_" -ne '' })
    } catch {
        return @()
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Get-FirstMatch {
    param([string]$Path, [string]$Pattern, [int]$Group = 1)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match $Pattern) { return $Matches[$Group] }
    }
    return $null
}

# --- git, read-only -------------------------------------------------------------------------
$gitOk = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'rev-parse', '--git-dir')).Count -gt 0

$branch = 'unknown'; $commit = 'unknown'; $repoName = 'unknown'
$tagCount = $null; $latestTag = $null
if ($gitOk) {
    $b = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'rev-parse', '--abbrev-ref', 'HEAD'))
    if ($b.Count -gt 0) { $branch = $b[0] }
    $c = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD'))
    if ($c.Count -gt 0) { $commit = $c[0] }
    # A remote URL is only a good name source when it looks like one. Stripping to the last path
    # segment turned a local remote of "." into the repository name "." -- a value that is not
    # wrong so much as useless. Take the name from a host-style URL; otherwise use the directory,
    # which is always meaningful; and say "unknown" only when neither yields a usable word.
    $remote = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'remote', 'get-url', 'origin'))
    $repoName = ''
    if ($remote.Count -gt 0 -and $remote[0] -match '^([a-z]+://|[^/]+@[^/]+:)') {
        $repoName = ($remote[0] -replace '/$', '' -replace '\.git$', '') -replace '.*[/:]', ''
    }
    if ($repoName -in @('', '.', '..') -or $repoName -notmatch '[A-Za-z0-9]') { $repoName = '' }
    if (-not $repoName) {
        $repoName = Split-Path -Leaf $repoRoot
        if ($repoName -in @('', '.', '..', '/', '\')) { $repoName = 'unknown' }
    }
    $tags = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'tag'))
    $tagCount = $tags.Count
    $sorted = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'tag', '--sort=-v:refname'))
    if ($sorted.Count -gt 0) { $latestTag = $sorted[0] }
} else {
    $missing.Add('git metadata')
    $repoName = Split-Path -Leaf $repoRoot
}

# --- blueprint.version ----------------------------------------------------------------------
$bpVersion = 'unknown'; $bpRole = 'unknown'
$bpPath = Join-Path $repoRoot 'blueprint.version'
if (Test-Path -LiteralPath $bpPath) {
    $v = Get-FirstMatch -Path $bpPath -Pattern '"version"\s*:\s*"([^"]+)"'
    $r = Get-FirstMatch -Path $bpPath -Pattern '"role"\s*:\s*"([^"]+)"'
    if ($v) { $bpVersion = $v }
    if ($r) { $bpRole = $r }
} else {
    $missing.Add('blueprint.version')
}

# --- the state ledger -----------------------------------------------------------------------
# A ledger bullet wraps across indented continuation lines; reading only the first line cuts the
# sentence mid-clause. Take the bullet and fold its continuations into one line.
$ledger = Join-Path $repoRoot '.ai\context\current-state.md'
$ledgerPresent = $false; $sNow = $null; $sNext = $null; $sBlocked = $null
function Get-Bullet {
    param([string[]]$Lines, [string]$Label)
    $found = $false; $buf = ''
    foreach ($line in $Lines) {
        if (-not $found -and $line.StartsWith("- $Label" + ':')) {
            $found = $true
            $buf = ($line -replace '^- [^:]*:\s*', '')
            continue
        }
        if ($found) {
            if ($line -match '^  [^ \-]') { $buf = $buf + ' ' + $line.Trim(); continue }
            break
        }
    }
    if ($found -and $buf) { return $buf }
    return $null
}
if (Test-Path -LiteralPath $ledger) {
    $ledgerPresent = $true
    $ledgerLines = @(Get-Content -LiteralPath $ledger -Encoding UTF8 -ErrorAction SilentlyContinue)
    $sNow     = Get-Bullet -Lines $ledgerLines -Label 'Now'
    $sNext    = Get-Bullet -Lines $ledgerLines -Label 'Next'
    $sBlocked = Get-Bullet -Lines $ledgerLines -Label 'Blocked by'
} else {
    $missing.Add('.ai/context/current-state.md')
}

# --- work in flight -------------------------------------------------------------------------
function Measure-Md {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    return @(Get-ChildItem -LiteralPath $Dir -File -Filter '*.md' -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ne 'README.md' }).Count
}
$tInbox  = Measure-Md (Join-Path $repoRoot '.ai\tasks\inbox')
$tActive = Measure-Md (Join-Path $repoRoot '.ai\tasks\active')
$tDone   = Measure-Md (Join-Path $repoRoot '.ai\tasks\completed')
$pActive = Measure-Md (Join-Path $repoRoot '.ai\plans\active')
if ($null -eq $tActive) { $missing.Add('.ai/tasks/') }
if ($null -eq $pActive) { $missing.Add('.ai/plans/') }

# --- the open-questions register --------------------------------------------------------------
$questions = Join-Path $repoRoot '.ai\memory\open-questions.md'
$qOpen = $null; $qAnswered = $null
if (Test-Path -LiteralPath $questions) {
    $qOpen = 0; $qAnswered = 0
    foreach ($line in (Get-Content -LiteralPath $questions -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^\|\s*[0-9]{3}\s*\|') {
            $cols = $line -split '\|'
            if ($cols.Count -gt 5) {
                $st = $cols[5].Trim()
                if ($st -eq 'open') { $qOpen++ }
                elseif ($st -eq 'answered') { $qAnswered++ }
            }
        }
    }
} else {
    $missing.Add('.ai/memory/open-questions.md')
}

# --- the validation surface --------------------------------------------------------------------
# The same grammar check-public-surface uses, deliberately -- one place decides what a row is.
# `placeholders` is declared inside the --strict if/else and is indented, so leading whitespace is
# allowed; a name declared both ways counts as informational, because the default run is what a
# reader sees.
$checkAll = Join-Path $repoRoot 'scripts\validation\check-all.sh'
$checkAllPresent = $false; $gating = $null; $informational = $null
if (Test-Path -LiteralPath $checkAll) {
    $checkAllPresent = $true
    $text = Get-Content -LiteralPath $checkAll -Raw -Encoding UTF8
    $names = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($m in [regex]::Matches($text, "(?m)^\s*run_check\s+'([a-z-]+)'")) {
        [void]$names.Add($m.Groups[1].Value)
    }
    $gating = 0; $informational = 0
    foreach ($n in $names) {
        $flags = @([regex]::Matches($text, "run_check\s+'$n'\s+'[^']+'\s+([01])") |
                   ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        if ($flags.Count -eq 1 -and $flags[0] -eq '1') { $gating++ } else { $informational++ }
    }
} else {
    $missing.Add('scripts/validation/check-all.sh')
}

# --- maturity, read from the decision that defines it -------------------------------------------
# Never computed here. The decision defines each track as criteria met over criteria declared, and
# an adopting project has no such record -- .ai/memory is project-owned and never synced -- so all
# three are $null there rather than inherited from this repository.
$decisionRel = 'docs/roadmap.md'
$decision = Join-Path $repoRoot ($decisionRel -replace '/', '\')
$mInstall = $null; $mPcc = $null; $mE2e = $null; $mSource = 'missing'
if (Test-Path -LiteralPath $decision) {
    $mSource = $decisionRel
    $dLines = @(Get-Content -LiteralPath $decision -Encoding UTF8 -ErrorAction SilentlyContinue)
    function Get-Pct {
        param([string[]]$Lines, [string]$Label)
        foreach ($line in $Lines) {
            if ($line.StartsWith("| $Label ") -and $line -match '~([0-9]+)%') { return [int]$Matches[1] }
        }
        return $null
    }
    $mInstall = Get-Pct -Lines $dLines -Label 'Installability'
    $mPcc     = Get-Pct -Lines $dLines -Label 'Project Command Center'
    $mE2e     = Get-Pct -Lines $dLines -Label 'Driving a real project end to end'
} else {
    $missing.Add($decisionRel)
}

# --- next phase, from the roadmap ----------------------------------------------------------------
$roadmap = Join-Path $repoRoot 'docs\roadmap.md'
$nextPhase = $null
if (Test-Path -LiteralPath $roadmap) {
    foreach ($line in (Get-Content -LiteralPath $roadmap -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^##\s+(M-[0-9]+.*)$') { $nextPhase = $Matches[1]; break }
    }
} else {
    $missing.Add('docs/roadmap.md')
}

# --- project state ---------------------------------------------------------------------------
# Order matters: undefined outranks blocked and active. A project that has not been defined cannot
# have meaningful work in flight, and saying so is more useful than reporting the work.
$blockingMarkers = $null
$placeholders = Join-Path $repoRoot 'scripts\validation\check-placeholders.ps1'
if (Test-Path -LiteralPath $placeholders) {
    $phOut = (Invoke-External -Exe 'powershell.exe' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $placeholders)) -join "`n"
    if ($phOut -match '\(blocking:\s*([0-9]+)\)') { $blockingMarkers = [int]$Matches[1] }
}

$projectState = 'ready'
if ($bpVersion -eq 'unknown' -or -not $gitOk) {
    $projectState = 'unknown'
} elseif ($null -ne $blockingMarkers -and $blockingMarkers -gt 0) {
    $projectState = 'undefined'
} elseif ($sBlocked -and $sBlocked -ne 'none') {
    $projectState = 'blocked'
} elseif (($null -ne $tActive -and $tActive -gt 0) -or ($null -ne $pActive -and $pActive -gt 0)) {
    $projectState = 'active'
}

# --- the project map ------------------------------------------------------------------------
# Ten sections, each answering the same three questions: does this surface exist, what was read,
# and how much is there. The state vocabulary is deliberately small -- present, partial, missing,
# unknown -- because a map that hedges in ten different ways is a map nobody can act on.
#
# "partial" means the documents exist and still carry TBD markers. That is a plainer measure than
# the one check-placeholders applies, and it is named plainly for that reason: unfilledDocuments,
# not "blocking". The gate's number is reported once, under requirements, and comes from the
# checker itself rather than from a fourth grammar invented here.
function Get-DocFiles {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    return @(Get-ChildItem -LiteralPath $Dir -File -Filter '*.md' -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)
}
function Measure-Unfilled {
    param([string]$Dir)
    $files = Get-DocFiles -Dir $Dir
    if ($null -eq $files) { return $null }
    $n = 0
    foreach ($f in $files) {
        $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($raw -and $raw -match 'TBD') { $n++ }
    }
    return $n
}
function Get-DocState {
    param($Count, $Unfilled)
    if ($null -eq $Count -or $Count -eq 0) { return 'missing' }
    if ($null -ne $Unfilled -and $Unfilled -gt 0) { return 'partial' }
    return 'present'
}
# PowerShell unwraps a single-element array to a scalar, and StrictMode then refuses .Count on it.
# Every consumer of Get-DocFiles re-wraps with @() for that reason.
function Measure-Docs { param([string]$Dir) $f = Get-DocFiles -Dir $Dir; if ($null -eq $f) { return $null } return @($f).Count }

$prodDir = Join-Path $repoRoot 'docs\product'
$archDir = Join-Path $repoRoot 'docs\architecture'
$domDir  = Join-Path $repoRoot 'docs\domains'
$decDir  = Join-Path $repoRoot '.ai\memory\decisions'

$prodN = Measure-Docs $prodDir; $prodU = Measure-Unfilled $prodDir
$archN = Measure-Docs $archDir; $archU = Measure-Unfilled $archDir
$domN  = Measure-Docs $domDir;  $domU  = Measure-Unfilled $domDir
$decN  = Measure-Docs $decDir
$decFiles = @(Get-DocFiles -Dir $decDir | Where-Object { $_ })
$decRecent = $null
if ($decFiles.Count -gt 0) { $decRecent = $decFiles[-1].Name }

# Migrations: only conventional locations, and null rather than 0 when none exists -- a project
# with no database is not a project with an empty migrations directory.
$migN = $null; $migDir = ''
foreach ($d in @('migrations', 'db\migrations', 'database\migrations', 'supabase\migrations', 'prisma\migrations')) {
    $full = Join-Path $repoRoot $d
    if (Test-Path -LiteralPath $full) {
        $migDir = ($d -replace '\\', '/')
        $migN = @(Get-ChildItem -LiteralPath $full -File -Recurse -ErrorAction SilentlyContinue).Count
        break
    }
}

$activeFiles = @(Get-DocFiles -Dir (Join-Path $repoRoot '.ai\tasks\active') | Where-Object { $_ })
$activeNames = @($activeFiles | ForEach-Object { $_.Name })
$doneFiles = @(Get-DocFiles -Dir (Join-Path $repoRoot '.ai\tasks\completed') | Where-Object { $_ })
$recentDone = $null
if ($doneFiles.Count -gt 0) { $recentDone = $doneFiles[-1].Name }
$nextSliceActive = ($null -ne $tActive -and $tActive -gt 0)

# Slice age. "Which slices are open and closed" was only half the criterion -- the other half is
# SINCE WHEN, and a name with no age cannot tell a week-old slice from a stalled one.
#
# Read from git and from nothing else. Filesystem mtime was considered and rejected: in a fresh
# clone it is the checkout time, so every task would report as brand new -- an answer to a different
# question than the one asked, which is exactly the invention this command refuses. When git cannot
# answer, the age is $null and ageSource says unknown.
#
# A shallow clone is treated as no answer at all. `git log` there walks only the fetched commits and
# happily returns the boundary commit for any path, which is how check-state-freshness once reported
# a stale ledger as fresh (1.15.1). A cheap rev-parse settles it before anything is measured.
$ageSource = 'unknown'
if ($gitOk) {
    $shallow = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'rev-parse', '--is-shallow-repository'))
    if ($shallow.Count -gt 0 -and "$($shallow[0])".Trim() -eq 'false') { $ageSource = 'git' }
}
$nowUtc = (Get-Date).ToUniversalTime()

function Get-DaysSince {
    param([string]$Stamp)
    if (-not $Stamp) { return $null }
    try { return [int][Math]::Floor(($nowUtc - ([datetimeoffset]::Parse($Stamp)).UtcDateTime).TotalDays) }
    catch { return $null }
}
function Get-AddedAge {
    param([string]$RelPath)
    if ($ageSource -ne 'git') { return $null }
    $out = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'log', '--diff-filter=A', '--format=%cI', '--', $RelPath))
    if ($out.Count -eq 0) { return $null }
    return Get-DaysSince -Stamp "$($out[-1])"
}
function Get-TouchedAge {
    param([string]$RelPath)
    if ($ageSource -ne 'git') { return $null }
    $out = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'log', '-1', '--format=%cI', '--', $RelPath))
    if ($out.Count -eq 0) { return $null }
    return Get-DaysSince -Stamp "$($out[0])"
}

# activeAge answers how long work has been open, so it is the OLDEST active task -- the one that has
# been waiting longest, not the one touched most recently. mostRecentCompletedAge answers how
# recently something was finished, so it is the last touch on the newest completed file: moving a
# task into completed/ is itself a commit against that path.
$tActiveAge = $null
foreach ($tn in $activeNames) {
    $a = Get-AddedAge -RelPath ".ai/tasks/active/$tn"
    if ($null -eq $a) { continue }
    if ($null -eq $tActiveAge -or $a -gt $tActiveAge) { $tActiveAge = $a }
}
$tDoneAge = $null
if ($recentDone) { $tDoneAge = Get-TouchedAge -RelPath ".ai/tasks/completed/$recentDone" }
# A source that produced no usable age for anything present is not a working source.
if ($ageSource -eq 'git' -and $null -eq $tActiveAge -and $null -eq $tDoneAge -and
    (@($activeNames).Count -gt 0 -or $recentDone)) {
    $ageSource = 'unknown'
}

# Governance: read, never touched. codeAuthorized and the window are facts about the project's own
# gate; this command reports them and has no path that could change either.
$govPath = Join-Path $repoRoot '.ai\context\governance.json'
$govState = 'missing'; $govAuthorized = $null; $govAllowed = $null; $govWindow = $null
if (Test-Path -LiteralPath $govPath) {
    $govState = 'present'
    try {
        $gov = Get-Content -LiteralPath $govPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $gov.codeAuthorized) { $govAuthorized = [bool]$gov.codeAuthorized }
        if ($null -ne $gov.implementationWindow) {
            if ($null -ne $gov.implementationWindow.active) { $govWindow = [bool]$gov.implementationWindow.active }
            $govAllowed = @($gov.implementationWindow.allowedPaths | Where-Object { $null -ne $_ }).Count
        }
    } catch { }
} else {
    $missing.Add('.ai/context/governance.json')
}

# The next capability that does not exist yet, read from the roadmap's own criteria table rather
# than decided here. First row still marked "not built" wins.
$nextCapability = $null
if (Test-Path -LiteralPath $roadmap) {
    foreach ($line in (Get-Content -LiteralPath $roadmap -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^\|\s*[0-9]+\s*\|.*\|\s*not built\s*\|') {
            $cols = $line -split '\|'
            if ($cols.Count -gt 2) { $nextCapability = $cols[2].Trim() }
            break
        }
    }
}

# --- the recommendation, the two drafts, and the generated prompt ------------------------------
# Derived from what was already read above, and none of it decides anything: the recommendation
# names a row the roadmap already carries, the governance draft is a suggestion a person applies,
# the validation plan is a list of commands nobody here has run, and the prompt is assembled from
# those three. No new source is opened for any of it.

# Choosing the next slice. "The first incomplete row" was a placeholder for this: it answered which
# row comes first in the table, not which one is smallest or whether it can actually be started.
#
# Every qualifying row is normalised once -- number, status, name, the rest of its cells, and the
# section that owns it -- and a table qualifies only when it carries a status column. A two-column
# criteria list has no status to read, and inferring one from the criterion's wording would be
# invention.
$recRows = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $roadmap) {
    $rowSection = $null
    foreach ($line in (Get-Content -LiteralPath $roadmap -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^##\s+(.*)$') { $rowSection = $Matches[1]; continue }
        if ($line -notmatch '^\|\s*[0-9]+\s*\|') { continue }
        $cols = $line -split '\|'
        if ($cols.Count -lt 6) { continue }
        # The verdict LEADS the cell and the rest is detail, so the match is anchored. Scanning the
        # whole cell read "**done** -- partial rows before unstarted ones" as partial: a row was
        # reclassified by a word in its own explanation, and the command then recommended a
        # criterion it had just been told was finished. -cmatch, not -match: awk compares
        # case-sensitively and the two shells have to agree on "Done" as well as on "done".
        $st = ($cols[$cols.Count - 2] -replace '\*', '').Trim()
        $s = 'unknown'
        if ($st -cmatch '^not built') { $s = 'not built' }
        elseif ($st -cmatch '^partial') { $s = 'partial' }
        elseif ($st -cmatch '^done') { $s = 'done' }
        $rest = ''
        for ($i = 3; $i -le $cols.Count - 2; $i++) { $rest = $rest + ' ' + $cols[$i] }
        $recRows.Add([pscustomobject]@{
            Number = $cols[1].Trim(); Status = $s; Name = $cols[2].Trim()
            Rest = $rest; Section = $rowSection
        })
    }
}
# The rows already complete, for the prerequisite test below, keyed by SECTION and number. Row
# numbers restart in every criteria table, so a global set of numbers let one phase's "#4 is done"
# satisfy another phase's "requires #4" -- a prerequisite marked met by a coincidence of numbering.
$recDoneKeys = @($recRows | Where-Object { $_.Status -eq 'done' } |
                 ForEach-Object { "$($_.Section)#$($_.Number)" })

# Two orderings decide "smallest", and both are read from the table rather than judged here:
# a partial row is less remaining work than an unstarted one, because part of it already exists; and
# within a status, the lower number comes first because that is the order the project declared.
#
# A prerequisite counts only when the row DECLARES it, as "requires #N". Absence of a declaration
# means no prerequisite -- a prerequisite this command inferred would be one nobody agreed to. A row
# whose declared prerequisite is unmet is skipped, and every skip is reported: silently dropping a
# row is how a recommendation starts lying about what it considered.
$recCapability = ''; $nextSection = $null
$recSelectedStatus = 'unknown'; $recSelectedNumber = ''
$recSkipped = New-Object System.Collections.Generic.List[string]
$recIncomplete = 0
$bestPartial = $null; $bestUnstarted = $null
foreach ($row in $recRows) {
    if ($row.Status -ne 'partial' -and $row.Status -ne 'not built') { continue }
    $recIncomplete++
    $unmet = @()
    foreach ($m in [regex]::Matches($row.Rest, 'requires #([0-9]+)')) {
        $req = $m.Groups[1].Value
        if ($recDoneKeys -notcontains "$($row.Section)#$req") { $unmet += ('#' + $req) }
    }
    if ($unmet.Count -gt 0) {
        $recSkipped.Add(("#{0} {1} -- declares requires {2}, which is not complete" -f $row.Number, $row.Name, ($unmet -join ', ')))
        continue
    }
    if ($row.Status -eq 'partial' -and $null -eq $bestPartial) { $bestPartial = $row }
    elseif ($row.Status -eq 'not built' -and $null -eq $bestUnstarted) { $bestUnstarted = $row }
}

$sel = $null
if ($null -ne $bestPartial) { $sel = $bestPartial; $recSelectedStatus = 'partial' }
elseif ($null -ne $bestUnstarted) { $sel = $bestUnstarted; $recSelectedStatus = 'not built' }
if ($null -ne $sel) {
    $recSelectedNumber = $sel.Number
    $recCapability = $sel.Name
    $nextSection = $sel.Section
}

# nextPhase was the FIRST phase heading, which stops being the next one the moment that phase is
# finished: a prompt would then be titled with a phase the roadmap itself calls complete. A phase is
# skipped only when it owns a status-bearing table and every row in it is done -- a phase whose
# criteria are prose has nothing to be complete by, so it is never skipped on a guess.
if ($recRows.Count -gt 0 -and (Test-Path -LiteralPath $roadmap)) {
    $withTable = @($recRows | ForEach-Object { $_.Section } | Sort-Object -Unique)
    $withIncomplete = @($recRows |
        Where-Object { $_.Status -eq 'partial' -or $_.Status -eq 'not built' } |
        ForEach-Object { $_.Section } | Sort-Object -Unique)
    $completeSections = @($withTable | Where-Object { $withIncomplete -notcontains $_ })
    foreach ($line in (Get-Content -LiteralPath $roadmap -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -notmatch '^##\s+(M-[0-9]+.*)$') { continue }
        $h = $Matches[1]
        if ($completeSections -notcontains $h) { $nextPhase = $h; break }
    }
}

$recSource = 'missing'
if (Test-Path -LiteralPath $roadmap) { $recSource = 'docs/roadmap.md' }
$recIneligible = $false
if ($recCapability) {
    if ($recSelectedStatus -eq 'partial') {
        $recReason = "the smallest eligible incomplete criterion, #$recSelectedNumber" + ': a partial row, which is less remaining work than an unstarted one'
    } else {
        $recReason = "the smallest eligible incomplete criterion, #$recSelectedNumber" + ': no partial row was eligible, so the lowest-numbered unstarted one'
    }
    if ($ledgerPresent -and $govState -eq 'present') { $recConfidence = 'high' } else { $recConfidence = 'medium' }
} elseif ($recIncomplete -gt 0) {
    # Rows remain, and every one of them was skipped. That is a blocked recommendation, not an absent
    # one, and the reasons are already in $recSkipped.
    $recCapability = 'unknown'
    $recReason = "every incomplete criterion declares a prerequisite that is not complete: $recIncomplete considered, $recIncomplete skipped"
    $recConfidence = 'unknown'
    $recIneligible = $true
} elseif ($recRows.Count -gt 0) {
    $recCapability = 'unknown'
    $recReason = 'every criterion in the roadmap criteria table is complete, so there is no incomplete row to name'
    $recConfidence = 'unknown'
} else {
    $recCapability = 'unknown'
    $recReason = 'no roadmap criteria table with a status column could be read, so no capability is named'
    $recConfidence = 'unknown'
}

# A blocker is a fact read from a file, never a judgement. Each one names where it came from.
$recBlockers = New-Object System.Collections.Generic.List[string]
if ($sBlocked -and $sBlocked -ne 'none') {
    $recBlockers.Add("the state ledger names a blocker: $sBlocked")
}
if ($govAuthorized -eq $false) {
    $recBlockers.Add('code writes are not authorized in .ai/context/governance.json')
}
if ($null -ne $tActive -and $tActive -gt 0) {
    $recBlockers.Add("a task is already active: " + ((@($activeNames) -join ' ').Trim()))
}
# Every skipped row becomes a blocker too when nothing was left to select. A recommendation that
# says "unknown" without saying what it rejected is a recommendation nobody can check.
if ($recIneligible) {
    foreach ($sk in $recSkipped) { $recBlockers.Add($sk) }
}
$recBlocked = ($recBlockers.Count -gt 0)

# The governance draft. One declared rule, for the one surface this repository actually has; a
# capability from a section with no rule gets an empty draft and says so. Guessing a path list for
# a surface that does not exist yet is exactly the invention this command refuses. Every drafted
# path is also required to exist, so a draft can never name a file the project does not have.
$gdPaths = New-Object System.Collections.Generic.List[string]
$gdRationale = New-Object System.Collections.Generic.List[string]
function Add-DraftPath {
    param([string]$Path, [string]$Why)
    $probe = Join-Path $repoRoot (($Path.TrimEnd('/')) -replace '/', '\')
    if (-not (Test-Path -LiteralPath $probe)) { return }
    $gdPaths.Add($Path)
    $gdRationale.Add("$Path -- $Why")
}
if ($nextSection -and $nextSection -match '(?i)command cent(er|re)') {
    Add-DraftPath 'scripts/command/'           'the surface the capability extends'
    Add-DraftPath 'scripts/hooks/selftest.sh'  'the contract requires a permanent case for each behaviour'
    Add-DraftPath 'scripts/hooks/selftest.ps1' 'the same case, on the other shell'
    Add-DraftPath 'docs/roadmap.md'            'the criteria table records the status this slice changes'
    Add-DraftPath 'blueprint.version'          'scripts/command is portable, so adopting projects receive the change'
}

# Required is answered conservatively: a gate that cannot be read is assumed closed, never open.
$gdRequired = $false
if ($govAuthorized -ne $true) { $gdRequired = $true }
if ($null -eq $govAuthorized) {
    $gdRationale.Add('.ai/context/governance.json -- the gate could not be read, so a window is assumed necessary')
}
if ((Test-Path -LiteralPath $govPath) -and $gdPaths.Count -gt 0) {
    try {
        $govDoc = Get-Content -LiteralPath $govPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($pp in @($govDoc.protectedPaths)) {
            if (-not $pp) { continue }
            $protRoot = ($pp -split '\*')[0]
            if (-not $protRoot) { continue }
            foreach ($dp in $gdPaths) {
                if ($dp.StartsWith($protRoot)) { $gdRequired = $true }
            }
        }
    } catch { }
}

# The validation plan. Every entry names a script that exists, so an adopting project is never told
# to run something it does not have. Nothing here has been executed -- that is the first note.
$shellSlice = (@($gdPaths | Where-Object { $_ -like '*scripts/*' }).Count -gt 0)
$vpNarrow = New-Object System.Collections.Generic.List[string]
$vpFull = New-Object System.Collections.Generic.List[string]
$vpNotes = New-Object System.Collections.Generic.List[string]
function Add-Plan {
    param([string]$Bucket, [string]$Command, [string]$Script)
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ($Script -replace '/', '\')))) { return }
    if ($Bucket -eq 'narrow') { $vpNarrow.Add($Command) } else { $vpFull.Add($Command) }
}
if ($recCapability -ne 'unknown') {
    Add-Plan 'narrow' 'bash scripts/command/project-status.sh --json' 'scripts/command/project-status.sh'
    Add-Plan 'narrow' 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/project-status.ps1 -Json' 'scripts/command/project-status.ps1'
    Add-Plan 'narrow' 'bash scripts/hooks/selftest.sh' 'scripts/hooks/selftest.sh'
    Add-Plan 'narrow' 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/selftest.ps1' 'scripts/hooks/selftest.ps1'
}
Add-Plan 'full' 'bash scripts/validation/check-all.sh' 'scripts/validation/check-all.sh'
Add-Plan 'full' 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1' 'scripts/validation/check-all.ps1'
Add-Plan 'full' 'bash scripts/release/selftest-release.sh' 'scripts/release/selftest-release.sh'
$hasShellCheck = $false
try { if (Get-Command shellcheck -ErrorAction SilentlyContinue) { $hasShellCheck = $true } } catch { }
$vpCi = ($shellSlice -and -not $hasShellCheck)
$vpNotes.Add('No check in this plan has been run.')
if ($vpCi) {
    $vpNotes.Add('ShellCheck is not installed here and this slice changes shell files, so CI is the only place its result can come from.')
}
if ($recCapability -eq 'unknown') {
    $vpNotes.Add('No capability could be read, so this plan lists the repository gates rather than a slice-specific narrow set.')
}

# The generated prompt, assembled from the fields above and from nothing else, so re-running the
# command on an unchanged repository produces the same text. A prohibition is dropped only when the
# roadmap section is itself about that subject -- a phase about the CLI may not be told to avoid
# the CLI.
# Matched against whatever the prompt is actually ABOUT. With no row selected there is no owning
# section, and reading the empty string kept every prohibition -- so a prompt titled with the CLI
# phase also told its reader not to start CLI work. The subject is the phase in that case.
$sectL = ''
if ($nextSection) { $sectL = $nextSection.ToLower() }
elseif ($nextPhase) { $sectL = $nextPhase.ToLower() }
$dn = New-Object System.Collections.Generic.List[string]

# WHERE THIS LIST COMES FROM, and why it is not written here any more. These entries used to be
# hardcoded above, and this file is portable -- so every adopting project's generated prompt named
# the private repositories of the project this engine was written in, and forbade a visibility
# change that was never that project's business. Those belong to whoever owns them.
#
# They now live in .ai/context/constraints.md, which is project-specific: sync never copies it, so
# a source repository keeps its own list while an adopter's copy is seeded from
# templates/constraints-template.md with generic entries instead. Note that this comment names no
# repository either: a comment in a portable file travels just as far as the code under it.
#
# Two forms, and nothing else is read:
#   - when-not `regex`: text     emitted unless the named slice is about that subject
#   - text                       always emitted
$constraintsPath = Join-Path $repoRoot '.ai\context\constraints.md'
$dnFound = $false
if (Test-Path -LiteralPath $constraintsPath) {
    # Read only the "## Prompt Prohibitions" section: the flag closes at the next same-level
    # heading, so a bullet elsewhere in the file can never be mistaken for one here.
    $inside = $false
    $subOn = $false
    foreach ($line in (Get-Content -LiteralPath $constraintsPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^##\s+Prompt Prohibitions\s*$') { $inside = $true; $subOn = $false; continue }
        # '^##\s' cannot match '### Conditional' -- the third # sits where the space must be -- so
        # the closing test is safe to run before the subsection test.
        if ($inside -and $line -match '^##\s') { $inside = $false }
        if (-not $inside) { continue }
        # Only bullets inside a ### subsection are entries. The prose above the first one explains
        # the format using bullets of its own, and reading those emitted the documentation as
        # prohibitions -- found by running it.
        if ($line -match '^###\s') { $subOn = $true; continue }
        if (-not $subOn) { continue }
        if ($line -notmatch '^-\s+(.*)$') { continue }
        $entry = $Matches[1].Trim()
        if (-not $entry) { continue }
        $dnFound = $true
        if ($entry -match '^when-not\s+`(.+)`:\s*(.+)$') {
            $cond = $Matches[1]
            $text = $Matches[2].Trim()
            # -notmatch is case-insensitive, which is what the POSIX half gets by lowercasing.
            if ($sectL -notmatch $cond) { $dn.Add('- ' + $text) }
        } else {
            # A malformed line is still a prohibition someone meant. Emit it verbatim rather than
            # dropping it silently: losing a "do not" is the one failure mode worth being loud about.
            $dn.Add('- ' + $entry)
        }
    }
}

# FAILS SAFE, NEVER SILENT. With no section to read, a prompt with no "Do not" list would be a
# prompt that quietly dropped its guardrails. The fallback restates the contract's own
# non-negotiable rules, which are true of every project, and names nothing specific to any.
if (-not $dnFound) {
    $dn.Add('- expand the scope beyond the capability named above')
    $dn.Add('- weaken, skip, or delete a test to obtain a passing result')
    $dn.Add('- disable or bypass a security control')
    $dn.Add('- commit secrets, credentials, tokens, or personal data')
    $dn.Add('- push')
    $vpNotes.Add('No "## Prompt Prohibitions" section was found in .ai/context/constraints.md, so the generated prompt carries the built-in default. Add that section to make the prompt name your own constraints.')
}

if ($gdRequired) {
    $govLine = 'A governance window is required before this slice may write. The draft is in this report; a person opens it, never the command.'
} else {
    $govLine = 'No governance window is required: the drafted paths are not protected and code writes are already authorized.'
}
# A prompt titled "unknown" is a defect in the artifact, not a fact about the project. When no row
# can be named -- every criterion complete, or none eligible -- the phase the roadmap already names
# is the honest subject, and the capability line still says unknown so nothing is dressed up.
$promptSubject = $recCapability
if ($recCapability -eq 'unknown' -and $nextPhase) { $promptSubject = $nextPhase }
$vpFirstNarrow = 'none derived -- no capability was named'
if ($vpNarrow.Count -gt 0) { $vpFirstNarrow = $vpNarrow[0] }
$vpFirstFull = 'none derived -- no gate script was found'
if ($vpFull.Count -gt 0) { $vpFirstFull = $vpFull[0] }
$dnText = ($dn -join "`n")
$ciText = $vpCi.ToString().ToLower()

$generatedPrompt = @"
# ForgeOS -- $promptSubject

You are working in:

$repoRoot

Current state:

- Repository: $repoName
- Branch: $branch
- HEAD: $commit
- Version: $bpVersion
- Project state: $projectState
- Next capability: $recCapability
- Read its wording from: $recSource

Goal:

Implement the capability named above. Its acceptance criteria are the row that names it in the
source above. Read that row before writing anything, and do not restate it from this prompt.

Pre-checks:

- confirm the branch, and that the working tree is clean
- confirm HEAD is $commit
- confirm the version is $bpVersion
- read the authoritative files before editing anything
- reproduce any defect before fixing it

Governance:

$govLine

Validation:

- narrow: $vpFirstNarrow
- full: $vpFirstFull
- ShellCheck must come from CI: $ciText

Do not:

$dnText

Stop after the local commit and report. Do not push.
"@

$map = [ordered]@{
    product = [ordered]@{
        state = (Get-DocState $prodN $prodU); sources = @('docs/product')
        documentCount = $prodN; unfilledDocuments = $prodU
    }
    architecture = [ordered]@{
        state = (Get-DocState $archN $archU); sources = @('docs/architecture', '.ai/memory/decisions')
        documentCount = $archN; unfilledDocuments = $archU
        decisionCount = $decN; mostRecentDecision = $decRecent
    }
    dataModel = [ordered]@{
        state = (Get-DocState $domN $domU)
        sources = @(@('docs/domains') + @($migDir | Where-Object { $_ }))
        documentCount = $domN; unfilledDocuments = $domU; migrationCount = $migN
    }
    requirements = [ordered]@{
        state = (Get-DocState $prodN $prodU); sources = @('docs/product', '.ai/context/project.md')
        documentCount = $prodN; blockingMarkers = $blockingMarkers
        discoveryClosed = ($null -ne $blockingMarkers -and $blockingMarkers -gt 0)
    }
    tasks = [ordered]@{
        state = $(if ($null -eq $tActive) { 'missing' } else { 'present' })
        sources = @('.ai/tasks', '.ai/plans')
        inbox = $tInbox; active = $tActive; completed = $tDone
        activeNames = $activeNames; mostRecentCompleted = $recentDone
        activeAge = $tActiveAge; mostRecentCompletedAge = $tDoneAge; ageSource = $ageSource
        nextSliceActive = $nextSliceActive
    }
    decisions = [ordered]@{
        state = $(if ($null -eq $decN) { 'missing' } else { 'present' })
        sources = @('.ai/memory/decisions'); count = $decN; mostRecent = $decRecent
    }
    openQuestions = [ordered]@{
        state = $(if ($null -eq $qOpen) { 'missing' } else { 'present' })
        sources = @('.ai/memory/open-questions.md'); open = $qOpen; answered = $qAnswered
    }
    validation = [ordered]@{
        state = $(if ($checkAllPresent) { 'present' } else { 'missing' })
        sources = @('scripts/validation/check-all.sh')
        gatingChecks = $gating; informationalChecks = $informational; blockingMarkers = $blockingMarkers
    }
    release = [ordered]@{
        state = $(if ($latestTag) { 'present' } else { 'missing' })
        sources = @('git tags'); tagCount = $tagCount; latestTag = $latestTag
    }
    governance = [ordered]@{
        state = $govState; sources = @('.ai/context/governance.json')
        codeAuthorized = $govAuthorized; allowedPathCount = $govAllowed; windowOpen = $govWindow
    }
}

# --- output ------------------------------------------------------------------------------------
$status = [ordered]@{
    schema        = 'forgeos.project-status/1'
    generatedFrom = 'repository files only'
    projectState  = $projectState
    repository    = [ordered]@{
        name       = $repoName
        branch     = $branch
        commit     = $commit
        visibility = 'unknown'
    }
    blueprint     = [ordered]@{ version = $bpVersion; role = $bpRole }
    state         = [ordered]@{
        ledgerPresent = $ledgerPresent
        now           = $sNow
        next          = $sNext
        blockedBy     = $sBlocked
    }
    work          = [ordered]@{
        tasksInbox        = $tInbox
        tasksActive       = $tActive
        tasksCompleted    = $tDone
        plansActive       = $pActive
        openQuestions     = $qOpen
        answeredQuestions = $qAnswered
    }
    validation    = [ordered]@{
        checkAllPresent     = $checkAllPresent
        gatingChecks        = $gating
        informationalChecks = $informational
        blockingMarkers     = $blockingMarkers
    }
    release       = [ordered]@{ tagCount = $tagCount; latestTag = $latestTag }
    maturity      = [ordered]@{
        installability         = $mInstall
        projectCommandCenter   = $mPcc
        endToEndProjectDriving = $mE2e
        source                 = $mSource
    }
    map            = $map
    nextPhase      = $nextPhase
    nextCapability = $nextCapability
    nextRecommendation = [ordered]@{
        capability = $recCapability
        reason     = $recReason
        source     = $recSource
        confidence = $recConfidence
        selectedStatus = $recSelectedStatus
        blocked    = $recBlocked
        blockers   = @($recBlockers)
        skipped    = @($recSkipped)
    }
    governanceDraft = [ordered]@{
        required              = $gdRequired
        allowedPaths          = @($gdPaths)
        rationale             = @($gdRationale)
        canApplyAutomatically = $false
    }
    validationPlan = [ordered]@{
        narrow     = @($vpNarrow)
        full       = @($vpFull)
        ciRequired = $vpCi
        notes      = @($vpNotes)
    }
    generatedPrompt = $generatedPrompt
    safety        = [ordered]@{
        canModifyFiles          = $false
        canAuthorizeCode        = $false
        canOpenGovernanceWindow = $false
    }
    missingSources = @($missing)
}

# The next-section subset. It carries its own schema id rather than reusing the status one: it is a
# different document with a different shape, and a consumer that trusted "forgeos.project-status/1"
# and then found half the keys missing would be right to complain.
if ($Json -and $Section -eq 'next') {
    ([ordered]@{
        schema             = 'forgeos.project-next/1'
        generatedFrom      = 'repository files only'
        nextRecommendation = $status.nextRecommendation
        governanceDraft    = $status.governanceDraft
        validationPlan     = $status.validationPlan
        generatedPrompt    = $status.generatedPrompt
        safety             = $status.safety
    }) | ConvertTo-Json -Depth 6
    exit 0
}

if ($Json) {
    $status | ConvertTo-Json -Depth 6
    exit 0
}

function Show-Row { param([string]$Label, $Value) Write-Output ("  {0,-22} {1}" -f $Label, $Value) }
function Nz {
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return 'unknown' }
    # PowerShell stringifies a boolean as True; POSIX prints true. The human output has to read the
    # same on both shells, so the lowering happens here, once, for every boolean that is displayed.
    # The JSON is untouched: ConvertTo-Json emits the JSON literal regardless of this.
    if ($Value -is [bool]) { return $Value.ToString().ToLower() }
    return $Value
}

# The human half of -Section next. The blocks themselves are printed by the same code further down,
# so this skips the report header and the map rather than reprinting anything.
$skipStatusBody = ($Section -eq 'next')
if ($skipStatusBody) {
    Write-Output ''
    Write-Output "ForgeOS next step  [$projectState]"
}

if (-not $skipStatusBody) {
Write-Output ''
Write-Output "ForgeOS project status  [$projectState]"
Write-Output ''
Show-Row 'repository' $repoName
Show-Row 'branch' $branch
Show-Row 'commit' $commit
Show-Row 'blueprint' "$bpVersion  (role: $bpRole)"
Show-Row 'latest tag' ("{0}  of {1}" -f (Nz $latestTag), (Nz $tagCount))
Write-Output ''
if ($ledgerPresent) {
    if ($sNow)     { Write-Output ("  now        {0}" -f $sNow) }
    if ($sNext)    { Write-Output ("  next       {0}" -f $sNext) }
    if ($sBlocked) { Write-Output ("  blocked by {0}" -f $sBlocked) }
} else {
    Write-Output '  state ledger missing -- .ai/context/current-state.md'
}
Write-Output ''
Show-Row 'tasks' ("inbox {0} - active {1} - completed {2}" -f (Nz $tInbox), (Nz $tActive), (Nz $tDone))
Show-Row 'plans active' (Nz $pActive)
Show-Row 'open questions' ("{0} open, {1} answered" -f (Nz $qOpen), (Nz $qAnswered))
Show-Row 'validation' ("{0} gating, {1} informational" -f (Nz $gating), (Nz $informational))
Show-Row 'blocking markers' (Nz $blockingMarkers)
Write-Output ''
Write-Output '  maturity toward the public launch bar (95% each):'
Show-Row '  installability' $(if ($null -ne $mInstall) { "$mInstall%" } else { 'unknown' })
Show-Row '  command centre' $(if ($null -ne $mPcc) { "$mPcc%" } else { 'unknown' })
Show-Row '  end-to-end driving' $(if ($null -ne $mE2e) { "$mE2e%" } else { 'unknown' })
Show-Row '  source' $mSource
Write-Output ''
Write-Output '  project map:'
function Show-MapRow { param([string]$Name, [string]$State, [string]$Detail)
    Write-Output ("    {0,-14} {1,-8} {2}" -f $Name, $State, $Detail) }
Show-MapRow 'product'       (Get-DocState $prodN $prodU) ("{0} doc(s), {1} unfilled" -f (Nz $prodN), (Nz $prodU))
Show-MapRow 'architecture'  (Get-DocState $archN $archU) ("{0} doc(s), {1} decision(s)" -f (Nz $archN), (Nz $decN))
Show-MapRow 'dataModel'     (Get-DocState $domN $domU)   ("{0} doc(s), migrations {1}" -f (Nz $domN), (Nz $migN))
Show-MapRow 'requirements'  (Get-DocState $prodN $prodU) ("{0} blocking marker(s)" -f (Nz $blockingMarkers))
Show-MapRow 'tasks'         $(if ($null -eq $tActive) { 'missing' } else { 'present' }) ("active {0} (age {1}), completed {2} (last {3}), age from {4}" -f (Nz $tActive), (Nz $tActiveAge), (Nz $tDone), (Nz $tDoneAge), $ageSource)
Show-MapRow 'decisions'     $(if ($null -eq $decN) { 'missing' } else { 'present' }) ("{0}, latest {1}" -f (Nz $decN), (Nz $decRecent))
Show-MapRow 'openQuestions' $(if ($null -eq $qOpen) { 'missing' } else { 'present' }) ("{0} open, {1} answered" -f (Nz $qOpen), (Nz $qAnswered))
Show-MapRow 'validation'    $(if ($checkAllPresent) { 'present' } else { 'missing' }) ("{0} gating, {1} informational" -f (Nz $gating), (Nz $informational))
Show-MapRow 'release'       $(if ($latestTag) { 'present' } else { 'missing' }) ("{0} of {1}" -f (Nz $latestTag), (Nz $tagCount))
Show-MapRow 'governance'    $govState ("codeAuthorized {0}, window open {1}, {2} allowed path(s)" -f (Nz $govAuthorized), (Nz $govWindow), (Nz $govAllowed))
Write-Output ''
if ($nextPhase) { Show-Row 'next phase' $nextPhase }
if ($nextCapability) { Show-Row 'next capability' $nextCapability }
if ($missing.Count -gt 0) {
    Write-Output ''
    Write-Output ("  missing sources ({0}) -- reported, not guessed:" -f $missing.Count)
    foreach ($m in $missing) { Write-Output "    - $m" }
}
}   # end of the status body that -Section next skips
Write-Output ''
Write-Output '  next recommendation:'
Write-Output ("    {0,-14} {1}" -f 'capability', $recCapability)
Write-Output ("    {0,-14} {1}" -f 'reason', $recReason)
Write-Output ("    {0,-14} {1}" -f 'source', $recSource)
Write-Output ("    {0,-14} {1}" -f 'confidence', $recConfidence)
Write-Output ("    {0,-14} {1}" -f 'row status', $recSelectedStatus)
Write-Output ("    {0,-14} {1}" -f 'blocked', (Nz $recBlocked))
foreach ($b in $recBlockers) { Write-Output ("      - {0}" -f $b) }
if ($recSkipped.Count -gt 0) {
    Write-Output ("    {0,-14} {1}" -f 'skipped', $recSkipped.Count)
    foreach ($sk in $recSkipped) { Write-Output ("      - {0}" -f $sk) }
}
Write-Output ''
Write-Output '  governance window draft -- a draft only; this command cannot open a window:'
Write-Output ("    {0,-22} {1}" -f 'required', (Nz $gdRequired))
Write-Output ("    {0,-22} {1}" -f 'canApplyAutomatically', 'false')
if ($gdRationale.Count -gt 0) {
    foreach ($r in $gdRationale) { Write-Output ("      - {0}" -f $r) }
} else {
    Write-Output '      - no rule covers this section, so no path is drafted'
}
Write-Output ''
Write-Output '  validation plan -- a plan; nothing in it has been run:'
foreach ($c in $vpNarrow) { Write-Output ("    narrow   {0}" -f $c) }
foreach ($c in $vpFull)   { Write-Output ("    full     {0}" -f $c) }
Write-Output ("    {0,-8} {1}" -f 'from CI', ("ShellCheck required: " + (Nz $vpCi)))
foreach ($nte in $vpNotes) { Write-Output ("    note     {0}" -f $nte) }
Write-Output ''
Write-Output '  generated prompt -- copy everything between the two rules:'
Write-Output '--------------------------------------------------------------------------------'
Write-Output $generatedPrompt
Write-Output '--------------------------------------------------------------------------------'

Write-Output ''
Write-Output '  This command reads. It writes nothing, authorizes nothing, and opens no governance window.'
Write-Output ''
exit 0
