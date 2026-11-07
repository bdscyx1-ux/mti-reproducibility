[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R pre-pilot attempt requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RPrePilotAttempt|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
$plan=Read-Gate12RJson $PilotPlanPath;$provenance=Read-Gate12RJson $ProvenancePath
$base=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))
if(-not$VerificationRoot.StartsWith($base.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'VerificationRoot is outside Gate12R versioned base.'}
if(Test-Path $VerificationRoot){throw "Create-new verification root exists: $VerificationRoot"}
$pilotRoot=Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/','\');$formalRoot=Join-Path $ProjectPath ([string]$plan.paths.reservedFormalRootRelativePath).Replace('/','\')
if(Test-Path $pilotRoot){throw 'Pilot root must be absent before the complete pre-pilot gate.'};if(Test-Path $formalRoot){throw 'Gate13R formal root must remain absent.'};if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-gt0-or(Test-Path (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and the project lock absent.'}
if((Get-Gate12RLowerSha256 $UnityPath)-ne[string]$plan.unity.executableSha256){throw 'Unity executable hash mismatch.'}
foreach($binding in @($provenance.boundFiles)){$path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\');if(-not(Test-Path $path)-or(Get-Gate12RLowerSha256 $path)-ne[string]$binding.sha256){throw "Outside-root provenance binding failed: $($binding.relativePath)"}}

$scripts=@(
 'Research\Run-Gate12RProcessReuseBlock.ps1','Research\Run-Gate12RTelemetryProbe.ps1','Research\Run-Gate12RColdReference.ps1','Research\Analyze-Gate12RPilot.ps1','Research\Run-Gate12RPilot.ps1',
 'Research\Verification\Run-Gate12RCompile.ps1','Research\Verification\Run-Gate12RStaticUnitAudit.ps1','Research\Verification\Run-Gate12RBlockAndRegressionGates.ps1','Research\Verification\Run-Gate12RValidationOnlyPrePilotAudit.ps1','Research\Verification\Run-Gate12RPostPilotReadinessAudit.ps1','Research\Verification\Run-Gate12RPrePilotAttempt.ps1'
)
foreach($relative in $scripts){$path=Join-Path $ProjectPath $relative;$tokens=$null;$parseErrors=$null;[void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors);if(@($parseErrors).Count){throw "Windows PowerShell parser check failed: $relative :: $((@($parseErrors)|ForEach-Object Message)-join'; ')"}}
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
function Invoke-Child([string[]]$Arguments,[string]$Stdout,[string]$Stderr){$old=$env:PSModulePath;try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell @Arguments 1>$Stdout 2>$Stderr;return [int]$LASTEXITCODE}finally{$env:PSModulePath=$old}}

$smokes=@(
 [pscustomobject]@{relative='Research\Run-Gate12RProcessReuseBlock.ps1';arguments=[string[]]@('-BlockPlanPath','dummy','-OutputDirectory','dummy','-AllowedRoot','dummy','-Mode','Verification','-ProjectPath',$ProjectPath,'-BindingSmokeOnly')},
 [pscustomobject]@{relative='Research\Run-Gate12RTelemetryProbe.ps1';arguments=[string[]]@('-ProjectPath',$ProjectPath,'-OutputDirectory','dummy','-AllowedRoot','dummy','-BindingSmokeOnly')},
 [pscustomobject]@{relative='Research\Run-Gate12RColdReference.ps1';arguments=[string[]]@('-ProjectPath',$ProjectPath,'-ScenarioPath','dummy','-OutputDirectory','dummy','-AllowedRoot','dummy','-RunId','dummy','-Algorithm','A*-R','-BindingSmokeOnly')},
 [pscustomobject]@{relative='Research\Analyze-Gate12RPilot.ps1';arguments=[string[]]@('-ProjectPath',$ProjectPath,'-PilotRoot','dummy','-PilotPlanPath','dummy','-ProvenancePath','dummy','-BindingSmokeOnly')},
 [pscustomobject]@{relative='Research\Run-Gate12RPilot.ps1';arguments=[string[]]@('-ProjectPath',$ProjectPath,'-PilotPlanPath','dummy','-ProvenancePath','dummy','-PrePilotAuditPath','dummy','-TelemetryResultPath','dummy','-BindingSmokeOnly')},
 [pscustomobject]@{relative='Research\Verification\Run-Gate12RCompile.ps1';arguments=[string[]]@('-ProjectPath',$ProjectPath,'-VerificationRoot','dummy','-BindingSmokeOnly')},
 [pscustomobject]@{relative='Research\Verification\Run-Gate12RStaticUnitAudit.ps1';arguments=[string[]]@('-ProjectPath',$ProjectPath,'-VerificationRoot','dummy','-ProvenancePath','dummy','-BindingSmokeOnly')},
 [pscustomobject]@{relative='Research\Verification\Run-Gate12RBlockAndRegressionGates.ps1';arguments=[string[]]@('-ProjectPath',$ProjectPath,'-VerificationRoot','dummy','-ProvenancePath','dummy','-TelemetryResultPath','dummy','-BindingSmokeOnly')},
 [pscustomobject]@{relative='Research\Verification\Run-Gate12RValidationOnlyPrePilotAudit.ps1';arguments=[string[]]@('-ProjectPath',$ProjectPath,'-VerificationRoot','dummy','-PilotPlanPath','dummy','-ProvenancePath','dummy','-TelemetryResultPath','dummy','-BindingSmokeOnly')},
 [pscustomobject]@{relative='Research\Verification\Run-Gate12RPostPilotReadinessAudit.ps1';arguments=[string[]]@('-ProjectPath',$ProjectPath,'-VerificationRoot','dummy','-PilotRoot','dummy','-PilotPlanPath','dummy','-ProvenancePath','dummy','-BindingSmokeOnly')}
)
foreach($smoke in $smokes){$relative=[string]$smoke.relative;$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath $relative))+[string[]]$smoke.arguments;$output=&$windowsPowerShell @arguments 2>&1;$exit=[int]$LASTEXITCODE;if($exit-ne0-or($output|Out-String)-notmatch'BINDING-SMOKE-PASSED'){throw "Binding smoke failed: $relative exit=$exit output=$($output|Out-String)"}}

New-Item -ItemType Directory -Path $VerificationRoot|Out-Null;$orchestration=Join-Path $VerificationRoot 'Orchestration';New-Item -ItemType Directory -Path $orchestration|Out-Null
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-pre-pilot-gates-execution-receipt-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');verificationRoot=$VerificationRoot;pilotPlanSha256=Get-Gate12RLowerSha256 $PilotPlanPath;provenanceSha256=Get-Gate12RLowerSha256 $ProvenancePath;authorizationSha256=Get-Gate12RLowerSha256 (Join-Path $ProjectPath 'Research\Gate12R_Execution_Authorization.v1.json');executionDesignId=[string]$plan.executionDesignId;attempt=[int]$plan.attempt;parserChecks=$scripts.Count;bindingSmokeChecks=$smokes.Count;pilotRootCreated=$false;formalRootCreated=$false;gate13rAuthorized=$false}
Write-Gate12RAtomicUtf8NoBomJson -Path (Join-Path $VerificationRoot 'execution-receipt.json') -Value $receipt -Depth 20
function Write-Checkpoint([string]$Status,[string]$ErrorMessage){$checkpoint=[ordered]@{schemaVersion=1;checkpointKind='gate12r-pre-pilot-verification-checkpoint-v1';status=$Status;savedAtUtc=[DateTime]::UtcNow.ToString('o');pilotPlanSha256=Get-Gate12RLowerSha256 $PilotPlanPath;provenanceSha256=Get-Gate12RLowerSha256 $ProvenancePath;error=$ErrorMessage;pilotRootPresent=Test-Path $pilotRoot;formalRootPresent=Test-Path $formalRoot;gate13rAuthorized=$false};Write-Gate12RAtomicUtf8NoBomJson -Path (Join-Path $VerificationRoot 'gate12r-checkpoint.json') -Value $checkpoint -Depth 20}
function Write-PartialManifest([string]$Status){$files=@(Get-ChildItem -LiteralPath $VerificationRoot -Recurse -File -Force|Where-Object {$_.Name-notlike'*.tmp-*'});$rows=New-Object Collections.Generic.List[object];foreach($file in $files){$rows.Add([pscustomobject]@{relativePath=Get-Gate12RProjectRelativePath $ProjectPath $file.FullName;rawBytes=[long]$file.Length;sha256=Get-Gate12RLowerSha256 $file.FullName})};$manifest=[ordered]@{schemaVersion=1;manifestKind='gate12r-pre-pilot-partial-output-manifest-v1';status=$Status;savedAtUtc=[DateTime]::UtcNow.ToString('o');fileCount=$rows.Count;rawBytes=[long](($files|Measure-Object Length -Sum).Sum);files=$rows.ToArray();pilotRootCreated=$false;formalRootCreated=$false;gate13rAuthorized=$false};Write-Gate12RAtomicUtf8NoBomJson -Path (Join-Path $VerificationRoot 'partial-output-manifest.json') -Value $manifest -Depth 20}
try{
    Write-Checkpoint 'execution-receipt-created' $null
    $staticScript=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RStaticUnitAudit.ps1';$exit=Invoke-Child @('-NoProfile','-ExecutionPolicy','Bypass','-File',$staticScript,'-ProjectPath',$ProjectPath,'-VerificationRoot',$VerificationRoot,'-ProvenancePath',$ProvenancePath) (Join-Path $orchestration '01-static.stdout.log') (Join-Path $orchestration '01-static.stderr.log');if($exit-ne0){throw "Static/unit gate failed: exit=$exit"};Write-Checkpoint 'static-unit-passed' $null
    $compileScript=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RCompile.ps1';$exit=Invoke-Child @('-NoProfile','-ExecutionPolicy','Bypass','-File',$compileScript,'-ProjectPath',$ProjectPath,'-VerificationRoot',$VerificationRoot,'-UnityPath',$UnityPath) (Join-Path $orchestration '02-compile.stdout.log') (Join-Path $orchestration '02-compile.stderr.log');if($exit-ne0){throw "Unity compile gate failed: exit=$exit"};Write-Checkpoint 'compile-passed' $null
    $telemetryScript=Join-Path $ProjectPath 'Research\Run-Gate12RTelemetryProbe.ps1';$telemetryOutput=Join-Path $VerificationRoot 'TelemetryProbe\v1';$exit=Invoke-Child @('-NoProfile','-ExecutionPolicy','Bypass','-File',$telemetryScript,'-ProjectPath',$ProjectPath,'-OutputDirectory',$telemetryOutput,'-AllowedRoot',$VerificationRoot,'-UnityPath',$UnityPath) (Join-Path $orchestration '03-telemetry.stdout.log') (Join-Path $orchestration '03-telemetry.stderr.log');if($exit-ne0){throw "Telemetry gate failed: exit=$exit"};$telemetryResult=Join-Path $telemetryOutput 'telemetry-probe-result.json';Write-Checkpoint 'telemetry-passed' $null
    $blockScript=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RBlockAndRegressionGates.ps1';$exit=Invoke-Child @('-NoProfile','-ExecutionPolicy','Bypass','-File',$blockScript,'-ProjectPath',$ProjectPath,'-VerificationRoot',$VerificationRoot,'-ProvenancePath',$ProvenancePath,'-TelemetryResultPath',$telemetryResult,'-UnityPath',$UnityPath) (Join-Path $orchestration '04-block-regression.stdout.log') (Join-Path $orchestration '04-block-regression.stderr.log');if($exit-ne0){throw "Block/regression gate failed: exit=$exit"};Write-Checkpoint 'block-regression-passed' $null
    $auditScript=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RValidationOnlyPrePilotAudit.ps1';$exit=Invoke-Child @('-NoProfile','-ExecutionPolicy','Bypass','-File',$auditScript,'-ProjectPath',$ProjectPath,'-VerificationRoot',$VerificationRoot,'-PilotPlanPath',$PilotPlanPath,'-ProvenancePath',$ProvenancePath,'-TelemetryResultPath',$telemetryResult) (Join-Path $orchestration '05-prepilot-audit.stdout.log') (Join-Path $orchestration '05-prepilot-audit.stderr.log');if($exit-ne0){throw "Validation-only pre-pilot audit failed: exit=$exit"}
    Write-Checkpoint 'PRE-PILOT-GATES-PASSED-PILOT-NOT-YET-STARTED' $null;Write-PartialManifest 'pre-pilot-gates-passed'
    [pscustomobject]@{passed=$true;verificationRoot=$VerificationRoot;prePilotAuditPath=Join-Path $VerificationRoot 'ValidationOnlyPrePilotAudit.summary.json';telemetryResultPath=$telemetryResult;pilotRootCreated=$false;formalRootCreated=$false;gate13rAuthorized=$false}|ConvertTo-Json -Depth 10
    exit 0
}catch{
    $message=$_.Exception.ToString();try{$failure=[ordered]@{schemaVersion=1;receiptKind='gate12r-pre-pilot-gates-failure-receipt-v1';failedAtUtc=[DateTime]::UtcNow.ToString('o');message=$message;status='FAILED-VERSIONED-REPAIR-RETRY-ALLOWED';pilotRootCreated=Test-Path $pilotRoot;formalRootCreated=Test-Path $formalRoot;gate13rAuthorized=$false};Write-Gate12RAtomicUtf8NoBomJson -Path (Join-Path $VerificationRoot 'failure-receipt.json') -Value $failure -Depth 20;Write-Checkpoint 'failed-versioned-repair-retry-allowed' $message;Write-PartialManifest 'failed-versioned-repair-retry-allowed'}catch{};Write-Error "Gate12R pre-pilot attempt failed closed: $message";exit 1
}
