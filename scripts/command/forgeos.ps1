<#
.SYNOPSIS
    The local ForgeOS command surface. Windows counterpart of forgeos.sh.

.DESCRIPTION
    A WRAPPER FOR THE PROJECT, AN ENGINE FOR ITSELF. `status`, `next` and `prompt` describe the
    PROJECT, so they route to project-status and add nothing: the reading, the schema and the flags
    belong to that one command, and a second place that read the same files would be a second
    answer waiting to disagree. `doctor` and `version` describe the INSTALLATION, so they are
    implemented here -- neither duplicates the engine, and neither could route to a command that
    may itself be the missing piece.

    READ-ONLY EXCEPT ON TWO EXPLICIT PATHS. Every command here reads and nothing more, with two
    exceptions: `adopt -Apply` and `update -Apply`, which delegate to sync-blueprint's own writing
    path. Dry run is the default for both -- neither writes unasked -- and -Force is never passed,
    so a file the project customized is skipped and reported rather than overwritten.

    adopt brings ForgeOS into a project that does not have it; update refreshes one that does, and
    refuses a target that has never adopted. Nothing here touches the network: the source is always
    this checkout, so there is no channel, no fetch and no version discovery.

.PARAMETER Command
    status, next, doctor, version, adopt, or update.

.PARAMETER Json
    Emit JSON on stdout and nothing else.

.PARAMETER Target
    adopt and update only: the project to sync the blueprint into.

.PARAMETER Apply
    adopt and update only, and the writing mode. Without it, both are dry runs.

.NOTES
    Exit 0 reported; 1 usage error or could not run; 2 is reserved by the house convention for a
    gate refusal and no command here can produce one.
#>
param(
    [Parameter(Position = 0)]
    [string]$Command = '',
    [switch]$Json,
    # adopt only. -Apply is the single writing mode in this file and must be typed to happen.
    [string]$Target = '',
    [switch]$Apply,
    # Anything else the caller typed. Without this the binder rejects an unknown option with its own
    # error, and the two shells would answer the same mistake differently -- POSIX with this
    # command's usage text, Windows with a PowerShell stack trace. The wrapper owns its usage errors
    # on both.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

Set-StrictMode -Version 2.0
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $here '..\..')).Path
$statusCmd = Join-Path $here 'project-status.ps1'

# Windows PowerShell 5.1 turns a native command's stderr into an ErrorRecord, and with
# $ErrorActionPreference = 'Stop' that becomes terminating. `git` outside a repository writes to
# stderr, so a reporting command would THROW exactly where it is supposed to report the source as
# missing. Every external call goes through here instead -- the same guard project-status carries,
# for the same reason.
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

function Show-Usage {
    $lines = @(
        'forgeos -- the local ForgeOS command surface',
        '',
        'Usage:',
        '  forgeos status  [--json]   where this project is, read from its own files',
        '  forgeos next    [--json]   what the next safe thing to do is',
        '  forgeos prompt  [--json]   the complete package for the next work session: session, model,',
        '                             effort, scope, policy, and a paste-ready prompt. Refuses to invent:',
        '                             missing context is named instead of guessed.',
        '  forgeos doctor  [--json]   whether this ForgeOS installation can run',
        '  forgeos version [--json]   which ForgeOS this is, and where it sits',
        '  forgeos adopt  -Target <path> [-Apply] [-Json]',
        '                             bring the portable blueprint into a project for the first time.',
        '                             DRY RUN unless -Apply is given.',
        '  forgeos update -Target <path> [-Apply] [-Json]',
        '                             refresh a project that has ALREADY adopted. Refuses one that has not.',
        '                             DRY RUN unless -Apply is given.',
        '',
        'Every command reads. The two exceptions are "adopt -Apply" and "update -Apply", which delegate',
        'to sync-blueprint to write; on their own both are dry runs. None authorizes code, opens a',
        'governance window, reaches the network, or passes -Force.',
        '',
        'Exit codes: 0 reported - 1 usage error or could not run - 2 refused by a gate (never from here).'
    )
    return $lines
}

