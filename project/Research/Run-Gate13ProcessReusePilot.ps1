[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PilotPlanPath,
    [string]$ProvenancePath
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($PilotPlanPath)) { $PilotPlanPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Pilot_Plan.v1.json' }
if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { $ProvenancePath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Provenance.v4.json' }
$PilotPlanPath = [System.IO.Path]::GetFullPath($PilotPlanPath)
$ProvenancePath = [System.IO.Path]::GetFullPath($ProvenancePath)
$modulePath = Join-Path $PSScriptRoot 'Gate13ProcessReusePreparation.psm1'
$blockRunnerPath = Join-Path $PSScriptRoot 'Run-PlanningProcessReuseBlock.ps1'
$coldRunnerPath = Join-Path $PSScriptRoot 'Run-Gate13ProcessReuseColdReference.ps1'
$analyzerPath = Join-Path $PSScriptRoot 'Analyze-Gate13ProcessReusePilot.ps1'
$prePilotAuditPath = Join-Path $ProjectPath 'Research\Verification\Gate13R2_PrePilotAudit.summary.json'
Import-Module $modulePath -Force
$plan = Read-G13R2Json -Path $PilotPlanPath
$provenance = Read-G13R2Json -Path $ProvenancePath
$planCheck = Test-G13R2PilotPlan -ProjectPath $ProjectPath -Plan $plan -PlanPath $PilotPlanPath
if (-not $planCheck.passed) { throw "Process-reuse pilot plan validation failed: $($planCheck.errors -join '; ')" }
if (-not (Test-Path -LiteralPath $prePilotAuditPath -PathType Leaf)) { throw 'Pre-pilot audit summary is missing.' }
$prePilotAudit = Read-G13R2Json -Path $prePilotAuditPath
if ($prePilotAudit.passed -ne $true -or $prePilotAudit.pilotExecutionAuthorizedByAudit -ne $true -or $prePilotAudit.formalExecutionAuthorized -ne $false) { throw 'Pre-pilot audit did not pass the non-formal execution gate.' }
if ([string]$prePilotAudit.pilotPlanSha256 -ne (Get-G13R2LowerSha256 -Path $PilotPlanPath) -or [string]$prePilotAudit.provenanceSha256 -ne (Get-G13R2LowerSha256 -Path $ProvenancePath)) { throw 'Pre-pilot audit is not bound to the current plan/provenance bytes.' }
foreach ($property in $provenance.PSObject.Properties | Where-Object { $_.Value -is [pscustomobject] -and $_.Value.PSObject.Properties.Name -contains 'relativePath' -and $_.Value.PSObject.Properties.Name -contains 'sha256' }) {
    [void](Assert-G13R2BoundFile -ProjectPath $ProjectPath -RelativePath ([string]$property.Value.relativePath) -ExpectedSha256 ([string]$property.Value.sha256) -Label ("Pilot provenance " + $property.Name))
}

$pilotRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/', '\')))
$reservedFormalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.reservedFormalRootRelativePath).Replace('/', '\')))
if (Test-Path -LiteralPath $pilotRoot) { throw "Create-new pilot root already exists: $pilotRoot" }
if (Test-Path -LiteralPath $reservedFormalRoot) { throw "Reserved formal root already exists: $reservedFormalRoot" }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be closed and the project lock absent before pilot launch.' }

$nativePowerShellModulePath = @(
    'C:\Users\bdscy\Documents\WindowsPowerShell\Modules',
    'C:\Program Files\WindowsPowerShell\Modules',
    'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
) -join ';'
$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$unityPath = [System.IO.Path]::GetFullPath(([string]$plan.unity.executablePath).Replace('/', '\'))
if ((Get-G13R2LowerSha256 -Path $unityPath) -ne [string]$plan.unity.executableSha256) { throw 'Unity executable hash mismatch.' }

function Get-EnvironmentSnapshot([string]$Phase) {
    $processors = @(Get-CimInstance Win32_Processor)
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $loadSamples = New-Object System.Collections.Generic.List[double]
    for ($index = 0; $index -lt [int]$plan.environmentPreflight.cpuLoadSampleCount; $index++) {
        $load = ($processors | Measure-Object -Property LoadPercentage -Average).Average
        $loadSamples.Add($(if ($null -eq $load) { 0.0 } else { [double]$load }))
        if ($index -lt [int]$plan.environmentPreflight.cpuLoadSampleCount - 1) { Start-Sleep -Seconds ([int]$plan.environmentPreflight.cpuLoadSampleIntervalSeconds); $processors = @(Get-CimInstance Win32_Processor) }
    }
    $powerRaw = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
    $powerMatch = [regex]::Match($powerRaw, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    $drive = New-Object System.IO.DriveInfo -ArgumentList @([System.IO.Path]::GetPathRoot($pilotRoot))
    $meanCpu = [double](($loadSamples.ToArray() | Measure-Object -Average).Average)
    $freeMemory = [int64]([double]$operatingSystem.FreePhysicalMemory * 1KB)
    $failed = New-Object System.Collections.Generic.List[string]
    if (-not $powerMatch.Success -or $powerMatch.Value.ToLowerInvariant() -ne [string]$plan.environmentPreflight.requiredActivePowerSchemeGuid) { $failed.Add('power-scheme') }
    if ($freeMemory -lt [int64]$plan.environmentPreflight.minimumFreePhysicalMemoryBytes) { $failed.Add('free-memory') }
    if ($meanCpu -gt [double]$plan.environmentPreflight.maximumMeanCpuLoadPercent) { $failed.Add('mean-cpu-load') }
    if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0) { $failed.Add('unity-process') }
    if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { $failed.Add('unity-lockfile') }
    if ($drive.AvailableFreeSpace -lt 10GB) { $failed.Add('pilot-storage-below-10GiB') }
    if (Test-Path -LiteralPath $reservedFormalRoot) { $failed.Add('reserved-formal-root-exists') }
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        phase = $Phase
        capturedAt = (Get-Date).ToString('o')
        machineName = $env:COMPUTERNAME
        userName = $env:USERNAME
        cpuModels = @($processors | ForEach-Object { ([string]$_.Name).Trim() })
        logicalProcessorCount = [int]$computerSystem.NumberOfLogicalProcessors
        totalPhysicalMemoryBytes = [int64]$computerSystem.TotalPhysicalMemory
        freePhysicalMemoryBytes = $freeMemory
        operatingSystem = [string]$operatingSystem.Caption
        powerSchemeRaw = $powerRaw
        powerSchemeGuid = if ($powerMatch.Success) { $powerMatch.Value.ToLowerInvariant() } else { $null }
        cpuLoadSamplesPercent = $loadSamples.ToArray()
        meanCpuLoadPercent = $meanCpu
        outputDriveFreeBytes = [int64]$drive.AvailableFreeSpace
        unityProcessIds = @(Get-Process -Name Unity -ErrorAction SilentlyContinue | ForEach-Object Id)
        unityLockfilePresent = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
        reservedFormalRootPresent = Test-Path -LiteralPath $reservedFormalRoot
        failedChecks = $failed.ToArray()
        passed = $failed.Count -eq 0
    }
}

function Write-PilotCheckpoint([string]$Status, [object[]]$Entries, [string]$ErrorMessage) {
    $checkpoint = [ordered]@{
        schemaVersion = 1
        checkpointKind = 'gate13-r2-process-reuse-pilot-checkpoint-v1'
        status = $Status
        savedAt = (Get-Date).ToString('o')
        planId = [string]$plan.planId
        planSha256 = Get-G13R2LowerSha256 -Path $PilotPlanPath
        provenanceSha256 = Get-G13R2LowerSha256 -Path $ProvenancePath
        prePilotAuditRelativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $prePilotAuditPath
        prePilotAuditSha256 = Get-G13R2LowerSha256 -Path $prePilotAuditPath
        completedEntryCount = @($Entries).Count
        entries = @($Entries)
        error = $ErrorMessage
        formalCampaign = $false
        excludedFromFormalAnalysis = $true
        automaticRetryAuthorized = $false
        automaticResumeAuthorized = $false
        formalExecutionAuthorized = $false
    }
    Write-G13R2AtomicUtf8NoBomJson -Path (Join-Path $pilotRoot 'pilot-checkpoint.json') -Value $checkpoint -Depth 30
}

function Invoke-OwnedPowerShell([string[]]$Arguments, [string]$StdoutPath, [string]$StderrPath) {
    $previousModulePath = $env:PSModulePath
    try {
        $env:PSModulePath = $nativePowerShellModulePath
        & $windowsPowerShell @Arguments 1> $StdoutPath 2> $StderrPath
        return [int]$LASTEXITCODE
    } finally { $env:PSModulePath = $previousModulePath }
}

function Invoke-ProcessReuseBlock($BlockPlan, [string]$Role, [string]$OutputDirectory, [string]$PlanFilePath, [int]$Ordinal) {
    if (Test-Path -LiteralPath $PlanFilePath) { throw "Block plan output exists: $PlanFilePath" }
    Write-G13R2Utf8NoBomJson -Path $PlanFilePath -Value $BlockPlan -Depth 30
    $outputParent = Split-Path -Parent $OutputDirectory
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $outputParent -Force)
    }
    $stdoutPath = $OutputDirectory + '.wrapper.stdout.log'
    $stderrPath = $OutputDirectory + '.wrapper.stderr.log'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $blockRunnerPath, '-BlockPlanPath', $PlanFilePath, '-OutputDirectory', $OutputDirectory, '-UnityPath', $unityPath, '-ProjectPath', $ProjectPath)
    $started = Get-Date
    Write-Host ("[{0}] Starting {1} block {2}" -f $Ordinal, $Role, $BlockPlan.blockId) -ForegroundColor Cyan
    $exitCode = Invoke-OwnedPowerShell -Arguments $arguments -StdoutPath $stdoutPath -StderrPath $stderrPath
    $completed = Get-Date
    if ($exitCode -ne 0) { throw "Process-reuse block failed without retry: $($BlockPlan.blockId), exit=$exitCode, stderr=$stderrPath" }
    $summaryPath = $OutputDirectory + '.summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Block wrapper summary missing: $summaryPath" }
    $summary = Read-G13R2Json -Path $summaryPath
    if ($summary.passed -ne $true -or $summary.formalCampaign -ne $false) { throw "Block wrapper summary invalid: $summaryPath" }
    return [pscustomobject][ordered]@{
        role = $Role
        ordinal = $Ordinal
        blockId = [string]$BlockPlan.blockId
        planRelativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $PlanFilePath
        planSha256 = Get-G13R2LowerSha256 -Path $PlanFilePath
        outputRelativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $OutputDirectory
        summaryRelativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $summaryPath
        summarySha256 = Get-G13R2LowerSha256 -Path $summaryPath
        processId = [int](Read-G13R2Json -Path (Join-Path $OutputDirectory 'block-manifest.json')).processId
        sampleCount = [int]$summary.sampleCount
        wallSeconds = ($completed - $started).TotalSeconds
        formalCampaign = $false
        completed = $true
    }
}

