<#
.SYNOPSIS
    Builds a deterministic, self-contained context package for handoff to another agent or session.

.DESCRIPTION
    Concatenates the operating contract core, the project context, and the named task and plan
    into a single Markdown document. Refuses to include oversized files or files containing
    secret-like content.

    Use when transferring work across tools, models, or people. Do not use inside an ongoing
    session where the files are already loaded -- that is redundant context, which
    .ai/contract/core.md section 10 tells you to avoid.

.PARAMETER Minimal
    Omit the contract and context files that every session in this project already loads.
    Use for a handoff inside the same project.

.PARAMETER Force
    Overwrite an existing output file. Without it, the script refuses rather than destroying
    a previous package.
#>
[CmdletBinding()]
param(
    [string]$TaskPath,
    [string]$PlanPath,
    [string]$OutputPath,
    [int]$MaxFileBytes = 65536,
    [switch]$IncludeDocumentation,

    # Omits the contract and context files that every session in this project already
    # loads. Use it for a handoff inside the same project; use full mode only when the
    # receiving environment cannot be trusted to read CLAUDE.md and .ai/context/ itself.
    [switch]$Minimal,
    [switch]$Force
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

function ConvertTo-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $root = $RepoRoot.TrimEnd('\') + '\'
    if ($FullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($root.Length)
    }
    return $FullPath
}

function Set-Utf8NoBomContent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Get-SecretLikeLines {
    # AllowEmptyString and AllowEmptyCollection are load-bearing on Windows PowerShell 5.1:
    # a Mandatory [string[]] there rejects the whole argument if ANY element is an empty
    # string. Every markdown file has blank lines, so without these this function -- and
    # therefore build-context.ps1 -- fails on the first file it is given.
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $patterns = @(
        '-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----',
        '\b(AKIA|ASIA)[0-9A-Z]{16}\b',
        '(?i)aws_secret_access_key\s*[:=]\s*\S{20,}',
        '\bgh[pousr]_[A-Za-z0-9]{30,}\b',
        '\bsk_(live|test)_[0-9A-Za-z]{20,}\b',
        '(?i)\b(api[_-]?key|secret|password|access[_-]?token|client[_-]?secret)\b\s*[:=]\s*["''][^"''\s]{12,}["'']',
        '(?i)\b(postgres|postgresql|mysql|mongodb(\+srv)?|redis|amqp)://[^:\s/]+:[^@\s]{6,}@'
    )

    # Conventional placeholders are documentation, not secrets.
    $placeholder = '(?i)(example|placeholder|change[_-]?me|your[_-][a-z0-9_-]*|goes[_-]?here|xxx+|\.\.\.|<[^>]+>|\$\{[^}]+\}|\{\{[^}]+\}\}|dummy|redacted|sample|test[_-]?only|fake|TBD)'

    $hits = @()
    $n = 0
    foreach ($line in $Lines) {
        $n++
        foreach ($pattern in $patterns) {
            if ([regex]::IsMatch($line, $pattern)) {
                if ([regex]::IsMatch($line, $placeholder)) { break }
                $hits += "line $n"
                break
            }
        }
    }
    return $hits
}

function Get-SafeFence {
    param([Parameter(Mandatory = $true)][string]$Content)

    # A fence must be longer than the longest backtick run inside the content,
    # otherwise a fenced block in an included file terminates the wrapper early.
    $longest = 0
    foreach ($m in [regex]::Matches($Content, '`+')) {
        if ($m.Value.Length -gt $longest) { $longest = $m.Value.Length }
    }
    $length = [Math]::Max(3, $longest + 1)
    return ('`' * $length)
}

function Add-ContextFile {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$MaxBytes
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Context file not found: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -gt $MaxBytes) {
        throw "Refusing to include large file ($($item.Length) bytes): $Path"
    }

    # -Encoding UTF8 is load-bearing on Windows PowerShell 5.1: without it, a BOM-less UTF-8
    # file -- which is every file in this repository -- is read as ANSI/CP1252, so an em-dash
    # arrives as three characters and Arabic arrives as ruins. The package then stores that
    # mojibake as valid UTF-8, which is worse than a crash: the handoff reads fine and lies.
    $content = (Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8).TrimEnd()
    $secretHits = Get-SecretLikeLines -Lines ($content -split "`r?`n")
    if ($secretHits.Count -gt 0) {
        throw "Refusing to include file with secret-like content: $Path ($($secretHits -join ', ')). Remove or parameterize the value, then retry."
    }

    $fence = Get-SafeFence -Content $content
    $relative = ConvertTo-RelativePath -RepoRoot $RepoRoot -FullPath $item.FullName
    [void]$script:lines.Add("")
    [void]$script:lines.Add("## $relative")
    [void]$script:lines.Add("")
    [void]$script:lines.Add("$fence markdown")
    [void]$script:lines.Add($content)
    [void]$script:lines.Add($fence)
}