# A writing flag accepted by a reading command is a bad surprise waiting to happen, so the options
# are checked against the command rather than merely bound. Only adopt takes -Apply or -Target.
if ($Command -ne 'adopt' -and $Command -ne 'update') {
    if ($Apply) {
        [Console]::Error.WriteLine("-Apply is only valid for 'forgeos adopt' and 'forgeos update'.")
        [Console]::Error.WriteLine('')
        Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit 1
    }
    if ($Target) {
        [Console]::Error.WriteLine("-Target is only valid for 'forgeos adopt' and 'forgeos update'.")
        [Console]::Error.WriteLine('')
        Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit 1
    }
}

# `-h` and `--help` start with a dash, so the binder hands them to $Rest instead of to $Command and
# the unknown-option guard below swallowed them: `forgeos --help` exited 1 saying "Unknown option"
# while POSIX printed the usage. Promote a help token before the guard runs, so both shells answer
# the same three spellings the same way.
if (-not $Command -and @($Rest | Where-Object { $_ }).Count -eq 1 -and
    @($Rest)[0] -in @('-h', '--help', 'help')) {
    $Command = @($Rest)[0]
    $Rest = @()
}

if (@($Rest | Where-Object { $_ }).Count -gt 0) {
    [Console]::Error.WriteLine("Unknown option: " + (@($Rest) -join ' '))
    [Console]::Error.WriteLine('')
    Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 1
}

switch ($Command) {
    { $_ -in @('status', 'next', 'prompt') } {
        if (-not (Test-Path -LiteralPath $statusCmd)) {
            [Console]::Error.WriteLine("Cannot run: project-status.ps1 is missing from $here")
            [Console]::Error.WriteLine('Run "forgeos doctor" for the full picture.')
            exit 1
        }
        $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $statusCmd)
        if ($Json) { $argv += '-Json' }
        if ($Command -eq 'next') { $argv += @('-Section', 'next') }
        if ($Command -eq 'prompt') { $argv += @('-Section', 'prompt') }
        & powershell.exe @argv
        exit $LASTEXITCODE
    }
    { $_ -in @('doctor', 'version', 'adopt', 'update') } { }
    { $_ -in @('-h', '--help', 'help') } { Show-Usage | ForEach-Object { Write-Output $_ }; exit 0 }
    '' {
        [Console]::Error.WriteLine('No command given.')
        [Console]::Error.WriteLine('')
        Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit 1
    }
    default {
        [Console]::Error.WriteLine("Unknown command: $Command")
        [Console]::Error.WriteLine('')
        Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit 1
    }
}

