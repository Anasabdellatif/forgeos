<#
.SYNOPSIS
    Gates task closure on mechanical completion signals, then archives the task and its plan.

.DESCRIPTION
    Checks that the task has no unchecked criteria, no pending completion evidence, and no active
    blocker, then moves the task and its related plan into their completed/ directories.

    This is a GATE, NOT A VERDICT. The Definition of Done in .ai/contract/lifecycle.md section 6
    has eleven conditions; this script mechanically checks five of them. The agent is responsible
    for the other six, and for the evidence behind all eleven.

.PARAMETER Check
    Report the completion state without moving anything.

.OUTPUTS
    Exit 0 on success, 1 on error, 2 when the task is not ready to close.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TaskPath,

    [switch]$Check
)

$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    $root = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    return $root.Path
}

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $resolved = Resolve-Path -LiteralPath $Path
    } else {
        $resolved = Resolve-Path -LiteralPath (Join-Path -Path $RepoRoot -ChildPath $Path)
    }
    return $resolved.Path
}

function Get-RelatedPlanPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $match = [regex]::Match($Content, '(?m)^\s*-\s*Related plan:\s*`?([^`\r\n]+)`?\s*$')
    if (-not $match.Success) {
        return $null
    }

    $value = $match.Groups[1].Value.Trim()
    if ($value -eq 'none' -or $value -eq '[path or none]') {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($value)) {
        return $value
    }
    return Join-Path -Path $RepoRoot -ChildPath $value
}

$repoRoot = Get-RepositoryRoot

try {
    $resolvedTask = Resolve-RepositoryPath -RepoRoot $repoRoot -Path $TaskPath
} catch {
    Write-Error "Task not found: $TaskPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $resolvedTask -PathType Leaf)) {
    Write-Error "Task not found: $resolvedTask"
    exit 1
}

# -Encoding UTF8 is load-bearing on Windows PowerShell 5.1: without it a BOM-less UTF-8 file --
# which every task file is -- is read as ANSI/CP1252, so Arabic acceptance criteria and Arabic
# placeholder evidence arrive as mojibake and no pattern written for the real text can match them.
# Same defect class as build-context before v1.12.2.
$taskContent = Get-Content -LiteralPath $resolvedTask -Raw -Encoding UTF8
$taskLines = Get-Content -LiteralPath $resolvedTask -Encoding UTF8

$blockers = [System.Collections.Generic.List[string]]::new()

# Gate 1 -- no unchecked acceptance criteria or checklist items.
$lineNumber = 0
foreach ($line in $taskLines) {
    $lineNumber++
    if ($line -match '^\s*-\s*\[\s\]\s+') {
        $blockers.Add("unchecked criterion   line ${lineNumber}: $($line.Trim())")
    }
}

# Gate 2 -- no pending completion evidence.
$lineNumber = 0
foreach ($line in $taskLines) {
    $lineNumber++
    if ($line -match '(?i)`\[?pending\]?`') {
        $blockers.Add("pending evidence      line ${lineNumber}: $($line.Trim())")
    }
}

# Gate 3 -- the task is not blocked.
if ($taskContent -match '(?im)^\s*-\s*Status:\s*`?(yes|blocked)`?\s*$') {
    $blockers.Add('active blocker        the Blocked section reports Status: yes')
}

# Gate 4 -- no unreplaced template placeholders in the objective or criteria.
$lineNumber = 0
foreach ($line in $taskLines) {
    $lineNumber++
    if ($line -match '\[(Observable criterion \d|Title|Verified fact|Required work)\]') {
        $blockers.Add("template placeholder  line ${lineNumber}: $($line.Trim())")
    }
}

