[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Test-Gate13RPR2Attempt2NegativeNoReceiptV2|$ProjectPath"; exit 0 }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1')).TrimEnd('\', '/')
if (-not $OutputDirectory.StartsWith($verificationBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputDirectory escapes the attempt-2 verification root.' }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Create-new negative-test output exists.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV5.psm1') -Force

$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v2'
$formalStatus = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v2.json'
$missingReceipt = Join-Path $OutputDirectory 'intentionally-missing-formal-receipt.json'
$stdout = Join-Path $OutputDirectory 'campaign.stdout.log'
$stderr = Join-Path $OutputDirectory 'campaign.stderr.log'
$campaign = Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalCampaignV6.ps1'
$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $campaign + '"'),
    '-ProjectPath',('"' + $ProjectPath + '"'),
    '-ConfigPath',('"' + (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Campaign_Config.v2.json') + '"'),
    '-SchedulePath',('"' + (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl') + '"'),
    '-ScheduleManifestPath',('"' + (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json') + '"'),
    '-ReadinessPath',('"' + (Join-Path $ProjectPath 'Research\Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json') + '"'),
    '-AdapterProvenancePath',('"' + (Join-Path $ProjectPath 'Research\Gate13R_PR2_Attempt2_Validation_Provenance.v1.json') + '"'),
    '-ExecutionReceiptPath',('"' + $missingReceipt + '"')
)
$child = Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -WorkingDirectory $ProjectPath -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
$childExit = [int]$child.ExitCode
$stderrText = if (Test-Path -LiteralPath $stderr) { [IO.File]::ReadAllText($stderr) } else { '' }
$passed = $childExit -ne 0 -and $stderrText.Contains('Required formal input is missing') -and -not (Test-Path -LiteralPath $missingReceipt) -and -not (Test-Path -LiteralPath $formalRoot) -and -not (Test-Path -LiteralPath $formalStatus) -and @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-attempt2-negative-no-receipt-fail-closed-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    childExitCode = $childExit
    expectedFailureObserved = $stderrText.Contains('Required formal input is missing')
    missingReceiptStillAbsent = -not (Test-Path -LiteralPath $missingReceipt)
    formalRootV2Absent = -not (Test-Path -LiteralPath $formalRoot)
    formalStatusV2Absent = -not (Test-Path -LiteralPath $formalStatus)
    unityProcessCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
    projectLockAbsent = -not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))
    passed = $passed
}
Write-G13RPR2AtomicJson -Path (Join-Path $OutputDirectory 'summary.json') -Value $summary -Depth 20
if (-not $passed) { Write-Error 'Attempt-2 negative no-receipt test failed.'; exit 1 }
Write-Output 'GATE13R-PR2-ATTEMPT2-NEGATIVE-NO-RECEIPT-PASSED'
exit 0
