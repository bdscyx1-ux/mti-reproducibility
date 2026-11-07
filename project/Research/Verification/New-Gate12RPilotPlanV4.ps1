[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($ProjectPath)
$sourcePath = Join-Path $root 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v3.json'
$targetPath = Join-Path $root 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v4.json'
$receiptPath = Join-Path $root 'Research\Gate12R_PilotPlanV4_Derivation.v1.json'
$amendmentPath = Join-Path $root 'Research\Gate12R_Memory_Gate_Amendment.v1.json'
$diagnosisPath = Join-Path $root 'Research\Gate12R_PilotAttempt3_Managed_Memory_Diagnosis.v1.md'
$preservationPath = Join-Path $root 'Research\Gate12R_PilotAttempt3_Terminal_Preservation.v1.json'
$commandPath = Join-Path $root 'Assets\_Scripts\Research\Editor\Gate12RProcessReuseBatchCommandV3.cs'
$utf8 = New-Object System.Text.UTF8Encoding($false)

foreach ($path in @($sourcePath, $amendmentPath, $diagnosisPath, $preservationPath, $commandPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required derivation input is missing: $path" }
}
if (Test-Path -LiteralPath $targetPath -or Test-Path -LiteralPath $receiptPath) {
    throw 'Gate12R pilot plan v4 or its derivation receipt already exists.'
}

$sourceSha = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceSha -ne '498f0bac34f5ba98c946efab5577f1feed5631a4766fdd8817c74f445b150c98') {
    throw 'Frozen pilot plan v3 SHA-256 mismatch.'
}

$plan = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
$plan.schemaVersion = 2
$plan.planId = 'gate12r-fresh-process-reuse-5pct-pilot-plan-v2-memory-aggregation'
$plan.attempt = 4
$plan.paths.pilotRootRelativePath = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4'
$plan.paths.verificationRootRelativePath = 'Research/Verification/Gate12R_ProcessReuse_5pct/v6'
$plan.telemetry.maximumSampleRetainedManagedGrowthBytes = 134217728L
$plan.telemetry.maximumBlockRetainedManagedGrowthBytes = 536870912L
$plan.telemetry | Add-Member -NotePropertyName memoryGatePolicyId -NotePropertyValue 'gate12r-sample-128mib-block-128mib-per-sample-v1'
$plan.telemetry | Add-Member -NotePropertyName blockManagedLimitFormulaId -NotePropertyValue 'checked-sample-limit-times-expected-sample-count-v1'
$plan.telemetry | Add-Member -NotePropertyName maximumBlockRetainedManagedGrowthBytesPerSample -NotePropertyValue 134217728L
$plan.telemetry | Add-Member -NotePropertyName twoSampleBlockRetainedManagedGrowthLimitBytes -NotePropertyValue 268435456L
$plan.telemetry | Add-Member -NotePropertyName fourSampleBlockRetainedManagedGrowthLimitBytes -NotePropertyValue 536870912L
$plan | Add-Member -NotePropertyName memoryGateAmendment -NotePropertyValue ([pscustomobject][ordered]@{
    amendmentId = 'gate12r-managed-memory-aggregation-amendment-v1'
    relativePath = 'Research/Gate12R_Memory_Gate_Amendment.v1.json'
    sha256 = (Get-FileHash -LiteralPath $amendmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    diagnosisRelativePath = 'Research/Gate12R_PilotAttempt3_Managed_Memory_Diagnosis.v1.md'
    diagnosisSha256 = (Get-FileHash -LiteralPath $diagnosisPath -Algorithm SHA256).Hash.ToLowerInvariant()
    attempt3PreservationRelativePath = 'Research/Gate12R_PilotAttempt3_Terminal_Preservation.v1.json'
    attempt3PreservationSha256 = (Get-FileHash -LiteralPath $preservationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    unityCommandRelativePath = 'Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV3.cs'
    unityCommandSha256 = (Get-FileHash -LiteralPath $commandPath -Algorithm SHA256).Hash.ToLowerInvariant()
})

$json = ($plan | ConvertTo-Json -Depth 30) + "`n"
[System.IO.File]::WriteAllText($targetPath, $json, $utf8)
$targetSha = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate12r-pilot-plan-v4-derivation-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('O')
    sourceRelativePath = 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v3.json'
    sourceSha256 = $sourceSha
    targetRelativePath = 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v4.json'
    targetSha256 = $targetSha
    changedFields = @(
        'schemaVersion', 'planId', 'attempt', 'paths.pilotRootRelativePath',
        'paths.verificationRootRelativePath', 'telemetry block managed-memory aggregation fields',
        'memoryGateAmendment'
    )
    unchangedSemantics = @(
        '12 campaigns', '8 warm-up blocks', '36 cold structural controls',
        '384 measured Williams blocks', '1152 measured samples', 'Williams order',
        'algorithm and workload semantics', 'per-sample reset', 'PSAPI/CIM telemetry',
        '5% precision', 'no formal sample cap', 'canonical input reference policy'
    )
    completed = $true
}
[System.IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 10) + "`n"), $utf8)
$receipt | ConvertTo-Json -Depth 10
