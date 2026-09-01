<#
.SYNOPSIS
    Detects secret-like content in files changed during the session.

.DESCRIPTION
    Runs as a Stop hook: once per turn, over every file Git reports as modified, added, or
    untracked. Exit 2 reports the findings to the agent so the value is removed before it is
    committed.

    Runs once per turn instead of once per write. An earlier design ran on PostToolUse for every
    Write and Edit; measured at ~280 ms of process startup per call, that cost more than it caught.
    Coverage is identical because every written file appears in git status.

    Also accepts a PostToolUse payload with tool_input.file_path, in which case it scans only that
    file. Kept so the script can be wired either way.

    Never prints the matched value. Reports the file, the line number, and the pattern name only.

.PARAMETER ScanTree
    Validation mode: scan every git-tracked file, read no stdin, and exit 1 on findings.

    This mode exists because the hook modes are useless in CI. A fresh checkout has nothing in
    git status, so a Stop-mode run would scan zero files and pass -- a security check that passes
    because it examined nothing is worse than no check. The patterns live here once and all three
    modes share them; a second copy under scripts/validation/ would be a second home for the one
    fact that matters most.

.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
    Wire up in .claude/settings.json under hooks.Stop.
#>
[CmdletBinding()]
param(
    [switch]$ScanTree
)

$ErrorActionPreference = 'Stop'

$patterns = @(
    @{ Name = 'Private key block';      Pattern = '-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----' }
    @{ Name = 'AWS access key id';      Pattern = '\b(AKIA|ASIA)[0-9A-Z]{16}\b' }
    @{ Name = 'AWS secret access key';  Pattern = '(?i)aws_secret_access_key\s*[:=]\s*\S{20,}' }
    @{ Name = 'GitHub token';           Pattern = '\bgh[pousr]_[A-Za-z0-9]{30,}\b' }
    @{ Name = 'Slack token';            Pattern = '\bxox[abposr]-[A-Za-z0-9-]{10,}\b' }
    @{ Name = 'Google API key';         Pattern = '\bAIza[0-9A-Za-z_\-]{35}\b' }
    @{ Name = 'Stripe secret key';      Pattern = '\bsk_(live|test)_[0-9A-Za-z]{20,}\b' }
    @{ Name = 'JSON Web Token';         Pattern = '\bey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b' }
    @{ Name = 'Generic assigned secret';Pattern = '(?i)\b(api[_-]?key|secret|passwd|password|access[_-]?token|auth[_-]?token|client[_-]?secret)\b\s*[:=]\s*["''][^"''\s]{12,}["'']' }
    @{ Name = 'Database URL with password'; Pattern = '(?i)\b(postgres|postgresql|mysql|mongodb(\+srv)?|redis|amqp)://[^:\s/]+:[^@\s]{6,}@' }
)

# Values that look like secrets but are conventional placeholders.
$placeholderPattern = '(?i)(example|placeholder|change[_-]?me|your[_-][a-z0-9_-]*|goes[_-]?here|insert[_-]?[a-z]*[_-]?here|xxx+|\.\.\.|<[^>]+>|\$\{[^}]+\}|\{\{[^}]+\}\}|dummy|redacted|sample|test[_-]?only|fake|noop|TBD)'

# Files that contain secret-shaped text by design.
$skipPattern = '(?i)[\\/](scripts[\\/]hooks|scripts[\\/]validation)[\\/]|[\\/]\.ai[\\/]rules[\\/](security|ai-safety)\.md$|[\\/]examples[\\/]'

# Extensions worth scanning. Binary and lock files are noise.
$scanExtensions = @(
    '.md', '.txt', '.json', '.yml', '.yaml', '.toml', '.ini', '.cfg', '.conf', '.xml',
    '.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx', '.py', '.rb', '.go', '.rs', '.java',
    '.kt', '.cs', '.php', '.sh', '.ps1', '.sql', '.env', '.tf', '.tfvars', '.properties'
)

