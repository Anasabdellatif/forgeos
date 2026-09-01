<#
.SYNOPSIS
    Detects unexpected empty or whitespace-only source and documentation files.

.DESCRIPTION
    An empty required file passes a naive existence check while telling an agent nothing.
    This catches both truly empty files and files that contain only whitespace.

    Exit 0 when nothing unexpected is found, 1 otherwise.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    $root = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    return $root.Path
}

function ConvertTo-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $root = $RepoRoot.TrimEnd('\') + '\'
    if ($FullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($root.Length).Replace('\', '/')
    }
    return $FullPath
}

$repoRoot = Get-RepositoryRoot
$extensions = @('.md', '.ps1', '.sh', '.json', '.yml', '.yaml')
$excludePattern = '[\\/](\.git|node_modules|dist|build|coverage|\.venv|venv|__pycache__|target|\.next|\.turbo)[\\/]'

# Extensions where a UTF-8 BOM is a defect rather than a cosmetic detail. Measured, not assumed:
#   .sh    -- a BOM before the shebang breaks execution outright
#             ("bom.sh: line 1: <BOM>#!/usr/bin/env: No such file or directory"),
#             and `bash -n` passes it silently, so the syntax gate cannot catch this class.
#   .json  -- python3 json.load raises "Unexpected UTF-8 BOM"; jq tolerates it, so a host
#             without jq fails while a host with it passes. That divergence broke check-all.sh.
#   .yml / .yaml -- precautionary. PyYAML tolerated a BOM in testing; other consumers may not,
#             and these files are machine-parsed configuration.
# .md and .ps1 are deliberately excluded: a BOM there is harmless, and a check that fails on
# harmless input is a check that gets disabled.
$bomSensitive = @('.sh', '.json', '.yml', '.yaml')

$empty = [System.Collections.Generic.List[string]]::new()
$whitespaceOnly = [System.Collections.Generic.List[string]]::new()
$withBom = [System.Collections.Generic.List[string]]::new()

$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force |
    Where-Object {
        ($extensions -contains $_.Extension.ToLowerInvariant()) -and
        ($_.FullName -notmatch $excludePattern)
    }

foreach ($file in $files) {
    $relative = ConvertTo-RelativePath -RepoRoot $repoRoot -FullPath $file.FullName

    if ($file.Length -eq 0) {
        $empty.Add($relative)
        continue
    }

    if ($file.Length -le 512) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($null -ne $content -and [string]::IsNullOrWhiteSpace($content)) {
            $whitespaceOnly.Add($relative)
        }
    }

    # Read only the first three bytes. Never load or print the content.
    if (($bomSensitive -contains $file.Extension.ToLowerInvariant()) -and $file.Length -ge 3) {
        $stream = [System.IO.File]::OpenRead($file.FullName)
        try {
            $head = New-Object byte[] 3
            $read = $stream.Read($head, 0, 3)
            if ($read -eq 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF) {
                $withBom.Add($relative)
            }
        } finally {
            $stream.Dispose()
        }
    }
}

$total = $empty.Count + $whitespaceOnly.Count + $withBom.Count

if ($total -gt 0) {
    if ($empty.Count -gt 0) {
        Write-Output 'Empty files:'
        $empty | Sort-Object | ForEach-Object { Write-Output "  - $_" }
    }
    if ($whitespaceOnly.Count -gt 0) {
        Write-Output 'Whitespace-only files:'
        $whitespaceOnly | Sort-Object | ForEach-Object { Write-Output "  - $_" }
    }
    if ($withBom.Count -gt 0) {
        Write-Output 'Files starting with a UTF-8 BOM:'
        $withBom | Sort-Object | ForEach-Object { Write-Output "  - $_" }
        Write-Output ''
        Write-Output 'A BOM before a shebang stops a shell script from running, and python3 refuses'
        Write-Output 'to parse JSON that starts with one. Re-save each file as UTF-8 without BOM.'
    }
    Write-Output ''
    Write-Output "Empty-file check FAILED  ($total file(s))"
    Write-Output 'A required file that exists but says nothing is worse than a missing one: it passes'
    Write-Output 'the structure check while giving every future agent no information.'
    exit 1
}

Write-Output "Empty-file check passed  ($($files.Count) file(s) scanned, 0 empty, 0 with BOM)"
exit 0
