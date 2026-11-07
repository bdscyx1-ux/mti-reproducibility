[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ProjectPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-AtomicUtf8NoBomJson {
    param([string]$LiteralPath, $Value)
    $temporary = $LiteralPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = ($Value | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false, $true)))
    Move-Item -LiteralPath $temporary -Destination $LiteralPath
}

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'ProjectPath must be an explicit absolute path.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$source = Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v1.json'
$destination = Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v2.json'
$receiptPath = Join-Path $ProjectPath 'Research\Gate12R_PilotPlanV2_Derivation.v1.json'
$expectedSourceSha256 = '68f32ee7acdeaa4c43a4f4932825e40e552bb5df473a96c66a9dcffef45d8ff3'

if (Test-Path -LiteralPath $destination) { throw "Create-new destination exists: $destination" }
if (Test-Path -LiteralPath $receiptPath) { throw "Create-new receipt exists: $receiptPath" }
$actualSourceSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSourceSha256 -ne $expectedSourceSha256) { throw "Frozen pilot plan v1 hash mismatch: $actualSourceSha256" }

$text = [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8)
$changes = @(
    [pscustomobject]@{ from = '"attempt": 1'; to = '"attempt": 2'; expected = 1 },
    [pscustomobject]@{ from = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1'; to = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v2'; expected = 1 },
    [pscustomobject]@{ from = 'Research/Verification/Gate12R_ProcessReuse_5pct/v1'; to = 'Research/Verification/Gate12R_ProcessReuse_5pct/v4'; expected = 1 }
)
$evidence = New-Object Collections.Generic.List[object]
foreach ($change in $changes) {
    $count = $text.Split([string[]]@([string]$change.from), [StringSplitOptions]::None).Count - 1
    if ($count -ne [int]$change.expected) { throw "Pilot plan replacement count for '$($change.from)' is $count, expected $($change.expected)." }
    $text = $text.Replace([string]$change.from, [string]$change.to)
    $evidence.Add([pscustomobject][ordered]@{ from = $change.from; to = $change.to; occurrenceCount = $count })
}
[IO.File]::WriteAllText($destination, $text, (New-Object Text.UTF8Encoding($false, $true)))

$v1 = Get-Content -LiteralPath $source -Raw -Encoding UTF8 | ConvertFrom-Json
$v2 = Get-Content -LiteralPath $destination -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$v2.planId -ne [string]$v1.planId -or [string]$v2.executionDesignId -ne [string]$v1.executionDesignId) { throw 'Plan/design identity changed.' }
if ([int]$v2.attempt -ne 2 -or [string]$v2.paths.pilotRootRelativePath -ne 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v2' -or [string]$v2.paths.verificationRootRelativePath -ne 'Research/Verification/Gate12R_ProcessReuse_5pct/v4') { throw 'Versioned attempt/root routing is incorrect.' }
if ($v2.precision.relativeHalfWidth -ne 0.05 -or $null -ne $v2.precision.hardCap -or [long]$v2.telemetry.maximumBlockRetainedManagedGrowthBytes -ne 134217728L) { throw 'Frozen precision/no-cap/memory rules changed.' }
if ([int]$v2.measuredBlocksPerCampaign -ne 32 -or [int]$v2.campaignIds.Count -ne 12 -or [int]$v2.totals.totalUnityProcesses -ne 429 -or [int]$v2.totals.totalSamples -ne 1212) { throw 'Frozen pilot cardinality changed.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v2')) { throw 'Fresh pilot v2 root must remain absent during plan derivation.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')) { throw 'Gate13R formal root must remain absent.' }

$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate12r-pilot-plan-v2-mechanical-root-routing-receipt-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    sourceRelativePath = 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v1.json'
    sourceSha256Before = $actualSourceSha256
    sourceSha256After = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    destinationRelativePath = 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v2.json'
    destinationSha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    mechanicalChanges = $evidence.ToArray()
    designIdentityChanged = $false
    matrixChanged = $false
    williamsOrderChanged = $false
    telemetryThresholdsChanged = $false
    precisionChanged = $false
    hardCapChanged = $false
    pilotV1ReferencedForAnalysis = $false
    pilotV2RootCreated = $false
    gate13rRootCreated = $false
    passed = $true
}
Write-AtomicUtf8NoBomJson -LiteralPath $receiptPath -Value $receipt
Write-Host "Gate12R pilot plan v2 derived: $destination" -ForegroundColor Green

