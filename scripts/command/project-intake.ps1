<#
.SYNOPSIS
    Project intake and forecast: what kind of project this is, how ready it is, and which prompt
    family the next session belongs to. Windows counterpart of project-intake.sh. M-26 slice 1.

.DESCRIPTION
    READ-ONLY, AND CHEAP BY CONSTRUCTION. The report is built from names, sizes, and presence. It
    opens exactly three small files -- blueprint.version for the role, .ai/context/project.md for a
    TBD marker, .ai/context/governance.json for codeAuthorized -- and never a governing document: all
    it learns about a specification is that it exists and how large it is. The directory scan is
    bounded: depth 3, dependency, build, and tooling directories pruned, at most 5000 directories.
    It writes nothing, authorizes nothing, opens no governance window, and reaches no network.

    THE SIGNAL NAMES ARE DETECTION DATA, NOT REQUIREMENTS. The core names no language or framework a
    project must use; a project matching none of the names below is still classified, as discovery
    or reconstruction. Every figure is an estimate: the report names a token RISK and never claims a
    saving.

.PARAMETER Json
    Emit JSON on stdout and nothing else.

.NOTES
    Exit 0 reported; 1 usage error.
#>
param(
    [switch]$Json,
    # Anything else the caller typed, so the usage error is this script's own on both shells.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

Set-StrictMode -Version 2.0
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$ErrorActionPreference = 'Stop'

if (@($Rest | Where-Object { $_ }).Count -gt 0) {
    [Console]::Error.WriteLine('Unknown option: ' + (@($Rest) -join ' '))
    [Console]::Error.WriteLine('Usage: project-intake.ps1 [-Json]')
    exit 1
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$rootFull = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')

function Join-Repo([string]$Rel) { return (Join-Path $repoRoot ($Rel -replace '/', '\')) }
function Test-FileUnder([string]$Rel) {
    $full = Join-Repo $Rel
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $false }
    $first = @(Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
    return ($first.Count -gt 0)
}
function Test-NonEmpty([string]$Rel) {
    $full = Join-Repo $Rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
    return ((Get-Item -LiteralPath $full -Force).Length -gt 0)
}
function Get-Sorted($List) {
    $a = [string[]]@($List | Where-Object { $_ })
    [Array]::Sort($a, [StringComparer]::Ordinal)
    return ,$a
}
# The first $Cap entries, comma-separated, and how many were left out. Lists are capped so the report
# stays short enough to paste into the next session.
function Format-Shown($List, [int]$Cap) {
    $items = @($List | Where-Object { $_ })
    if ($items.Count -eq 0) { return 'none' }
    $text = (@($items | Select-Object -First $Cap) -join ', ')
    if ($items.Count -gt $Cap) { $text += ('  (+{0} more)' -f ($items.Count - $Cap)) }
    return $text
}
function ConvertTo-JStr([string]$S) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $S.ToCharArray()) {
        if ($ch -eq [char]'\') { [void]$sb.Append('\\') }
        elseif ($ch -eq [char]'"') { [void]$sb.Append('\"') }
        elseif ([int]$ch -lt 32) { }
        else { [void]$sb.Append($ch) }
    }
    return ('"' + $sb.ToString() + '"')
}
function ConvertTo-JArr($List, [int]$Cap) {
    $items = @($List | Where-Object { $_ } | Select-Object -First $Cap)
    return ('[' + (@($items | ForEach-Object { ConvertTo-JStr $_ }) -join ',') + ']')
}
function ConvertTo-JBool([bool]$B) { if ($B) { return 'true' } else { return 'false' } }
function Get-YesNo([bool]$B) { if ($B) { return 'yes' } else { return 'no' } }
function Format-Row([string]$Label, [string]$Value) { return ('  {0,-13} {1}' -f $Label, $Value) }
function Format-FRow([string]$Label, [string]$Status, [string]$Reason) { return ('  {0,-15} {1,-8} {2}' -f $Label, $Status, $Reason) }

# --- evidence -------------------------------------------------------------------------------------
$role = 'unknown'
$bv = Join-Repo 'blueprint.version'
if (Test-Path -LiteralPath $bv -PathType Leaf) {
    $line = @(Get-Content -LiteralPath $bv | Where-Object { $_ -match '"role"' } | Select-Object -First 1)
    if ($line.Count -gt 0) {
        $v = ($line[0] -replace '.*:\s*"', '') -replace '".*', ''
        if ($v) { $role = $v }
    }
}

# Governing document directories: one logical place in up to two spellings, the first that holds a
# file reported, so a case-insensitive filesystem answers once and both shells print the same name.
$governing = New-Object System.Collections.Generic.List[string]
foreach ($pair in @('docs/Client:docs/client', 'docs/Developer:docs/developer', 'docs/data:docs/Data',
                    'docs/specifications:', 'docs/specs:')) {
    foreach ($cand in ($pair -split ':')) {
        if (-not $cand) { continue }
        if (Test-FileUnder $cand) { $governing.Add($cand); break }
    }
}
$govN = $governing.Count
$dataDocs = (@($governing | Where-Object { $_ -ieq 'docs/data' }).Count -gt 0)

$product = '.ai/product'
$intelN = 0; $intelMissing = New-Object System.Collections.Generic.List[string]
foreach ($m in @('authority-map', 'source-index', 'project-concept', 'module-map', 'requirement-matrix', 'implementation-roadmap', 'open-decisions')) {
    if (Test-NonEmpty "$product/$m.md") { $intelN++ } else { $intelMissing.Add($m) }
}
$discN = 0; $discMissing = New-Object System.Collections.Generic.List[string]
foreach ($m in @('project-brief', 'stakeholders', 'module-map-draft', 'questions', 'assumptions', 'phase-roadmap')) {
    if (Test-NonEmpty "$product/$m.md") { $discN++ } else { $discMissing.Add($m) }
}
$authority = Test-NonEmpty "$product/authority-map.md"
$moduleMap = ((Test-NonEmpty "$product/module-map.md") -or (Test-NonEmpty "$product/module-map-draft.md"))
$G = ($govN -gt 0 -or $authority)

$codeList = New-Object System.Collections.Generic.List[string]
foreach ($f in @('package.json', 'composer.json', 'pyproject.toml', 'requirements.txt', 'go.mod', 'Cargo.toml', 'pom.xml', 'build.gradle', 'Gemfile', 'mix.exs', 'deno.json')) {
    if (Test-Path -LiteralPath (Join-Repo $f) -PathType Leaf) { $codeList.Add($f) }
}
foreach ($d in @('src', 'app', 'apps', 'lib', 'packages', 'server', 'backend', 'frontend', 'api', 'services')) {
    if (Test-Path -LiteralPath (Join-Repo $d) -PathType Container) { $codeList.Add($d) }
}
$code = Get-Sorted $codeList; $codeN = @($code).Count

$webList = New-Object System.Collections.Generic.List[string]
$webCfg = 0; $pages = $false; $public = $false
foreach ($item in @(Get-ChildItem -LiteralPath $repoRoot -File -ErrorAction SilentlyContinue)) {
    $b = $item.Name
    if ($b -clike 'astro.config.*' -or $b -clike 'next.config.*' -or $b -clike 'nuxt.config.*' -or
        $b -clike 'vite.config.*' -or $b -clike 'svelte.config.*' -or $b -clike 'gatsby-config.*' -or
        $b -clike 'docusaurus.config.*' -or $b -ceq 'hugo.toml') {
        $webList.Add($b); $webCfg++
    }
}
foreach ($d in @('pages', 'src/pages')) {
    if (Test-Path -LiteralPath (Join-Repo $d) -PathType Container) { $webList.Add($d); $pages = $true }
}
if (Test-Path -LiteralPath (Join-Repo 'public') -PathType Container) { $webList.Add('public'); $public = $true }
$web = Get-Sorted $webList; $webN = @($web).Count
$W = ($webCfg -gt 0 -or ($pages -and $public))

# The one directory walk: depth 3, pruned, capped. Names only.
$prune = @('.git', 'node_modules', 'vendor', 'dist', 'build', '.next', '.nuxt', '.venv', 'venv', 'target',
           '.ai', '.claude', '.github', 'docs', 'scripts', 'templates')
$entNames = @('migrations', 'permissions', 'roles', 'tenants', 'workers', 'queues', 'jobs', 'audit', 'ledger', 'billing', 'invoices', 'payments', 'modules')
$testNames = @('test', 'tests', '__tests__', 'e2e')
$entList = New-Object System.Collections.Generic.List[string]
$entFound = New-Object System.Collections.Generic.List[string]
$tests = $false; $migrations = $false; $seen = 0
$queue = New-Object System.Collections.Generic.Queue[object]
$queue.Enqueue(@($rootFull, 0))
while ($queue.Count -gt 0 -and $seen -lt 5000) {
    $entry = $queue.Dequeue()
    $dirPath = [string]$entry[0]; $depth = [int]$entry[1]
    if ($depth -ge 3) { continue }
    $children = @()
    try { $children = [System.IO.Directory]::GetDirectories($dirPath) } catch { $children = @() }
    foreach ($child in $children) {
        if ($seen -ge 5000) { break }
        $name = [System.IO.Path]::GetFileName($child)
        if ($prune -ccontains $name) { continue }
        $seen++
        $rel = $child.Substring($rootFull.Length + 1).Replace('\', '/')
        $lower = $name.ToLowerInvariant()
        if ($entNames -ccontains $lower) {
            $entList.Add($rel); $entFound.Add($lower)
            if ($lower -ceq 'migrations') { $migrations = $true }
        } elseif ($testNames -ccontains $lower) {
            $tests = $true
        }
        $queue.Enqueue(@($child, ($depth + 1)))
    }
}
$ent = Get-Sorted $entList
$entN = @($entFound | Sort-Object -Unique).Count
$E = ($entN -ge 3)
$hasCode = ($codeN -gt 0 -or $W -or $E)

$ci = ((Test-FileUnder '.github/workflows') -or (Test-Path -LiteralPath (Join-Repo '.gitlab-ci.yml') -PathType Leaf) -or
       (Test-Path -LiteralPath (Join-Repo 'azure-pipelines.yml') -PathType Leaf) -or (Test-Path -LiteralPath (Join-Repo 'Jenkinsfile') -PathType Leaf))

$pmd = Join-Repo '.ai/context/project.md'
$tbd = $false; $pmdState = 'defined'
if (-not (Test-Path -LiteralPath $pmd -PathType Leaf)) { $tbd = $true; $pmdState = 'absent' }
elseif (Select-String -LiteralPath $pmd -Pattern 'TBD' -SimpleMatch -CaseSensitive -Quiet) { $tbd = $true; $pmdState = 'TBD' }
$govFile = $false; $codeAuth = $false
$govPath = Join-Repo '.ai/context/governance.json'
if (Test-Path -LiteralPath $govPath -PathType Leaf) {
    $govFile = $true
    $codeAuth = (@(Get-Content -LiteralPath $govPath | Where-Object { $_ -cmatch '"codeAuthorized"\s*:\s*true' }).Count -gt 0)
}
$constraints = Test-Path -LiteralPath (Join-Repo '.ai/context/constraints.md') -PathType Leaf
$decN = 0
$decDir = Join-Repo '.ai/memory/decisions'
if (Test-Path -LiteralPath $decDir -PathType Container) {
    $decN = @(Get-ChildItem -LiteralPath $decDir -File -Force | Where-Object { $_.Name -clike '*.md' -and $_.Name -cne 'README.md' }).Count
}

$tokBytes = 0
foreach ($f in @('CLAUDE.md', '.ai/contract/core.md', '.ai/context/project.md', '.ai/context/constraints.md', '.ai/context/current-state.md')) {
    $full = Join-Repo $f
    if (Test-Path -LiteralPath $full -PathType Leaf) { $tokBytes += (Get-Item -LiteralPath $full -Force).Length }
}
$tokens = [int][math]::Floor($tokBytes / 4)
$large = 0
foreach ($d in $governing) {
    $large += @(Get-ChildItem -LiteralPath (Join-Repo $d) -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 204800 } | Select-Object -First 1000).Count
}

# --- classification -------------------------------------------------------------------------------
if ($role -ceq 'source') { $mode = 'NOT_APPLICABLE' }
elseif ($G) { $mode = 'PROJECT_WITH_GOVERNING_DOCS' }
elseif ($hasCode) {
    if ($W -and -not $E) { $mode = 'WEBSITE_PROJECT' }
    elseif ($E) { $mode = 'ENTERPRISE_SYSTEM' }
    else { $mode = 'CODEBASE_RECONSTRUCTION_REQUIRED' }
}
else { $mode = 'PROJECT_DISCOVERY_REQUIRED' }

$tagList = New-Object System.Collections.Generic.List[string]
if ($mode -cne 'NOT_APPLICABLE') {
    if ($G) { $tagList.Add('PROJECT_WITH_GOVERNING_DOCS') }
    if ($hasCode -and -not $G -and $intelN -eq 0) { $tagList.Add('CODEBASE_RECONSTRUCTION_REQUIRED') }
    if ($W) { $tagList.Add('WEBSITE_PROJECT') }
    if ($E) { $tagList.Add('ENTERPRISE_SYSTEM') }
}
$tags = @($tagList | Where-Object { $_ -cne $mode })

$evidence = New-Object System.Collections.Generic.List[string]
switch ($mode) {
    'NOT_APPLICABLE' { $support = 2; $evidence.Add('blueprint.version') }
    'PROJECT_WITH_GOVERNING_DOCS' {
        $support = $govN; if ($authority) { $support++ }; if ($intelN -gt 0) { $support++ }
        foreach ($g in $governing) { $evidence.Add($g) }
        if ($authority) { $evidence.Add("$product/authority-map.md") }
    }
    'WEBSITE_PROJECT' { $support = $webN; foreach ($x in $web) { $evidence.Add($x) } }
    'ENTERPRISE_SYSTEM' { $support = $entN - 2; foreach ($x in $ent) { $evidence.Add($x) } }
    'CODEBASE_RECONSTRUCTION_REQUIRED' { $support = $codeN; foreach ($x in $code) { $evidence.Add($x) } }
    default {
        $support = 1; if ($tbd) { $support++ }
        if (Test-Path -LiteralPath $pmd -PathType Leaf) { $evidence.Add('.ai/context/project.md') }
    }
}
if ($support -ge 2) { $confidence = 'high' } elseif ($support -eq 1) { $confidence = 'medium' } else { $confidence = 'low' }

# --- forecast -------------------------------------------------------------------------------------
if ($mode -ceq 'NOT_APPLICABLE') {
    $na = 'source blueprint: no product of its own'
    $ptS = 'n/a'; $ptR = $na; $arS = 'n/a'; $arR = $na; $daS = 'n/a'; $daR = $na; $goS = 'n/a'; $goR = $na; $imS = 'n/a'; $imR = $na
} else {
    if ($G) {
        if ($intelN -eq 7) { $ptS = 'ready'; $ptR = 'governing documents mapped, 7 of 7' }
        else { $ptS = 'partial'; $ptR = "governing documents present, $intelN of 7 maps" }
    } elseif ($discN -eq 6 -and -not $tbd) { $ptS = 'ready'; $ptR = 'discovery records complete, 6 of 6' }
    elseif (-not $tbd -or $discN -gt 0) { $ptS = 'partial'; $ptR = "no governing documents, $discN of 6 discovery records" }
    else { $ptS = 'missing'; $ptR = "no governing documents, project.md $pmdState" }

    if ($moduleMap -and $decN -gt 0) { $arS = 'ready'; $arR = "module map and $decN decision record(s)" }
    elseif ($moduleMap -or $decN -gt 0) { $arS = 'partial'; $arR = ('module map {0}, {1} decision record(s)' -f (Get-YesNo $moduleMap), $decN) }
    else { $arS = 'missing'; $arR = 'no module map, no decision record' }

    if ($dataDocs -and $migrations) { $daS = 'ready'; $daR = 'data documents and migrations' }
    elseif ($dataDocs) { $daS = 'partial'; $daR = 'data documents, no migrations directory' }
    elseif ($migrations) { $daS = 'partial'; $daR = 'migrations, no data documents' }
    elseif ($mode -ceq 'WEBSITE_PROJECT') { $daS = 'n/a'; $daR = 'no data layer signalled' }
    else { $daS = 'missing'; $daR = 'no data documents, no migrations directory' }

    if (-not $govFile) { $goS = 'missing'; $goR = '.ai/context/governance.json absent' }
    elseif ($tbd) { $goS = 'partial'; $goR = "gates present, project.md $pmdState" }
    elseif (-not $constraints) { $goS = 'partial'; $goR = 'gates present, constraints.md absent' }
    else { $goS = 'ready'; $goR = 'governance, constraints, and a defined project' }

    if ($tbd) { $imS = 'blocked'; $imR = "discovery gate: project.md $pmdState" }
    elseif (-not $codeAuth) { $imS = 'blocked'; $imR = 'governance: codeAuthorized is not true' }
    elseif ($hasCode -and $ci -and $tests) { $imS = 'ready'; $imR = 'code, CI, and tests present' }
    elseif ($hasCode) { $imS = 'partial'; $imR = ('code present, CI {0}, tests {1}' -f (Get-YesNo $ci), (Get-YesNo $tests)) }
    else { $imS = 'missing'; $imR = 'no application signal' }
}

$tkL = 'low'
if ($tokens -gt 5000 -or ($G -and $intelN -eq 0 -and $large -gt 0)) { $tkL = 'high' }
elseif ($tokens -gt 4000 -or ($G -and $intelN -lt 7) -or $large -gt 0) { $tkL = 'medium' }
$tkR = "~$tokens always-loaded tokens (bytes/4), $large document(s) over 200 KB"
if ($G -and $intelN -lt 7) { $tkR += ", governing documents $intelN of 7 mapped" }

# --- next prompt family ---------------------------------------------------------------------------
if ($mode -ceq 'NOT_APPLICABLE') { $famKey = 'none'; $famLabel = 'none, the source blueprint has no product of its own'; $famRead = '' }
elseif ($G -and $intelN -lt 7) { $famKey = 'extract-project-intelligence'; $famLabel = 'extract project intelligence'; $famRead = '.ai/workflows/ingest-project.md' }
elseif ($mode -ceq 'PROJECT_DISCOVERY_REQUIRED' -and $tbd) { $famKey = 'run-discovery'; $famLabel = 'run discovery'; $famRead = '.ai/workflows/discovery.md' }
elseif ($mode -ceq 'CODEBASE_RECONSTRUCTION_REQUIRED') { $famKey = 'reconstruct-from-codebase'; $famLabel = 'reconstruct from codebase'; $famRead = '.ai/skills/codebase-navigation.md' }
elseif ($mode -ceq 'WEBSITE_PROJECT') { $famKey = 'website-path'; $famLabel = 'website review/build/deploy path'; $famRead = '.ai/contract/safety.md' }
elseif ($mode -ceq 'ENTERPRISE_SYSTEM') { $famKey = 'enterprise-phasing'; $famLabel = 'enterprise module/phasing path'; $famRead = '.ai/contract/lifecycle.md' }
elseif ($imS -ceq 'blocked') { $famKey = 'blocked-owner-decision'; $famLabel = 'blocked-owner-decision path'; $famRead = '.ai/memory/open-questions.md' }
else { $famKey = 'safe-implementation'; $famLabel = 'safe implementation path'; $famRead = '.ai/workflows/start-task.md' }

if ($G) { $missingMaps = @($intelMissing) } else { $missingMaps = @($discMissing) }

# --- output ---------------------------------------------------------------------------------------
if ($Json) {
    function Format-FJson([string]$S, [string]$R) { return ('{"status": ' + (ConvertTo-JStr $S) + ', "reason": ' + (ConvertTo-JStr $R) + '}') }
    if ($famRead) { $readJson = ConvertTo-JStr $famRead } else { $readJson = 'null' }
    $out = @(
        '{',
        '  "schema": "forgeos.project-intake/1",',
        ('  "role": ' + (ConvertTo-JStr $role) + ','),
        ('  "mode": ' + (ConvertTo-JStr $mode) + ','),
        ('  "confidence": ' + (ConvertTo-JStr $confidence) + ','),
        ('  "tags": ' + (ConvertTo-JArr $tags 5) + ','),
        ('  "evidence": {"total": ' + $evidence.Count + ', "paths": ' + (ConvertTo-JArr $evidence 5) + '},'),
        ('  "governingDirectories": ' + (ConvertTo-JArr $governing 5) + ','),
        ('  "maps": {"directory": ".ai/product", "intelligence": {"present": ' + $intelN + ', "total": 7, "missing": ' + (ConvertTo-JArr $intelMissing 7) +
            '}, "discovery": {"present": ' + $discN + ', "total": 6, "missing": ' + (ConvertTo-JArr $discMissing 6) + '}},'),
        ('  "signals": {"code": {"count": ' + $codeN + ', "paths": ' + (ConvertTo-JArr $code 5) + '}, "website": {"count": ' + $webN +
            ', "paths": ' + (ConvertTo-JArr $web 5) + '}, "enterprise": {"count": ' + $entN + ', "paths": ' + (ConvertTo-JArr $ent 5) +
            '}, "ci": ' + (ConvertTo-JBool $ci) + ', "tests": ' + (ConvertTo-JBool $tests) + '},'),
        '  "forecast": {',
        ('    "productTruth": ' + (Format-FJson $ptS $ptR) + ','),
        ('    "architecture": ' + (Format-FJson $arS $arR) + ','),
        ('    "data": ' + (Format-FJson $daS $daR) + ','),
        ('    "governance": ' + (Format-FJson $goS $goR) + ','),
        ('    "implementation": ' + (Format-FJson $imS $imR) + ','),
        ('    "tokenRisk": {"level": ' + (ConvertTo-JStr $tkL) + ', "reason": ' + (ConvertTo-JStr $tkR) + ', "alwaysLoadedTokens": ' + $tokens + ', "largeDocuments": ' + $large + '}'),
        '  },',
        ('  "nextPromptFamily": {"key": ' + (ConvertTo-JStr $famKey) + ', "label": ' + (ConvertTo-JStr $famLabel) + ', "readFirst": ' + $readJson + '},'),
        '  "safety": {"readOnly": true, "canModifyFiles": false, "canAuthorizeCode": false, "canOpenGovernanceWindow": false, "networkAccess": false}',
        '}'
    )
    $out | ForEach-Object { Write-Output $_ }
    exit 0
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('ForgeOS project intake  (read-only)')
$lines.Add((Format-Row 'role' $role))
$lines.Add((Format-Row 'mode' "$mode  (confidence $confidence)"))
$lines.Add((Format-Row 'tags' (Format-Shown $tags 4)))
$lines.Add((Format-Row 'evidence' (Format-Shown $evidence 3)))
$lines.Add((Format-Row 'governing' (Format-Shown $governing 3)))
$lines.Add((Format-Row 'maps' "intelligence $intelN of 7, discovery $discN of 6"))
if ($mode -cne 'NOT_APPLICABLE' -and $missingMaps.Count -gt 0) {
    $lines.Add((Format-Row 'missing maps' ((Format-Shown $missingMaps 3) + '  in .ai/product/')))
}
$lines.Add((Format-Row 'code' ("$codeN signal(s): " + (Format-Shown $code 3))))
$lines.Add((Format-Row 'website' ("$webN signal(s): " + (Format-Shown $web 3))))
$lines.Add((Format-Row 'enterprise' ("$entN signal(s): " + (Format-Shown $ent 3))))
$lines.Add('Forecast')
$lines.Add((Format-FRow 'product truth' $ptS $ptR))
$lines.Add((Format-FRow 'architecture' $arS $arR))
$lines.Add((Format-FRow 'data' $daS $daR))
$lines.Add((Format-FRow 'governance' $goS $goR))
$lines.Add((Format-FRow 'implementation' $imS $imR))
$lines.Add((Format-FRow 'token risk' $tkL $tkR))
$lines.Add('Next prompt family')
if ($famRead) { $lines.Add("  $famLabel  (read first: $famRead)") } else { $lines.Add("  $famLabel") }
$lines.Add('Nothing was written, authorized, or opened. Token figures are estimates, not a claimed saving.')
$lines | ForEach-Object { Write-Output $_ }
exit 0
