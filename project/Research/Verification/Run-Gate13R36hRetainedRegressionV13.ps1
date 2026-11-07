[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$allowedRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v13'))
if(-not$OutputDirectory.StartsWith($allowedRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Retained-regression output is outside the authorized verification root.'}
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13R36hRetainedRegressionV13|$ProjectPath");exit 0}
if(Test-Path -LiteralPath $OutputDirectory){throw "Create-new retained-regression output exists: $OutputDirectory"}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null

$sourceDirectory=Join-Path $ProjectPath 'Research\Verification'
$sourceScriptPath=Join-Path $sourceDirectory 'Run-Gate12AnalysisUnitTests.ps1'
$originalSummaryPath=Join-Path $sourceDirectory 'Gate12_AnalysisUnitTests.summary.json'
$derivedScriptPath=Join-Path $OutputDirectory 'Run-Gate12AnalysisUnitTests.Gate13R36h.derived.ps1'
$summaryPath=Join-Path $OutputDirectory 'Gate12_AnalysisUnitTests.summary.json'
$stdoutPath=Join-Path $OutputDirectory 'child.stdout.log'
$stderrPath=Join-Path $OutputDirectory 'child.stderr.log'
$receiptPath=Join-Path $OutputDirectory 'mechanical-derivation-receipt.json'
$expectedSourceSha='e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1'
$sourceHashBefore=(Get-FileHash -LiteralPath $sourceScriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
$originalSummaryHashBefore=(Get-FileHash -LiteralPath $originalSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($sourceHashBefore-ne$expectedSourceSha){throw 'Frozen retained-regression source hash changed.'}

$source=[IO.File]::ReadAllText($sourceScriptPath)
$sourceDirectoryLiteral=$sourceDirectory.Replace("'","''")
$summaryLiteral=$summaryPath.Replace("'","''")
$fromDirectory='$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path'
$toDirectory="`$scriptDirectory = '$sourceDirectoryLiteral'"
$fromSummary="`$summaryPath = Join-Path `$scriptDirectory 'Gate12_AnalysisUnitTests.summary.json'"
$toSummary="`$summaryPath = '$summaryLiteral'"
if(([regex]::Matches($source,[regex]::Escape($fromDirectory))).Count-ne1-or([regex]::Matches($source,[regex]::Escape($fromSummary))).Count-ne1){throw 'Frozen harness no longer has the expected single mechanical transform sites.'}
$derived=$source.Replace($fromDirectory,$toDirectory).Replace($fromSummary,$toSummary)
[IO.File]::WriteAllText($derivedScriptPath,$derived,(New-Object Text.UTF8Encoding($false,$true)))
$tokens=$null;$parseErrors=$null;[void][Management.Automation.Language.Parser]::ParseFile($derivedScriptPath,[ref]$tokens,[ref]$parseErrors);if($parseErrors.Count){throw "Derived harness parser failure: $($parseErrors.Message-join'; ')"}

$windowsPowerShell='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$process=Start-Process -FilePath $windowsPowerShell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$derivedScriptPath,'-ProjectPath',$ProjectPath) -WorkingDirectory $ProjectPath -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -Wait -PassThru
$exitCode=[int]$process.ExitCode
$sourceHashAfter=(Get-FileHash -LiteralPath $sourceScriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
$originalSummaryHashAfter=(Get-FileHash -LiteralPath $originalSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
$summary=if(Test-Path -LiteralPath $summaryPath -PathType Leaf){Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8|ConvertFrom-Json}else{$null}
$passed=$exitCode-eq0-and$null-ne$summary-and$summary.passed-eq$true-and[int]$summary.assertionCount-eq63-and$sourceHashAfter-eq$sourceHashBefore-and$originalSummaryHashAfter-eq$originalSummaryHashBefore
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-retained-regression-mechanical-file-scope-derivation-v13';completedAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/Run-Gate12AnalysisUnitTests.ps1';sourceSha256Before=$sourceHashBefore;sourceSha256After=$sourceHashAfter;originalSummaryRelativePath='Research/Verification/Gate12_AnalysisUnitTests.summary.json';originalSummarySha256Before=$originalSummaryHashBefore;originalSummarySha256After=$originalSummaryHashAfter;derivedScriptRelativePath=$derivedScriptPath.Substring($ProjectPath.TrimEnd('\').Length+1).Replace('\','/');derivedScriptSha256=(Get-FileHash -LiteralPath $derivedScriptPath -Algorithm SHA256).Hash.ToLowerInvariant();transformCount=2;executionScope='file-script-scope';exitCode=$exitCode;assertionCount=if($null-ne$summary){[int]$summary.assertionCount}else{0};passed=$passed}
$json=($receipt|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,(New-Object Text.UTF8Encoding($false,$true)))
if(-not$passed){Write-Error 'Gate13R 36h retained regression failed; evidence was preserved and no retry was attempted.';exit 1}
Write-Host 'Gate13R 36h retained regression passed 63/63 in a mechanically derived file-scope harness.' -ForegroundColor Green
exit 0