# --- version -----------------------------------------------------------------------------------
# Which ForgeOS this is, and where this checkout sits relative to the last tag. Like doctor, it
# describes the INSTALLATION rather than the project, which is why it is implemented here instead
# of routed: a version command that could not answer because the engine was missing would be a poor
# version command, and the doctor fixture proves that case is real.
#
# Every value is read from a local file or from local git metadata. Nothing here reaches the
# network.
if ($Command -eq 'version') {
    $vMissing = New-Object System.Collections.Generic.List[string]

    $vVersion = 'unknown'; $vRole = 'unknown'; $vSource = 'missing'
    $vBp = Join-Path $repoRoot 'blueprint.version'
    if (Test-Path -LiteralPath $vBp) {
        $vSource = 'blueprint.version'
        try {
            $vDoc = Get-Content -LiteralPath $vBp -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($vDoc.version) { $vVersion = $vDoc.version }
            if ($vDoc.role) { $vRole = $vDoc.role }
        } catch { }
    } else {
        $vMissing.Add('blueprint.version')
    }

    # git, read-only. A shallow clone is treated as no answer for the DISTANCE: `git rev-list` there
    # counts only the fetched commits, so the number would be a floor rather than a fact.
    $vCommit = 'unknown'; $vTag = $null; $vDistance = $null
    $vGitOk = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'rev-parse', '--git-dir')).Count -gt 0
    if ($vGitOk) {
        $vc = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD'))
        if ($vc.Count -gt 0) { $vCommit = $vc[0] }
        $vt = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'tag', '--sort=-v:refname'))
        if ($vt.Count -gt 0) { $vTag = $vt[0] }
        if ($vTag) {
            $vShallow = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'rev-parse', '--is-shallow-repository'))
            if ($vShallow.Count -gt 0 -and "$($vShallow[0])".Trim() -eq 'false') {
                $vd = @(Invoke-External -Exe 'git' -Arguments @('-C', $repoRoot, 'rev-list', '--count', "$vTag..HEAD"))
                if ($vd.Count -gt 0 -and "$($vd[0])".Trim() -match '^[0-9]+$') { $vDistance = [int]"$($vd[0])".Trim() }
            }
        }
    } else {
        $vMissing.Add('git metadata')
    }

    # A GitHub Release is a REMOTE fact and no local file records one, so this command says it does
    # not know rather than guessing from the latest tag. The two are related but not the same: a tag
    # can exist with no release behind it, and reporting one as the other is how a version command
    # starts claiming something nobody published.
    $vReleaseKnown = $false
    $vRelease = $null
    $vMissing.Add('GitHub release (remote; this command reads only local files)')

    if ($Json) {
        ([ordered]@{
            schema                = 'forgeos.version/1'
            version               = $vVersion
            role                  = $vRole
            commit                = $vCommit
            latestTag             = $vTag
            distanceFromLatestTag = $vDistance
            releaseKnown          = $vReleaseKnown
            releaseVersion        = $vRelease
            source                = $vSource
            missingSources        = @($vMissing)
            safety                = [ordered]@{
                canModifyFiles          = $false
                canAuthorizeCode        = $false
                canOpenGovernanceWindow = $false
            }
        }) | ConvertTo-Json -Depth 6
        exit 0
    }

    function Vnz { param($Value) if ($null -eq $Value -or "$Value" -eq '') { return 'unknown' } return $Value }
    Write-Output ''
    Write-Output 'ForgeOS version'
    Write-Output ''
    Write-Output ("  {0,-22} {1}" -f 'version', (Vnz $vVersion))
    Write-Output ("  {0,-22} {1}" -f 'role', (Vnz $vRole))
    Write-Output ("  {0,-22} {1}" -f 'commit', (Vnz $vCommit))
    Write-Output ("  {0,-22} {1}" -f 'latest tag', (Vnz $vTag))
    Write-Output ("  {0,-22} {1}" -f 'commits since that tag', (Vnz $vDistance))
    Write-Output ("  {0,-22} {1}" -f 'release', 'unknown -- remote fact, not read here')
    Write-Output ("  {0,-22} {1}" -f 'source', $vSource)
    if ($vMissing.Count -gt 0) {
        Write-Output ''
        Write-Output '  not read -- reported, not guessed:'
        foreach ($m in $vMissing) { Write-Output ("    - {0}" -f $m) }
    }
    Write-Output ''
    Write-Output '  This command reads. It writes nothing, authorizes nothing, and opens no governance window.'
    Write-Output ''
    exit 0
}

