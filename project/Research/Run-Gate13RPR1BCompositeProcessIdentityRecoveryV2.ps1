[CmdletBinding()]
param(
    [string]$ProjectPath = '',
    [string]$PythonPath = 'C:\Users\bdscy\AppData\Local\Python\bin\python3.exe',
    [string]$VerificationRoot = '',
    [string]$RecoveryRoot = ''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)){$ProjectPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
if([string]::IsNullOrWhiteSpace($VerificationRoot)){$VerificationRoot=Join-Path $ProjectPath 'Research\Verification\Gate13R_PR1B_CompositeProcessIdentity_Recovery\v2'}
if([string]::IsNullOrWhiteSpace($RecoveryRoot)){$RecoveryRoot=Join-Path $ProjectPath 'Research\Analysis\Gate13R_PR1B_CompositeProcessIdentity_Recovery\v1'}
$pilotRoot=Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v7-gate13r-pr1b-order-effect-pathsafe-v4'
$plan=Join-Path $ProjectPath 'Research\Gate13R_PR1B_OrderEffect_Pilot_Plan.v9.json'
$sourceProvenance=Join-Path $ProjectPath 'Research\Gate13R_PR1B_OrderEffect_Provenance.v10.json'
$analyzer=Join-Path $ProjectPath 'Research\Analyze-Gate13RPR1BCompositeProcessIdentityRecoveryV1.py'
$schema=Join-Path $ProjectPath 'Research\Gate13R_PR1B_v4_AnalysisRecovery_Output_Schema.v1.json'
$preflight=Join-Path $VerificationRoot 'pilot-structural-preanalysis-audit.json'
$summaryPath=Join-Path $VerificationRoot 'validation-summary.json'
$formalRoot=Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned\v1'

if(-not(Test-Path -LiteralPath $summaryPath)){throw 'validation v2 summary missing'}
$summary=Get-Content -LiteralPath $summaryPath -Raw|ConvertFrom-Json
if(-not$summary.passed-or$summary.schemaVersion-ne2){throw 'validation v2 summary is not passed'}
if(Test-Path -LiteralPath $RecoveryRoot){throw 'one-shot recovery root already exists; automatic retry is prohibited'}
if(Test-Path -LiteralPath $formalRoot){throw 'formal root must remain absent'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')){throw 'Unity lockfile present'}
if(@(Get-Process -Name Unity,UnityEditor -ErrorAction SilentlyContinue).Count-ne0){throw 'active Unity process present'}

# Exactly one Python recovery invocation; the earlier v1 wrapper never reached
# this invocation point and therefore did not consume the authorized recovery.
$result=& $PythonPath $analyzer --project $ProjectPath --recover --pilot-root $pilotRoot --plan $plan --provenance $sourceProvenance --preflight-report $preflight --schema $schema --expected-tree-sha256 '4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed' --output-root $RecoveryRoot 2>&1
$exitCode=$LASTEXITCODE
$result|ForEach-Object{Write-Output $_}
if($exitCode-ne0){throw "single read-only analysis recovery failed with exit code $exitCode; no retry is authorized"}
$checkpoint=Get-Content -LiteralPath (Join-Path $RecoveryRoot 'analysis-recovery-checkpoint.json') -Raw|ConvertFrom-Json
if(-not$checkpoint.passed){throw 'recovery checkpoint is not passed'}
if(@(Get-Process -Name Unity,UnityEditor -ErrorAction SilentlyContinue).Count-ne0){throw 'unexpected Unity process after recovery'}
if(Test-Path -LiteralPath $formalRoot){throw 'formal root appeared unexpectedly'}
