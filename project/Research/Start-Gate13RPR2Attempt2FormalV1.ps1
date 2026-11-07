[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$LaunchEvidenceDirectory,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'ProjectPath must be an explicit absolute path.'
}
if ([string]::IsNullOrWhiteSpace($LaunchEvidenceDirectory) -or -not [IO.Path]::IsPathRooted($LaunchEvidenceDirectory)) {
    throw 'LaunchEvidenceDirectory must be an explicit absolute path.'
}

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
$LaunchEvidenceDirectory = [IO.Path]::GetFullPath($LaunchEvidenceDirectory).TrimEnd('\', '/')
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Start-Gate13RPR2Attempt2FormalV1|$ProjectPath|$LaunchEvidenceDirectory"
    exit 0
}
$powershellExe = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$campaignScript = Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalCampaignV6.ps1'
$configPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Campaign_Config.v2.json'
$schedulePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl'
$scheduleManifestPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json'
$readinessPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json'
$adapterProvenancePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Attempt2_Formal_Execution_Adapter_Provenance.v2.json'
$executionReceiptPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v2.json'
$receiptValidationPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\ReceiptValidationAttempt1\summary.json'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v2'
$formalStatusPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v2.json'
$unityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe'
$lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$expectedNativeModulePath = @(
    'C:\Users\bdscy\Documents\WindowsPowerShell\Modules',
    'C:\Program Files\WindowsPowerShell\Modules',
    'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
) -join ';'
$expectedReceiptSha256 = 'a21466228b1e91dd8670093953b28333e235c9ff031b54fe385301c93ee8365e'
$expectedReceiptValidationSha256 = '306aa5e0cdeeadc0a1123258cc54656119ef6929bbb311578e6152b5c60aa560'
$minimumFreeBytes = 57397541440L

foreach ($requiredPath in @(
    $powershellExe,
    $campaignScript,
    $configPath,
    $schedulePath,
    $scheduleManifestPath,
    $readinessPath,
    $adapterProvenancePath,
    $executionReceiptPath,
    $receiptValidationPath,
    $unityPath
)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required launch input is missing: $requiredPath"
    }
}

if (Test-Path -LiteralPath $LaunchEvidenceDirectory) {
    throw 'LaunchEvidenceDirectory must be absent before the one-shot launch.'
}
if (Test-Path -LiteralPath $formalRoot) {
    throw 'Attempt-2 formal root already exists; retry/resume is forbidden.'
}
if (Test-Path -LiteralPath $formalStatusPath) {
    throw 'Attempt-2 formal status already exists; retry/resume is forbidden.'
}
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Unity is not quiescent at the one-shot launch boundary.'
}
if (Test-Path -LiteralPath $lockPath) {
    throw 'Unity project lock exists at the one-shot launch boundary.'
}