# Gate 5 -- profile compliance. Enforcement is the intersection of two declarations: the task says
# what it touches, the profile says which of those areas demand a role. A task that touches nothing
# sensitive owes nothing, and a role with nothing to examine is never demanded.
$profileNote = $null
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'scripts\lib\blueprint-manifest.json'
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch { $manifest = $null }
    $compliance = if ($manifest) { $manifest.policy.profileCompliance } else { $null }

    if ($compliance) {
        $sectionPattern = '(?m)^' + [regex]::Escape($compliance.taskSection) + '\s*$'
        if ($taskContent -notmatch $sectionPattern) {
            # The task predates this rule. Record it at closure rather than blocking work that was
            # opened before the requirement existed -- same principle as the discovery gate note.
            $profileNote = 'no Profile Compliance section'
        } else {
            $scopeLine = [regex]::Match($taskContent, '(?m)^\s*-\s*' + [regex]::Escape($compliance.scopeField) + '\s*(.+)$')
            $tags = @()
            if ($scopeLine.Success) {
                foreach ($m in [regex]::Matches($scopeLine.Groups[1].Value, '`([^`]+)`')) { $tags += $m.Groups[1].Value.Trim() }
            }
            $tags = @($tags | Where-Object { $_ -and $_ -ne $compliance.noneTag })

            $known = @{}
            foreach ($sr in $compliance.scopeRoles) { $known[$sr.tag] = $sr.role }

            # An unrecognized tag must fail. A typo would otherwise disable the check silently.
            foreach ($tag in $tags) {
                if (-not $known.ContainsKey($tag)) {
                    $blockers.Add("unknown scope tag     '$tag' is not one of: " + (($known.Keys | Sort-Object) -join ', ') + ", $($compliance.noneTag)")
                }
            }

            # Which roles this project actually enforces: the profile's required set, plus any the
            # project promoted in .ai/context/project.md.
            $enforced = @{}
            $contextPath = Join-Path -Path $repoRoot -ChildPath '.ai\context\project.md'
            $profileName = $null
            if (Test-Path -LiteralPath $contextPath -PathType Leaf) {
                $contextRaw = Get-Content -LiteralPath $contextPath -Raw
                $pm = [regex]::Match($contextRaw, '(?m)^\s*-\s*Profile:\s*`([^`]+)`')
                if ($pm.Success) { $profileName = $pm.Groups[1].Value.Trim() }
                # Structured first: a "- Promoted roles: `role`" line. The prose form is still read
                # as a fallback, but order-insensitively and only for names that are actually roles.
                # The old regex required the word "promoted" BEFORE the role, so the natural sentence
                # "`security-reviewer` is promoted from optional to required" was invisible to it --
                # while the POSIX twin saw it, and also mistook the profile name on the same line for
                # a role. Two platforms, two different wrong answers, from one inference over prose.
                $roleNames = @{}
                foreach ($sr in $compliance.scopeRoles) { $roleNames[$sr.role] = $true }

                $promotedPattern = '(?im)^\s*-\s*' + [regex]::Escape($compliance.promotedField) + '\s*(.+)$'
                $promotedLine = [regex]::Match($contextRaw, $promotedPattern)
                if ($promotedLine.Success) {
                    foreach ($m in [regex]::Matches($promotedLine.Groups[1].Value, '`([a-z-]+)`')) {
                        if ($m.Groups[1].Value -ne 'none') { $enforced[$m.Groups[1].Value] = $true }
                    }
                }

                foreach ($line in ($contextRaw -split "`r?`n")) {
                    if ($line -notmatch '(?i)promoted') { continue }
                    foreach ($m in [regex]::Matches($line, '`([a-z-]+)`')) {
                        if ($roleNames.ContainsKey($m.Groups[1].Value)) { $enforced[$m.Groups[1].Value] = $true }
                    }
                }
            }
            if ($profileName -and $profileName -ne 'none') {
                $profilePath = Join-Path -Path $repoRoot -ChildPath ".ai\profiles\$profileName.md"
                if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
                    $fm = [regex]::Match((Get-Content -LiteralPath $profilePath -Raw), '(?m)^requiredRoles:\s*\[([^\]]*)\]')
                    if ($fm.Success) {
                        foreach ($r in ($fm.Groups[1].Value -split ',')) {
                            $r = $r.Trim()
                            if ($r) { $enforced[$r] = $true }
                        }
                    }
                }
            }

            # Evidence lines: "- `role`: what was examined". A placeholder is not evidence.
            #
            # Presence was not enough. A real adoption closed a task whose only evidence was an
            # Arabic "to be filled later" -- the field was filled, the reviews were not, and by the
            # time they happened the task sat in completed/, where it is immutable and could not be
            # reopened. The gate now reads the text, not just the field.
            #
            # Three shapes: a bracketed prompt copied from the template, an English "not yet" word,
            # and its Arabic equivalents. The bracket form is this repository's own convention from
            # check-placeholders -- five characters or more, starting with a letter, and not a
            # markdown link, so `[the upload path](src/upload.ts)` still counts as evidence.
            #
            # The Arabic alternatives are built from codepoints on purpose: every .ps1 here is pure
            # ASCII, because Windows PowerShell 5.1 parses a BOM-less script as ANSI and would
            # corrupt a literal before it was ever compared. Same reason selftest.ps1 does it.
            $arFillDiacritic = [string][char]0x064A + [char]0x064F + [char]0x0645 + [char]0x0644 + [char]0x0623  # "to be filled"
            $arFillPlain     = [string][char]0x064A + [char]0x0645 + [char]0x0644 + [char]0x0623                 # same, undiacritised
            $arLater         = [string][char]0x0644 + [char]0x0627 + [char]0x062D + [char]0x0642 + [char]0x0627  # "later"
            $evBracket = '\[[A-Za-z][^\]]{4,}\]([^(]|$)'
            $evWords   = '(^|[^A-Za-z])(TBD|TODO|FIXME)([^A-Za-z]|$)|to be (filled|completed|done)|fill (in )?later|placeholder|' +
                         [regex]::Escape($arFillDiacritic) + '|' + [regex]::Escape($arFillPlain) + '|' + [regex]::Escape($arLater)

            $evidence = @{}
            $placeholderRoles = @{}
            # [ \t] and not \s: in .NET, \s matches a newline, so an EMPTY evidence value let the
            # match run past the end of its line and capture the NEXT one as the detail --
            # "- `security-reviewer`:" followed by "- Promoted roles: (none)" archived the task on
            # Windows while POSIX, which reads line by line, refused it. A gate whose verdict
            # depends on the platform is the failure this gate exists to prevent. Same house rule
            # as policy.entrypoints.forbiddenPatterns in the manifest: spell the intent, do not
            # inherit it from an engine default.
            foreach ($m in [regex]::Matches($taskContent, '(?m)^[ \t]*-[ \t]*`([a-z-]+)`[ \t]*:[ \t]*(.+)$')) {
                $detail = $m.Groups[2].Value.Trim()
                $role = $m.Groups[1].Value
                if (-not $detail) { continue }
                if ($detail -match '^`?\[.*\]`?$' -or $detail -match $evBracket -or $detail -match $evWords) {
                    $placeholderRoles[$role] = $true
                    continue
                }
                $evidence[$role] = $true
            }

            foreach ($tag in $tags) {
                if (-not $known.ContainsKey($tag)) { continue }
                $role = $known[$tag]
                if (-not $enforced.ContainsKey($role)) { continue }
                if (-not $evidence.ContainsKey($role)) {
                    # "Missing" and "still a placeholder" are different problems, and telling an
                    # agent its evidence is missing while it is looking at a filled line teaches it
                    # to distrust the gate.
                    if ($placeholderRoles.ContainsKey($role)) {
                        $blockers.Add("placeholder role evidence scope tag '$tag' needs real evidence from ``$role`` under '$($compliance.evidenceField)' -- say what was reviewed and what came of it; template text does not satisfy the gate")
                    } else {
                        $blockers.Add("missing role evidence scope tag '$tag' requires evidence from ``$role`` under '$($compliance.evidenceField)'")
                    }
                }
            }
        }
    }
}

