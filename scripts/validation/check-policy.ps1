<#
.SYNOPSIS
    Verifies that the controls living in .claude/settings.json are actually present, and that the
    .claude/ adapter layer contains no rules of its own.

.DESCRIPTION
    Two checks that protect two accepted design decisions.

    1. Permission controls. Immutable-archive, secret-file, and key-material protection moved out
       of a hook into deny rules because the harness enforces those with zero process startup.
       A control that moves out of a tested hook must not become an untested one. This verifies
       every required deny and ask rule is present, and that both hook events are wired.

    2. Adapter discipline. .claude/ is an adapter, not a home for rules -- the load-bearing
       constraint recorded in the project decision log.
       Every adapter file must reference .ai/. Without this check that constraint is documentation
       only, and documentation does not stop a contributor from writing a rule in the wrong place.

    Exit 0 when both hold, 1 otherwise.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    $root = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    return $root.Path
}

$repoRoot = Get-RepositoryRoot
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'scripts\lib\blueprint-manifest.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Error "Manifest not found: $manifestPath"
    exit 1
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$policy = $manifest.policy
$failures = [System.Collections.Generic.List[string]]::new()
$okCount = 0

# --- 1. Permission and hook controls ----------------------------------------------------------

$settingsPath = Join-Path -Path $repoRoot -ChildPath ($policy.settingsFile -replace '/', '\')
if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    $failures.Add("Settings file not found: $($policy.settingsFile)")
} else {
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    } catch {
        $failures.Add("Settings file is not valid JSON: $($policy.settingsFile)")
        $settings = $null
    }

    if ($settings) {
        $deny = @()
        if ($settings.permissions -and $settings.permissions.deny) { $deny = @($settings.permissions.deny) }
        foreach ($rule in $policy.requiredDeny) {
            if ($deny -contains $rule) { $okCount++ } else { $failures.Add("Missing deny rule: $rule") }
        }

        $ask = @()
        if ($settings.permissions -and $settings.permissions.ask) { $ask = @($settings.permissions.ask) }
        foreach ($rule in $policy.requiredAsk) {
            if ($ask -contains $rule) { $okCount++ } else { $failures.Add("Missing ask rule: $rule") }
        }

        foreach ($event in $policy.requiredHooks) {
            if ($settings.hooks -and $settings.hooks.PSObject.Properties.Name -contains $event) {
                $okCount++
            } else {
                $failures.Add("Missing hook event: $event")
            }
        }

        # An event being declared is not the same as a guard being wired: a settings file can
        # list PreToolUse and reference nothing. Assert each hook script by name.
        $settingsRaw = Get-Content -LiteralPath $settingsPath -Raw
        foreach ($script in @($policy.requiredHookScripts)) {
            if ($settingsRaw -match [regex]::Escape($script)) {
                $okCount++
            } else {
                $failures.Add("Hook script not wired in $($policy.settingsFile): $script")
            }
        }
    }
}

# --- 1b. Thin entrypoints ----------------------------------------------------------------------
# CLAUDE.md and AGENTS.md are the only files an agent is guaranteed to read, which makes them the
# most tempting place to restate a rule "for salience" and the least visible place for that copy to
# drift. It already happened once, undetected for two versions.

$entrypoints = $policy.entrypoints
if ($entrypoints) {
    foreach ($name in @($entrypoints.files)) {
        $path = Join-Path -Path $repoRoot -ChildPath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $failures.Add("Entrypoint not found: $name")
            continue
        }

        $lines = @(Get-Content -LiteralPath $path)

        if ($lines.Count -gt $entrypoints.maxLines) {
            $failures.Add("Entrypoint too long: $name has $($lines.Count) lines, limit $($entrypoints.maxLines). Move the content into .ai/ and link to it.")
        } else {
            $okCount++
        }

        if ($lines -join "`n" | Select-String -SimpleMatch -Pattern $entrypoints.mustReference -Quiet) {
            $okCount++
        } else {
            $failures.Add("Entrypoint does not reference $($entrypoints.mustReference): $name")
        }

        foreach ($heading in @($entrypoints.forbiddenHeadings)) {
            $hit = @($lines | Where-Object { $_.TrimEnd() -eq $heading })
            if ($hit.Count -gt 0) {
                $failures.Add("Entrypoint carries a rules section: $name has '$heading'. That subject is owned by .ai/contract/ or .ai/rules/.")
            }
        }
        $okCount++

        foreach ($pattern in @($entrypoints.forbiddenPatterns)) {
            $hit = @($lines | Where-Object { $_ -match $pattern })
            if ($hit.Count -gt 0) {
                $failures.Add("Entrypoint restates contract rules: $name matches /$pattern/ on $($hit.Count) line(s). Link to .ai/contract/core.md instead of copying it.")
            }
        }
        $okCount++
    }
}

