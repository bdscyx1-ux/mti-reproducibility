[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PilotPlanPath,
    [string]$ProvenancePath
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($PilotPlanPath)) { $PilotPlanPath = Join-Path $ProjectPath 'Research\Gate13R2_v2_Pilot_Plan.v1.json' }
if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { $ProvenancePath = Join-Path $ProjectPath 'Research\Gate13R2_v2_Provenance.v1.json' }
$PilotPlanPath = [System.IO.Path]::GetFullPath($PilotPlanPath)
$ProvenancePath = [System.IO.Path]::GetFullPath($ProvenancePath)
$modulePath = Join-Path $PSScriptRoot 'Gate13R2V2Preparation.psm1'
$blockRunnerPath = Join-Path $PSScriptRoot 'Run-PlanningProcessReuseBlockV2.ps1'
$coldRunnerPath = Join-Path $PSScriptRoot 'Run-Gate13R2V2ColdReference.ps1'
$analyzerPath = Join-Path $PSScriptRoot 'Analyze-Gate13R2V2Pilot.ps1'
$prePilotAuditPath = Join-Path $ProjectPath 'Research\Verification\Gate13R2_v2_PrePilotAudit.summary.json'
$telemetryProbeResultPath = Join-Path $ProjectPath 'Research\Verification\Gate13R2_v2\TelemetryProbe\v1\telemetry-probe-result.json'
Import-Module $modulePath -Force
$plan = Read-G13R2V2Json -Path $PilotPlanPath
$provenance = Read-G13R2V2Json -Path $ProvenancePath
$planCheck = Test-G13R2V2PilotPlan -ProjectPath $ProjectPath -Plan $plan -PlanPath $PilotPlanPath
if (-not $planCheck.passed) { throw "V2 pilot plan validation failed: $($planCheck.errors -join '; ')" }
if (-not (Test-Path -LiteralPath $prePilotAuditPath -PathType Leaf)) { throw 'V2 pre-pilot audit summary is missing.' }
$prePilotAudit = Read-G13R2V2Json -Path $prePilotAuditPath
if ($prePilotAudit.passed -ne $true -or $prePilotAudit.pilotExecutionAuthorizedByAudit -ne $true -or $prePilotAudit.formalExecutionAuthorized -ne $false) { throw 'V2 pre-pilot audit did not pass the one-shot non-formal execution gate.' }
if ([string]$prePilotAudit.pilotPlanSha256 -ne (Get-G13R2V2LowerSha256 -Path $PilotPlanPath) -or [string]$prePilotAudit.provenanceSha256 -ne (Get-G13R2V2LowerSha256 -Path $ProvenancePath)) { throw 'V2 pre-pilot audit is not bound to current plan/provenance bytes.' }
if (-not (Test-Path -LiteralPath $telemetryProbeResultPath -PathType Leaf)) { throw 'Successful v2 telemetry probe result is missing.' }
$probe = Read-G13R2V2Json -Path $telemetryProbeResultPath
if ($probe.passed -ne $true) { throw 'V2 telemetry probe did not pass.' }
foreach ($property in $provenance.PSObject.Properties | Where-Object { $_.Value -is [pscustomobject] -and $_.Value.PSObject.Properties.Name -contains 'relativePath' -and $_.Value.PSObject.Properties.Name -contains 'sha256' }) {
    [void](Assert-G13R2V2BoundFile -ProjectPath $ProjectPath -RelativePath ([string]$property.Value.relativePath) -ExpectedSha256 ([string]$property.Value.sha256) -Label ('V2 provenance ' + $property.Name))
}

$pilotRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/', '\')))
$formalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.reservedFormalRootRelativePath).Replace('/', '\')))
if (-not (Test-Path -LiteralPath $pilotRoot -PathType Container)) { throw 'Initialized v2 pilot root is missing.' }
if (Test-Path -LiteralPath $formalRoot) { throw 'Reserved process-reuse formal root must remain absent.' }
$initialChildren = @(Get-ChildItem -LiteralPath $pilotRoot -Force)
if ($initialChildren.Count -ne 2 -or @($initialChildren.Name | Sort-Object) -join '|' -ne 'preparation-checkpoint.json|root-initialization-receipt.json') { throw 'V2 pilot root is not in the exact preparation-only state.' }
$preparationCheckpointPath = Join-Path $pilotRoot 'preparation-checkpoint.json'
$preparationCheckpoint = Read-G13R2V2Json -Path $preparationCheckpointPath
if ([string]$preparationCheckpoint.status -ne 'PREPARATION-ONLY-PILOT-NOT-STARTED' -or $preparationCheckpoint.pilotExecutionStarted -ne $false) { throw 'V2 preparation checkpoint does not permit the one authorized pilot start.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be closed and the project lock absent before v2 pilot launch.' }

$nativePowerShellModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$unityPath = [System.IO.Path]::GetFullPath(([string]$plan.unity.executablePath).Replace('/', '\'))
if ((Get-G13R2V2LowerSha256 -Path $unityPath) -ne [string]$plan.unity.executableSha256) { throw 'Unity executable hash mismatch.' }

function Get-EnvironmentSnapshot([string]$Phase) {
    $processors = @(Get-CimInstance Win32_Processor)
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $loadSamples = New-Object System.Collections.Generic.List[double]
    for ($index = 0; $index -lt [int]$plan.environmentPreflight.cpuLoadSampleCount; $index++) {
        $load = ($processors | Measure-Object LoadPercentage -Average).Average
        $loadSamples.Add($(if ($null -eq $load) { 0.0 } else { [double]$load }))
        if ($index -lt [int]$plan.environmentPreflight.cpuLoadSampleCount - 1) { Start-Sleep -Seconds ([int]$plan.environmentPreflight.cpuLoadSampleIntervalSeconds); $processors = @(Get-CimInstance Win32_Processor) }
    }
    $powerRaw = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
    $powerMatch = [regex]::Match($powerRaw, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    $drive = New-Object System.IO.DriveInfo -ArgumentList @([System.IO.Path]::GetPathRoot($pilotRoot))
    $meanCpu = [double](($loadSamples.ToArray() | Measure-Object -Average).Average)
    $freeMemory = [long]([double]$operatingSystem.FreePhysicalMemory * 1KB)
    $failed = New-Object System.Collections.Generic.List[string]
    if (-not $powerMatch.Success -or $powerMatch.Value.ToLowerInvariant() -ne [string]$plan.environmentPreflight.requiredActivePowerSchemeGuid) { $failed.Add('power-scheme') }
    if ($freeMemory -lt [long]$plan.environmentPreflight.minimumFreePhysicalMemoryBytes) { $failed.Add('free-memory') }
    if ($meanCpu -gt [double]$plan.environmentPreflight.maximumMeanCpuLoadPercent) { $failed.Add('mean-cpu-load') }
    if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0) { $failed.Add('unity-process') }
    if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { $failed.Add('unity-lockfile') }
    if ($drive.AvailableFreeSpace -lt 10GB) { $failed.Add('pilot-storage-below-10GiB') }
    if (Test-Path -LiteralPath $formalRoot) { $failed.Add('reserved-formal-root-exists') }
    return [pscustomobject][ordered]@{ schemaVersion = 1; phase = $Phase; capturedAt = (Get-Date).ToString('o'); machineName = $env:COMPUTERNAME; userName = $env:USERNAME; cpuModels = @($processors | ForEach-Object { ([string]$_.Name).Trim() }); logicalProcessorCount = [int]$computerSystem.NumberOfLogicalProcessors; totalPhysicalMemoryBytes = [long]$computerSystem.TotalPhysicalMemory; freePhysicalMemoryBytes = $freeMemory; operatingSystem = [string]$operatingSystem.Caption; powerSchemeRaw = $powerRaw; powerSchemeGuid = if ($powerMatch.Success) { $powerMatch.Value.ToLowerInvariant() } else { $null }; cpuLoadSamplesPercent = $loadSamples.ToArray(); meanCpuLoadPercent = $meanCpu; outputDriveFreeBytes = [long]$drive.AvailableFreeSpace; unityProcessIds = @(Get-Process -Name Unity -ErrorAction SilentlyContinue | ForEach-Object Id); unityLockfilePresent = Test-Path (Join-Path $ProjectPath 'Temp\UnityLockfile'); reservedFormalRootPresent = Test-Path $formalRoot; failedChecks = $failed.ToArray(); passed = $failed.Count -eq 0 }
}

function Write-PilotCheckpoint([string]$Status, [object[]]$Entries, [string]$ErrorMessage) {
    $checkpoint = [ordered]@{ schemaVersion = 1; checkpointKind = 'gate13-r2-v2-process-reuse-pilot-checkpoint-v1'; status = $Status; savedAtUtc = [DateTime]::UtcNow.ToString('o'); planId = [string]$plan.planId; planSha256 = Get-G13R2V2LowerSha256 $PilotPlanPath; provenanceSha256 = Get-G13R2V2LowerSha256 $ProvenancePath; telemetryProbeResultSha256 = Get-G13R2V2LowerSha256 $telemetryProbeResultPath; prePilotAuditRelativePath = Get-G13R2V2ProjectRelativePath $ProjectPath $prePilotAuditPath; prePilotAuditSha256 = Get-G13R2V2LowerSha256 $prePilotAuditPath; completedEntryCount = @($Entries).Count; entries = @($Entries); error = $ErrorMessage; formalCampaign = $false; excludedFromFormalAnalysis = $true; automaticRetryAuthorized = $false; automaticResumeAuthorized = $false; formalExecutionAuthorized = $false }
    Write-G13R2V2AtomicUtf8NoBomJson -Path (Join-Path $pilotRoot 'pilot-checkpoint.json') -Value $checkpoint -Depth 40
}

function Invoke-OwnedPowerShell([string[]]$Arguments, [string]$StdoutPath, [string]$StderrPath) {
    $previous = $env:PSModulePath
    try { $env:PSModulePath = $nativePowerShellModulePath; & $windowsPowerShell @Arguments 1> $StdoutPath 2> $StderrPath; return [int]$LASTEXITCODE } finally { $env:PSModulePath = $previous }
}

function Invoke-ProcessReuseBlock($BlockPlan, [string]$Role, [string]$OutputDirectory, [string]$PlanFilePath, [int]$Ordinal) {
    if (Test-Path -LiteralPath $PlanFilePath) { throw "V2 block plan output exists: $PlanFilePath" }
    Write-G13R2V2Utf8NoBomJson -Path $PlanFilePath -Value $BlockPlan -Depth 40
    $parent = Split-Path -Parent $OutputDirectory; if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    $stdoutPath = $OutputDirectory + '.wrapper.stdout.log'; $stderrPath = $OutputDirectory + '.wrapper.stderr.log'
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$blockRunnerPath,'-BlockPlanPath',$PlanFilePath,'-OutputDirectory',$OutputDirectory,'-UnityPath',$unityPath,'-ProjectPath',$ProjectPath)
    $started = Get-Date
    Write-Host ("[{0}/36] Starting v2 {1} block {2}" -f $Ordinal, $Role, $BlockPlan.blockId) -ForegroundColor Cyan
    $exitCode = Invoke-OwnedPowerShell $arguments $stdoutPath $stderrPath
    $completed = Get-Date
    if ($exitCode -ne 0) { throw "V2 block failed without retry: $($BlockPlan.blockId), exit=$exitCode, stderr=$stderrPath" }
    $summaryPath = $OutputDirectory + '.summary.json'; if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "V2 block summary missing: $summaryPath" }
    $summary = Read-G13R2V2Json $summaryPath; if ($summary.passed -ne $true -or $summary.formalCampaign -ne $false) { throw "V2 block summary invalid: $summaryPath" }
    $manifest = Read-G13R2V2Json (Join-Path $OutputDirectory 'block-manifest.json')
    return [pscustomobject][ordered]@{ role = $Role; ordinal = $Ordinal; blockId = [string]$BlockPlan.blockId; planRelativePath = Get-G13R2V2ProjectRelativePath $ProjectPath $PlanFilePath; planSha256 = Get-G13R2V2LowerSha256 $PlanFilePath; outputRelativePath = Get-G13R2V2ProjectRelativePath $ProjectPath $OutputDirectory; summaryRelativePath = Get-G13R2V2ProjectRelativePath $ProjectPath $summaryPath; summarySha256 = Get-G13R2V2LowerSha256 $summaryPath; processId = [int]$manifest.processId; processStartTimeUtc = [string]$manifest.processStartTimeUtc; sampleCount = [int]$summary.sampleCount; wallSeconds = ($completed - $started).TotalSeconds; formalCampaign = $false; completed = $true }
}

function Invoke-ColdReference([string]$ScenarioId, [string]$ScenarioRelativePath, [string]$AlgorithmId, [int]$Ordinal) {
    $scenarioPath = Join-Path $ProjectPath $ScenarioRelativePath.Replace('/', '\'); $slug = Get-G13R2V2AlgorithmSlug $AlgorithmId
    $outputDirectory = Join-Path $pilotRoot ("cold-reference\{0}\{1}" -f $ScenarioId, $slug); $parent = Split-Path -Parent $outputDirectory; if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    $runId = "g13r2v2p-ref-$ScenarioId-$slug"; $stdoutPath = $outputDirectory + '.wrapper.stdout.log'; $stderrPath = $outputDirectory + '.wrapper.stderr.log'
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$coldRunnerPath,'-ScenarioPath',$scenarioPath,'-OutputDirectory',$outputDirectory,'-RunId',$runId,'-Algorithm',$AlgorithmId,'-UnityPath',$unityPath,'-ProjectPath',$ProjectPath)
    Write-Host ("[{0}/8] Starting v2 cold control {1}/{2}" -f $Ordinal, $ScenarioId, $AlgorithmId) -ForegroundColor DarkCyan
    $started = Get-Date; $exitCode = Invoke-OwnedPowerShell $arguments $stdoutPath $stderrPath; $completed = Get-Date
    if ($exitCode -ne 0) { throw "V2 cold structural control failed without retry: $runId, exit=$exitCode" }
    $manifestPath = Join-Path $outputDirectory 'manifest.json'; $resultPath = Join-Path $outputDirectory 'workload-result.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw "V2 cold control artifacts missing: $runId" }
    return [pscustomobject][ordered]@{ role = 'fresh-cold-structural-control'; ordinal = $Ordinal; runId = $runId; scenarioId = $ScenarioId; algorithmId = $AlgorithmId; outputRelativePath = Get-G13R2V2ProjectRelativePath $ProjectPath $outputDirectory; manifestSha256 = Get-G13R2V2LowerSha256 $manifestPath; workloadResultSha256 = Get-G13R2V2LowerSha256 $resultPath; sampleCount = 1; wallSeconds = ($completed - $started).TotalSeconds; formalCampaign = $false; completed = $true }
}

function Write-RootEvidenceManifest([string]$Name, [string[]]$Disposition) {
    $path = Join-Path $pilotRoot $Name
    $files = @(Get-ChildItem -LiteralPath $pilotRoot -File -Recurse | Where-Object FullName -ne $path | Sort-Object FullName)
    $rows = foreach ($file in $files) { [ordered]@{ relativePath = $file.FullName.Substring($pilotRoot.TrimEnd('\').Length + 1).Replace('\','/'); byteCount = [long]$file.Length; sha256 = Get-G13R2V2LowerSha256 $file.FullName } }
    $aggregateText = ($rows | ForEach-Object { '{0}|{1}|{2}' -f $_.relativePath, $_.byteCount, $_.sha256 }) -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create(); try { $aggregate = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($aggregateText)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    $manifest = [ordered]@{ schemaVersion = 1; manifestKind = 'gate13-r2-v2-pilot-root-evidence-manifest-v1'; recordedAtUtc = [DateTime]::UtcNow.ToString('o'); rootAbsolutePath = $pilotRoot; disposition = $Disposition; capturedFileCountExcludingThisManifest = $rows.Count; capturedRawByteCount = [long](($files | Measure-Object Length -Sum).Sum); aggregateSha256 = $aggregate; aggregateDefinition = 'sha256(UTF8(join(LF, sorted root-relative-path|raw-byte-count|lowercase-file-sha256)))'; files = $rows }
    Write-G13R2V2AtomicUtf8NoBomJson $path $manifest 60
    return $path
}

$entries = New-Object System.Collections.Generic.List[object]
$startedAt = Get-Date
try {
    $preflight = Get-EnvironmentSnapshot 'launch-preflight-before-pilot-start'
    Write-G13R2V2Utf8NoBomJson (Join-Path $pilotRoot 'environment-start.json') $preflight 20
    if (-not $preflight.passed) { throw "V2 pilot preflight failed before the single pilot start: $($preflight.failedChecks -join ', ')" }
    $preparationCheckpoint.status = 'PILOT-STARTED-NO-RETRY-NO-RESUME'; $preparationCheckpoint.savedAtUtc = [DateTime]::UtcNow.ToString('o'); $preparationCheckpoint.telemetryProbePassed = $true; $preparationCheckpoint.prePilotAuditPassed = $true; $preparationCheckpoint.pilotExecutionStarted = $true; $preparationCheckpoint.telemetryProbeResultSha256 = Get-G13R2V2LowerSha256 $telemetryProbeResultPath; $preparationCheckpoint.prePilotAuditSha256 = Get-G13R2V2LowerSha256 $prePilotAuditPath
    Write-G13R2V2AtomicUtf8NoBomJson $preparationCheckpointPath $preparationCheckpoint 30
    New-Item -ItemType Directory -Path (Join-Path $pilotRoot 'plans') | Out-Null
    Write-PilotCheckpoint 'preflight-passed-pilot-started' @() $null

    $warmup = $plan.warmup
    $warmupPlan = New-G13R2V2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId ([string]$warmup.campaignId) -ScenarioRelativePath ([string]$warmup.scenarioRelativePath) -ScenarioSourceSha256 ([string]$warmup.scenarioSourceSha256) -ComparisonCohortId ([string]$warmup.comparisonCohortId) -Block ([int]$warmup.block) -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $telemetryProbeResultPath -Warmup
    $entries.Add((Invoke-ProcessReuseBlock $warmupPlan 'excluded-process-reuse-warmup' (Join-Path $pilotRoot 'warmup\block-b001') (Join-Path $pilotRoot 'plans\warmup-b001.block-plan.json') 0))
    Write-PilotCheckpoint 'warmup-completed' $entries.ToArray() $null
    Start-Sleep -Seconds ([int]$warmup.quietStabilizationSecondsAfterWarmup)
    $postWarmup = Get-EnvironmentSnapshot 'post-warmup-stabilized'; Write-G13R2V2Utf8NoBomJson (Join-Path $pilotRoot 'environment-post-warmup.json') $postWarmup 20
    if (-not $postWarmup.passed) { throw "V2 post-warmup environment check failed: $($postWarmup.failedChecks -join ', ')" }

    $ordinal = 0
    foreach ($reference in @($plan.freshColdReferences)) { foreach ($algorithm in @($reference.algorithms)) { $ordinal++; $entries.Add((Invoke-ColdReference ([string]$reference.scenarioId) ([string]$reference.scenarioRelativePath) ([string]$algorithm) $ordinal)); Write-PilotCheckpoint 'running-fresh-cold-controls' $entries.ToArray() $null } }
    $measuredOrdinal = 0
    foreach ($campaign in @($plan.measuredCampaigns | Sort-Object ordinal)) {
        $campaignDirectory = Join-Path $pilotRoot ('measured\{0:D3}-{1}' -f [int]$campaign.ordinal, [string]$campaign.campaignId)
        for ($block = 1; $block -le [int]$campaign.blocks; $block++) {
            $measuredOrdinal++
            $blockPlan = New-G13R2V2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId ([string]$campaign.campaignId) -ScenarioRelativePath ([string]$campaign.scenarioRelativePath) -ScenarioSourceSha256 ([string]$campaign.scenarioSourceSha256) -ComparisonCohortId ([string]$campaign.comparisonCohortId) -Block $block -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $telemetryProbeResultPath
            $blockName = 'b{0:D3}' -f $block; $outputDirectory = Join-Path $campaignDirectory $blockName; $planFilePath = Join-Path $pilotRoot ('plans\{0}-{1}.block-plan.json' -f [string]$campaign.campaignId, $blockName)
            $entries.Add((Invoke-ProcessReuseBlock $blockPlan 'measured-non-formal-process-reuse' $outputDirectory $planFilePath $measuredOrdinal)); Write-PilotCheckpoint 'running-measured-blocks' $entries.ToArray() $null
        }
    }

    $endEnvironment = Get-EnvironmentSnapshot 'end-after-measured-blocks'; Write-G13R2V2Utf8NoBomJson (Join-Path $pilotRoot 'environment-end.json') $endEnvironment 20
    $warmupEntries = @($entries | Where-Object role -eq 'excluded-process-reuse-warmup'); $coldEntries = @($entries | Where-Object role -eq 'fresh-cold-structural-control'); $measuredEntries = @($entries | Where-Object role -eq 'measured-non-formal-process-reuse')
    if ($warmupEntries.Count -ne 1 -or $coldEntries.Count -ne 8 -or $measuredEntries.Count -ne 36 -or [int](($measuredEntries | Measure-Object sampleCount -Sum).Sum) -ne 96) { throw 'V2 pilot execution cardinality mismatch before analysis.' }
    $executionManifest = [ordered]@{ schemaVersion = 1; manifestKind = 'gate13-r2-v2-process-reuse-pilot-execution-manifest-v1'; startedAt = $startedAt.ToString('o'); completedAt = (Get-Date).ToString('o'); planId = [string]$plan.planId; planSha256 = Get-G13R2V2LowerSha256 $PilotPlanPath; provenanceSha256 = Get-G13R2V2LowerSha256 $ProvenancePath; telemetryProbeResultSha256 = Get-G13R2V2LowerSha256 $telemetryProbeResultPath; warmupBlockProcessCount = $warmupEntries.Count; warmupSampleCount = [int](($warmupEntries | Measure-Object sampleCount -Sum).Sum); freshColdProcessCount = $coldEntries.Count; freshColdSampleCount = [int](($coldEntries | Measure-Object sampleCount -Sum).Sum); measuredBlockProcessCount = $measuredEntries.Count; measuredSampleCount = [int](($measuredEntries | Measure-Object sampleCount -Sum).Sum); totalUnityProcessCount = $warmupEntries.Count + $coldEntries.Count + $measuredEntries.Count; entries = $entries.ToArray(); formalCampaign = $false; excludedFromFormalAnalysis = $true; automaticRetryCount = 0; automaticResumeCount = 0; formalExecutionAuthorized = $false; completed = $true }
    Write-G13R2V2Utf8NoBomJson (Join-Path $pilotRoot 'pilot-execution-manifest.json') $executionManifest 50
    Write-PilotCheckpoint 'pilot-execution-completed-analysis-pending' $entries.ToArray() $null

    $analysisStdout = Join-Path $pilotRoot 'analysis.stdout.log'; $analysisStderr = Join-Path $pilotRoot 'analysis.stderr.log'
    $analysisArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$analyzerPath,'-ProjectPath',$ProjectPath,'-PilotRoot',$pilotRoot,'-PilotPlanPath',$PilotPlanPath,'-ProvenancePath',$ProvenancePath)
    $analysisExit = Invoke-OwnedPowerShell $analysisArguments $analysisStdout $analysisStderr
    if ($analysisExit -ne 0) { throw "V2 pilot analysis failed without retry: exit=$analysisExit, stderr=$analysisStderr" }
    $pilotManifestPath = Join-Path $pilotRoot 'pilot-manifest.json'; $pilotManifest = Read-G13R2V2Json $pilotManifestPath
    if ($pilotManifest.completed -ne $true -or $pilotManifest.formalExecutionAuthorized -ne $false) { throw 'V2 pilot manifest is not a completed non-formal result.' }
    Write-PilotCheckpoint 'PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED' $entries.ToArray() $null
    $readiness = [ordered]@{ schemaVersion = 1; checkpointId = 'gate13-r2-v2-readiness-checkpoint-v1'; status = 'PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED'; savedAtUtc = [DateTime]::UtcNow.ToString('o'); pilotManifestSha256 = Get-G13R2V2LowerSha256 $pilotManifestPath; candidateSampleSizesSha256 = Get-G13R2V2LowerSha256 (Join-Path $pilotRoot 'candidate-sample-sizes.json'); measuredBlockProcessCount = 36; measuredSampleCount = 96; structuralMismatchCount = 0; formalCampaign = $false; formalExecutionAuthorized = $false; formalRootCreated = Test-Path $formalRoot; automaticRetryAttempted = $false; automaticResumeAttempted = $false; requiredNextAuthorization = 'separate-formal-campaign-authorization' }
    Write-G13R2V2AtomicUtf8NoBomJson (Join-Path $pilotRoot 'readiness-checkpoint.json') $readiness 30
    $outputManifestPath = Write-RootEvidenceManifest 'pilot-output-manifest.json' @('NON-FORMAL','EXCLUDED-FROM-FORMAL-ANALYSIS','PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED','NO-AUTO-RETRY','NO-RESUME')
    Get-ChildItem -LiteralPath $pilotRoot -File -Recurse | ForEach-Object { $_.IsReadOnly = $true }
    [pscustomobject][ordered]@{ passed = $true; pilotRoot = $pilotRoot; pilotManifestSha256 = Get-G13R2V2LowerSha256 $pilotManifestPath; readinessCheckpointSha256 = Get-G13R2V2LowerSha256 (Join-Path $pilotRoot 'readiness-checkpoint.json'); outputManifestSha256 = Get-G13R2V2LowerSha256 $outputManifestPath; totalUnityProcessCount = 45; measuredBlockProcessCount = 36; measuredSampleCount = 96; formalCampaign = $false; formalExecutionAuthorized = $false } | ConvertTo-Json -Depth 20
    exit 0
} catch {
    $message = $_.Exception.Message
    try {
        $failure = [ordered]@{ schemaVersion = 1; failureKind = 'gate13-r2-v2-process-reuse-pilot-failure-v1'; failedAtUtc = [DateTime]::UtcNow.ToString('o'); message = $message; completedEntryCount = $entries.Count; entries = $entries.ToArray(); automaticRetryAttempted = $false; automaticResumeAttempted = $false; formalCampaign = $false; formalExecutionAuthorized = $false }
        Write-G13R2V2AtomicUtf8NoBomJson (Join-Path $pilotRoot 'pilot-failure.json') $failure 50
        Write-PilotCheckpoint 'FAILED-NO-AUTO-RETRY-NO-RESUME' $entries.ToArray() $message
        [void](Write-RootEvidenceManifest 'pilot-partial-output-manifest.json' @('FAILED-NO-AUTO-RETRY','NO-RESUME','NON-FORMAL','EXCLUDED-FROM-FORMAL-ANALYSIS'))
        Get-ChildItem -LiteralPath $pilotRoot -File -Recurse | ForEach-Object { $_.IsReadOnly = $true }
    } catch { }
    Write-Error "Gate 13-R2 v2 pilot failed without auto-retry/resume: $message"
    exit 1
}
