[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or -not[IO.Path]::IsPathRooted($ProjectPath)){throw 'An explicit absolute ProjectPath is required.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output "BINDING-SMOKE-PASSED|Invoke-Gate13RPR2MP1V2PrePilotValidation|$ProjectPath";exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$base=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1_v2')).TrimEnd('\','/')
if(-not $VerificationRoot.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Pre-pilot root is outside the v2 verification base.'}
if(Test-Path -LiteralPath $VerificationRoot){throw 'Create-new v2 pre-pilot validation root exists.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2')){throw 'Measured v2 root must remain absent during validation.'}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-ne0-or(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be quiescent before validation.'}
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1') -Force
New-Item -ItemType Directory -Path $VerificationRoot,(Join-Path $VerificationRoot 'Logs') -Force|Out-Null
$pwsh=(Get-Process -Id $PID).Path;$ps51='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
$stepResults=New-Object Collections.Generic.List[object];$currentStep='INITIALIZE'
function Invoke-ValidationChild([string]$Step,[string]$Executable,[string[]]$Arguments){
 $script:currentStep=$Step;$previous=$env:PSModulePath
 try{if([IO.Path]::GetFileName($Executable).Equals('powershell.exe',[StringComparison]::OrdinalIgnoreCase)){$env:PSModulePath=$nativeModulePath};$started=[DateTime]::UtcNow;$lines=@(& $Executable @Arguments 2>&1);$exit=$LASTEXITCODE;$ended=[DateTime]::UtcNow}
 finally{$env:PSModulePath=$previous}
 $logPath=Join-Path (Join-Path $VerificationRoot 'Logs') ($Step+'.log');[IO.File]::WriteAllText($logPath,($lines-join"`r`n")+"`r`n",(New-Object Text.UTF8Encoding($false)))
 $script:stepResults.Add([ordered]@{step=$Step;executable=$Executable;exitCode=$exit;startedAtUtc=$started.ToString('o');endedAtUtc=$ended.ToString('o');durationSeconds=($ended-$started).TotalSeconds;logRelativePath=$logPath.Substring($VerificationRoot.Length+1).Replace('\','/');logSha256=Get-G13RPR2MP1V2Sha256 $logPath;passed=$exit-eq0})
 if($exit-ne0){throw "Validation child failed: $Step (exit $exit)"}
 return $lines
}
try{
 $staticOut=Join-Path $VerificationRoot 'Static\static-unit-summary.json';$null=Invoke-ValidationChild '01-static-unit' 'py' @('-3',(Join-Path $ProjectPath 'Research\Test-Gate13RPR2MemoryPolicyPilotV2.py'),'--project-root',$ProjectPath,'--output',$staticOut)

 $parser=Join-Path $ProjectPath 'Research\Test-Gate13RPR2MP1PowerShellParserV2.ps1';$runtimeDir=Join-Path $VerificationRoot 'RuntimeValidation';New-Item -ItemType Directory -Path $runtimeDir -Force|Out-Null
 $parserResults=New-Object Collections.Generic.List[object]
 foreach($runtime in @([ordered]@{id='ps7';exe=$pwsh},[ordered]@{id='ps51';exe=$ps51})){$lines=Invoke-ValidationChild ('02-parser-'+$runtime.id) $runtime.exe @('-NoProfile','-ExecutionPolicy','Bypass','-File',$parser,'-ProjectPath',$ProjectPath);$value=($lines-join"`n")|ConvertFrom-Json;$parserResults.Add([ordered]@{runtimeId=$runtime.id;runtime=$value.runtime;fileCount=$value.fileCount;passedFileCount=$value.passedFileCount;passed=$value.passed})}
 $bindingEntries=@(
  [ordered]@{id='checkpoint-fixtures';path='Research\Test-Gate13RPR2MP1V2CheckpointStateMachine.ps1';args=@('-ProjectPath',$ProjectPath,'-OutputRoot',(Join-Path $base 'binding-checkpoint'),'-BindingSmokeOnly')},
  [ordered]@{id='zero-block-fixture';path='Research\Test-Gate13RPR2MP1V2ZeroBlockFailure.ps1';args=@('-ProjectPath',$ProjectPath,'-OutputRoot',(Join-Path $base 'binding-zero'),'-ChildPowerShellPath',$pwsh,'-BindingSmokeOnly')},
  [ordered]@{id='block-wrapper';path='Research\Run-Gate13RPR2MemoryPolicyPilotBlockV2.ps1';args=@('-ProjectPath',$ProjectPath,'-BlockPlanPath',(Join-Path $base 'binding-plan.json'),'-OutputDirectory',(Join-Path $base 'binding-block'),'-AllowedRoot',$base,'-ExecutionReceiptPath',(Join-Path $base 'binding-receipt.json'),'-BindingSmokeOnly')},
  [ordered]@{id='campaign';path='Research\Run-Gate13RPR2MemoryPolicyPilotV2.ps1';args=@('-ProjectPath',$ProjectPath,'-PilotRoot',(Join-Path $base 'binding-campaign'),'-ExecutionReceiptPath',(Join-Path $base 'binding-receipt.json'),'-BindingSmokeOnly')},
  [ordered]@{id='launcher';path='Research\Start-Gate13RPR2MemoryPolicyPilotV2.ps1';args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly')},
  [ordered]@{id='unity-self-tests';path='Research\Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV2.ps1';args=@('-ProjectPath',$ProjectPath,'-VerificationRoot',(Join-Path $base 'binding-selftests'),'-BindingSmokeOnly')},
  [ordered]@{id='telemetry';path='Research\Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV2.ps1';args=@('-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $base 'binding-probe'),'-AllowedRoot',$base,'-BindingSmokeOnly')},
  [ordered]@{id='block-validation';path='Research\Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV2.ps1';args=@('-ProjectPath',$ProjectPath,'-VerificationRoot',(Join-Path $base 'binding-block-validation'),'-BindingSmokeOnly')},
  [ordered]@{id='finalizer';path='Research\Finalize-Gate13RPR2MP1PrePilotV2.ps1';args=@('-ProjectPath',$ProjectPath,'-VerificationRoot',(Join-Path $base 'binding-finalizer'),'-BindingSmokeOnly')},
  [ordered]@{id='prepilot-orchestrator';path='Research\Invoke-Gate13RPR2MP1V2PrePilotValidation.ps1';args=@('-ProjectPath',$ProjectPath,'-VerificationRoot',(Join-Path $base 'binding-prepilot'),'-BindingSmokeOnly')}
 )
 $bindingResults=New-Object Collections.Generic.List[object]
 foreach($runtime in @([ordered]@{id='ps7';exe=$pwsh},[ordered]@{id='ps51';exe=$ps51})){foreach($entry in $bindingEntries){$lines=Invoke-ValidationChild ('03-binding-'+$runtime.id+'-'+$entry.id) $runtime.exe (@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath $entry.path))+@($entry.args));$output=$lines-join"`n";$bindingResults.Add([ordered]@{runtimeId=$runtime.id;entryId=$entry.id;passed=$output-match'^BINDING-SMOKE-PASSED\|'})}}
 $runtimeSummary=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr2-mp1-v2-runtime-validation-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');parserResults=$parserResults.ToArray();parserPassedCount=@($parserResults|Where-Object{$_.passed}).Count;bindingTestCount=$bindingResults.Count;bindingPassedCount=@($bindingResults|Where-Object{$_.passed}).Count;bindingFailedCount=@($bindingResults|Where-Object{-not$_.passed}).Count;bindingResults=$bindingResults.ToArray();passed=(@($parserResults|Where-Object{-not$_.passed}).Count-eq0-and@($bindingResults|Where-Object{-not$_.passed}).Count-eq0)}
 Write-G13RPR2MP1V2AtomicJson -Path (Join-Path $runtimeDir 'runtime-validation-summary.json') -Value $runtimeSummary -Depth 60
 if(-not$runtimeSummary.passed){throw 'Runtime parser/binding validation failed.'}

 $null=Invoke-ValidationChild '04-checkpoint-ps7' $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Test-Gate13RPR2MP1V2CheckpointStateMachine.ps1'),'-ProjectPath',$ProjectPath,'-OutputRoot',(Join-Path $VerificationRoot 'CheckpointPS7'))
 $null=Invoke-ValidationChild '05-checkpoint-ps51' $ps51 @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Test-Gate13RPR2MP1V2CheckpointStateMachine.ps1'),'-ProjectPath',$ProjectPath,'-OutputRoot',(Join-Path $VerificationRoot 'CheckpointPS51'))
 $null=Invoke-ValidationChild '06-zero-block-ps7' $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Test-Gate13RPR2MP1V2ZeroBlockFailure.ps1'),'-ProjectPath',$ProjectPath,'-OutputRoot',(Join-Path $VerificationRoot 'ZeroBlockPS7'),'-ChildPowerShellPath',$pwsh)
 $null=Invoke-ValidationChild '07-zero-block-ps51' $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Test-Gate13RPR2MP1V2ZeroBlockFailure.ps1'),'-ProjectPath',$ProjectPath,'-OutputRoot',(Join-Path $VerificationRoot 'ZeroBlockPS51'),'-ChildPowerShellPath',$ps51)
 $null=Invoke-ValidationChild '08-unity-self-tests' $ps51 @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV2.ps1'),'-ProjectPath',$ProjectPath,'-VerificationRoot',(Join-Path $VerificationRoot 'UnitySelfTests'),'-UnityPath',$UnityPath)
 $null=Invoke-ValidationChild '09-telemetry-probe' $ps51 @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV2.ps1'),'-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $VerificationRoot 'TelemetryProbe\probe'),'-AllowedRoot',(Join-Path $VerificationRoot 'TelemetryProbe'),'-UnityPath',$UnityPath)
 $null=Invoke-ValidationChild '10-positive-negative-blocks' $ps51 @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV2.ps1'),'-ProjectPath',$ProjectPath,'-VerificationRoot',(Join-Path $VerificationRoot 'BlockValidation'),'-UnityPath',$UnityPath)
 $null=Invoke-ValidationChild '11-failure-precedence-ps7' $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Test-Gate13RPR2MP1FailurePrecedenceV1.ps1'),'-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $VerificationRoot 'FailurePrecedencePS7'))
 $null=Invoke-ValidationChild '12-failure-precedence-ps51' $ps51 @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Test-Gate13RPR2MP1FailurePrecedenceV1.ps1'),'-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $VerificationRoot 'FailurePrecedencePS51'))
 $null=Invoke-ValidationChild '13-frozen-roots-audit' 'py' @('-3',(Join-Path $ProjectPath 'Research\Audit-Gate13RPR2MP1V2FrozenRoots.py'),'--output',(Join-Path $VerificationRoot 'FrozenRoots\frozen-roots-audit.json'))
 $null=Invoke-ValidationChild '14-finalizer' $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Finalize-Gate13RPR2MP1PrePilotV2.ps1'),'-ProjectPath',$ProjectPath,'-VerificationRoot',$VerificationRoot)
 $execution=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr2-mp1-v2-prepilot-execution-summary-v1';completedAtUtc=[DateTime]::UtcNow.ToString('o');stepCount=$stepResults.Count;passedStepCount=@($stepResults|Where-Object{$_.passed}).Count;steps=$stepResults.ToArray();measuredPilotStarted=$false;pilotV2RootExists=Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2');formalAttempt3Started=$false;passed=$true}
 Write-G13RPR2MP1V2AtomicJson -Path (Join-Path $VerificationRoot 'prepilot-execution-summary.json') -Value $execution -Depth 60
 Write-Host "Gate13R-PR2-MP1 v2 pre-pilot validation passed: $($execution.passedStepCount)/$($execution.stepCount) steps." -ForegroundColor Green
 exit 0
}catch{
 $failure=$_;$files=@(Get-ChildItem -LiteralPath $VerificationRoot -Recurse -File -Force|Sort-Object FullName);$bytes=0L;if($files.Count -gt 0){$bytes=[long](($files|Measure-Object Length -Sum).Sum)};$manifest=[ordered]@{schemaVersion=1;manifestKind='gate13r-pr2-mp1-v2-validation-partial-manifest-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');failedStep=$currentStep;fileCount=$files.Count;bytes=$bytes;files=@($files|ForEach-Object{[ordered]@{relativePath=$_.FullName.Substring($VerificationRoot.Length+1).Replace('\','/');bytes=[long]$_.Length;sha256=Get-G13RPR2MP1V2Sha256 $_.FullName}})}
 $manifestPath=Join-Path $VerificationRoot 'validation-partial-output-manifest.json';if(-not(Test-Path -LiteralPath $manifestPath)){Write-G13RPR2MP1V2AtomicJson -Path $manifestPath -Value $manifest -Depth 100}
 $receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-pr2-mp1-v2-validation-failure-receipt-v1';failedAtUtc=[DateTime]::UtcNow.ToString('o');failedStep=$currentStep;failureClass=$failure.Exception.GetType().FullName;failureMessage=$failure.Exception.Message;partialManifestSha256=Get-G13RPR2MP1V2Sha256 $manifestPath;measuredPilotStarted=$false;pilotV2RootCreated=$false;formalAttempt3Started=$false;status='VALIDATION-FAILED-PRESERVED / VERSIONED-REPAIR-ALLOWED-BEFORE-MEASURED-ROOT'}
 $receiptPath=Join-Path $VerificationRoot 'validation-failure-receipt.json';if(-not(Test-Path -LiteralPath $receiptPath)){Write-G13RPR2MP1V2AtomicJson -Path $receiptPath -Value $receipt -Depth 50}
 $checkpoint=[ordered]@{schemaVersion=1;checkpointKind='gate13r-pr2-mp1-v2-validation-failure-checkpoint-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-PRESERVED';failedStep=$currentStep;failureReceiptSha256=Get-G13RPR2MP1V2Sha256 $receiptPath;partialManifestSha256=Get-G13RPR2MP1V2Sha256 $manifestPath;measuredPilotStarted=$false}
 $checkpointPath=Join-Path $VerificationRoot 'validation-failure-checkpoint.json';if(-not(Test-Path -LiteralPath $checkpointPath)){Write-G13RPR2MP1V2AtomicJson -Path $checkpointPath -Value $checkpoint -Depth 40}
 throw $failure
}