function Invoke-ColdReference([string]$ScenarioId, [string]$ScenarioRelativePath, [string]$AlgorithmId, [int]$Ordinal) {
    $scenarioPath = Join-Path $ProjectPath $ScenarioRelativePath.Replace('/', '\')
    $slug = Get-G13R2AlgorithmSlug -AlgorithmId $AlgorithmId
    $outputDirectory = Join-Path $pilotRoot ("cold-reference\{0}\{1}" -f $ScenarioId, $slug)
    $outputParent = Split-Path -Parent $outputDirectory
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $outputParent -Force)
    }
    $runId = "g13r2p-ref-$ScenarioId-$slug"
    $stdoutPath = $outputDirectory + '.wrapper.stdout.log'
    $stderrPath = $outputDirectory + '.wrapper.stderr.log'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $coldRunnerPath, '-ScenarioPath', $scenarioPath, '-OutputDirectory', $outputDirectory, '-RunId', $runId, '-Algorithm', $AlgorithmId, '-UnityPath', $unityPath, '-ProjectPath', $ProjectPath)
    $started = Get-Date
    Write-Host ("[{0}] Starting fresh cold structural control {1}/{2}" -f $Ordinal, $ScenarioId, $AlgorithmId) -ForegroundColor DarkCyan
    $exitCode = Invoke-OwnedPowerShell -Arguments $arguments -StdoutPath $stdoutPath -StderrPath $stderrPath
    $completed = Get-Date
    if ($exitCode -ne 0) { throw "Fresh cold structural control failed without retry: $runId, exit=$exitCode" }
    $manifestPath = Join-Path $outputDirectory 'manifest.json'
    $resultPath = Join-Path $outputDirectory 'workload-result.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw "Fresh cold structural control artifacts missing: $runId" }
    $manifest = Read-G13R2Json -Path $manifestPath
    if ($manifest.completed -ne $true -or $manifest.runId -ne $runId -or $manifest.algorithmId -ne $AlgorithmId) { throw "Fresh cold control manifest invalid: $runId" }
    return [pscustomobject][ordered]@{
        role = 'fresh-cold-structural-control'
        ordinal = $Ordinal
        runId = $runId
        scenarioId = $ScenarioId
        algorithmId = $AlgorithmId
        outputRelativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $outputDirectory
        manifestSha256 = Get-G13R2LowerSha256 -Path $manifestPath
        workloadResultSha256 = Get-G13R2LowerSha256 -Path $resultPath
        sampleCount = 1
        wallSeconds = ($completed - $started).TotalSeconds
        formalCampaign = $false
        completed = $true
    }
}

