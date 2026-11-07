[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'PR1B v3 static/unit requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BStaticUnitV4|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath)
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR1BOrderEffectPreparationV4.psm1') -Force
$plan=Read-Gate13RPR1BV3Json $PilotPlanPath;$provenance=Read-Gate13RPR1BV3Json $ProvenancePath
$root=Join-Path $VerificationRoot 'StaticUnit';if(Test-Path -LiteralPath $root){throw "Create-new PR1B v3 static/unit root exists: $root"};New-Item -ItemType Directory -Path $root -Force|Out-Null
$checks=New-Object Collections.Generic.List[object];$errors=New-Object Collections.Generic.List[string]
function Add-Check([string]$Id,[bool]$Passed,[string]$Detail){$script:checks.Add([pscustomobject][ordered]@{id=$Id;passed=$Passed;detail=$Detail});if(-not$Passed){$script:errors.Add("$Id`: $Detail")}}
try{Assert-Gate13RPR1BV3PlanIdentity $plan;Add-Check 'plan-identity-and-memory-policy' $true ([string]$plan.planId)}catch{Add-Check 'plan-identity-and-memory-policy' $false $_.Exception.Message}
$campaigns=@();$measured=@();$warmup=@()
try{$campaigns=@(Get-Gate13RPR1BV3Campaigns -ProjectPath $ProjectPath -Plan $plan);$measured=@(Get-Gate13RPR1BV3ProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'measured-non-formal-pilot');$warmup=@(Get-Gate13RPR1BV3ProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'excluded-warmup');$schedule=Test-Gate13RPR1BV3Schedule -Plan $plan -Measured $measured -Warmup $warmup;Add-Check 'frozen-balanced-schedule' ($schedule.passed-eq$true-and$campaigns.Count-eq6) (($schedule.errors)-join'; ')}catch{Add-Check 'frozen-balanced-schedule' $false $_.Exception.Message}

foreach($binding in @($provenance.boundFiles)){
    $path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\')
    $ok=(Test-Path -LiteralPath $path -PathType Leaf)-and(Get-Gate13RPR1BV3LowerSha256 $path)-eq[string]$binding.sha256
    Add-Check ('provenance-'+([string]$binding.relativePath).Replace('/','_').Replace('.','_')) $ok ([string]$binding.relativePath)
}

$attempt1Terminal=Join-Path $ProjectPath 'Research\Gate13R_PR1B_OrderEffect_Pilot_Attempt1_Terminal_Preservation.v1.json'
$attempt1Root=Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v5-gate13r-pr1b-order-effect'
Add-Check 'attempt1-terminal-hash' ((Get-Gate13RPR1BV3LowerSha256 $attempt1Terminal)-eq'3b8192b5c8b6ca1defa495bce36698ccd8d9f04125df75bd118255374db15c38') $attempt1Terminal
Add-Check 'attempt1-root-present-terminal' (Test-Path -LiteralPath (Join-Path $attempt1Root 'failure-receipt.json') -PathType Leaf) $attempt1Root
$v3=Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate12RProcessReuseBatchCommandV3.cs'
Add-Check 'frozen-v3-command-hash' ((Get-Gate13RPR1BV3LowerSha256 $v3)-eq'eeca58f7e1121d0a297e8796430a90ae32f8492c32fc5fb676ae102b5f4a0c97') $v3
$v2Command=Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RPR1BMemoryAwareProcessReuseBatchCommandV2.cs'
Add-Check 'frozen-pr1b-v2-command-hash' ((Get-Gate13RPR1BV3LowerSha256 $v2Command)-eq'3d5cea49e983ba44a7bec7ff29100d4c6ba8e2ee7bd2e879b7b20a8c4ec46bbf') $v2Command

$command=Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.cs'
$source=[IO.File]::ReadAllText($command,[Text.Encoding]::UTF8)
$writeIndex=$source.IndexOf('WriteAtomicJson(evaluationPath, evaluation);',[StringComparison]::Ordinal)
$decisionIndex=$source.IndexOf('if (!evaluation.telemetryValid',[StringComparison]::Ordinal)
Add-Check 'evaluation-written-before-threshold-decision' ($writeIndex-ge0-and$decisionIndex-gt$writeIndex) "write=$writeIndex decision=$decisionIndex"
Add-Check 'failure-artifact-evaluation-references' ($source.Contains('memoryGateEvaluationSha256 = currentMemoryEvaluation.sha256')-and$source.Contains('memoryGateEvaluationSha256 = memoryEvaluation.sha256')) 'sample/block/checkpoint reference fields'
Add-Check 'memory-threshold-constants' ($source.Contains('SampleManagedAlertThresholdBytes = 134217728L')-and$source.Contains('SampleManagedEmergencyStopBytes = 268435456L')-and$source.Contains('TwoSampleBlockManagedGrowthLimitBytes = 268435456L')-and$source.Contains('NativeGrowthLimitBytes = 536870912L')) '128/256/256/512 MiB constants'
foreach($fixture in @('below-128-pass','exact-128-pass','above-128-alert','exact-256-alert-not-emergency','above-256-emergency','final-block-exact-256-pass','final-block-above-256-fail','final-working-exact-512-pass','final-working-above-512-fail','final-private-exact-512-pass','final-private-above-512-fail','missing-before','mixed-pid','mixed-process-start','nonfinite-process-age')){Add-Check ('source-fixture-'+$fixture) $source.Contains('"'+$fixture+'"') $fixture}
Add-Check 'two-sample-only-command' $source.Contains('accepts only a two-sample heterogeneous Williams block') 'shared four-sample blocks rejected'
Add-Check 'pathsafe-short-temp-leaf' ($source.Contains('AtomicTemporaryPrefix = ".g13tmp-"')-and$source.Contains('AtomicTemporaryLeafLength = 40')) 'fixed 40-character temporary leaf'
Add-Check 'pathsafe-create-new' $source.Contains('FileMode.CreateNew') 'temporary collision must not overwrite'
Add-Check 'pathsafe-reparse-rejection' ($source.Contains('FileAttributes.ReparsePoint')-and$source.Contains('ValidateOrdinaryDirectoryIdentity')) 'reparse traversal rejected'
Add-Check 'pathsafe-same-directory' $source.Contains('string temporary = Path.Combine(parent, temporaryLeaf)') 'temporary shares verified final parent'
Add-Check 'legacy-long-temp-removed' (-not$source.Contains('string temporary = path + ".tmp-"')) 'v2 filename-appending helper absent'
Add-Check 'pathsafe-boundary-fixtures' ($source.Contains('cff-position-legacy-temp-259')-and$source.Contains('idff-v6-legacy-temp-260')-and$source.Contains('legacy-temp-261')-and$source.Contains('legacy-temp-280')) '259/260/261/280 fixtures'

$scripts=@(
 'Research\Gate13RPR1BOrderEffectPreparationV4.psm1','Research\Run-Gate13RPR1BMemoryAwareBlockV4.ps1','Research\Run-Gate13RPR1BMemoryTelemetryProbeV4.ps1','Research\Run-Gate13RPR1BOrderEffectPilotV4.ps1',
 'Research\Verification\Run-Gate13RPR1BStaticUnitV4.ps1','Research\Verification\Run-Gate13RPR1BPathSafeAtomicSelfTestV4.ps1','Research\Verification\Run-Gate13RPR1BMemoryPolicySelfTestV5.ps1','Research\Verification\Run-Gate13RPR1BBlockVerificationV5.ps1','Research\Verification\Run-Gate13RPR1BValidationOnlyPrePilotAuditV4.ps1','Research\Verification\Run-Gate13RPR1BPrePilotV6.ps1'
)
foreach($relative in $scripts){$path=Join-Path $ProjectPath $relative;$tokens=$null;$parseErrors=$null;if(Test-Path $path){[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)|Out-Null};Add-Check ('parser-'+$relative.Replace('\','_')) ((Test-Path $path)-and@($parseErrors).Count-eq0) $(if(Test-Path $path){(@($parseErrors|ForEach-Object Message)-join'; ')}else{'missing'})}

$python=Join-Path $ProjectPath 'Research\Analyze-Gate13RPR1BOrderEffectPilotV4.py';$selfTest=Join-Path $root 'analyzer-self-test.json'
& py.exe -3 $python --project $ProjectPath --self-test --self-test-output $selfTest
$pythonExit=[int]$LASTEXITCODE;$self=if(Test-Path $selfTest){Read-Gate13RPR1BV3Json $selfTest}else{$null}
Add-Check 'analyzer-synthetic-self-test' ($pythonExit-eq0-and$null-ne$self-and$self.passed-eq$true) "exit=$pythonExit"

$pilotRoot=Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/','\');$formalRoot=Join-Path $ProjectPath ([string]$plan.paths.reservedFormalRootRelativePath).Replace('/','\')
Add-Check 'fresh-pilot-root-absent' (-not(Test-Path $pilotRoot)) $pilotRoot
Add-Check 'formal-root-absent' (-not(Test-Path $formalRoot)) $formalRoot
$summary=[ordered]@{schemaVersion=3;summaryKind='gate13r-pr1b-v3-pathsafe-static-unit-summary-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');checkCount=$checks.Count;passedCheckCount=@($checks|Where-Object passed).Count;checks=$checks.ToArray();errors=$errors.ToArray();unityInvoked=$false;formalCampaign=$false;passed=$errors.Count-eq0}
Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path (Join-Path $root 'summary.json') -Value $summary -Depth 50
if($errors.Count){Write-Error("PR1B v3 static/unit failed: "+($errors-join'; '));exit 1};Write-Host 'PR1B v3 static/unit passed.' -ForegroundColor Green;exit 0

