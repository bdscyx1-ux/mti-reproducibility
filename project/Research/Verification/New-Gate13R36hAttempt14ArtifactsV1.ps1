[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-NewText([string]$Path,[string]$Text){if(Test-Path -LiteralPath $Path){throw "Create-new target exists: $Path"};$parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null};[IO.File]::WriteAllText($Path,$Text,$utf8)}
function Write-NewJson([string]$Path,$Value,[int]$Depth=100){$json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")+"`n";Write-NewText $Path $json}
function Parse-PowerShell([string]$Path){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors);if(@($errors).Count){throw "PowerShell 5.1 parser failure in $Path`: $(@($errors|ForEach-Object Message)-join'; ')"}}
function Bound([string]$RelativePath){$path=Join-Path $ProjectPath $RelativePath;return [ordered]@{relativePath=$RelativePath.Replace('\','/');sha256=Hash $path;bytes=[long](Get-Item -LiteralPath $path).Length}}

$amendmentRelative='Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v14.json'
$diagnosisRelative='Research\Gate13R_36h_10pct_4Lane_v13_Bootstrap_Log_Finalization_Diagnosis.v1.json'
$generatorRelative='Research\Verification\New-Gate13R36hAttempt14ArtifactsV1.ps1'
foreach($required in @($amendmentRelative,$diagnosisRelative,$generatorRelative)){if(-not(Test-Path -LiteralPath (Join-Path $ProjectPath $required) -PathType Leaf)){throw "Required v14 input missing: $required"}}
$amendment=Get-Content -LiteralPath (Join-Path $ProjectPath $amendmentRelative) -Raw -Encoding UTF8|ConvertFrom-Json
if([string]$amendment.status-ne'AUTHORIZED-VERSIONED-PRE-PILOT-DEFECT-REPAIR'-or[bool]$amendment.executionBoundary.formalCampaignAuthorized-ne$false){throw 'Attempt-14 amendment boundary is invalid.'}
if([string]$amendment.upstreamDiagnosis.sha256-ne(Hash (Join-Path $ProjectPath $diagnosisRelative))){throw 'Attempt-14 amendment does not bind the v13 diagnosis.'}

$formalRoot=Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1'
$pilotRoot=Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v14'
$verificationRoot=Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v14'
$cloneRoot='H:\DDM_Final_Project_Gate13R36H\v14'
foreach($path in @($formalRoot,$pilotRoot,$verificationRoot,$cloneRoot)){if(Test-Path -LiteralPath $path){throw "Forbidden/create-new root already exists: $path"}}

$sources=[ordered]@{
 'Research\Gate13R36hConcurrencyPreparationV13.psm1'='Research\Gate13R36hConcurrencyPreparationV14.psm1'
 'Research\Run-Gate13R36hBlockV13.ps1'='Research\Run-Gate13R36hBlockV14.ps1'
 'Research\Run-Gate13R36hTelemetryProbeV13.ps1'='Research\Run-Gate13R36hTelemetryProbeV14.ps1'
 'Research\Initialize-Gate13R36hLaneCopiesV13.ps1'='Research\Initialize-Gate13R36hLaneCopiesV14.ps1'
 'Research\Run-Gate13R36hConcurrencyPilotV13.ps1'='Research\Run-Gate13R36hConcurrencyPilotV14.ps1'
 'Research\Analyze-Gate13R36hConcurrencyPilotV13.ps1'='Research\Analyze-Gate13R36hConcurrencyPilotV14.ps1'
 'Research\Verification\New-Gate13R36hPilotScheduleV13.ps1'='Research\Verification\New-Gate13R36hPilotScheduleV14.ps1'
 'Research\Verification\Run-Gate13R36hStaticUnitV13.ps1'='Research\Verification\Run-Gate13R36hStaticUnitV14.ps1'
 'Research\Verification\Run-Gate13R36hRetainedRegressionV13.ps1'='Research\Verification\Run-Gate13R36hRetainedRegressionV14.ps1'
 'Research\Verification\Run-Gate13R36hVerificationV13.ps1'='Research\Verification\Run-Gate13R36hVerificationV14.ps1'
 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV13.ps1'='Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV14.ps1'
 'Research\Verification\Run-Gate13R36hLockHygieneUnitV13.ps1'='Research\Verification\Run-Gate13R36hLockHygieneUnitV14.ps1'
 'Research\Verification\Run-Gate13R36hLaneBootstrapCompileV13.ps1'='Research\Verification\Run-Gate13R36hLaneBootstrapCompileV14.ps1'
}
$v13Evidence=@(
 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v13.json',
 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v13.json',
 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v13.json',
 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v13.json',
 'Research\Gate13R_36h_10pct_4Lane_Provenance.v13.json',
 'Research\Gate13R_36h_10pct_4Lane_Attempt13_Derivation_Receipt.v1.json',
 'Research\Verification\New-Gate13R36hAttempt13ArtifactsV1.ps1',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\execution-receipt.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\verification-checkpoint.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\failure-receipt.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\partial-output-manifest.json'
)+@($sources.Keys)
$before=@{}
foreach($relative in $v13Evidence){$path=Join-Path $ProjectPath $relative;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Frozen v13 evidence missing: $relative"};$before[$relative]=Hash $path}

$derivations=New-Object Collections.Generic.List[object]
foreach($entry in $sources.GetEnumerator()){
    $sourcePath=Join-Path $ProjectPath ([string]$entry.Key);$destinationPath=Join-Path $ProjectPath ([string]$entry.Value)
    $sourceText=[IO.File]::ReadAllText($sourcePath);$upperCount=[regex]::Matches($sourceText,[regex]::Escape('V13')).Count;$lowerCount=[regex]::Matches($sourceText,[regex]::Escape('v13')).Count
    if(($upperCount+$lowerCount)-lt1){throw "No active v13 identity found in $($entry.Key)"}
    $derived=$sourceText.Replace('V13','V14').Replace('v13','v14')
    Write-NewText $destinationPath $derived;Parse-PowerShell $destinationPath
    $derivations.Add([pscustomobject][ordered]@{sourceRelativePath=[string]$entry.Key;sourceSha256=Hash $sourcePath;destinationRelativePath=[string]$entry.Value;destinationSha256=Hash $destinationPath;uppercaseRouteCount=$upperCount;lowercaseRouteCount=$lowerCount;parserPassed=$true})
}

# Repair only post-exit log finalization: bounded read-only hash retry and atomic failure reporting.
$bootstrapPath=Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hLaneBootstrapCompileV14.ps1'
$bootstrap=[IO.File]::ReadAllText($bootstrapPath)
$exitAnchor=@'
if($timedOut){&taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{}}
$process.Refresh()
'@
$exitReplacement=@'
if($timedOut){&taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{}}
try{$process.WaitForExit()}catch{}
$process.Refresh()
'@
if(-not$bootstrap.Contains($exitAnchor)){throw 'Bootstrap process-finalization anchor missing.'};$bootstrap=$bootstrap.Replace($exitAnchor,$exitReplacement)
$diagnosticAnchor=@'
$patterns=@('error CS\d+','Compilation failed','Scripts have compiler errors','executeMethod.+could not be found','PostProcessing failed','Tundra build failed','System\.IO\.IOException.+being used by another process')
$matches=@()
if(Test-Path -LiteralPath $unityLog){$matches=@(Select-String -LiteralPath $unityLog -Pattern $patterns -CaseSensitive:$false)}
$errors=New-Object Collections.Generic.List[string]
if($timedOut){$errors.Add("Hard timeout after $TimeoutSeconds seconds.")}
if($exitCode-ne0){$errors.Add("Unity exit code $exitCode.")}
if(-not(Test-Path -LiteralPath $unityLog -PathType Leaf)){$errors.Add('Bootstrap Unity log is missing.')}
if($matches.Count){$errors.Add("Compiler/import contention patterns: $($matches.Count).")}
if($laneProcesses.Count){$errors.Add('Lane-owned Unity process remains after bootstrap exit.')}
if($lockExists){$errors.Add('Lane Unity lock remains after natural bootstrap quiescence.')}
if($observedMask.ToUpperInvariant()-ne$AffinityMaskHex.ToUpperInvariant()){$errors.Add('Observed affinity differs from requested affinity.')}
'@
$diagnosticReplacement=@'
$patterns=@('error CS\d+','Compilation failed','Scripts have compiler errors','executeMethod.+could not be found','PostProcessing failed','Tundra build failed','System\.IO\.IOException.+being used by another process')
$matches=@()
$errors=New-Object Collections.Generic.List[string]
if($timedOut){$errors.Add("Hard timeout after $TimeoutSeconds seconds.")}
if($exitCode-ne0){$errors.Add("Unity exit code $exitCode.")}
$logHash=$null;$logHashError='';$logHashWaitStarted=[DateTimeOffset]::Now
if(Test-Path -LiteralPath $unityLog -PathType Leaf){
    $logHashDeadline=(Get-Date).AddSeconds(60)
    do{try{$logHash=Get-LowerHash $unityLog;$logHashError='';break}catch{$logHashError=$_.Exception.Message;Start-Sleep -Milliseconds 250}}while((Get-Date)-lt$logHashDeadline)
    if($null-eq$logHash){$errors.Add('Bootstrap Unity log did not become readable for hashing within 60 seconds: '+$logHashError)}
}else{$errors.Add('Bootstrap Unity log is missing.')}
$logHashWaitSeconds=([DateTimeOffset]::Now-$logHashWaitStarted).TotalSeconds
if($null-ne$logHash){try{$matches=@(Select-String -LiteralPath $unityLog -Pattern $patterns -CaseSensitive:$false)}catch{$errors.Add('Bootstrap Unity log could not be scanned after hashing: '+$_.Exception.Message)}}
if($matches.Count){$errors.Add("Compiler/import contention patterns: $($matches.Count).")}
if($laneProcesses.Count){$errors.Add('Lane-owned Unity process remains after bootstrap exit.')}
if($lockExists){$errors.Add('Lane Unity lock remains after natural bootstrap quiescence.')}
if($observedMask.ToUpperInvariant()-ne$AffinityMaskHex.ToUpperInvariant()){$errors.Add('Observed affinity differs from requested affinity.')}
'@
if(-not$bootstrap.Contains($diagnosticAnchor)){throw 'Bootstrap log-finalization anchor missing.'};$bootstrap=$bootstrap.Replace($diagnosticAnchor,$diagnosticReplacement)
$hashAnchor='    unityLogSha256=if(Test-Path -LiteralPath $unityLog){Get-LowerHash $unityLog}else{$null}'
$hashReplacement="    unityLogSha256=`$logHash`n    logHashFinalized=`$null-ne`$logHash`n    logHashWaitSeconds=`$logHashWaitSeconds"
if(-not$bootstrap.Contains($hashAnchor)){throw 'Bootstrap inline-hash anchor missing.'};$bootstrap=$bootstrap.Replace($hashAnchor,$hashReplacement)
[IO.File]::WriteAllText($bootstrapPath,$bootstrap,$utf8);Parse-PowerShell $bootstrapPath

# Strengthen the v14 static source test for bounded read-only log finalization.
$staticPath=Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hStaticUnitV14.ps1'
$static=[IO.File]::ReadAllText($staticPath)
$staticAnchor=@'
$bootstrapRunnerText.Contains('PostProcessing failed')-and-not$bootstrapRunnerText.Contains('RunPlanningWorkload')
'@
$staticReplacement=@'
$bootstrapRunnerText.Contains('PostProcessing failed')-and$bootstrapRunnerText.Contains('logHashDeadline=(Get-Date).AddSeconds(60)')-and$bootstrapRunnerText.Contains('logHashFinalized=')-and-not$bootstrapRunnerText.Contains('RunPlanningWorkload')
'@
if(-not$static.Contains($staticAnchor)){throw 'Static log-finalization coverage anchor missing.'};$static=$static.Replace($staticAnchor,$staticReplacement)
[IO.File]::WriteAllText($staticPath,$static,$utf8);Parse-PowerShell $staticPath

$planV13Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v13.json'
$planV14Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v14.json'
$plan=Get-Content -LiteralPath $planV13Path -Raw -Encoding UTF8|ConvertFrom-Json
$plan.planId='gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v14';$plan.pilotAttempt=14
$plan.paths.pilotRootRelativePath='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v14';$plan.paths.verificationRootRelativePath='Research/Verification/Gate13R_36h_10pct_4Lane/v14';$plan.paths.cloneRootAbsolutePath='H:/DDM_Final_Project_Gate13R36H/v14'
foreach($lane in @($plan.lanes)){$lane.projectPath=([string]$lane.projectPath).Replace('/v13/','/v14/')}
$plan.upstreamHashes.prePilotDefectRepairAmendment=Hash (Join-Path $ProjectPath $amendmentRelative)
$plan.upstreamHashes|Add-Member -NotePropertyName attempt13Plan -NotePropertyValue (Hash $planV13Path)
$plan.upstreamHashes|Add-Member -NotePropertyName attempt13VerificationFailure -NotePropertyValue (Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\failure-receipt.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt13VerificationCheckpoint -NotePropertyValue (Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\verification-checkpoint.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt13BootstrapDiagnosis -NotePropertyValue (Hash (Join-Path $ProjectPath $diagnosisRelative))
$plan.upstreamHashes|Add-Member -NotePropertyName laneBootstrapRunnerV14 -NotePropertyValue (Hash $bootstrapPath)
Write-NewJson $planV14Path $plan 100

$scheduleGenerator=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hPilotScheduleV14.ps1'
&'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File $scheduleGenerator -ProjectPath $ProjectPath
if($LASTEXITCODE-ne0){throw "V14 schedule generation failed with exit $LASTEXITCODE."}

$provenanceV13Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v13.json'
$provenancePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v14.json'
$provenance=Get-Content -LiteralPath $provenanceV13Path -Raw -Encoding UTF8|ConvertFrom-Json
$provenance.schemaVersion=5;$provenance.provenanceId='gate13r-36h-10pct-four-isolated-editor-lanes-provenance-v14';$provenance.createdAtUtc=[DateTime]::UtcNow.ToString('o')
$provenance.executionAuthorization=Bound $amendmentRelative;$provenance.config=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v14.json';$provenance.schedule=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v14.json';$provenance.scheduleGeneration=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v14.json'
$provenance.preparationModule=Bound 'Research\Gate13R36hConcurrencyPreparationV14.psm1';$provenance.blockRunner=Bound 'Research\Run-Gate13R36hBlockV14.ps1';$provenance.telemetryRunner=Bound 'Research\Run-Gate13R36hTelemetryProbeV14.ps1';$provenance.laneCopyInitializer=Bound 'Research\Initialize-Gate13R36hLaneCopiesV14.ps1';$provenance.pilotOrchestrator=Bound 'Research\Run-Gate13R36hConcurrencyPilotV14.ps1';$provenance.pilotAnalyzer=Bound 'Research\Analyze-Gate13R36hConcurrencyPilotV14.ps1';$provenance.scheduleGenerator=Bound 'Research\Verification\New-Gate13R36hPilotScheduleV14.ps1';$provenance.staticUnitRunner=Bound 'Research\Verification\Run-Gate13R36hStaticUnitV14.ps1';$provenance.retainedRegressionRunner=Bound 'Research\Verification\Run-Gate13R36hRetainedRegressionV14.ps1';$provenance.verificationRunner=Bound 'Research\Verification\Run-Gate13R36hVerificationV14.ps1';$provenance.validationOnlyAuditRunner=Bound 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV14.ps1';$provenance.lockHygieneUnitRunner=Bound 'Research\Verification\Run-Gate13R36hLockHygieneUnitV14.ps1';$provenance.laneBootstrapRunner=Bound 'Research\Verification\Run-Gate13R36hLaneBootstrapCompileV14.ps1'
$provenance.paths.verificationRoot='Research/Verification/Gate13R_36h_10pct_4Lane/v14';$provenance.paths.pilotRoot='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v14';$provenance.paths.cloneRoot='H:/DDM_Final_Project_Gate13R36H/v14'
$provenance|Add-Member -NotePropertyName attempt13DerivationReceipt -NotePropertyValue (Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt13_Derivation_Receipt.v1.json')
$provenance|Add-Member -NotePropertyName attempt13Plan -NotePropertyValue (Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v13.json')
$provenance|Add-Member -NotePropertyName attempt13Provenance -NotePropertyValue (Bound 'Research\Gate13R_36h_10pct_4Lane_Provenance.v13.json')
$provenance|Add-Member -NotePropertyName attempt13VerificationReceipt -NotePropertyValue (Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\execution-receipt.json')
$provenance|Add-Member -NotePropertyName attempt13VerificationCheckpoint -NotePropertyValue (Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\verification-checkpoint.json')
$provenance|Add-Member -NotePropertyName attempt13VerificationFailure -NotePropertyValue (Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\failure-receipt.json')
$provenance|Add-Member -NotePropertyName attempt13VerificationManifest -NotePropertyValue (Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\partial-output-manifest.json')
$provenance|Add-Member -NotePropertyName attempt13BootstrapDiagnosis -NotePropertyValue (Bound $diagnosisRelative)
$provenance|Add-Member -NotePropertyName attempt14Amendment -NotePropertyValue (Bound $amendmentRelative)
$provenance|Add-Member -NotePropertyName attempt14DerivationGenerator -NotePropertyValue (Bound $generatorRelative)
Write-NewJson $provenancePath $provenance 110

$preserved=New-Object Collections.Generic.List[object]
foreach($relative in $v13Evidence){$after=Hash (Join-Path $ProjectPath $relative);$same=$after-eq[string]$before[$relative];$preserved.Add([pscustomobject][ordered]@{relativePath=$relative.Replace('\','/');beforeSha256=[string]$before[$relative];afterSha256=$after;preserved=$same});if(-not$same){throw "Frozen v13 evidence changed: $relative"}}
$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt14_Derivation_Receipt.v1.json'
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-prepilot-attempt14-bootstrap-log-finalization-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='NON-EXECUTING-PRE-PILOT-REPAIR';amendmentRelativePath=$amendmentRelative.Replace('\','/');amendmentSha256=Hash (Join-Path $ProjectPath $amendmentRelative);diagnosisRelativePath=$diagnosisRelative.Replace('\','/');diagnosisSha256=Hash (Join-Path $ProjectPath $diagnosisRelative);derivations=$derivations.ToArray();authorizedOverlay='bounded-read-only-bootstrap-log-finalization-v1';bootstrapRunnerV14Sha256=Hash $bootstrapPath;planV14Sha256=Hash $planV14Path;scheduleV14Sha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v14.json');scheduleGenerationV14Sha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v14.json');provenanceV14Sha256=Hash $provenancePath;frozenV13Evidence=$preserved.ToArray();frozenV13EvidencePreserved=$true;verificationRootCreated=$false;cloneRootCreated=$false;pilotRootCreated=$false;formalRootCreated=$false;pilotStarted=$false;formalCampaign=$false;passed=$true}
Write-NewJson $receiptPath $receipt 110
$receipt|ConvertTo-Json -Depth 8