$preflight = Get-EnvironmentSnapshot -Phase 'launch-preflight-before-pilot-root'
if (-not $preflight.passed) { throw "Process-reuse pilot preflight failed before root creation: $($preflight.failedChecks -join ', ')" }
New-Item -ItemType Directory -Path $pilotRoot | Out-Null
$entries = New-Object System.Collections.Generic.List[object]
$startedAt = Get-Date
try {
    Write-G13R2Utf8NoBomJson -Path (Join-Path $pilotRoot 'environment-start.json') -Value $preflight -Depth 20
    New-Item -ItemType Directory -Path (Join-Path $pilotRoot 'plans') | Out-Null
    Write-PilotCheckpoint -Status 'preflight-passed' -Entries @() -ErrorMessage $null

    $warmup = $plan.warmup
    $warmupPlan = New-G13R2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId ([string]$warmup.campaignId) -ScenarioRelativePath ([string]$warmup.scenarioRelativePath) -ScenarioSourceSha256 ([string]$warmup.scenarioSourceSha256) -ComparisonCohortId ([string]$warmup.comparisonCohortId) -Block ([int]$warmup.block) -ProvenancePath $ProvenancePath -Warmup
    $warmupOutput = Join-Path $pilotRoot 'warmup\block-b001'
    $warmupPlanPath = Join-Path $pilotRoot 'plans\warmup-b001.block-plan.json'
    $entries.Add((Invoke-ProcessReuseBlock -BlockPlan $warmupPlan -Role 'excluded-process-reuse-warmup' -OutputDirectory $warmupOutput -PlanFilePath $warmupPlanPath -Ordinal 0))
    Write-PilotCheckpoint -Status 'warmup-completed' -Entries $entries.ToArray() -ErrorMessage $null
    Start-Sleep -Seconds ([int]$warmup.quietStabilizationSecondsAfterWarmup)
    $postWarmup = Get-EnvironmentSnapshot -Phase 'post-warmup-stabilized'
    Write-G13R2Utf8NoBomJson -Path (Join-Path $pilotRoot 'environment-post-warmup.json') -Value $postWarmup -Depth 20
    if (-not $postWarmup.passed) { throw "Post-warmup environment check failed: $($postWarmup.failedChecks -join ', ')" }

    $ordinal = 0
    foreach ($reference in @($plan.freshColdReferences)) {
        foreach ($algorithm in @($reference.algorithms)) {
            $ordinal++
            $entries.Add((Invoke-ColdReference -ScenarioId ([string]$reference.scenarioId) -ScenarioRelativePath ([string]$reference.scenarioRelativePath) -AlgorithmId ([string]$algorithm) -Ordinal $ordinal))
            Write-PilotCheckpoint -Status 'running-fresh-cold-controls' -Entries $entries.ToArray() -ErrorMessage $null
        }
    }

    $measuredOrdinal = 0
    foreach ($campaign in @($plan.measuredCampaigns | Sort-Object ordinal)) {
        $campaignDirectory = Join-Path $pilotRoot ('measured\{0:D3}-{1}' -f [int]$campaign.ordinal, [string]$campaign.campaignId)
        for ($block = 1; $block -le [int]$campaign.blocks; $block++) {
            $measuredOrdinal++
            $blockPlan = New-G13R2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId ([string]$campaign.campaignId) -ScenarioRelativePath ([string]$campaign.scenarioRelativePath) -ScenarioSourceSha256 ([string]$campaign.scenarioSourceSha256) -ComparisonCohortId ([string]$campaign.comparisonCohortId) -Block $block -ProvenancePath $ProvenancePath
            $blockName = 'b{0:D3}' -f $block
            $outputDirectory = Join-Path $campaignDirectory $blockName
            $planFilePath = Join-Path $pilotRoot ('plans\{0}-{1}.block-plan.json' -f [string]$campaign.campaignId, $blockName)
            $entries.Add((Invoke-ProcessReuseBlock -BlockPlan $blockPlan -Role 'measured-non-formal-process-reuse' -OutputDirectory $outputDirectory -PlanFilePath $planFilePath -Ordinal $measuredOrdinal))
            Write-PilotCheckpoint -Status 'running-measured-blocks' -Entries $entries.ToArray() -ErrorMessage $null
        }
    }

    $endEnvironment = Get-EnvironmentSnapshot -Phase 'end-after-measured-blocks'
    Write-G13R2Utf8NoBomJson -Path (Join-Path $pilotRoot 'environment-end.json') -Value $endEnvironment -Depth 20
    $warmupEntries = @($entries | Where-Object role -eq 'excluded-process-reuse-warmup')
    $coldEntries = @($entries | Where-Object role -eq 'fresh-cold-structural-control')
    $measuredEntries = @($entries | Where-Object role -eq 'measured-non-formal-process-reuse')
    if ($warmupEntries.Count -ne 1 -or $coldEntries.Count -ne 8 -or $measuredEntries.Count -ne 36 -or [int](($measuredEntries | Measure-Object sampleCount -Sum).Sum) -ne 96) { throw 'Pilot execution cardinality mismatch before analysis.' }
    $executionManifest = [ordered]@{
        schemaVersion = 1
        manifestKind = 'gate13-r2-process-reuse-pilot-execution-manifest-v1'
        startedAt = $startedAt.ToString('o')
        completedAt = (Get-Date).ToString('o')
        planId = [string]$plan.planId
        planSha256 = Get-G13R2LowerSha256 -Path $PilotPlanPath
        provenanceSha256 = Get-G13R2LowerSha256 -Path $ProvenancePath
        warmupBlockProcessCount = $warmupEntries.Count
        warmupSampleCount = [int](($warmupEntries | Measure-Object sampleCount -Sum).Sum)
        freshColdProcessCount = $coldEntries.Count
        freshColdSampleCount = [int](($coldEntries | Measure-Object sampleCount -Sum).Sum)
        measuredBlockProcessCount = $measuredEntries.Count
        measuredSampleCount = [int](($measuredEntries | Measure-Object sampleCount -Sum).Sum)
        totalUnityProcessCount = $warmupEntries.Count + $coldEntries.Count + $measuredEntries.Count
        entries = $entries.ToArray()
        formalCampaign = $false
        excludedFromFormalAnalysis = $true
        automaticRetryCount = 0
        automaticResumeCount = 0
        formalExecutionAuthorized = $false
        completed = $true
    }
    Write-G13R2Utf8NoBomJson -Path (Join-Path $pilotRoot 'pilot-execution-manifest.json') -Value $executionManifest -Depth 30
    Write-PilotCheckpoint -Status 'pilot-execution-completed-analysis-pending' -Entries $entries.ToArray() -ErrorMessage $null

    $analysisStdout = Join-Path $pilotRoot 'analysis.stdout.log'
    $analysisStderr = Join-Path $pilotRoot 'analysis.stderr.log'
    $analysisArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $analyzerPath, '-ProjectPath', $ProjectPath, '-PilotRoot', $pilotRoot, '-PilotPlanPath', $PilotPlanPath, '-ProvenancePath', $ProvenancePath)
    $analysisExit = Invoke-OwnedPowerShell -Arguments $analysisArguments -StdoutPath $analysisStdout -StderrPath $analysisStderr
    if ($analysisExit -ne 0) { throw "Process-reuse pilot analysis failed without retry: exit=$analysisExit, stderr=$analysisStderr" }
    $pilotManifestPath = Join-Path $pilotRoot 'pilot-manifest.json'
    $pilotManifest = Read-G13R2Json -Path $pilotManifestPath
    if ($pilotManifest.completed -ne $true -or $pilotManifest.formalExecutionAuthorized -ne $false) { throw 'Pilot manifest is not a completed non-formal result.' }
    Write-PilotCheckpoint -Status 'PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED' -Entries $entries.ToArray() -ErrorMessage $null
    [pscustomobject][ordered]@{
        passed = $true
        pilotRoot = $pilotRoot
        pilotManifestPath = $pilotManifestPath
        pilotManifestSha256 = Get-G13R2LowerSha256 -Path $pilotManifestPath
        totalUnityProcessCount = [int]$executionManifest.totalUnityProcessCount
        measuredBlockProcessCount = [int]$executionManifest.measuredBlockProcessCount
        measuredSampleCount = [int]$executionManifest.measuredSampleCount
        formalCampaign = $false
        formalExecutionAuthorized = $false
    } | ConvertTo-Json -Depth 12
    exit 0
} catch {
    $message = $_.Exception.Message
    try {
        $failure = [ordered]@{
            schemaVersion = 1
            failureKind = 'gate13-r2-process-reuse-pilot-failure-v1'
            failedAt = (Get-Date).ToString('o')
            message = $message
            completedEntryCount = $entries.Count
            entries = $entries.ToArray()
            automaticRetryAttempted = $false
            automaticResumeAttempted = $false
            formalCampaign = $false
            formalExecutionAuthorized = $false
        }
        Write-G13R2AtomicUtf8NoBomJson -Path (Join-Path $pilotRoot 'pilot-failure.json') -Value $failure -Depth 30
        Write-PilotCheckpoint -Status 'failed-no-auto-retry' -Entries $entries.ToArray() -ErrorMessage $message
    } catch { }
    Write-Error "Gate 13-R2 process-reuse pilot failed without auto-retry: $message"
    exit 1
}
