[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'PR1B static/unit requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BStaticUnitV1|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath)
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR1BOrderEffectPreparationV1.psm1') -Force
$plan=Read-Gate13RPR1BJson $PilotPlanPath;$provenance=Read-Gate13RPR1BJson $ProvenancePath
$outputRoot=Join-Path $VerificationRoot 'StaticUnit';if(Test-Path -LiteralPath $outputRoot){throw "Create-new static/unit root exists: $outputRoot"};New-Item -ItemType Directory -Path $outputRoot -Force|Out-Null
$errors=New-Object Collections.Generic.List[string];$checks=New-Object Collections.Generic.List[object]
function Add-Check([string]$Id,[bool]$Passed,[string]$Detail){$script:checks.Add([pscustomobject][ordered]@{id=$Id;passed=$Passed;detail=$Detail});if(-not$Passed){$script:errors.Add("$Id`: $Detail")}}
try{Assert-Gate13RPR1BPlanIdentity $plan;Add-Check 'plan-identity' $true 'Plan identity and non-formal boundary passed.'}catch{Add-Check 'plan-identity' $false $_.Exception.Message}
Add-Check 'plan-provenance-config-binding' ((Get-Gate13RPR1BLowerSha256 $PilotPlanPath)-eq[string]$provenance.config.sha256) 'Plan SHA-256 must equal provenance config binding.'
foreach($binding in @($provenance.boundFiles)){
    $path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\')
    $passed=(Test-Path -LiteralPath $path -PathType Leaf)-and(Get-Gate13RPR1BLowerSha256 $path)-eq[string]$binding.sha256
    Add-Check ('bound-'+([string]$binding.relativePath).Replace('/','_').Replace('.','_')) $passed ([string]$binding.relativePath)
}
$parserFiles=@(
 'Research\Gate13RPR1BOrderEffectPreparationV1.psm1','Research\Run-Gate13RPR1BOrderEffectPilotV1.ps1',
 'Research\Verification\Run-Gate13RPR1BStaticUnitV1.ps1','Research\Verification\Run-Gate13RPR1BBlockVerificationV1.ps1',
 'Research\Verification\Run-Gate13RPR1BValidationOnlyPrePilotAuditV1.ps1','Research\Verification\Run-Gate13RPR1BPrePilotV1.ps1'
)
foreach($relative in $parserFiles){
    $path=Join-Path $ProjectPath $relative;$tokens=$null;$parseErrors=$null;[void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    Add-Check ('parser-'+[IO.Path]::GetFileName($relative)) (@($parseErrors).Count-eq0) ((@($parseErrors)|ForEach-Object{$_.Message})-join'; ')
}
try{
    $campaigns=@(Get-Gate13RPR1BCampaigns -ProjectPath $ProjectPath -Plan $plan)
    $measured=@(Get-Gate13RPR1BProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'measured-non-formal-pilot')
    $warmup=@(Get-Gate13RPR1BProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'excluded-warmup')
    $scheduleCheck=Test-Gate13RPR1BSchedule -Plan $plan -Measured $measured -Warmup $warmup
    Add-Check 'schedule-contract' ($scheduleCheck.passed-eq$true) (($scheduleCheck.errors)-join'; ')
    $scheduleManifest=[ordered]@{schemaVersion=1;manifestKind='gate13r-pr1b-generated-schedule-validation-v1';measuredProcessCount=$measured.Count;warmupProcessCount=$warmup.Count;measuredPairCount=@($measured|Group-Object mirroredPairId).Count;scenarioIds=@($plan.scenarioIds);measured=@($measured|ForEach-Object{[pscustomobject][ordered]@{ordinal=$_.ordinal;wave=$_.wave;scenarioWaveSlot=$_.scenarioWaveSlot;scenarioId=$_.scenarioId;block=$_.block;mirroredPairId=$_.mirroredPairId;firstSuperblockOrder=$_.firstSuperblockOrder;superblockOrder=$_.superblockOrder;pairProcessPosition=$_.pairProcessPosition;campaignId=$_.campaign.campaignId;comparisonCohortId=$_.campaign.comparisonCohortId;campaignIdPrefix=$_.campaignIdPrefix;relativeOutput=$_.relativeOutput}});passed=$scheduleCheck.passed}
    Write-Gate13RPR1BAtomicUtf8NoBomJson -Path (Join-Path $outputRoot 'generated-schedule-validation.json') -Value $scheduleManifest -Depth 20
}catch{Add-Check 'schedule-generation' $false $_.Exception.Message}
$pilotRoot=Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/','\');$formalRoot=Join-Path $ProjectPath ([string]$plan.paths.reservedFormalRootRelativePath).Replace('/','\')
Add-Check 'pilot-root-absent' (-not(Test-Path -LiteralPath $pilotRoot)) $pilotRoot
Add-Check 'formal-root-absent' (-not(Test-Path -LiteralPath $formalRoot)) $formalRoot
Add-Check 'no-unity-process' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-eq0) 'Static/unit must not coexist with Unity.'
$pilotScript=Join-Path $ProjectPath 'Research\Run-Gate13RPR1BOrderEffectPilotV1.ps1';$dummy=Join-Path $ProjectPath 'Research\Gate13R_PR1B_OrderEffect_Pilot_Plan.v1.json';$winps='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$bindingOutput=&$winps -NoProfile -ExecutionPolicy Bypass -File $pilotScript -ProjectPath $ProjectPath -PilotPlanPath $dummy -ProvenancePath $dummy -PrePilotAuditPath $dummy -TelemetryResultPath $dummy -BindingSmokeOnly 2>&1|Out-String;$bindingExit=[int]$LASTEXITCODE
Add-Check 'pilot-binding-smoke' ($bindingExit-eq0-and$bindingOutput.Contains('BINDING-SMOKE-PASSED')) $bindingOutput.Trim()
$analyzer=Join-Path $ProjectPath 'Research\Analyze-Gate13RPR1BOrderEffectPilotV1.py';$selfTest=Join-Path $outputRoot 'analyzer-self-test.json';$python=(Get-Command py.exe -ErrorAction Stop).Source
&$python -3 -c "import ast,pathlib; ast.parse(pathlib.Path(r'$analyzer').read_text(encoding='utf-8'))" 2>&1|Set-Content -LiteralPath (Join-Path $outputRoot 'python-parser.log') -Encoding UTF8
Add-Check 'python-parser' ($LASTEXITCODE-eq0) 'Python AST parser result.'
&$python -3 $analyzer --self-test --self-test-output $selfTest 1>(Join-Path $outputRoot 'analyzer-self-test.stdout.log') 2>(Join-Path $outputRoot 'analyzer-self-test.stderr.log')
$selfPassed=$LASTEXITCODE-eq0-and(Test-Path -LiteralPath $selfTest)-and((Read-Gate13RPR1BJson $selfTest).passed-eq$true)
Add-Check 'analyzer-self-test' $selfPassed 'Synthetic estimator and classification fixtures.'
$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr1b-static-unit-summary-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');checkCount=$checks.Count;passedCheckCount=@($checks|Where-Object passed).Count;checks=$checks.ToArray();errors=$errors.ToArray();unityInvoked=$false;formalCampaign=$false;passed=$errors.Count-eq0}
Write-Gate13RPR1BAtomicUtf8NoBomJson -Path (Join-Path $outputRoot 'summary.json') -Value $summary -Depth 30
if($errors.Count){Write-Error("PR1B static/unit failed: "+($errors-join'; '));exit 1};Write-Host 'PR1B static/unit passed.' -ForegroundColor Green;exit 0