if ($blockers.Count -gt 0) {
    Write-Output "Task is NOT ready to close: $resolvedTask"
    Write-Output ''
    $blockers | ForEach-Object { Write-Output "  - $_" }
    Write-Output ''
    Write-Output 'Fix these, or keep the task active and record the blocker honestly.'
    Write-Output 'See .ai/contract/lifecycle.md section 6 for the full Definition of Done.'
    exit 2
}

# --- Discovery awareness: records, never blocks -------------------------------------------------
# new-task refuses to OPEN an active task while the project is undefined. Closing is different:
# .ai/contract/discovery.md section 1 forbids starting work, not finishing work already started.
# Blocking closure here would strand every task the override legitimately created, and would push
# people to archive by hand -- which destroys the record this directory exists to keep.
#
# So closure proceeds, and the circumstance is written down. The rule about what counts as
# "undefined" is not restated here; check-placeholders is asked, exactly as new-task asks it.
$gateBlocking = 0
$gateChecker = Join-Path -Path $repoRoot -ChildPath 'scripts\validation\check-placeholders.ps1'
if (Test-Path -LiteralPath $gateChecker -PathType Leaf) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $gateOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gateChecker -FailOnBlocking 2>&1 | Out-String
    $gateCode = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($gateCode -ne 0) {
        $gateBlocking = -1
        $m = [regex]::Match($gateOutput, '(\d+)\s+blocking marker')
        if ($m.Success) { $gateBlocking = [int]$m.Groups[1].Value }
    }
}
$hasOverride = $taskContent -match '(?m)^##\s+Discovery Gate Override\s*$'
$needsGateNote = ($gateBlocking -ne 0) -and (-not $hasOverride)

