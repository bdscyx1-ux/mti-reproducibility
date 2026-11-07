[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$AdapterProvenancePath,
    [Parameter(Mandatory = $true)][string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$AdapterProvenancePath = [IO.Path]::GetFullPath($AdapterProvenancePath)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw "Create-new negative-test root exists: $OutputRoot" }
if (-not (Test-Path -LiteralPath $AdapterProvenancePath -PathType Leaf)) { throw "Adapter provenance is missing: $AdapterProvenancePath" }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV3.psm1') -Force
$nativePowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$campaign = Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalCampaignV4.ps1'
$config = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Campaign_Config.v2.json'
$schedule = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl'
$scheduleManifest = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json'
$readiness = Join-Path $ProjectPath 'Research\Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json'
$unity = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe'
$missingReceipt = Join-Path $OutputRoot 'deliberately-absent-formal-execution-receipt.json'
$stdout = Join-Path $OutputRoot 'wrapper.stdout.log'
$stderr = Join-Path $OutputRoot 'wrapper.stderr.log'
$summaryPath = Join-Path $OutputRoot 'negative-no-receipt-summary.json'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v1'
$formalStatus = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v1.json'
$expectedModulePath = @(
    'C:\Users\bdscy\Documents\WindowsPowerShell\Modules',
    'C:\Program Files\WindowsPowerShell\Modules',
    'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
) -join ';'

$before = [ordered]@{
    formalRootExists = Test-Path -LiteralPath $formalRoot
    formalStatusExists = Test-Path -LiteralPath $formalStatus
    missingReceiptExists = Test-Path -LiteralPath $missingReceipt
    unityProcessCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
    projectLockExists = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
}
if ($before.formalRootExists -or $before.formalStatusExists -or $before.missingReceiptExists -or [int]$before.unityProcessCount -ne 0 -or $before.projectLockExists) {
    throw 'Negative no-receipt fixture precondition failed.'
}

$priorModulePath = $env:PSModulePath
try {
    $env:PSModulePath = $expectedModulePath
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $campaign + '"'),
        '-ProjectPath', ('"' + $ProjectPath + '"'),
        '-ConfigPath', ('"' + $config + '"'),
        '-SchedulePath', ('"' + $schedule + '"'),
        '-ScheduleManifestPath', ('"' + $scheduleManifest + '"'),
        '-ReadinessPath', ('"' + $readiness + '"'),
        '-AdapterProvenancePath', ('"' + $AdapterProvenancePath + '"'),
        '-ExecutionReceiptPath', ('"' + $missingReceipt + '"'),
        '-UnityPath', ('"' + $unity + '"')
    )
    $process = Start-Process -FilePath $nativePowerShell -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
}
finally {
    $env:PSModulePath = $priorModulePath
}

$stderrText = if (Test-Path -LiteralPath $stderr) { [IO.File]::ReadAllText($stderr, [Text.Encoding]::UTF8) } else { '' }
$after = [ordered]@{
    formalRootExists = Test-Path -LiteralPath $formalRoot
    formalStatusExists = Test-Path -LiteralPath $formalStatus
    missingReceiptExists = Test-Path -LiteralPath $missingReceipt
    unityProcessCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
    projectLockExists = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
}
$checks = @(
    [ordered]@{ name = 'child-exit-nonzero'; passed = [int]$process.ExitCode -ne 0; detail = "exitCode=$($process.ExitCode)" },
    [ordered]@{ name = 'missing-receipt-rejected'; passed = $stderrText.Contains('Required formal input is missing:'); detail = 'The one-shot orchestrator rejected the absent receipt before commit.' },
    [ordered]@{ name = 'formal-root-remained-absent'; passed = -not $after.formalRootExists; detail = $formalRoot },
    [ordered]@{ name = 'formal-status-remained-absent'; passed = -not $after.formalStatusExists; detail = $formalStatus },
    [ordered]@{ name = 'receipt-remained-absent'; passed = -not $after.missingReceiptExists; detail = $missingReceipt },
    [ordered]@{ name = 'unity-never-launched'; passed = [int]$after.unityProcessCount -eq 0; detail = "unityProcessCount=$($after.unityProcessCount)" },
    [ordered]@{ name = 'project-lock-remained-absent'; passed = -not $after.projectLockExists; detail = "projectLockExists=$($after.projectLockExists)" }
)
$failed = @($checks | Where-Object { $_.passed -ne $true })
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-formal-negative-no-receipt-fail-closed-validation-v1'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    input = [ordered]@{
        orchestratorRelativePath = 'Research/Run-Gate13RPR2FormalCampaignV4.ps1'
        orchestratorSha256 = Get-G13RPR2Sha256 $campaign
        adapterProvenanceRelativePath = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $AdapterProvenancePath
        adapterProvenanceSha256 = Get-G13RPR2Sha256 $AdapterProvenancePath
        deliberatelyAbsentReceiptPath = $missingReceipt.Replace('\', '/')
    }
    before = $before
    childExitCode = [int]$process.ExitCode
    after = $after
    checks = $checks
    passed = $failed.Count -eq 0
    noFormalSampleCreated = (-not $after.formalRootExists) -and ([int]$after.unityProcessCount -eq 0)
}
Write-G13RPR2AtomicJson -Path $summaryPath -Value $summary -Depth 20
if ($failed.Count -ne 0) { throw ('Negative no-receipt validation failed: ' + (@($failed.name) -join ', ')) }
Write-Host 'Gate13R-PR2 negative no-receipt validation passed.' -ForegroundColor Green
