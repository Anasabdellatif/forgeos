<#
.SYNOPSIS
    Verifies that repository-relative file paths referenced from Markdown actually resolve.

.DESCRIPTION
    A reference to a file that does not exist sends an agent somewhere empty and costs it a whole
    turn to discover that. Broken references are the most common form of documentation rot, and
    they are entirely mechanical to catch.

    Checks two reference forms:
      - Markdown links: [text](path/to/file.md)
      - Backticked paths: `path/to/file.md`

    Ignores external URLs, anchors, and the illustrative paths in examples/ that describe a
    fictional project. Those exclusions are declared in the manifest, not hardcoded.

    Also runs a PORTABILITY pass. Resolving here is not enough: a file in the portable half is
    copied into every adopting project, so a reference it makes to something sync never places
    resolves in this repository and breaks in all of them. That is invisible to an existence check
    run here, and it is the first thing an adopting project sees.

    Exit 0 when every reference resolves and every portable reference travels, 1 otherwise.
#>
[CmdletBinding()]
param(
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    $root = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    return $root.Path
}

$repoRoot = Get-RepositoryRoot
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'scripts\lib\blueprint-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$config = $manifest.linkCheck

$ignorePrefixes = @($config.ignorePrefixes)
$ignorePatterns = @($config.ignorePathPatterns)

# Portability sets: everything sync actually places in an adopting project -- the portable half,
# plus the scaffolding it seeds. A file that lands there and references something that does not
# resolves here and breaks there. See the portability pass below.
$dist = $manifest.distribution
$portableDirs = @($dist.portable)
$sourceOnlyPaths = @()
if ($dist.PSObject.Properties.Name -contains 'sourceOnly') { $sourceOnlyPaths = @($dist.sourceOnly) }
$availableFiles = @{}
foreach ($f in (@($dist.portableFiles) + @($dist.seedFiles))) { $availableFiles[$f] = $true }