$receiptItem = Get-Item -LiteralPath $executionReceiptPath -Force
$receiptSha256 = (Get-FileHash -LiteralPath $executionReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($receiptSha256 -ne $expectedReceiptSha256) {
    throw "Execution receipt SHA-256 mismatch: $receiptSha256"
}
if (-not $receiptItem.IsReadOnly) {
    throw 'Execution receipt must be read-only before launch.'
}

$receipt = Get-Content -Raw -LiteralPath $executionReceiptPath | ConvertFrom-Json
if ([string]$receipt.receiptKind -ne 'gate13r-pr2-s48-h48-formal-raw-acquisition-execution-receipt-attempt-2-v1' -or
    [string]$receipt.status -ne 'AUTHORIZED-FOR-ONE-RAW-ACQUISITION-ATTEMPT' -or
    [int]$receipt.formalAttemptOrdinal -ne 2 -or
    $receipt.formalCampaignAuthorized -ne $true -or
    $receipt.rawAcquisitionAuthorized -ne $true -or
    $receipt.formalAnalysisAuthorized -ne $false -or
    $receipt.gate14RAuthorized -ne $false -or
    $receipt.noAutomaticRetry -ne $true -or
    $receipt.noAutomaticResume -ne $true -or
    $receipt.noTopUp -ne $true -or
    $receipt.noPartialMerge -ne $true) {
    throw 'Execution receipt identity, authorization boundary, or failure policy mismatch.'
}

$preflightCompletedAtUtc = ([DateTime]$receipt.preflightCompletedAtUtc).ToUniversalTime()
$preflightAgeSeconds = ([DateTime]::UtcNow - $preflightCompletedAtUtc).TotalSeconds
if ($preflightAgeSeconds -lt 0 -or $preflightAgeSeconds -gt 900) {
    throw "The final prelaunch audit is stale: $preflightAgeSeconds seconds."
}

$validationSha256 = (Get-FileHash -LiteralPath $receiptValidationPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($validationSha256 -ne $expectedReceiptValidationSha256) {
    throw "Receipt-validation summary SHA-256 mismatch: $validationSha256"
}
$validation = Get-Content -Raw -LiteralPath $receiptValidationPath | ConvertFrom-Json
if ($validation.passed -ne $true -or
    [string]$validation.receiptSha256 -ne $expectedReceiptSha256 -or
    $validation.formalRootV2Absent -ne $true -or
    $validation.formalStatusV2Absent -ne $true -or
    [int]$validation.unityProcessCount -ne 0 -or
    $validation.projectLockAbsent -ne $true) {
    throw 'Receipt-validation summary did not pass the frozen launch contract.'
}

$drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($formalRoot))
if ([long]$drive.AvailableFreeSpace -lt $minimumFreeBytes) {
    throw "Fresh storage gate failed: $($drive.AvailableFreeSpace) bytes available."
}

New-Item -ItemType Directory -Path $LaunchEvidenceDirectory | Out-Null
$stdoutPath = Join-Path $LaunchEvidenceDirectory 'orchestrator.stdout.log'
$stderrPath = Join-Path $LaunchEvidenceDirectory 'orchestrator.stderr.log'
$launchReceiptPath = Join-Path $LaunchEvidenceDirectory 'launch-receipt.json'

$argumentList = @(
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"' + $campaignScript + '"'),
    '-ProjectPath', ('"' + $ProjectPath + '"'),
    '-ConfigPath', ('"' + $configPath + '"'),
    '-SchedulePath', ('"' + $schedulePath + '"'),
    '-ScheduleManifestPath', ('"' + $scheduleManifestPath + '"'),
    '-ReadinessPath', ('"' + $readinessPath + '"'),
    '-AdapterProvenancePath', ('"' + $adapterProvenancePath + '"'),
    '-ExecutionReceiptPath', ('"' + $executionReceiptPath + '"'),
    '-UnityPath', ('"' + $unityPath + '"'),
    '-BlockTimeoutSeconds', '3600'
)

$previousModulePath = $env:PSModulePath
try {
    $env:PSModulePath = $expectedNativeModulePath
    $process = Start-Process -FilePath $powershellExe -ArgumentList $argumentList -WorkingDirectory $ProjectPath -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
}
finally {
    $env:PSModulePath = $previousModulePath
}

if ($null -eq $process -or $process.Id -le 0) {
    throw 'Start-Process did not return a valid orchestrator process.'
}

$startedAtUtc = [DateTime]::UtcNow
try {
    $startedAtUtc = $process.StartTime.ToUniversalTime()
}
catch {
    # The PID itself remains the authoritative launch result if StartTime races.
}

$launchReceipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-formal-attempt-2-one-shot-launch-receipt-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'LAUNCHED-ONE-SHOT-RAW-ACQUISITION-ATTEMPT-2'
    orchestratorPid = [int]$process.Id
    orchestratorStartTimeUtc = $startedAtUtc.ToString('o')
    powershellExecutable = $powershellExe
    powershellMajorVersion = 5
    projectPath = $ProjectPath
    formalRoot = $formalRoot
    formalRootAbsentImmediatelyBeforeLaunch = $true
    formalStatusAbsentImmediatelyBeforeLaunch = $true
    executionReceiptPath = $executionReceiptPath
    executionReceiptSha256 = $receiptSha256
    receiptValidationPath = $receiptValidationPath
    receiptValidationSha256 = $validationSha256
    campaignScriptPath = $campaignScript
    campaignScriptSha256 = (Get-FileHash -LiteralPath $campaignScript -Algorithm SHA256).Hash.ToLowerInvariant()
    configSha256 = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
    scheduleSha256 = (Get-FileHash -LiteralPath $schedulePath -Algorithm SHA256).Hash.ToLowerInvariant()
    scheduleManifestSha256 = (Get-FileHash -LiteralPath $scheduleManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    readinessSha256 = (Get-FileHash -LiteralPath $readinessPath -Algorithm SHA256).Hash.ToLowerInvariant()
    adapterProvenanceSha256 = (Get-FileHash -LiteralPath $adapterProvenancePath -Algorithm SHA256).Hash.ToLowerInvariant()
    preflightCompletedAtUtc = $preflightCompletedAtUtc.ToString('o')
    preflightAgeSecondsAtLaunch = [Math]::Round($preflightAgeSeconds, 3)
    availableFreeBytesAtLaunch = [long]$drive.AvailableFreeSpace
    minimumFreeBytes = $minimumFreeBytes
    maximumConcurrentUnityEditorProcesses = 1
    formalAttemptOrdinal = 2
    formalAnalysisAuthorized = $false
    gate14RAuthorized = $false
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    topUpAuthorized = $false
    partialAttemptMergeAuthorized = $false
    twoPhaseRawCommitRequired = $true
    successTerminalState = 'RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE'
    stdoutPath = $stdoutPath
    stderrPath = $stderrPath
}

$temporaryReceiptPath = $launchReceiptPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
try {
    $launchReceipt | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $temporaryReceiptPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryReceiptPath -Destination $launchReceiptPath
}
finally {
    if (Test-Path -LiteralPath $temporaryReceiptPath) {
        Remove-Item -LiteralPath $temporaryReceiptPath -Force
    }
}
(Get-Item -LiteralPath $launchReceiptPath -Force).IsReadOnly = $true

[pscustomobject][ordered]@{
    launched = $true
    orchestratorPid = [int]$process.Id
    orchestratorStartTimeUtc = $startedAtUtc.ToString('o')
    launchReceiptPath = $launchReceiptPath
    launchReceiptSha256 = (Get-FileHash -LiteralPath $launchReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    stdoutPath = $stdoutPath
    stderrPath = $stderrPath
    preflightAgeSecondsAtLaunch = [Math]::Round($preflightAgeSeconds, 3)
    availableFreeBytesAtLaunch = [long]$drive.AvailableFreeSpace
} | ConvertTo-Json -Depth 10