if ($Check) {
    Write-Output "Task passes the mechanical completion gates: $resolvedTask"
    if ($gateBlocking -ne 0) {
        if ($hasOverride) {
            Write-Output "Note: the project is still undefined ($gateBlocking blocking marker(s)). This task carries a Discovery Gate Override."
        } else {
            Write-Output "Note: the project is still undefined ($gateBlocking blocking marker(s)) and this task carries no Discovery Gate Override."
            Write-Output '      Closing it will append a Discovery Gate Note recording that. Closure is not blocked.'
        }
    }
    if ($profileNote) {
        Write-Output "Note: this task has $profileNote, so profile role evidence was not checked."
    }
    Write-Output 'Nothing was moved (-Check). The remaining Definition of Done conditions are yours to verify.'
    exit 0
}

$completedTaskDir = Join-Path -Path $repoRoot -ChildPath '.ai\tasks\completed'
if (-not (Test-Path -LiteralPath $completedTaskDir -PathType Container)) {
    Write-Error "Completed task directory not found: $completedTaskDir"
    exit 1
}

$taskDestination = Join-Path -Path $completedTaskDir -ChildPath (Split-Path -Path $resolvedTask -Leaf)
if (Test-Path -LiteralPath $taskDestination) {
    Write-Error "Refusing to overwrite completed task: $taskDestination"
    exit 1
}

$relatedPlan = Get-RelatedPlanPath -RepoRoot $repoRoot -Content $taskContent
$planDestination = $null
if ($relatedPlan -and (Test-Path -LiteralPath $relatedPlan -PathType Leaf)) {
    $completedPlanDir = Join-Path -Path $repoRoot -ChildPath '.ai\plans\completed'
    if (-not (Test-Path -LiteralPath $completedPlanDir -PathType Container)) {
        Write-Error "Completed plan directory not found: $completedPlanDir"
        exit 1
    }
    $planDestination = Join-Path -Path $completedPlanDir -ChildPath (Split-Path -Path $relatedPlan -Leaf)
    if (Test-Path -LiteralPath $planDestination) {
        Write-Error "Refusing to overwrite completed plan: $planDestination"
        exit 1
    }
}

if ($needsGateNote) {
    # Written while the task is still in active/ -- completed/ is an immutable archive, denied to
    # the write tools by .claude/settings.json, and it should stay that way.
    $closedOn = Get-Date -Format 'yyyy-MM-dd'
    $note = @"

## Discovery Gate Note

Recorded automatically by ``scripts/ai/finish-task`` at closure on ``$closedOn``.

This task was closed while the project was still undefined: $gateBlocking blocking placeholder
marker(s) remained in always-loaded context, and the task carried no ``Discovery Gate Override``.
It was therefore opened either before the gate existed or outside it.

``.ai/contract/discovery.md`` section 1 governs *opening* work, not closing it, so closure was not
blocked. This note exists so the archive does not imply the project was defined at the time.
"@
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($resolvedTask, ($note -replace "`r`n", "`n"), $encoding)
}

if ($PSCmdlet.ShouldProcess($resolvedTask, "Move task to $taskDestination")) {
    Move-Item -LiteralPath $resolvedTask -Destination $taskDestination
}

if ($relatedPlan -and (Test-Path -LiteralPath $relatedPlan -PathType Leaf)) {
    if ($PSCmdlet.ShouldProcess($relatedPlan, "Move related plan to $planDestination")) {
        Move-Item -LiteralPath $relatedPlan -Destination $planDestination
    }
}

Write-Output "Archived task -> $taskDestination"
if ($planDestination) {
    Write-Output "Archived plan -> $planDestination"
}
if ($profileNote) {
    Write-Output "Note: this task has $profileNote, so profile role evidence was not checked."
}
if ($needsGateNote) {
    Write-Output "DISCOVERY GATE NOTE appended: closed with $gateBlocking blocking marker(s) and no override."
} elseif ($gateBlocking -ne 0 -and $hasOverride) {
    Write-Output "Closed under a recorded Discovery Gate Override ($gateBlocking blocking marker(s) remain)."
}
Write-Output ''
Write-Output 'Reminder: this script checked 5 mechanical gates. The Definition of Done has 11'
Write-Output 'conditions. Confirm the other 6 in your final report, with evidence.'
exit 0