function Test-PathPortable {
    param([string]$Path)
    # Source-only first: release tooling sits inside a portable directory but is dropped by
    # sync, so requiring its references to travel would fail on paths no adopter receives.
    foreach ($q in $sourceOnlyPaths) {
        if (-not $q) { continue }
        if ($Path -eq $q -or $Path.StartsWith("$q/", [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    if ($availableFiles.ContainsKey($Path)) { return $true }
    foreach ($dir in $portableDirs) {
        if ($Path.StartsWith("$dir/")) { return $true }
    }
    return $false
}

# A seeded file can still be the PROJECT'S. sync places docs/README.md and .ai/context/project.md
# once, and from that moment they belong to the project: it fills them with references to its own
# documentation, which the blueprint neither knows nor distributes. Judging those references by the
# portability rule fails every real adoption -- found by a dry run against a project whose
# docs/README.md points at docs/Client/, docs/Developer/, docs/data/.
#
# So projectSpecific decides who OWNS a file, and ownership decides whether the portability rule
# applies to what it references. It does not exempt the file from link checking: a broken link in
# a project's own index is still broken, and is still reported.
$projectOwned = @($dist.projectSpecific)

function Test-PathProjectOwned {
    param([string]$Path)
    foreach ($p in $projectOwned) {
        if ($Path -eq $p -or $Path.StartsWith("$p/", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# Collect the Markdown files to scan.
$files = [System.Collections.Generic.List[string]]::new()
foreach ($name in $config.includeRootFiles) {
    $p = Join-Path -Path $repoRoot -ChildPath $name
    if (Test-Path -LiteralPath $p -PathType Leaf) { $files.Add($p) }
}
foreach ($root in $config.roots) {
    $p = Join-Path -Path $repoRoot -ChildPath ($root -replace '/', '\')
    if (Test-Path -LiteralPath $p -PathType Container) {
        Get-ChildItem -LiteralPath $p -Recurse -File -Filter '*.md' | ForEach-Object { $files.Add($_.FullName) }
    }
}

# A reference worth checking is a *path* -- it contains a separator and ends in a known extension.
# A bare filename such as `core.md` is prose shorthand inside an already-established context, not
# a claim about location, so checking it would produce noise instead of findings.
$pathShape = '^[A-Za-z0-9_.][A-Za-z0-9_./\-]*/[A-Za-z0-9_.\-]+\.(md|ps1|sh|json|ya?ml|txt)$'

$broken = [System.Collections.Generic.List[psobject]]::new()
$unportable = [System.Collections.Generic.List[psobject]]::new()
$checked = 0

function Test-Ignored {
    param([string]$Path)
    foreach ($prefix in $ignorePrefixes) {
        if ($Path.StartsWith($prefix)) { return $true }
    }
    foreach ($pattern in $ignorePatterns) {
        if ([regex]::IsMatch($Path, $pattern)) { return $true }
    }
    return $false
}

foreach ($file in $files) {
    $fileRel = $file.Substring($repoRoot.Length + 1).Replace('\', '/')
    $fileDir = Split-Path -Path $file -Parent
    $fileIsPortable = (Test-PathPortable -Path $fileRel) -and -not (Test-PathProjectOwned -Path $fileRel)
    $lineNumber = 0

    foreach ($line in (Get-Content -LiteralPath $file)) {
        $lineNumber++

        $references = @()

        # Markdown links: [text](target)
        foreach ($m in [regex]::Matches($line, '\[[^\]]*\]\(([^)\s]+)\)')) {
            $references += $m.Groups[1].Value
        }
        # Backticked paths: `target`
        foreach ($m in [regex]::Matches($line, '`([^`\s]+)`')) {
            $references += $m.Groups[1].Value
        }

        foreach ($ref in $references) {
            $target = ($ref -split '#')[0].Trim()
            if ([string]::IsNullOrWhiteSpace($target)) { continue }
            if (Test-Ignored -Path $target) { continue }
            if ($target -notmatch $pathShape) { continue }

            $checked++

            # Resolve relative to the referencing file first, then to the repository root. The
            # portability pass needs the repository-relative form, not the reference as written:
            # `architecture/decisions.md` inside docs/ is docs/architecture/decisions.md.
            $candidateA = Join-Path -Path $fileDir -ChildPath ($target -replace '/', '\')
            $candidateB = Join-Path -Path $repoRoot -ChildPath ($target -replace '/', '\')

            $targetRel = $null
            if (Test-Path -LiteralPath $candidateA) {
                $resolved = (Resolve-Path -LiteralPath $candidateA).Path
                if ($resolved.StartsWith($repoRoot)) {
                    $targetRel = $resolved.Substring($repoRoot.Length + 1).Replace('\', '/')
                }
            } elseif (Test-Path -LiteralPath $candidateB) {
                $targetRel = $target
            }

            if ($null -eq $targetRel) {
                $broken.Add([pscustomobject]@{
                    File   = $fileRel
                    Line   = $lineNumber
                    Target = $target
                })
                continue
            }

            # Portability: a file that lands in an adopting project may reference only what also
            # lands there. Anything else resolves here -- where the whole repository exists -- and
            # breaks on the first adoption, which is the one place nobody was looking.
            if ($fileIsPortable -and -not (Test-PathPortable -Path $targetRel)) {
                $unportable.Add([pscustomobject]@{
                    File   = $fileRel
                    Line   = $lineNumber
                    Target = $targetRel
                })
            }
        }
    }
}

$failed = $false

if ($broken.Count -gt 0) {
    $failed = $true
    Write-Output "Link check FAILED  ($checked reference(s) checked, $($broken.Count) broken)"
    Write-Output ''
    $broken | Sort-Object File, Line | ForEach-Object {
        Write-Output ("  {0}:{1}  ->  {2}" -f $_.File, $_.Line, $_.Target)
    }
    Write-Output ''
    Write-Output 'Fix the path, create the file, or add the pattern to linkCheck.ignorePathPatterns'
    Write-Output 'in scripts/lib/blueprint-manifest.json if the reference is deliberately illustrative.'
}

if ($unportable.Count -gt 0) {
    $failed = $true
    if ($broken.Count -gt 0) { Write-Output '' }
    Write-Output "Portability check FAILED  ($($unportable.Count) portable file reference(s) that sync does not place)"
    Write-Output ''
    $unportable | Sort-Object File, Line | ForEach-Object {
        Write-Output ("  {0}:{1}  ->  {2}" -f $_.File, $_.Line, $_.Target)
    }
    Write-Output ''
    Write-Output 'These resolve in this repository and break in every adopting project. State the'
    Write-Output 'fact inline, or point at a portable file or a seeded one -- see distribution in'
    Write-Output 'scripts/lib/blueprint-manifest.json.'
}

if ($failed) { exit 1 }

Write-Output "Link check passed  ($checked reference(s) checked across $($files.Count) file(s), 0 broken, 0 unportable)"
exit 0