# --- 2. Adapter discipline ---------------------------------------------------------------------

$exempt = @($policy.adapter.exempt)
$reference = $policy.adapter.mustReference

foreach ($dir in $policy.adapter.directories) {
    $full = Join-Path -Path $repoRoot -ChildPath ($dir -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        $failures.Add("Adapter directory not found: $dir")
        continue
    }

    Get-ChildItem -LiteralPath $full -Recurse -File -Filter '*.md' | ForEach-Object {
        $rel = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
        if ($exempt -contains $rel) { return }

        $content = Get-Content -LiteralPath $_.FullName -Raw
        if ($content -like "*$reference*") {
            $okCount++
        } else {
            $failures.Add("Adapter file does not reference '$reference' (a rule may have been written here instead of in .ai/): $rel")
        }
    }
}

# --- 3. Adapter thinness ------------------------------------------------------------------------
#
# Referencing .ai/ is necessary but not sufficient. An adapter can cite its source and restate it
# in different words -- which is what happened before v1.2.0, at up to 2.1x the size of the file
# it pointed at, with zero literal duplicate lines so no diff could show it.
#
# Rules are grouped per surface: a role adapter needs only a pointer, while a slash command
# legitimately carries the concrete invocations for two shells. One limit for both would be wrong.

foreach ($group in @($policy.adapter.thin)) {
    if (-not $group) { continue }
    $forbidden = @($group.forbiddenHeadings)
    $maxLines = [int]$group.maxLines

    foreach ($dir in $group.directories) {
        $full = Join-Path -Path $repoRoot -ChildPath ($dir -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }

        Get-ChildItem -LiteralPath $full -Recurse -File -Filter '*.md' | ForEach-Object {
            $rel = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
            if ($exempt -contains $rel) { return }

            $lines = @(Get-Content -LiteralPath $_.FullName)
            if ($lines.Count -gt $maxLines) {
                $failures.Add("Adapter is too long ($($lines.Count) lines, limit $maxLines for $($group.name)) -- move the content to .ai/ and point at it: $rel")
            } else {
                $okCount++
            }

            foreach ($heading in $forbidden) {
                $hit = $lines | Where-Object { $_.TrimEnd() -eq $heading }
                if ($hit) {
                    $failures.Add("Adapter carries an operational section '$heading' -- that belongs in .ai/, not here: $rel")
                }
            }
        }
    }
}

# --- 3b. Source/adapter pairing -----------------------------------------------------------------
#
# An adapter with no source in .ai/ is a second knowledge source by definition. A source with no
# adapter is a role Claude Code cannot dispatch. Both directions are failures.