function Get-FileFindings {
    param([Parameter(Mandatory = $true)][string]$Path)

    $findings = @()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $findings }
    if ($Path -match $skipPattern) { return $findings }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -gt 2MB) { return $findings }
    if ($scanExtensions -notcontains $item.Extension.ToLowerInvariant()) { return $findings }

    $lineNumber = 0
    try {
        foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
            $lineNumber++
            if ($line.Length -gt 4000) { continue }
            foreach ($p in $patterns) {
                if ([regex]::IsMatch($line, $p.Pattern)) {
                    if ([regex]::IsMatch($line, $placeholderPattern)) { continue }
                    $findings += "  {0}:{1}  {2}" -f $Path, $lineNumber, $p.Name
                    break
                }
            }
        }
    } catch {
        return $findings
    }
    return $findings
}

$payload = $null
if (-not $ScanTree) {
    # Only read stdin in hook mode. In validation mode there is no payload and this would block.
    try {
        $raw = [Console]::In.ReadToEnd()
        $payload = if ([string]::IsNullOrWhiteSpace($raw)) { $null } else { $raw | ConvertFrom-Json }
    } catch {
        exit 0
    }

    # A Stop hook that exits 2 makes Claude continue. Without this guard that is an infinite loop.
    if ($payload -and $payload.PSObject.Properties.Name -contains 'stop_hook_active' -and $payload.stop_hook_active) {
        exit 0
    }
}

$targets = @()

if ($ScanTree) {
    # Validation mode: every git-tracked file in the committed tree.
    $projectDir = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    Push-Location -LiteralPath $projectDir
    try {
        $ErrorActionPreference = 'Continue'
        $tracked = & git ls-files 2>$null
        if ($LASTEXITCODE -ne 0) {
            # A freshly synced project is not a repository yet, and this is the first command an
            # adopting project runs. Say what to do, not just what is wrong.
            Write-Output 'This check requires a git repository: it scans the git-tracked tree.'
            Write-Output "Run 'git init' in the project root, commit or stage the files, then re-run validation."
            exit 1
        }
        foreach ($rel in $tracked) {
            if ($rel) { $targets += (Join-Path -Path $projectDir -ChildPath ($rel -replace '/', '\')) }
        }
    } finally {
        Pop-Location
        $ErrorActionPreference = 'Stop'
    }
} elseif ($payload -and $payload.tool_input -and $payload.tool_input.file_path) {
    # PostToolUse mode: a single file.
    $targets = @($payload.tool_input.file_path)
} else {
    # Stop mode: every file Git reports as changed or untracked.
    $projectDir = $env:CLAUDE_PROJECT_DIR
    if ([string]::IsNullOrWhiteSpace($projectDir)) {
        $projectDir = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    }

    Push-Location -LiteralPath $projectDir
    try {
        $ErrorActionPreference = 'Continue'
        $status = & git status --porcelain --untracked-files=all 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $status) { exit 0 }

        foreach ($line in $status) {
            if ($line.Length -lt 4) { continue }
            $state = $line.Substring(0, 2)
            if ($state -eq 'D ' -or $state -eq ' D') { continue }
            $relative = $line.Substring(3).Trim('"')
            if ($relative -match '\s->\s') { $relative = ($relative -split '\s->\s')[-1] }
            $targets += (Join-Path -Path $projectDir -ChildPath $relative)
        }
    } finally {
        Pop-Location
        $ErrorActionPreference = 'Stop'
    }
}

$allFindings = @()
foreach ($target in ($targets | Select-Object -Unique)) {
    $allFindings += Get-FileFindings -Path $target
}

if ($allFindings.Count -gt 0) {
    $joined = $allFindings -join [Environment]::NewLine
    $message = @"
SECRET-LIKE CONTENT DETECTED by blueprint hook (scripts/hooks/scan-secrets.ps1).

$joined

Required action, per .ai/rules/security.md section 1:
  1. Remove the value from the file now. Do not commit it.
  2. Do not print or echo the value anywhere.
  3. Replace it with an environment variable or a secret-manager reference.
  4. If the value is real and was ever committed, tell the user it must be rotated.

If this is a false positive (a documented placeholder), say so explicitly and continue.
"@
    [Console]::Error.WriteLine($message)
    # Validation semantics are exit 1; hook semantics are exit 2.
    if ($ScanTree) {
        Write-Output "Secret scan FAILED  ($($allFindings.Count) finding(s))"
        exit 1
    }
    exit 2
}

if ($ScanTree) {
    Write-Output "Secret scan passed  ($($targets.Count) tracked file(s) considered, 0 findings)"
}

exit 0
