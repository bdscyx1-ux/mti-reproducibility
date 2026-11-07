[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath,[switch]$BindingSmokeOnly)

$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Attempt 2 requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RRetainedRegressionV2|'+$ProjectPath);exit 0}
$sourceScriptPath=Join-Path $PSScriptRoot 'Run-Gate12AnalysisUnitTests.ps1'
$originalSummaryPath=Join-Path $PSScriptRoot 'Gate12_AnalysisUnitTests.summary.json'
$root=Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v2\RetainedRegression'
$summaryPath=Join-Path $root 'RetainedRegression63.summary.json'
$stdoutPath=Join-Path $root 'RetainedRegression63.stdout.log'
$stderrPath=Join-Path $root 'RetainedRegression63.stderr.log'
if(Test-Path -LiteralPath $root){throw 'Gate 10R retained-regression evidence exists; refusing retry/overwrite.'}
if(-not(Test-Path -LiteralPath $sourceScriptPath -PathType Leaf)-or-not(Test-Path -LiteralPath $originalSummaryPath -PathType Leaf)){throw 'Retained regression source/evidence is missing.'}
New-Item -ItemType Directory -Path $root|Out-Null
$originalHashBefore=(Get-FileHash -LiteralPath $originalSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
$source=[IO.File]::ReadAllText($sourceScriptPath)
$escapedDirectory=$PSScriptRoot.Replace("'","''")
$escapedSummary=$summaryPath.Replace("'","''")
$source=$source.Replace('$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path',("`$scriptDirectory = '"+$escapedDirectory+"'"))
$source=$source.Replace("`$summaryPath = Join-Path `$scriptDirectory 'Gate12_AnalysisUnitTests.summary.json'",("`$summaryPath = '"+$escapedSummary+"'"))
$nativePowerShellModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join ';'
$previous=$env:PSModulePath
try{
    $env:PSModulePath=$nativePowerShellModulePath
    $source|& 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -Command '& ([ScriptBlock]::Create([Console]::In.ReadToEnd()))' 1>$stdoutPath 2>$stderrPath
    $exitCode=[int]$LASTEXITCODE
}finally{$env:PSModulePath=$previous}
if($exitCode-ne 0){Write-Error "Retained 63-assertion regression failed with exit $exitCode; no retry was attempted.";exit 1}
if(-not(Test-Path -LiteralPath $summaryPath -PathType Leaf)){throw 'Gate 10R retained-regression summary is missing.'}
$summary=Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8|ConvertFrom-Json
$originalHashAfter=(Get-FileHash -LiteralPath $originalSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($summary.passed-ne $true-or[int]$summary.assertionCount-ne 63-or$originalHashAfter-ne$originalHashBefore){throw 'Retained regression did not pass 63/63 or modified original evidence.'}
Write-Host 'Gate 10R retained regression passed 63/63.' -ForegroundColor Green
exit 0