foreach ($pair in @($policy.adapter.pairing)) {
    if (-not $pair) { continue }
    $srcDir = Join-Path -Path $repoRoot -ChildPath ($pair.source -replace '/', '\')
    $adpDir = Join-Path -Path $repoRoot -ChildPath ($pair.adapter -replace '/', '\')
    if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) { continue }
    if (-not (Test-Path -LiteralPath $adpDir -PathType Container)) { continue }

    $pairExempt = @($pair.exempt)
    $srcNames = @(Get-ChildItem -LiteralPath $srcDir -File -Filter '*.md' | Where-Object { $pairExempt -notcontains $_.Name } | ForEach-Object { $_.Name })
    $adpNames = @(Get-ChildItem -LiteralPath $adpDir -File -Filter '*.md' | Where-Object { $pairExempt -notcontains $_.Name } | ForEach-Object { $_.Name })

    foreach ($n in $srcNames) {
        if ($adpNames -contains $n) {
            $okCount++
        } else {
            $failures.Add("Role has no Claude adapter, so it cannot be dispatched: $($pair.source)/$n has no $($pair.adapter)/$n")
        }
    }
    foreach ($n in $adpNames) {
        if ($srcNames -notcontains $n) {
            $failures.Add("Adapter has no source, which makes it a second knowledge source: $($pair.adapter)/$n has no $($pair.source)/$n")
        }
    }
}

# --- 4. Source-of-truth discipline --------------------------------------------------------------
#
# docs/ owns project facts; .ai/context/ summarizes and links. Deliberately dumb: it checks that
# the pointer is present and that a known-duplicated heading has not come back. It cannot catch a
# paraphrase, and is not meant to.

$sot = $manifest.sourceOfTruth
if ($sot -and $sot.summaries) {
    $reference = $sot.summaries.mustReference

    foreach ($rel in $sot.summaries.files) {
        $path = Join-Path -Path $repoRoot -ChildPath ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $failures.Add("Context summary is missing: $rel")
            continue
        }

        $lines = @(Get-Content -LiteralPath $path)

        if (($lines -join "`n") -like "*$reference*") {
            $okCount++
        } else {
            $failures.Add("Context summary does not point at '$reference' -- it may have become a source of truth instead of a summary: $rel")
        }

        foreach ($heading in $sot.summaries.forbiddenHeadings) {
            $pattern = '^#{1,6}\s+' + [regex]::Escape($heading) + '\s*$'
            if ($lines | Where-Object { $_ -match $pattern }) {
                $failures.Add("Context summary carries a section '$heading' that docs/ owns -- summarize and link instead: $rel")
            }
        }
    }
}

# --- 4b. Profile integrity ----------------------------------------------------------------------
#
# A profile that names a role which does not exist is a lie. A profile that never points at docs/
# has started to become a source of truth instead of a selector. Roles are read from frontmatter,
# so the check is exact rather than a guess over prose.

