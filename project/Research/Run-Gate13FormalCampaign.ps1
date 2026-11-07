[CmdletBinding(DefaultParameterSetName = 'ValidationOnly')]
param(
    [string]$ProjectPath,
    [string]$ConfigPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'ValidationOnly')][switch]$ValidationOnly,
    [Parameter(Mandatory = $true, ParameterSetName = 'Execute')][switch]$Execute,
    [Parameter(Mandatory = $true, ParameterSetName = 'Execute')][string]$ExecutionAuthorizationPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $ProjectPath 'Research\Gate13_Formal_Campaign_Config.v1.json' }
elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath = Join-Path $ProjectPath $ConfigPath }
$ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)

$modulePath = Join-Path $scriptDirectory 'Gate13FormalPreparation.psm1'
$scenarioRunnerPath = Join-Path $scriptDirectory 'Run-Gate13FormalScenarioCampaign.ps1'
Import-Module $modulePath -Force
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Gate 13 formal config not found: $ConfigPath" }
if (-not (Test-Path -LiteralPath $scenarioRunnerPath -PathType Leaf)) { throw "Gate 13 scenario runner not found: $scenarioRunnerPath" }
$config = Read-Gate13Json -Path $ConfigPath
$configCheck = Test-Gate13FormalConfig -ProjectPath $ProjectPath -Config $config -ConfigPath $ConfigPath
if (-not $configCheck.passed) { throw "Gate 13 config validation failed: $($configCheck.errors -join '; ')" }
$configSha256 = Get-Gate13LowerSha256 -Path $ConfigPath
$amendmentPath = Join-Path $ProjectPath ([string]$config.frozenInputs.gate13Amendment.relativePath).Replace('/', '\')
$amendmentSha256 = Get-Gate13LowerSha256 -Path $amendmentPath
$formalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$config.output.rootRelativePath).Replace('/', '\')))
$bundleRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalScenarios\v1'))
if (Test-Gate13PathWithin -CandidatePath $formalRoot -RootPath $bundleRoot -AllowRoot) { throw 'Formal output root cannot be inside the Gate 11 retained bundle.' }

if ($ValidationOnly) {
    $rootBefore = Test-Path -LiteralPath $formalRoot
    if ($rootBefore) { throw "Gate 13 formal root already exists: $formalRoot" }
    $preflight = Get-Gate13EnvironmentPreflight -ProjectPath $ProjectPath -Config $config -Purpose 'validation-only-advisory'
    $rootAfter = Test-Path -LiteralPath $formalRoot
    $unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
    $lockPresent = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
    $passed = $configCheck.passed -and $preflight.passed -and -not $rootBefore -and -not $rootAfter -and $unityProcesses.Count -eq 0 -and -not $lockPresent
    [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'validation-only'
        configId = $config.configId
        configSha256 = $configSha256
        amendmentSha256 = $amendmentSha256
        campaignCount = @($config.campaigns).Count
        expectedUnityProcessCount = [int]$config.totals.expectedUnityProcessCount
        maximumBlocksSupported = [int]$config.scheduleDesign.maximumBlocksSupported
        formalOutputRoot = $formalRoot
        formalRootPresentBefore = $rootBefore
        formalRootPresentAfter = $rootAfter
        unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
        unityLockfilePresent = $lockPresent
        preflight = $preflight
        executionAuthorizationValidated = $false
        executionAttempted = $false
        outputCreated = $false
        launchAuthorizationConferred = $false
        passed = $passed
    } | ConvertTo-Json -Depth 16
    if (-not $passed) { Write-Error "Gate 13 validation-only checks failed: $($preflight.failedChecks -join ', ')"; exit 1 }
    Write-Host 'Gate 13 validation-only checks passed; no formal root or Unity process was created.' -ForegroundColor Green
    exit 0
}

if (-not $Execute) { throw 'Choose exactly one mode: -ValidationOnly or -Execute.' }
if (-not [System.IO.Path]::IsPathRooted($ExecutionAuthorizationPath)) { $ExecutionAuthorizationPath = Join-Path $ProjectPath $ExecutionAuthorizationPath }
$ExecutionAuthorizationPath = [System.IO.Path]::GetFullPath($ExecutionAuthorizationPath)
if (-not (Test-Path -LiteralPath $ExecutionAuthorizationPath -PathType Leaf)) { throw "Execution authorization receipt not found: $ExecutionAuthorizationPath" }
$authorization = Read-Gate13Json -Path $ExecutionAuthorizationPath
$authorizationCheck = Test-Gate13ExecutionAuthorization -Authorization $authorization -ExpectedConfigSha256 $configSha256 -ExpectedAmendmentSha256 $amendmentSha256 -ExpectedOutputRootRelativePath ([string]$config.output.rootRelativePath)
if (-not $authorizationCheck.passed) { throw "Gate 13 execution authorization invalid: $($authorizationCheck.errors -join '; ')" }
$authorizationSha256 = Get-Gate13LowerSha256 -Path $ExecutionAuthorizationPath
if (Test-Path -LiteralPath $formalRoot) { throw "Formal output root already exists; create-new policy refuses overwrite/resume: $formalRoot" }

# This launch preflight deliberately occurs after receipt/config validation and immediately before root creation.
$launchPreflight = Get-Gate13EnvironmentPreflight -ProjectPath $ProjectPath -Config $config -Purpose 'launch-after-authorization'
if (-not $launchPreflight.passed) { throw "Gate 13 launch preflight failed before formal-root creation: $($launchPreflight.failedChecks -join ', ')" }
New-Item -ItemType Directory -Path $formalRoot | Out-Null

$checkpointPath = Join-Path $formalRoot ([string]$config.checkpoint.relativePath).Replace('/', '\')
$logsDirectory = Join-Path $formalRoot 'logs'
New-Item -ItemType Directory -Path $logsDirectory | Out-Null
Write-Gate13Utf8NoBomJson -Path (Join-Path $formalRoot 'launch-preflight.json') -Value $launchPreflight -Depth 20
Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $formalRoot 'frozen-config.json')
Copy-Item -LiteralPath $ExecutionAuthorizationPath -Destination (Join-Path $formalRoot 'execution-authorization.json')
$completedCampaigns = New-Object System.Collections.Generic.List[object]
$formalStartedAt = Get-Date

function Write-FormalCheckpoint {
    param([string]$Status, [int]$CurrentCampaignOrdinal, [string]$CurrentCampaignId, [string]$ErrorMessage)
    $completedSamples = 0
    if ($completedCampaigns.Count -gt 0) { $completedSamples = [int](($completedCampaigns.ToArray() | Measure-Object -Property sampleCount -Sum).Sum) }
    $checkpoint = [ordered]@{
        schemaVersion = 1
        checkpointId = 'gate13-formal-checkpoint-v1'
        status = $Status
        savedAt = (Get-Date).ToString('o')
        formalStartedAt = $formalStartedAt.ToString('o')
        configId = $config.configId
        configSha256 = $configSha256
        amendmentSha256 = $amendmentSha256
        executionAuthorizationId = $authorization.authorizationId
        executionAuthorizationSha256 = $authorizationSha256
        expectedCampaignCount = [int]$config.totals.campaignCount
        expectedUnityProcessCount = [int]$config.totals.expectedUnityProcessCount
        completedCampaignCount = $completedCampaigns.Count
        completedSampleCount = $completedSamples
        currentCampaignOrdinal = $CurrentCampaignOrdinal
        currentCampaignId = $CurrentCampaignId
        completedCampaigns = $completedCampaigns.ToArray()
        error = $ErrorMessage
        automaticResumeAuthorized = $false
        automaticRetryAuthorized = $false
        formalCampaign = $true
    }
    Write-Gate13AtomicUtf8NoBomJson -Path $checkpointPath -Value $checkpoint -Depth 20
}

Write-FormalCheckpoint -Status 'preflight-passed-awaiting-first-campaign' -CurrentCampaignOrdinal 0 -CurrentCampaignId $null -ErrorMessage $null

$campaign = $null
try {
    foreach ($campaign in @($config.campaigns)) {
        $ordinal = [int]$campaign.ordinal
        $campaignId = [string]$campaign.campaignId
        $campaignDirectory = Join-Path $formalRoot ([string]$campaign.outputRelativePath).Replace('/', '\')
        $stdoutPath = Join-Path $logsDirectory ('c{0:D3}.stdout.log' -f $ordinal)
        $stderrPath = Join-Path $logsDirectory ('c{0:D3}.stderr.log' -f $ordinal)
        $monitorPath = Join-Path $logsDirectory ('c{0:D3}.monitor.jsonl' -f $ordinal)
        foreach ($path in @($campaignDirectory, ($campaignDirectory + '.summary.json'), $stdoutPath, $stderrPath, $monitorPath)) {
            if (Test-Path -LiteralPath $path) { throw "Create-new policy found an existing campaign artifact: $path" }
        }
        Write-FormalCheckpoint -Status 'running-campaign' -CurrentCampaignOrdinal $ordinal -CurrentCampaignId $campaignId -ErrorMessage $null

        $quotedProject = '"' + $ProjectPath.Replace('"', '\"') + '"'
        $quotedConfig = '"' + $ConfigPath.Replace('"', '\"') + '"'
        $quotedAuthorization = '"' + $ExecutionAuthorizationPath.Replace('"', '\"') + '"'
        $arguments = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $scenarioRunnerPath.Replace('"', '\"') + '"'),
            '-ProjectPath', $quotedProject,
            '-ConfigPath', $quotedConfig,
            '-CampaignOrdinal', $ordinal,
            '-Execute',
            '-ExecutionAuthorizationPath', $quotedAuthorization
        )
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastBytes = [int64]-1
        $noGrowthChecks = 0
        $timedOut = $false
        while (-not $process.HasExited) {
            Start-Sleep -Seconds ([int]$config.monitoring.checkIntervalSeconds)
            $process.Refresh()
            $observedBytes = Get-Gate13DirectoryByteCount -Path $campaignDirectory
            foreach ($path in @($stdoutPath, $stderrPath)) { if (Test-Path -LiteralPath $path -PathType Leaf) { $observedBytes += [int64](Get-Item -LiteralPath $path).Length } }
            if ($observedBytes -le $lastBytes) { $noGrowthChecks++ } else { $noGrowthChecks = 0 }
            $lastBytes = $observedBytes
            $decision = Get-Gate13MonitorDecision -ElapsedSeconds $stopwatch.Elapsed.TotalSeconds -NoGrowthChecks $noGrowthChecks -HardTimeoutSeconds ([double]$config.monitoring.hardTimeoutSecondsPerCampaign) -OutputStallChecks ([int]$config.monitoring.outputStallChecks)
            $event = [ordered]@{ capturedAt = (Get-Date).ToString('o'); elapsedSeconds = $stopwatch.Elapsed.TotalSeconds; observedBytes = $observedBytes; noGrowthChecks = $noGrowthChecks; action = $decision.action }
            [System.IO.File]::AppendAllText($monitorPath, (ConvertTo-Gate13JsonText -Value $event -Depth 6), (New-Object System.Text.UTF8Encoding($false, $true)))
            if ($decision.action -eq 'hard-timeout') {
                $timedOut = $true
                & taskkill.exe /PID $process.Id /T /F | Out-Null
                break
            }
        }
        $process.WaitForExit()
        $stopwatch.Stop()
        if ($timedOut) { throw "Campaign $campaignId reached the 10,800-second hard timeout; owned process tree was terminated and no retry was attempted." }
        if ($process.ExitCode -ne 0) { throw "Campaign $campaignId exited with code $($process.ExitCode); no retry was attempted. See $stderrPath" }

        $summaryPath = $campaignDirectory + '.summary.json'
        $manifestPath = Join-Path $campaignDirectory 'campaign-manifest.json'
        if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Campaign completion artifacts are missing: $campaignId" }
        $summary = Read-Gate13Json -Path $summaryPath
        $manifest = Read-Gate13Json -Path $manifestPath
        if ($summary.passed -ne $true -or $summary.formalCampaign -ne $true -or $manifest.completed -ne $true -or $manifest.formalCampaign -ne $true -or [int]$manifest.sampleCount -ne [int]$campaign.sampleCount -or $manifest.canonicalScheduleSha256 -ne $campaign.canonicalScheduleSha256) { throw "Campaign completion identity invalid: $campaignId" }
        $completedCampaigns.Add([pscustomobject][ordered]@{
            ordinal = $ordinal
            campaignId = $campaignId
            sampleCount = [int]$campaign.sampleCount
            outputRelativePath = [string]$campaign.outputRelativePath
            campaignManifestSha256 = Get-Gate13LowerSha256 -Path $manifestPath
            campaignSummarySha256 = Get-Gate13LowerSha256 -Path $summaryPath
            elapsedSeconds = $stopwatch.Elapsed.TotalSeconds
            completed = $true
        })
        Write-FormalCheckpoint -Status 'campaign-completed' -CurrentCampaignOrdinal $ordinal -CurrentCampaignId $campaignId -ErrorMessage $null
    }

    $completedSamples = [int](($completedCampaigns.ToArray() | Measure-Object -Property sampleCount -Sum).Sum)
    if ($completedCampaigns.Count -ne [int]$config.totals.campaignCount -or $completedSamples -ne [int]$config.totals.expectedUnityProcessCount) { throw 'Final formal campaign/sample totals mismatch.' }
    $formalManifest = [ordered]@{
        schemaVersion = 1
        campaignKind = 'gate13-formal-campaign-v1'
        configId = $config.configId
        configSha256 = $configSha256
        amendmentSha256 = $amendmentSha256
        executionAuthorizationId = $authorization.authorizationId
        executionAuthorizationSha256 = $authorizationSha256
        outputRootRelativePath = $config.output.rootRelativePath
        campaignCount = $completedCampaigns.Count
        unityProcessCount = $completedSamples
        campaigns = $completedCampaigns.ToArray()
        startedAt = $formalStartedAt.ToString('o')
        completedAt = (Get-Date).ToString('o')
        formalCampaign = $true
        completed = $true
    }
    Write-Gate13Utf8NoBomJson -Path (Join-Path $formalRoot 'formal-campaign-manifest.json') -Value $formalManifest -Depth 20
    Write-FormalCheckpoint -Status 'formal-campaign-completed' -CurrentCampaignOrdinal 74 -CurrentCampaignId $null -ErrorMessage $null
    $formalManifest | ConvertTo-Json -Depth 10
    Write-Host 'Gate 13 formal campaign completed.' -ForegroundColor Green
    exit 0
} catch {
    $message = $_.Exception.Message
    $currentOrdinal = 0
    $currentId = $null
    if ($null -ne $campaign) { $currentOrdinal = [int]$campaign.ordinal; $currentId = [string]$campaign.campaignId }
    Write-FormalCheckpoint -Status 'failed-no-auto-retry' -CurrentCampaignOrdinal $currentOrdinal -CurrentCampaignId $currentId -ErrorMessage $message
    $failure = [ordered]@{ schemaVersion = 1; savedAt = (Get-Date).ToString('o'); message = $message; currentCampaignOrdinal = $currentOrdinal; currentCampaignId = $currentId; automaticRetryAttempted = $false; formalCampaign = $true }
    Write-Gate13AtomicUtf8NoBomJson -Path (Join-Path $formalRoot 'formal-failure.json') -Value $failure -Depth 10
    throw
}
