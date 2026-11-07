[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [Parameter(Mandatory=$true)][string]$TelemetryResultPath,
    [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'PR1B validation-only audit requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BValidationOnlyPrePilotAuditV1|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR1BOrderEffectPreparationV1.psm1') -Force
$plan=Read-Gate13RPR1BJson $PilotPlanPath;$provenance=Read-Gate13RPR1BJson $ProvenancePath;$errors=New-Object Collections.Generic.List[string];$checks=New-Object Collections.Generic.List[object]
function Add-Check([string]$Id,[bool]$Passed,[string]$Detail){$script:checks.Add([pscustomobject][ordered]@{id=$Id;passed=$Passed;detail=$Detail});if(-not$Passed){$script:errors.Add("$Id`: $Detail")}}
$summaries=@{
 static=Join-Path $VerificationRoot 'StaticUnit\summary.json';compile=Join-Path $VerificationRoot 'Compile\summary.json';telemetry=Join-Path $VerificationRoot 'TelemetryProbe\v1.summary.json';block=Join-Path $VerificationRoot 'BlockVerification\summary.json'
}
foreach($key in @('static','compile','telemetry','block')){$path=$summaries[$key];$present=Test-Path -LiteralPath $path -PathType Leaf;$passed=$present-and((Read-Gate13RPR1BJson $path).passed-eq$true);Add-Check ("upstream-$key") $passed $path}
$telemetry=if(Test-Path $TelemetryResultPath){Read-Gate13RPR1BJson $TelemetryResultPath}else{$null};Add-Check 'telemetry-result-positive-crosscheck' ($null-ne$telemetry-and$telemetry.passed-eq$true-and[long]$telemetry.nativeBefore.workingSetBytes-gt0-and[long]$telemetry.nativeBefore.privateMemoryBytes-gt0-and[long]$telemetry.externalQuery.workingSetBytes-gt0-and[long]$telemetry.externalQuery.privateMemoryBytes-gt0) $TelemetryResultPath
foreach($binding in @($provenance.boundFiles)){$path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\');Add-Check ('hash-'+([string]$binding.relativePath).Replace('/','_').Replace('.','_')) ((Test-Path $path)-and(Get-Gate13RPR1BLowerSha256 $path)-eq[string]$binding.sha256) ([string]$binding.relativePath)}
try{$campaigns=@(Get-Gate13RPR1BCampaigns -ProjectPath $ProjectPath -Plan $plan);$measured=@(Get-Gate13RPR1BProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'measured-non-formal-pilot');$warmup=@(Get-Gate13RPR1BProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'excluded-warmup');$schedule=Test-Gate13RPR1BSchedule -Plan $plan -Measured $measured -Warmup $warmup;Add-Check 'schedule-regeneration' ($schedule.passed-eq$true) (($schedule.errors)-join'; ')}catch{Add-Check 'schedule-regeneration' $false $_.Exception.Message}
$pilotRoot=Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/','\');$formalRoot=Join-Path $ProjectPath ([string]$plan.paths.reservedFormalRootRelativePath).Replace('/','\')
Add-Check 'pilot-root-absent' (-not(Test-Path $pilotRoot)) $pilotRoot;Add-Check 'formal-root-absent' (-not(Test-Path $formalRoot)) $formalRoot;Add-Check 'unity-closed' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-eq0) 'No Unity process may remain.';Add-Check 'unity-lock-absent' (-not(Test-Path (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'Unity project lock must be absent.'
$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr1b-validation-only-pre-pilot-audit-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');pilotPlanSha256=Get-Gate13RPR1BLowerSha256 $PilotPlanPath;provenanceSha256=Get-Gate13RPR1BLowerSha256 $ProvenancePath;telemetryResultSha256=Get-Gate13RPR1BLowerSha256 $TelemetryResultPath;checkCount=$checks.Count;passedCheckCount=@($checks|Where-Object passed).Count;checks=$checks.ToArray();errors=$errors.ToArray();pilotExecutionAuthorized=$errors.Count-eq0;formalCampaign=$false;gate13rFormalAuthorized=$false;passed=$errors.Count-eq0}
Write-Gate13RPR1BAtomicUtf8NoBomJson -Path (Join-Path $VerificationRoot 'ValidationOnlyPrePilotAudit.summary.json') -Value $summary -Depth 40
if($errors.Count){Write-Error("PR1B validation-only pre-pilot audit failed: "+($errors-join'; '));exit 1};Write-Host 'PR1B validation-only pre-pilot audit passed.' -ForegroundColor Green;exit 0