if ($MaxFileBytes -lt 1024) {
    Write-Error 'MaxFileBytes must be at least 1024.'
    exit 1
}

$repoRoot = Get-RepositoryRoot
$script:lines = [System.Collections.Generic.List[string]]::new()
[void]$script:lines.Add('# AI Context Package')
[void]$script:lines.Add("")
[void]$script:lines.Add("- Repository: $repoRoot")
if ($Minimal) {
    [void]$script:lines.Add("- Scope: MINIMAL -- the work only. The receiving agent is expected to load the")
    [void]$script:lines.Add("  contract and context itself, exactly as any session in this project does.")
} else {
    [void]$script:lines.Add("- Scope: core context, active task, optional plan, and selected indexes")
}

$coreFiles = @(
    '.ai/contract/core.md',
    '.ai/context/project.md',
    '.ai/context/constraints.md',
    '.ai/context/stack.md',
    '.ai/context/structure.md',
    '.ai/rules/README.md',
    '.ai/tasks/README.md',
    '.ai/plans/README.md'
)

# Full mode repeats what every session already loads. That is right for a transfer into an
# environment that cannot be trusted to read CLAUDE.md, and pure waste inside this project.
$embedFiles = @()
if (-not $Minimal) { $embedFiles = $coreFiles }
foreach ($relative in $embedFiles) {
    Add-ContextFile -RepoRoot $repoRoot -Path (Join-Path -Path $repoRoot -ChildPath $relative) -MaxBytes $MaxFileBytes
}

if ($TaskPath) {
    $resolvedTask = Resolve-RepositoryPath -RepoRoot $repoRoot -Path $TaskPath
    Add-ContextFile -RepoRoot $repoRoot -Path $resolvedTask -MaxBytes $MaxFileBytes
}

if ($PlanPath) {
    $resolvedPlan = Resolve-RepositoryPath -RepoRoot $repoRoot -Path $PlanPath
    Add-ContextFile -RepoRoot $repoRoot -Path $resolvedPlan -MaxBytes $MaxFileBytes
}

if ($IncludeDocumentation) {
    $docFiles = @(
        'docs/README.md',
        'docs/product/README.md',
        'docs/architecture/README.md',
        'docs/domains/README.md',
        'docs/design/README.md',
        'docs/operations/README.md'
    )
    foreach ($relative in $docFiles) {
        Add-ContextFile -RepoRoot $repoRoot -Path (Join-Path -Path $repoRoot -ChildPath $relative) -MaxBytes $MaxFileBytes
    }
}

$output = ($script:lines -join [Environment]::NewLine) + [Environment]::NewLine

if ($OutputPath) {
    $resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path -Path $repoRoot -ChildPath $OutputPath }
    $outputDir = Split-Path -Path $resolvedOutput -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        Write-Error "Output directory not found: $outputDir"
        exit 1
    }
    if ((Test-Path -LiteralPath $resolvedOutput) -and (-not $Force)) {
        Write-Error "Refusing to overwrite existing context package: $resolvedOutput. Pass -Force to replace it."
        exit 1
    }
    Set-Utf8NoBomContent -Path $resolvedOutput -Value $output
    Write-Output "Wrote context package to $resolvedOutput"
} else {
    # Stdout goes through the console codepage on Windows PowerShell 5.1, which mangles
    # non-ASCII on redirect. Emit UTF-8 so a captured stream carries the same bytes
    # -OutputPath writes. Some hosts refuse the assignment; the package content is already
    # correct either way, so that is not fatal.
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    Write-Output $output
}

exit 0
