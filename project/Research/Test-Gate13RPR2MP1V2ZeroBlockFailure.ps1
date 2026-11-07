[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [Parameter(Mandatory = $true)][string]$ChildPowerShellPath,
    [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or -not[IO.Path]::IsPathRooted($ProjectPath)){throw 'An explicit absolute ProjectPath is required.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output "BINDING-SMOKE-PASSED|Test-Gate13RPR2MP1V2ZeroBlockFailure|$ProjectPath";exit 0}
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot);$ChildPowerShellPath=[IO.Path]::GetFullPath($ChildPowerShellPath)
$base=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1_v2')).TrimEnd('\','/')
if(-not $OutputRoot.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Zero-block fixture root is outside the v2 verification base.'}
if(Test-Path -LiteralPath $OutputRoot){throw 'Create-new zero-block fixture root exists.'}
if(-not(Test-Path -LiteralPath $ChildPowerShellPath -PathType Leaf)){throw 'Child PowerShell executable is missing.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2')){throw 'Measured v2 root must remain absent during zero-block fixture.'}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -ne 0){throw 'Unity must be absent before zero-block fixture.'}
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1') -Force
$rawRoot=Join-Path $OutputRoot 'raw';New-Item -ItemType Directory -Path $rawRoot -Force|Out-Null
$receiptPath=Join-Path $OutputRoot 'validation-execution-receipt.json';$checkpointPath=Join-Path $OutputRoot 'pilot-checkpoint.json'
$config=Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Config.v2.json';$schedule=Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl';$provenance=Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Provenance.v2_4.json'
$receipt=[ordered]@{schemaVersion=2;receiptKind='gate13r-pr2-mp1-orchestrator-validation-receipt-v2';createdAtUtc=[DateTime]::UtcNow.ToString('o');verificationRoot=$OutputRoot;configSha256=Get-G13RPR2MP1V2Sha256 $config;scheduleSha256=Get-G13RPR2MP1V2Sha256 $schedule;provenanceSha256=Get-G13RPR2MP1V2Sha256 $provenance;measuredPilotAuthorized=$false;formalCampaignAuthorized=$false;formalAnalysisAuthorized=$false;gate14RAuthorized=$false}
Write-G13RPR2MP1V2AtomicJson -Path $receiptPath -Value $receipt -Depth 30
Write-G13RPR2MP1V2AtomicJson -Path $checkpointPath -Value (New-G13RPR2MP1V2Checkpoint) -Depth 50
$campaign=Join-Path $ProjectPath 'Research\Run-Gate13RPR2MemoryPolicyPilotV2.ps1'
$previous=$env:PSModulePath
try{
 if([IO.Path]::GetFileName($ChildPowerShellPath).Equals('powershell.exe',[StringComparison]::OrdinalIgnoreCase)){$env:PSModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'}
 & $ChildPowerShellPath -NoProfile -ExecutionPolicy Bypass -File $campaign -ProjectPath $ProjectPath -PilotRoot $OutputRoot -ExecutionReceiptPath $receiptPath -ConfigPath $config -SchedulePath $schedule -ProvenancePath $provenance -ValidationOnly -InjectedFailureStage BeforeFirstBlock
 $exit=$LASTEXITCODE
}finally{$env:PSModulePath=$previous}
if($exit -eq 0){throw 'Injected zero-block orchestrator unexpectedly succeeded.'}
$partialPath=Join-Path $OutputRoot 'pilot-partial-output-manifest.json';$failurePath=Join-Path $OutputRoot 'pilot-failure-receipt.json'
foreach($path in @($partialPath,$failurePath,$checkpointPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Durable zero-block failure artifact is absent: $path"}}
$partial=Read-G13RPR2MP1V2Json $partialPath;$failure=Read-G13RPR2MP1V2Json $failurePath;$checkpoint=Read-G13RPR2MP1V2Json $checkpointPath;$null=Test-G13RPR2MP1V2CheckpointSchema $checkpoint
$checks=[ordered]@{
 childExitWasNonzero=($exit -ne 0)
 zeroRawFiles=([int]$partial.fileCount -eq 0 -and [int]$partial.rawBytes -eq 0)
 zeroCompletedBlocks=([int]$checkpoint.completedBlockCount -eq 0 -and [int]$checkpoint.completedSampleCount -eq 0)
 failedCheckpoint=([string]$checkpoint.status -eq 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE')
 failureStage=([string]$failure.failureStage -eq 'BEFORE-FIRST-BLOCK' -and [string]$checkpoint.failureStage -eq 'BEFORE-FIRST-BLOCK')
 evidenceHashes=([string]$checkpoint.failureReceiptSha256 -eq (Get-G13RPR2MP1V2Sha256 $failurePath) -and [string]$checkpoint.partialOutputManifestSha256 -eq (Get-G13RPR2MP1V2Sha256 $partialPath))
 unityNotStarted=(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0)
 measuredRootAbsent=(-not(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2')))
}
if(@($checks.GetEnumerator()|Where-Object{-not $_.Value}).Count -ne 0){throw ('Zero-block fixture failed: '+((@($checks.GetEnumerator()|Where-Object{-not $_.Value}|ForEach-Object{$_.Key})) -join ','))}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr2-mp1-v2-zero-block-failure-fixture-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');childPowerShellPath=$ChildPowerShellPath;childExitCode=$exit;checks=$checks;passed=$true}
Write-G13RPR2MP1V2AtomicJson -Path (Join-Path $OutputRoot 'zero-block-failure-summary.json') -Value $summary -Depth 30
Write-Host "Gate13R-PR2-MP1 v2 zero-block failure fixture passed for $ChildPowerShellPath." -ForegroundColor Green
exit 0