if ($sot -and $sot.profiles) {
    $prof = $sot.profiles
    $profDir = Join-Path -Path $repoRoot -ChildPath ($prof.directory -replace '/', '\')
    $roleDir = Join-Path -Path $repoRoot -ChildPath ($prof.roleDirectory -replace '/', '\')
    $profExempt = @($prof.exempt)

    if ((Test-Path -LiteralPath $profDir -PathType Container) -and (Test-Path -LiteralPath $roleDir -PathType Container)) {
        $knownRoles = @(Get-ChildItem -LiteralPath $roleDir -File -Filter '*.md' |
            Where-Object { $_.Name -ne 'README.md' } | ForEach-Object { $_.BaseName })

        Get-ChildItem -LiteralPath $profDir -File -Filter '*.md' | ForEach-Object {
            if ($profExempt -contains $_.Name) { return }
            $rel = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
            $content = Get-Content -LiteralPath $_.FullName -Raw

            if ($content -like "*$($prof.mustReference)*") {
                $okCount++
            } else {
                $failures.Add("Profile never points at '$($prof.mustReference)' -- it may be becoming a source of truth instead of a selector: $rel")
            }

            $named = 0
            foreach ($key in $prof.roleKeys) {
                $m = [regex]::Match($content, "(?m)^\s*$([regex]::Escape($key))\s*:\s*\[(.*?)\]")
                if (-not $m.Success) { continue }
                foreach ($role in ($m.Groups[1].Value -split ',')) {
                    $role = $role.Trim()
                    if (-not $role) { continue }
                    $named++
                    if ($knownRoles -contains $role) {
                        $okCount++
                    } else {
                        $failures.Add("Profile names a role that does not exist in $($prof.roleDirectory)/: '$role' in $rel")
                    }
                }
            }
            if ($named -eq 0) {
                $failures.Add("Profile declares no roles in frontmatter ($($prof.roleKeys -join ' / ')): $rel")
            }
        }
    }
}

# --- 5. Open-questions register -----------------------------------------------------------------
#
# An operational file may mention an assumption or an open question, but it must send the reader
# to the single register in the same file. Otherwise the knowledge lands where nobody will look.

if ($sot -and $sot.openQuestions) {
    $oq = $sot.openQuestions
    $oqExempt = @($oq.exempt)
    $markerRegex = '(?i)(' + (($oq.markers | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'

    foreach ($dir in $oq.scanDirectories) {
        $full = Join-Path -Path $repoRoot -ChildPath ($dir -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }

        Get-ChildItem -LiteralPath $full -Recurse -File -Filter '*.md' | ForEach-Object {
            $rel = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
            if ($oqExempt -contains $rel) { return }

            $content = Get-Content -LiteralPath $_.FullName -Raw
            if ($content -notmatch $markerRegex) { return }

            if ($content -like "*$($oq.register)*") {
                $okCount++
            } else {
                $failures.Add("File records an assumption or open question but never points at $($oq.register): $rel")
            }
        }
    }
}

# --- 6. Source-only classification ---------------------------------------------------------------
#
# A source-only path is release tooling: carried by this repository, never copied into a project.
# It lives inside a portable directory because the discovery gate permits writes nowhere else, so
# nothing about its location says "do not distribute" -- only this declaration does. Verify the
# declaration is not contradicted elsewhere in the manifest, and that it points at something real.
# A classification that names a path nobody created protects an empty space.

$soRole = ''
$soVersionPath = Join-Path $repoRoot 'blueprint.version'
if (Test-Path -LiteralPath $soVersionPath) {
    $soVerText = Get-Content -LiteralPath $soVersionPath -Raw -Encoding UTF8
    $soRoleMatch = [regex]::Match($soVerText, '"role"[ 	]*:[ 	]*"([^"]+)"')
    if ($soRoleMatch.Success) { $soRole = $soRoleMatch.Groups[1].Value }
}
$srcOnly = @()
if ($manifest.distribution.PSObject.Properties.Name -contains 'sourceOnly') {
    $srcOnly = @($manifest.distribution.sourceOnly)
}
foreach ($so in $srcOnly) {
    if (-not $so) { continue }
    $soBad = $false
    # The assertion is role-dependent, and getting that wrong broke every adopter of v1.15.0+:
    # a source-only path exists HERE and must be ABSENT there, so requiring existence everywhere
    # reported the classification working as if it had failed. Both directions are checked now,
    # which makes the adopted side a leak detector rather than a false alarm.
    $soPath = Join-Path $repoRoot ($so -replace '/', '\')
    if ($soRole -eq 'source') {
        if (-not (Test-Path -LiteralPath $soPath)) {
            $failures.Add("Source-only path does not exist: $so"); $soBad = $true
        }
    } elseif (Test-Path -LiteralPath $soPath) {
        $failures.Add("Source-only path reached this project: $so"); $soBad = $true
    }
    foreach ($p in @($manifest.distribution.portableFiles)) {
        if ($p -eq $so -or $p.StartsWith("$so/")) {
            $failures.Add("Source-only path is also a portable file: $p"); $soBad = $true
        }
    }
    foreach ($p in @($manifest.distribution.seedFiles)) {
        if ($p -eq $so -or $p.StartsWith("$so/")) {
            $failures.Add("Source-only path is also a seed file: $p"); $soBad = $true
        }
    }
    if (-not $soBad) { $okCount++ }
}

# --- Report ------------------------------------------------------------------------------------

if ($failures.Count -gt 0) {
    Write-Output "Policy check FAILED  ($okCount ok, $($failures.Count) failed)"
    Write-Output ''
    $failures | ForEach-Object { Write-Output "  - $_" }
    Write-Output ''
    Write-Output 'A missing deny rule means a control that used to be enforced no longer is.'
    Write-Output 'An adapter file with no .ai/ reference means the single-source-of-truth design has'
    Write-Output 'started to drift -- write the rule in .ai/ and point to it from here.'
    exit 1
}

Write-Output "Policy check passed  ($okCount control(s) verified: permissions, hooks, adapter discipline, source-of-truth summaries, open-questions register, source-only classification)"
exit 0
