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

# CONTAINMENT. A path may reach outside its permitted root through `..` or through a link, so the
# RESOLVED target is what gets checked, never the text. GetFullPath collapses traversal; the reparse
# walk catches a junction or symlink planted inside the root, which Windows PowerShell 5.1 cannot
# resolve on its own. Returns the resolved path, or an empty string when it escapes.
function Resolve-ContainedPath {
    param([string]$Path, [string]$Root)
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    } catch { return '' }
    if (-not $full.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return '' }
    # Walk from the root down to the file: a reparse point anywhere on the way can leave the root.
    $cursor = Split-Path -Path $full -Parent
    while ($cursor -and $cursor.Length -ge $rootFull.Length) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
            if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return '' }
        }
        $parent = Split-Path -Path $cursor -Parent
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $leafItem = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        if ($leafItem -and ($leafItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return '' }
    }
    return $full
}

# A task names its plan in ONE metadata line; everything else on that line is prose. The rules: one
# line only, `none` (with or without an explanation after it) means no plan, a path is the single
# backticked token, and it must live under .ai/plans/. Anything ambiguous refuses instead of
# guessing. The defect this replaces: a line reading "Related plan: `docs/roadmap.md` section M-0"
# resolved to the project's roadmap, and closing that task archived the ROADMAP as a plan.
function Resolve-RelatedPlan {
    param(
        # No Mandatory here: a task file's blank lines arrive as empty strings, and a mandatory
        # [string[]] rejects an empty element before the function ever runs.
        [string]$RepoRoot,
        [AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines
    )

    $result = @{ Relative = ''; Resolved = ''; Blocker = ''; Note = '' }
    $planLines = @($Lines | Where-Object { $_ -match '^\s*-\s*Related plan:' })
    if ($planLines.Count -eq 0) { return $result }
    if ($planLines.Count -gt 1) {
        $result.Blocker = "ambiguous related plan  $($planLines.Count) 'Related plan:' lines; exactly one is allowed"
        return $result
    }

    $value = ($planLines[0] -replace '^[^:]*:\s*', '').Trim()
    $lower = ($value -replace '`', '').ToLowerInvariant()
    if ($lower -eq '[path or none]' -or $lower -eq 'none' -or $lower -match '^none[^a-z0-9]') { return $result }

    $ticks = ([regex]::Matches($value, '`')).Count
    $reference = ''
    if ($ticks -ge 4) {
        $result.Blocker = 'ambiguous related plan  more than one quoted path on the line'
        return $result
    } elseif ($ticks -ge 2) {
        $reference = [regex]::Match($value, '`([^`]+)`').Groups[1].Value.Trim()
    } else {
        $candidate = ($value -split '\s+')[0]
        if ($candidate -like '*.md') {
            $reference = $candidate
        } else {
            $result.Note = 'the Related plan line is prose, not a path; no plan was archived'
            return $result
        }
    }

    $relative = $reference -replace '\\', '/'
    $rootForward = ($RepoRoot -replace '\\', '/').TrimEnd('/')
    if ($relative.StartsWith($rootForward + '/')) {
        $relative = $relative.Substring($rootForward.Length + 1)
    } elseif ([System.IO.Path]::IsPathRooted($relative)) {
        $relative = ''
    }
    if ($relative.StartsWith('./')) { $relative = $relative.Substring(2) }

    if (-not $relative.StartsWith('.ai/plans/')) {
        $result.Blocker = "out-of-scope plan       '$reference' is not under .ai/plans/; refusing to archive it"
        return $result
    }

    # The prefix above is the text. This is the fact: `.ai/plans/../../docs/roadmap.md` passes any
    # prefix test and IS the roadmap.
    $candidate = Join-Path -Path $RepoRoot -ChildPath ($relative -replace '/', '\')
    $plansRoot = Join-Path -Path $RepoRoot -ChildPath '.ai\plans'
    $contained = Resolve-ContainedPath -Path $candidate -Root $plansRoot
    if (-not $contained) {
        $escaped = $candidate
        try { $escaped = [System.IO.Path]::GetFullPath($candidate) } catch { }
        $result.Blocker = "out-of-scope plan       '$reference' resolves outside .ai/plans/ -> $escaped"
        return $result
    }

    $result.Relative = $relative
    $result.Resolved = $contained
    return $result
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

# CONTAINMENT, before anything else reads the file: a file that is not a task must never be
# archived as one, and `..` or a link must not reach out of .ai/tasks/.
$tasksRoot = Join-Path -Path $repoRoot -ChildPath '.ai\tasks'
$containedTask = Resolve-ContainedPath -Path $resolvedTask -Root $tasksRoot
if (-not $containedTask) {
    $shownTask = $resolvedTask
    try { $shownTask = [System.IO.Path]::GetFullPath($resolvedTask) } catch { }
    [Console]::Error.WriteLine("Refusing: the task resolves outside .ai/tasks/ -> $shownTask")
    [Console]::Error.WriteLine('Only a record inside .ai/tasks/ can be closed.')
    exit 1
}
$resolvedTask = $containedTask

# A record can exist in BOTH active/ and completed/ when a closure was interrupted between writing
# the archive and removing the original. That is not "already closed", and it is not a plain refusal
# either: it is one of two states, told apart by content, never by filename.
#
#   recoverable  the archive is this record plus exactly the changes a closure makes
#   conflicting  anything else -- someone edited a copy, or they are different records
function Get-NormalizedRecord {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $ds = $false; $du = $false; $dp = $false; $gate = $false
    $out = foreach ($line in $lines) {
        if ($line -match '^##\s+Discovery Gate Note\s*$') { $gate = $true }
        if ($gate) { continue }
        if (-not $ds -and $line -match '^\s*-\s*Status:') { $ds = $true; '- Status: <closure>' }
        elseif (-not $du -and $line -match '^\s*-\s*Updated:') { $du = $true; '- Updated: <closure>' }
        elseif (-not $dp -and $line -match '^\s*-\s*Related plan:') { $dp = $true; '- Related plan: <closure>' }
        else { $line }
    }
    return ($out -join "`n")
}

$taskLeaf = Split-Path -Path $resolvedTask -Leaf
$activeTwin = Join-Path -Path $repoRoot -ChildPath (".ai\tasks\active\" + $taskLeaf)
$archivedTwin = Join-Path -Path $repoRoot -ChildPath (".ai\tasks\completed\" + $taskLeaf)

if ((Test-Path -LiteralPath $activeTwin -PathType Leaf) -and (Test-Path -LiteralPath $archivedTwin -PathType Leaf)) {
    if ((Get-NormalizedRecord -Path $activeTwin) -ceq (Get-NormalizedRecord -Path $archivedTwin)) {
        if ($Check) {
            Write-Output "Interrupted closure: $(($activeTwin -replace [regex]::Escape($repoRoot + '\'), '') -replace '\\', '/') and its archive are the same record."
            Write-Output 'Running without -Check would remove the active copy and finish the closure.'
            Write-Output 'Nothing was moved or edited (-Check).'
            exit 0
        }
        try {
            Remove-Item -LiteralPath $activeTwin -Force -ErrorAction Stop
        } catch {
            [Console]::Error.WriteLine("Could not remove $activeTwin; both copies remain.")
            exit 1
        }
        Write-Output "Recovered an interrupted closure: removed $(($activeTwin -replace [regex]::Escape($repoRoot + '\'), '') -replace '\\', '/')"
        Write-Output "The archive at $(($archivedTwin -replace [regex]::Escape($repoRoot + '\'), '') -replace '\\', '/') was already complete and was not touched."
        exit 0
    }
    [Console]::Error.WriteLine("CONFLICT: two different records share the name $taskLeaf.")
    [Console]::Error.WriteLine("  active:   $(($activeTwin -replace [regex]::Escape($repoRoot + '\'), '') -replace '\\', '/')")
    [Console]::Error.WriteLine("  archived: $(($archivedTwin -replace [regex]::Escape($repoRoot + '\'), '') -replace '\\', '/')")
    [Console]::Error.WriteLine('They differ by more than a closure would change, so neither was touched.')
    [Console]::Error.WriteLine('Compare them yourself, keep the one that is right, and remove the other.')
    exit 2
}

# Closing something already closed is a repeat, not an error: an interrupted session reruns the same
# command, and the archive must not be touched for it.
if (($resolvedTask -replace '\\', '/') -match '/\.ai/tasks/completed/') {
    $shown = ($resolvedTask -replace '\\', '/')
    $rootForward = ($repoRoot -replace '\\', '/').TrimEnd('/')
    if ($shown.StartsWith($rootForward + '/')) { $shown = $shown.Substring($rootForward.Length + 1) }
    Write-Output "Already closed: $shown"
    Write-Output 'Nothing to do. The archive was not touched.'
    exit 0
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

# Gate 6 -- validation evidence must be observed. Pending or unknown is not success.
# The archive is read later as proof that something ran; a field reading "unknown" or "not run" is
# proof of nothing. It must carry a result, or be waived deliberately and in writing.
$evidenceSection = $false
foreach ($line in $taskLines) {
    if ($line -match '^##\s+Completion Evidence') { $evidenceSection = $true; continue }
    if ($line -match '^##\s') { $evidenceSection = $false }
    if (-not $evidenceSection) { continue }
    if ($line -match '^\s*-\s*(Commands executed|Results|Final diff reviewed)\s*:(.*)$') {
        $field = $Matches[1]
        $value = ($Matches[2] -replace '`', '').Trim().ToLowerInvariant()
        # A waiver is an exception someone wrote down, not a word that switches the gate off. It
        # must say WHY, in its own words. Text cannot authenticate who allowed it, and this script
        # never claims to: it checks that a human sentence is there to review.
        if ($value -like 'waived:*') {
            # The contract's "a check that could not be run is documented with the reason and the
            # residual risk" (lifecycle.md section 6), in a shape a script can check:
            #   waived: scope=<this field>; reason=<why>; risk=<what may bite>; ref=<a file here>
            # Structure and resolution are verified. Authorship is not: this cannot authenticate who
            # allowed the exception, and it cannot prove a command ran. A waiver covers its own field.
            $body = $value.Substring('waived:'.Length).Trim()
            $wScope = ''; $wReason = ''; $wRisk = ''; $wRef = ''
            foreach ($part in ($body -split ';')) {
                if ($part -notmatch '=') { continue }
                $key = ($part -split '=', 2)[0].Trim().ToLowerInvariant()
                $val = ($part -split '=', 2)[1].Trim()
                switch ($key) {
                    'scope'  { $wScope = $val }
                    'reason' { $wReason = $val }
                    'risk'   { $wRisk = $val }
                    'ref'    { $wRef = $val }
                }
            }
            $fieldName = $field.ToLowerInvariant()
            if (-not $wScope -or -not $wReason -or -not $wRisk -or -not $wRef) {
                $blockers.Add("waiver is malformed    ${field}: expected 'waived: scope=...; reason=...; risk=...; ref=...'")
            } elseif ($wScope.ToLowerInvariant() -ne $fieldName) {
                $blockers.Add("waiver scope mismatch  ${field}: the waiver names scope '$wScope', not this field")
            } elseif ($wReason.Length -lt 12) {
                $blockers.Add("waiver without a reason ${field}: the reason must say why, in at least 12 characters")
            } elseif ($wRisk.Length -lt 6) {
                $blockers.Add("waiver without a risk  ${field}: the residual risk must be stated")
            } elseif ($wReason -match '^(pending|unknown|tbd|todo|later|not run|not yet|n/a)') {
                $blockers.Add("waiver restates pending ${field}: '$wReason' is pending evidence wearing a waiver")
            } else {
                $refCandidate = Join-Path -Path $repoRoot -ChildPath ($wRef -replace '/', '\')
                $refContained = Resolve-ContainedPath -Path $refCandidate -Root $repoRoot
                if (-not $refContained) {
                    $blockers.Add("waiver reference escapes ${field}: ref '$wRef' resolves outside the repository")
                } elseif (-not (Test-Path -LiteralPath $refContained -PathType Leaf)) {
                    $blockers.Add("waiver reference missing ${field}: ref '$wRef' does not resolve to a file in this repository")
                }
            }
            continue
        }
        if ($value -in @('', 'unknown', 'not run', 'not yet', 'none', 'n/a', 'tbd', 'pending', 'no')) {
            $blockers.Add("unobserved evidence   ${field}: '$value' is not an observed result")
        }
    }
}

# The related plan, resolved structurally. A refusal here is a blocker like any other, so the task
# is reported unready and NOTHING is moved or edited.
$planResolution = Resolve-RelatedPlan -RepoRoot $repoRoot -Lines $taskLines
if ($planResolution.Blocker) { $blockers.Add($planResolution.Blocker) }
$planNote = $planResolution.Note

if ($blockers.Count -gt 0) {
    Write-Output "Task is NOT ready to close: $resolvedTask"
    Write-Output ''
    $blockers | ForEach-Object { Write-Output "  - $_" }
    Write-Output ''
    Write-Output 'Nothing was moved and nothing was edited.'
    Write-Output 'Fix these, or keep the task active and record the blocker honestly.'
    Write-Output 'See .ai/contract/lifecycle.md section 6 for the full Definition of Done.'
    exit 2
}

# --- Discovery awareness: records, never blocks -------------------------------------------------
# new-task refuses to OPEN an active task while the project is undefined. Closing is different:
# .ai/contract/discovery.md section 1 forbids starting work, not finishing work already started.
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

# Where each record is going, decided before anything moves. A plan that is missing, or that another
# active task still names, is reported rather than archived: one task's closure does not retire a
# plan its siblings are still working from.
$planFull = ''
if ($planResolution.Relative) {
    $candidate = $planResolution.Resolved
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $planNote = "the related plan $($planResolution.Relative) does not exist, so nothing was archived for it"
    } else {
        $planLeaf = Split-Path -Path $candidate -Leaf
        $activeDir = Join-Path -Path $repoRoot -ChildPath '.ai\tasks\active'
        $shared = 0
        if (Test-Path -LiteralPath $activeDir -PathType Container) {
            foreach ($other in @(Get-ChildItem -LiteralPath $activeDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
                # By leaf, not by full path: the same file can arrive as a short 8.3 path and as its
                # long form, and a task that counted ITSELF as a sibling would never archive its plan.
                if ($other.Name -eq (Split-Path -Path $resolvedTask -Leaf)) { continue }
                $otherText = Get-Content -LiteralPath $other.FullName -Raw -Encoding UTF8
                if ($otherText -and $otherText.Contains($planLeaf)) { $shared++ }
            }
        }
        # A forwarding record is not a plan: the plan it names was archived when its last active
        # task closed, so there is nothing left to archive here.
        if (@(Get-Content -LiteralPath $candidate -Encoding UTF8) -ccontains '- Status: `moved`') {
            $planNote = "$($planResolution.Relative) is a forwarding record; its plan was archived earlier and was not touched"
        } elseif ($shared -gt 0) {
            $planNote = "the related plan $($planResolution.Relative) is still named by $shared other active task(s), so it stays active"
        } elseif (@(Get-Content -LiteralPath $candidate -Encoding UTF8 | Where-Object { $_ -match '^\s*-\s*\[\s\]\s+' }).Count -gt 0) {
            # No other task names it, which says nothing about whether the PLAN is finished. Its own
            # unchecked items decide that, and the person closing the task decides what to do next.
            $planNote = "the related plan $($planResolution.Relative) still has unchecked items, so it stays active"
        } else {
            $planFull = $candidate
        }
    }
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

$planDestination = ''
if ($planFull) {
    $completedPlanDir = Join-Path -Path $repoRoot -ChildPath '.ai\plans\completed'
    if (-not (Test-Path -LiteralPath $completedPlanDir -PathType Container)) {
        Write-Error "Completed plan directory not found: $completedPlanDir"
        exit 1
    }
    $planDestination = Join-Path -Path $completedPlanDir -ChildPath (Split-Path -Path $planFull -Leaf)
    if (Test-Path -LiteralPath $planDestination) {
        Write-Error "Refusing to overwrite completed plan: $planDestination"
        exit 1
    }
}

function Get-RepoRelative {
    param([string]$RepoRoot, [string]$Path)
    $forward = $Path -replace '\\', '/'
    $rootForward = ($RepoRoot -replace '\\', '/').TrimEnd('/')
    if ($forward.StartsWith($rootForward + '/')) { return $forward.Substring($rootForward.Length + 1) }
    return $forward
}

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
    if ($profileNote) { Write-Output "Note: this task has $profileNote, so profile role evidence was not checked." }
    if ($planNote) { Write-Output "Note: $planNote." }
    Write-Output "Would set Status to completed and archive -> $(Get-RepoRelative -RepoRoot $repoRoot -Path $taskDestination)"
    if ($planDestination) { Write-Output "Would archive the plan -> $(Get-RepoRelative -RepoRoot $repoRoot -Path $planDestination)" }
    Write-Output 'Nothing was moved or edited (-Check). The remaining Definition of Done conditions are yours to verify.'
    exit 0
}

# --- Writing starts here ------------------------------------------------------------------------
# ORDER IS THE GUARANTEE. Both archives are written from staged copies FIRST; the originals keep
# their original bytes until both destinations exist. A failure therefore leaves the records exactly
# as they were, never an active record marked completed, and never a link to a plan that was not
# archived. This is recoverable-failure safety, not crash atomicity: a process killed between two
# file operations can still leave a copy in completed/ and the original in active/, which the
# already-closed answer and the refuse-to-overwrite check make safe to re-run and easy to see.
$today = Get-Date -Format 'yyyy-MM-dd'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$stageDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('forgeos-close-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

# The FIRST Status and Updated lines only: the task template carries a second Status inside its
# Blocked section, and that one answers a different question.
function Set-RecordState {
    param([string]$Path, [string]$State, [string]$Today, [System.Text.Encoding]$Encoding)
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $doneStatus = $false; $doneUpdated = $false
    $out = foreach ($line in $lines) {
        if (-not $doneStatus -and $line -match '^\s*-\s*Status:') { $doneStatus = $true; "- Status: ``$State``" }
        elseif (-not $doneUpdated -and $line -match '^\s*-\s*Updated:') { $doneUpdated = $true; "- Updated: ``$Today``" }
        else { $line }
    }
    [System.IO.File]::WriteAllText($Path, (($out -join "`n") + "`n"), $Encoding)
}

# Keep the forward link pointing at where the record actually went. A trailing annotation, if the
# line carries one, is preserved: it is the author's, not this script's.
function Set-RecordLink {
    param([string]$Path, [string]$Field, [string]$NewPath, [System.Text.Encoding]$Encoding)
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $done = $false
    $out = foreach ($line in $lines) {
        if (-not $done -and $line -match ('^\s*-\s*' + [regex]::Escape($Field) + ':')) {
            $done = $true
            $parts = $line -split '`'
            $tail = ''
            if ($parts.Count -ge 3) { $tail = $parts[2] }
            "- ${Field}: ``$NewPath``$tail"
        } else { $line }
    }
    [System.IO.File]::WriteAllText($Path, (($out -join "`n") + "`n"), $Encoding)
}

function Remove-StageDir {
    param([string]$Dir)
    foreach ($f in @('task.md', 'plan.md')) {
        $sf = Join-Path $Dir $f
        if (Test-Path -LiteralPath $sf) { Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Force -ErrorAction SilentlyContinue }
}

$stageTask = Join-Path $stageDir 'task.md'
try {
    Copy-Item -LiteralPath $resolvedTask -Destination $stageTask -ErrorAction Stop
} catch {
    [Console]::Error.WriteLine('Could not stage the task; nothing was changed.')
    Remove-StageDir -Dir $stageDir
    exit 1
}
Set-RecordState -Path $stageTask -State 'completed' -Today $today -Encoding $utf8NoBom
if ($planDestination) {
    Set-RecordLink -Path $stageTask -Field 'Related plan' -NewPath ('.ai/plans/completed/' + (Split-Path -Path $planFull -Leaf)) -Encoding $utf8NoBom
}

if ($needsGateNote) {
    $note = @"

## Discovery Gate Note

Recorded automatically by ``scripts/ai/finish-task`` at closure on ``$today``.

This task was closed while the project was still undefined: $gateBlocking blocking placeholder
marker(s) remained in always-loaded context, and the task carried no ``Discovery Gate Override``.
It was therefore opened either before the gate existed or outside it.

``.ai/contract/discovery.md`` section 1 governs *opening* work, not closing it, so closure was not
blocked. This note exists so the archive does not imply the project was defined at the time.
"@
    [System.IO.File]::AppendAllText($stageTask, ($note -replace "`r`n", "`n"), $utf8NoBom)
}

$stagePlan = ''
if ($planDestination) {
    $stagePlan = Join-Path $stageDir 'plan.md'
    try {
        Copy-Item -LiteralPath $planFull -Destination $stagePlan -ErrorAction Stop
    } catch {
        [Console]::Error.WriteLine('Could not stage the plan; nothing was changed.')
        Remove-StageDir -Dir $stageDir
        exit 1
    }
    Set-RecordState -Path $stagePlan -State 'completed' -Today $today -Encoding $utf8NoBom
    Set-RecordLink -Path $stagePlan -Field 'Related task' -NewPath ('.ai/tasks/completed/' + (Split-Path -Path $resolvedTask -Leaf)) -Encoding $utf8NoBom
}

function Get-RepoRelative {
    param([string]$RepoRoot, [string]$Path)
    $forward = $Path -replace '\\', '/'
    $rootForward = ($RepoRoot -replace '\\', '/').TrimEnd('/')
    if ($forward.StartsWith($rootForward + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $forward.Substring($rootForward.Length + 1) }
    return $forward
}

# Publish. Destinations first, originals afterwards.
try {
    Copy-Item -LiteralPath $stageTask -Destination $taskDestination -ErrorAction Stop
} catch {
    if (Test-Path -LiteralPath $taskDestination) { Remove-Item -LiteralPath $taskDestination -Force -ErrorAction SilentlyContinue }
    [Console]::Error.WriteLine("Could not write $taskDestination; nothing was closed and both records are unchanged.")
    Remove-StageDir -Dir $stageDir
    exit 1
}
if ($planDestination) {
    try {
        Copy-Item -LiteralPath $stagePlan -Destination $planDestination -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $taskDestination -Force -ErrorAction SilentlyContinue
        [Console]::Error.WriteLine("Could not write $planDestination; nothing was closed and both records are unchanged.")
        Remove-StageDir -Dir $stageDir
        exit 1
    }
}

$incomplete = $false
try {
    Remove-Item -LiteralPath $resolvedTask -Force -ErrorAction Stop
} catch {
    [Console]::Error.WriteLine("WARNING: the task was archived to $(Get-RepoRelative -RepoRoot $repoRoot -Path $taskDestination) but the original could not be removed.")
    [Console]::Error.WriteLine("         Both copies now exist. Remove $(Get-RepoRelative -RepoRoot $repoRoot -Path $resolvedTask) yourself to finish the closure.")
    $incomplete = $true
}
# Historical references keep resolving. Completed tasks named this plan at its ACTIVE path, and a
# completed record is immutable -- so instead of rewriting somebody's archive, the old path keeps a
# forwarding record saying where the plan went. It carries `Status: moved`, which the status readers
# skip, so it never counts as an active plan.
$planForward = ''
if ($planDestination) {
    $forwardRefs = 0
    $completedTaskDir = Join-Path -Path $repoRoot -ChildPath '.ai\tasks\completed'
    if (Test-Path -LiteralPath $completedTaskDir -PathType Container) {
        foreach ($past in @(Get-ChildItem -LiteralPath $completedTaskDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
            $pastText = Get-Content -LiteralPath $past.FullName -Raw -Encoding UTF8
            if ($pastText -and $pastText.Contains($planResolution.Relative)) { $forwardRefs++ }
        }
    }
    if ($forwardRefs -gt 0) {
        $planForward = $planFull
        $planLeafName = [System.IO.Path]::GetFileNameWithoutExtension($planFull)
        $archivedLeaf = Split-Path -Path $planDestination -Leaf
        $forwardText = @"
# Moved: $planLeafName

- Status: ``moved``
- Moved: ``$today``
- Now at: ``.ai/plans/completed/$archivedLeaf``

This file is a **forwarding record, not a plan**. The plan that lived here was archived when its
last active task closed. $forwardRefs completed task record(s) still name this path, and a completed
record is never rewritten, so this note keeps those references resolving.

Read the plan at its archived path above. Nothing should be added here.
"@
        [System.IO.File]::WriteAllText($planForward, ($forwardText -replace "`r`n", "`n"), $utf8NoBom)
    }
}

if ($planDestination -and -not $planForward) {
    try {
        Remove-Item -LiteralPath $planFull -Force -ErrorAction Stop
    } catch {
        [Console]::Error.WriteLine("WARNING: the plan was archived to $(Get-RepoRelative -RepoRoot $repoRoot -Path $planDestination) but the original could not be removed.")
        [Console]::Error.WriteLine("         Both copies now exist. Remove $(Get-RepoRelative -RepoRoot $repoRoot -Path $planFull) yourself to finish the closure.")
        $incomplete = $true
    }
}
Remove-StageDir -Dir $stageDir

Write-Output "Archived task -> $(Get-RepoRelative -RepoRoot $repoRoot -Path $taskDestination)"
if ($planDestination) { Write-Output "Archived plan -> $(Get-RepoRelative -RepoRoot $repoRoot -Path $planDestination)" }
if ($planForward) { Write-Output "Left a forwarding record -> $(Get-RepoRelative -RepoRoot $repoRoot -Path $planForward)" }

Write-Output ''
if ($profileNote) { Write-Output "Note: this task has $profileNote, so profile role evidence was not checked." }
if ($planNote) { Write-Output "Note: $planNote." }
if ($needsGateNote) {
    Write-Output "DISCOVERY GATE NOTE appended: closed with $gateBlocking blocking marker(s) and no override."
} elseif ($gateBlocking -ne 0 -and $hasOverride) {
    Write-Output "Closed under a recorded Discovery Gate Override ($gateBlocking blocking marker(s) remain)."
}
Write-Output 'Status set to completed. This script checked 6 mechanical gates; the Definition of Done has 11'
Write-Output 'conditions. Confirm the other 5 in your final report, with evidence.'
if ($incomplete) { exit 1 }
exit 0