# --- adopt ---------------------------------------------------------------------------------------
# Syncs the portable blueprint into another project by DELEGATING to sync-blueprint. It
# re-implements none of that engine: fifteen versions of proven behaviour and the cases that pin
# them live there, and a second copy of the copy rules would be a second answer waiting to disagree.
#
# Dry run is the default, because sync-blueprint's default already is -- "WITHOUT -Apply THIS ONLY
# REPORTS" is its own header. This command adds no writing path; it chooses between two that exist.
#
# -Force is never passed and never exposed. It is the flag that overwrites a file the project
# customized, and a wrapper that quietly offered it would undo the guarantee the engine exists for.
#
# `update` is the same delegation with one precondition in front of it. adopt brings ForgeOS into a
# project that does not have it; update refreshes one that does. They share this block on purpose:
# two copies of the same delegation would eventually disagree about -Force or about a counter.
if ($Command -eq 'adopt' -or $Command -eq 'update') {
    $syncCmd = Join-Path $repoRoot 'scripts\blueprint\sync-blueprint.ps1'
    $aMissing = New-Object System.Collections.Generic.List[string]

    if (-not $Target) {
        [Console]::Error.WriteLine("$Command needs -Target <path>: the project to sync the blueprint into.")
        [Console]::Error.WriteLine('')
        Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit 1
    }

    # What separates update from adopt, and the reason it is a command rather than an alias: update
    # refreshes a project that has ALREADY adopted, so it refuses one that has not. It fails closed --
    # syncing into a project that never adopted is an adoption, and calling it an update would hide a
    # first-time seeding behind a word that promises only a refresh.
    $aFromVersion = $null
    if ($Command -eq 'update') {
        $tgtBp = Join-Path $Target 'blueprint.version'
        if (-not (Test-Path -LiteralPath $tgtBp)) {
            [Console]::Error.WriteLine("Nothing to update: $Target has no blueprint.version, so it has never adopted ForgeOS.")
            [Console]::Error.WriteLine("Adopt it first:  forgeos adopt -Target `"$Target`"")
            exit 1
        }
        $tgtRole = 'unknown'
        try {
            $tgtDoc = Get-Content -LiteralPath $tgtBp -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($tgtDoc.role) { $tgtRole = $tgtDoc.role }
            if ($tgtDoc.version) { $aFromVersion = $tgtDoc.version }
        } catch { }
        if ($tgtRole -ne 'adopted') {
            [Console]::Error.WriteLine("Refusing to update: $Target reports role '$tgtRole', not 'adopted'.")
            [Console]::Error.WriteLine('update refreshes a project that adopted ForgeOS; this target is not one.')
            exit 1
        }
    }
    if (-not (Test-Path -LiteralPath $syncCmd)) {
        [Console]::Error.WriteLine("Cannot run: scripts/blueprint/sync-blueprint.ps1 is missing from $repoRoot")
        [Console]::Error.WriteLine('Run "forgeos doctor" for the full picture.')
        exit 1
    }

    $aMode = 'dry-run'
    if ($Apply) { $aMode = 'apply' }

    # The version this checkout would bring. Read from the file, never assumed.
    $aToVersion = 'unknown'
    $srcBp = Join-Path $repoRoot 'blueprint.version'
    if (Test-Path -LiteralPath $srcBp) {
        try {
            $srcDoc = Get-Content -LiteralPath $srcBp -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($srcDoc.version) { $aToVersion = $srcDoc.version }
        } catch { }
    }

    # The delegation itself. Exactly the engine's own two routes, and nothing else on the line.
    $syncArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $syncCmd, '-Source', $repoRoot, '-Target', $Target)
    if ($Apply) { $syncArgs += '-Apply' }
    $syncOut = (Invoke-External -Exe 'powershell.exe' -Arguments $syncArgs) -join "`n"
    $syncCode = $LASTEXITCODE
    if ($null -eq $syncCode) { $syncCode = 0 }

    # The engine's counters are printed with fixed labels from array lengths, so they can be read
    # back without re-deriving anything. A label that is absent yields $null -- never a zero, because
    # "the engine did not print this" and "the engine printed zero" are different facts. A self-test
    # case pins these labels, so a change to the engine's report fails loudly instead of quietly
    # nulling every counter.
    function Get-SyncCount {
        param([string]$Label)
        $rx = '(?m)^  ' + [regex]::Escape($Label) + ' +([0-9]+)'
        $m = [regex]::Match($syncOut, $rx)
        if ($m.Success) { return [int]$m.Groups[1].Value }
        return $null
    }
    $aNew         = Get-SyncCount 'new'
    $aUpdated     = Get-SyncCount 'updated'
    $aUnchanged   = Get-SyncCount 'unchanged'
    $aPreExisting = Get-SyncCount 'pre-existing'
    $aLocalMods   = Get-SyncCount 'locally modified'
    $aRemoved     = Get-SyncCount 'removed in source'
    $aOwned       = Get-SyncCount 'project-owned'
    $aSeedFiles   = Get-SyncCount 'seeded'
    $aSeedDirs    = $null
    $sd = [regex]::Match($syncOut, '(?m)^  seeded +[0-9]+ file\(s\), ([0-9]+) directory')
    if ($sd.Success) { $aSeedDirs = [int]$sd.Groups[1].Value }
    if ($null -eq $aNew) { $aMissing.Add('the counter table sync-blueprint prints (its labels may have changed)') }

    # planned is what a dry run would write: new files plus updated ones plus first-time seeds.
    $aPlanned = $null
    if ($null -ne $aNew -and $null -ne $aUpdated) {
        $aPlanned = $aNew + $aUpdated
        if ($null -ne $aSeedFiles) { $aPlanned = $aPlanned + $aSeedFiles }
    }

    $aWritten = $null
    if ($Apply) {
        $wm = [regex]::Match($syncOut, '(?m)^Applied\. ([0-9]+) file\(s\) written')
        if ($wm.Success) { $aWritten = [int]$wm.Groups[1].Value }
    }

    # Warnings are read from the engine's own counters, never invented. Each names something a person
    # would want to know before applying.
    $aWarnings = New-Object System.Collections.Generic.List[string]
    if ($null -ne $aLocalMods -and $aLocalMods -gt 0) {
        $aWarnings.Add("$aLocalMods file(s) were customized in the target and are skipped, not overwritten")
    }
    if ($null -ne $aPreExisting -and $aPreExisting -gt 0) {
        $aWarnings.Add("$aPreExisting file(s) already exist in the target and were never placed by sync; they are skipped")
    }
    if ($null -ne $aRemoved -and $aRemoved -gt 0) {
        $aWarnings.Add("$aRemoved file(s) are gone from the source; sync deletes nothing, so remove them by hand if that is intended")
    }
    if ($syncOut -match 'not a git repository yet') {
        $aWarnings.Add('the target is not a git repository yet, so its validation suite cannot scan a tracked tree until it is')
    }
    if ($syncCode -ne 0) {
        $aWarnings.Add("sync-blueprint exited $syncCode; nothing above should be trusted as a completed plan")
    }

    if ($Json) {
        # canModifyFiles is TRUE in apply mode. It is the one writing path in this file, and a flag
        # that said false while files were being written would be the exact lie these flags prevent.
        $aCanWrite = [bool]$Apply
        ([ordered]@{
            schema           = "forgeos.$Command/1"
            mode             = $aMode
            fromVersion      = $aFromVersion
            toVersion        = $aToVersion
            wouldWrite       = $aCanWrite
            delegatesTo      = 'scripts/blueprint/sync-blueprint.ps1'
            forcePassed      = $false
            source           = $repoRoot
            target           = $Target
            plannedFileCount = $aPlanned
            filesWritten     = $aWritten
            counters         = [ordered]@{
                new               = $aNew
                updated           = $aUpdated
                unchanged         = $aUnchanged
                preExisting       = $aPreExisting
                locallyModified   = $aLocalMods
                removedInSource   = $aRemoved
                projectOwned      = $aOwned
                seededFiles       = $aSeedFiles
                seededDirectories = $aSeedDirs
            }
            exitCode         = $syncCode
            warnings         = @($aWarnings)
            missingSources   = @($aMissing)
            safety           = [ordered]@{
                canModifyFiles          = $aCanWrite
                canAuthorizeCode        = $false
                canOpenGovernanceWindow = $false
            }
        }) | ConvertTo-Json -Depth 6
        exit $syncCode
    }

    # The engine's own report is the report. Reprinting it in this command's words would be a second
    # description of the same plan, and the two would drift.
    Write-Output $syncOut
    Write-Output ''
    if ($Apply) {
        Write-Output '  Applied through sync-blueprint. -Force was not passed, so any file this project had'
        Write-Output '  customized was left alone rather than overwritten.'
    } else {
        Write-Output '  This was a DRY RUN. Nothing was written.'
        Write-Output '  To apply it:'
        # QUOTED, and that is not cosmetic. A target path containing a space -- which is ordinary on
        # Windows and on any Desktop folder -- came back unquoted, and copying that line verbatim
        # failed on the stray second word. A suggested command that cannot be pasted is worse than
        # none: it teaches the reader to distrust the output.
        Write-Output ("    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/forgeos.ps1 {0} -Target `"{1}`" -Apply" -f $Command, $Target)
    }
    if ($Command -eq 'update') {
        $fromShown = 'unknown'
        if ($aFromVersion) { $fromShown = $aFromVersion }
        Write-Output ("  {0,-22} {1} -> {2}" -f 'version', $fromShown, $aToVersion)
    }
    Write-Output ''
    exit $syncCode
}

# --- doctor -----------------------------------------------------------------------------------
# Whether this installation can run, and when it cannot, which prerequisite failed and what to do
# about it. A missing tool is REPORTED, never hidden and never silently worked around: a doctor
# that hides a missing dependency is how a first run fails with a stack trace instead of a
# sentence.
#
# Rows are ok / missing / unknown. "unknown" is for a question this command cannot answer without
# doing something it must not do -- there is no network call and no write anywhere in here.
$rows = New-Object System.Collections.Generic.List[object]
$ready = $true
function Add-Row {
    param([string]$Name, [string]$State, [string]$Detail, [bool]$Required)
    $rows.Add([pscustomobject]@{ Name = $Name; State = $State; Detail = $Detail; Required = $Required })
    if ($Required -and $State -ne 'ok') { $script:ready = $false }
}

# 1. the shell itself
Add-Row 'shell' 'ok' ("PowerShell " + $PSVersionTable.PSVersion.ToString()) $true

# 2. and 3. the engine and the gates this surface depends on
if (Test-Path -LiteralPath $statusCmd) {
    Add-Row 'project-status' 'ok' 'scripts/command/project-status.ps1' $true
} else {
    Add-Row 'project-status' 'missing' 'expected scripts/command/project-status.ps1 -- re-sync the blueprint' $true
}
if (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts\validation\check-all.ps1')) {
    Add-Row 'validation' 'ok' 'scripts/validation/check-all.ps1' $true
} else {
    Add-Row 'validation' 'missing' 'expected scripts/validation/check-all.ps1 -- re-sync the blueprint' $true
}

# 4. and 5. the two files that tell this installation what it is
$bp = Join-Path $repoRoot 'blueprint.version'
if (Test-Path -LiteralPath $bp) {
    $dv = 'unknown'; $dr = 'unknown'
    try {
        $doc = Get-Content -LiteralPath $bp -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($doc.version) { $dv = $doc.version }
        if ($doc.role) { $dr = $doc.role }
    } catch { }
    Add-Row 'blueprint.version' 'ok' "version $dv, role $dr" $true
} else {
    Add-Row 'blueprint.version' 'missing' 'expected blueprint.version at the repository root' $true
}
if (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts\lib\blueprint-manifest.json')) {
    Add-Row 'manifest' 'ok' 'scripts/lib/blueprint-manifest.json' $true
} else {
    Add-Row 'manifest' 'missing' 'expected scripts/lib/blueprint-manifest.json -- re-sync the blueprint' $true
}

# 6. the JSON reader. On this shell it is built in -- ConvertFrom-Json needs no external tool -- so
# the row exists to answer the same question as its POSIX twin rather than to report a risk.
Add-Row 'json reader' 'ok' 'ConvertFrom-Json, built into PowerShell' $false

# 7. git. Optional for reporting: without it the status command reports its git fields as missing
# rather than failing, so this is a warning and not a stop.
$gitVer = $null
try { $gitVer = (& git --version 2>$null | Select-Object -First 1) } catch { }
if ($gitVer) {
    $inRepo = $false
    try { $null = & git -C $repoRoot rev-parse --git-dir 2>$null; $inRepo = ($LASTEXITCODE -eq 0) } catch { }
    if ($inRepo) {
        Add-Row 'git' 'ok' "$gitVer" $false
    } else {
        Add-Row 'git' 'missing' 'git is installed but this is not a repository -- branch, commit and ages report unknown' $false
    }
} else {
    Add-Row 'git' 'missing' 'git not on PATH -- branch, commit and slice ages report unknown' $false
}

# 8. hook wiring. The hooks are the safety net; a settings file that does not reference them means
# the net is not attached, which is worth saying out loud even though nothing here depends on it.
$settings = Join-Path $repoRoot '.claude\settings.json'
if (Test-Path -LiteralPath $settings) {
    $hooked = @(Select-String -LiteralPath $settings -Pattern 'scripts/hooks' -AllMatches -ErrorAction SilentlyContinue).Count
    if ($hooked -gt 0) {
        Add-Row 'hook wiring' 'ok' ".claude/settings.json references scripts/hooks ($hooked time(s))" $false
    } else {
        Add-Row 'hook wiring' 'missing' '.claude/settings.json does not reference scripts/hooks -- the guards are not wired' $false
    }
} else {
    Add-Row 'hook wiring' 'unknown' '.claude/settings.json not readable here' $false
}

# 9. line-ending policy. Its absence is what lets a .ps1 and a .sh disagree across platforms.
$attrs = Join-Path $repoRoot '.gitattributes'
if (Test-Path -LiteralPath $attrs) {
    $eol = @(Select-String -LiteralPath $attrs -Pattern 'eol=' -ErrorAction SilentlyContinue).Count
    Add-Row 'line endings' 'ok' ".gitattributes pins $eol rule(s)" $false
} else {
    Add-Row 'line endings' 'missing' 'no .gitattributes -- line endings would follow whatever the platform does' $false
}

$verdict = 'ready'
if (-not $ready) { $verdict = 'not ready' }

if ($Json) {
    ([ordered]@{
        schema        = 'forgeos.doctor/1'
        generatedFrom = 'local installation only'
        ready         = $ready
        checks        = @($rows | ForEach-Object {
            [ordered]@{ name = $_.Name; state = $_.State; required = $_.Required; detail = $_.Detail }
        })
        safety        = [ordered]@{
            canModifyFiles          = $false
            canAuthorizeCode        = $false
            canOpenGovernanceWindow = $false
        }
    }) | ConvertTo-Json -Depth 6
    exit 0
}

Write-Output ''
Write-Output "ForgeOS doctor  [$verdict]"
Write-Output ''
foreach ($r in $rows) {
    $req = 'optional'
    if ($r.Required) { $req = 'required' }
    Write-Output ("  {0,-18} {1,-8} {2,-9} {3}" -f $r.Name, $r.State, $req, $r.Detail)
}
Write-Output ''
if ($ready) {
    Write-Output '  Every required prerequisite is present. Optional rows marked missing are safe to ignore'
    Write-Output '  unless you need what they provide.'
} else {
    Write-Output '  A required prerequisite is missing. Each row above names what it expected and what to do.'
}
Write-Output ''
Write-Output '  This command reads. It writes nothing, authorizes nothing, and opens no governance window.'
Write-Output ''
exit 0
