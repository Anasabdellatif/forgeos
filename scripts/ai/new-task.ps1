[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [ValidateSet('task', 'bug')]
    [string]$Type = 'task',

    [ValidateSet('inbox', 'active')]
    [string]$Status = 'inbox',

    [ValidateSet('critical', 'high', 'medium', 'low')]
    [string]$Priority = 'medium',

    [string]$Owner = 'unassigned',

    # .ai/contract/discovery.md section 1 forbids opening a task in .ai/tasks/active/ while the
    # project is still undefined. Nothing measured that, so the rule was bypassable by accident.
    # This override exists because a human may legitimately decide otherwise -- but it is never
    # silent: it demands a reason and writes the whole circumstance into the task file.
    [switch]$AcknowledgeDiscoveryGate,

    [string]$OverrideReason
)

$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    $root = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
    return $root.Path
}

function New-SafeSlug {
    param([Parameter(Mandatory = $true)][string]$Value)

    $slug = $Value.Trim().ToLowerInvariant()
    $slug = [regex]::Replace($slug, '[^\p{L}\p{Nd}]+', '-')
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = 'untitled'
    }
    if ($slug.Length -gt 80) {
        $slug = $slug.Substring(0, 80).Trim('-')
    }
    return $slug
}

function Set-Utf8NoBomContent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

$repoRoot = Get-RepositoryRoot
$templateName = if ($Type -eq 'bug') { 'bug-template.md' } else { 'task-template.md' }
$templatePath = Join-Path -Path $repoRoot -ChildPath ".ai\tasks\templates\$templateName"
$targetDir = Join-Path -Path $repoRoot -ChildPath ".ai\tasks\$Status"

if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    Write-Error "Template not found: $templatePath"
    exit 1
}
if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
    Write-Error "Target task directory not found: $targetDir"
    exit 1
}

# --- Discovery gate --------------------------------------------------------------------------
# Only 'active' is gated. 'inbox' is the correct destination for work captured before discovery
# finishes -- the contract wants requests recorded, not lost, it just forbids starting them.
$gateBlocking = 0
$gateOverridden = $false

if ($Status -eq 'active') {
    $checker = Join-Path -Path $repoRoot -ChildPath 'scripts\validation\check-placeholders.ps1'
    $gateReadable = $false

    if (Test-Path -LiteralPath $checker -PathType Leaf) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $gateOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $checker -FailOnBlocking 2>&1 | Out-String
        $gateCode = $LASTEXITCODE
        $ErrorActionPreference = $previous

        $gateReadable = $true
        if ($gateCode -eq 0) {
            $gateBlocking = 0
        } else {
            $gateBlocking = -1
            $m = [regex]::Match($gateOutput, '(\d+)\s+blocking marker')
            if ($m.Success) { $gateBlocking = [int]$m.Groups[1].Value }
        }
    }

    if (-not $gateReadable) {
        # Refuse rather than guess. Opening an active task is deliberate and infrequent, so the
        # safe direction is closed -- unlike a per-write hook, where that would be intolerable.
        Write-Output 'Cannot measure the discovery gate: scripts/validation/check-placeholders.ps1 not found.'
        Write-Output 'Refusing to open an active task without knowing whether the project is defined.'
        exit 2
    }

    if ($gateBlocking -ne 0) {
        if (-not $AcknowledgeDiscoveryGate) {
            Write-Output "REFUSED: this project is still undefined -- $gateBlocking blocking placeholder marker(s) remain."
            Write-Output ''
            Write-Output '.ai/contract/discovery.md section 1: while the project is undefined, opening a task in'
            Write-Output '.ai/tasks/active/ is forbidden. The interview is the only permitted activity.'
            Write-Output ''
            Write-Output 'Do one of these:'
            Write-Output '  1. Capture it without starting it:  -Status inbox'
            Write-Output '  2. Finish discovery, then open it:  .ai/contract/discovery.md'
            Write-Output '  3. Override deliberately, with a reason recorded in the task file:'
            Write-Output '       -Status active -AcknowledgeDiscoveryGate -OverrideReason "<why>"'
            exit 2
        }

        if ([string]::IsNullOrWhiteSpace($OverrideReason)) {
            Write-Output 'REFUSED: -AcknowledgeDiscoveryGate requires -OverrideReason.'
            Write-Output 'An override with no stated reason is a silent override, which is the thing this check exists to prevent.'
            exit 2
        }

        $gateOverridden = $true
    }
}

$date = Get-Date -Format 'yyyy-MM-dd'
$slug = New-SafeSlug -Value $Title
$targetPath = Join-Path -Path $targetDir -ChildPath "$date-$slug.md"

if (Test-Path -LiteralPath $targetPath) {
    Write-Error "Refusing to overwrite existing task: $targetPath"
    exit 1
}

$content = Get-Content -LiteralPath $templatePath -Raw
$content = $content.Replace('[Title]', $Title)
$content = $content.Replace('Status: `inbox`', "Status: ``$Status``")
$content = $content.Replace('Priority: `[critical / high / medium / low]`', "Priority: ``$Priority``")
$content = $content.Replace('Owner: `[person or agent]`', "Owner: ``$Owner``")
$content = $content.Replace('Created: `[YYYY-MM-DD]`', "Created: ``$date``")
$content = $content.Replace('Updated: `[YYYY-MM-DD]`', "Updated: ``$date``")
$content = $content.Replace('Reported: `[YYYY-MM-DD]`', "Reported: ``$date``")

if ($gateOverridden) {
    $trace = @"

## Discovery Gate Override

**This task was opened while the project was still undefined.** When it was created on ``$date``,
$gateBlocking blocking placeholder marker(s) remained in always-loaded context.

``.ai/contract/discovery.md`` section 1 forbids opening a task in ``.ai/tasks/active/`` before
discovery completes. That rule was overridden deliberately, with human authorization, by passing
``-AcknowledgeDiscoveryGate``.

**Reason given:** $OverrideReason

Anyone reviewing this task should read its acceptance criteria knowing they were written against a
project whose requirements were not yet fully defined. If the criteria and the finished discovery
disagree, discovery wins.
"@
    $content = $content.TrimEnd() + "`n" + $trace
}

Set-Utf8NoBomContent -Path $targetPath -Value $content
Write-Output "Created $Type at $targetPath"
if ($gateOverridden) {
    Write-Output "DISCOVERY GATE OVERRIDDEN: $gateBlocking blocking marker(s). The reason is recorded in the task file."
}
exit 0
