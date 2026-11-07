[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BlockPlanPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][ValidateSet('Verification','Pilot')][string]$Mode,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly,
    [switch]$ExpectFailure,
    [int]$ExpectedCompletedSamplesBeforeFailure=1,
    [int]$TimeoutSeconds=3600
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R v5 memory-amended block wrapper requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RProcessReuseBlockV5|$ProjectPath|$Mode");exit 0}
$BlockPlanPath=[IO.Path]::GetFullPath($BlockPlanPath);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory);$AllowedRoot=[IO.Path]::GetFullPath($AllowedRoot);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$baseWrapper=Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlockV3.ps1';$module=Join-Path $ProjectPath 'Research\Gate12RCanonicalInputReferenceV2.psm1'
if(-not(Test-Path -LiteralPath $baseWrapper -PathType Leaf)-or-not(Test-Path -LiteralPath $module -PathType Leaf)){throw 'Gate12R v5 memory-amended block dependencies are missing.'}
$plan=Get-Content -LiteralPath $BlockPlanPath -Raw -Encoding UTF8|ConvertFrom-Json
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$baseWrapper,'-BlockPlanPath',$BlockPlanPath,'-OutputDirectory',$OutputDirectory,'-AllowedRoot',$AllowedRoot,'-Mode',$Mode,'-UnityPath',$UnityPath,'-ProjectPath',$ProjectPath,'-TimeoutSeconds',$TimeoutSeconds)
if($ExpectFailure){$arguments+=@('-ExpectFailure','-ExpectedCompletedSamplesBeforeFailure',$ExpectedCompletedSamplesBeforeFailure)}
&$windowsPowerShell @arguments
$baseExit=[int]$LASTEXITCODE
if($baseExit-ne0){Write-Error "Gate12R base block wrapper failed: exit=$baseExit";exit $baseExit}
if($ExpectFailure){Write-Host 'Gate12R v5 negative block passed without storage transformation.' -ForegroundColor Green;exit 0}

$failurePath=$OutputDirectory+'.canonical-storage-failure.json'
try{
    Import-Module $module -Force
    $beforeBytes=[long](Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File -Force|Measure-Object Length -Sum).Sum
    $result=Invoke-Gate12RCanonicalInputExternalization -ProjectPath $ProjectPath -OutputDirectory $OutputDirectory -BlockPlanPath $BlockPlanPath
    if($result.passed-ne$true){throw 'Canonical input externalization did not return passed=true.'}
    $afterBytes=[long](Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File -Force|Measure-Object Length -Sum).Sum
    $summaryPath=$OutputDirectory+'.summary.json';$summary=Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8|ConvertFrom-Json
    $summary.summaryKind='gate12r-process-reuse-block-wrapper-summary-v3-memory-aggregation-upstream-canonical-reference'
    $summary.blockManifestSha256=[string]$result.blockManifestSha256
    foreach($property in @(
        [pscustomobject]@{n='canonicalScenarioStorageKind';v=[string]$result.storageKind},
        [pscustomobject]@{n='canonicalInputReferenceReceiptRelativePath';v='canonical-input-reference-receipt.json'},
        [pscustomobject]@{n='canonicalInputReferenceReceiptSha256';v=[string]$result.receiptSha256},
        [pscustomobject]@{n='canonicalReferenceCount';v=[int]$result.referenceCount},
        [pscustomobject]@{n='canonicalLogicalRawBytesRemoved';v=[long]$result.removedLocalCanonicalRawBytes},
        [pscustomobject]@{n='blockRawBytesBeforeExternalization';v=$beforeBytes},
        [pscustomobject]@{n='blockRawBytesAfterExternalization';v=$afterBytes},
        [pscustomobject]@{n='canonicalReferenceValidationPassed';v=$true}
    )){if($null-ne$summary.PSObject.Properties[$property.n]){$summary.($property.n)=$property.v}else{$summary|Add-Member -NotePropertyName $property.n -NotePropertyValue $property.v}}
    $json=($summary|ConvertTo-Json -Depth 40).Replace("`r`n","`n").Replace("`r","`n")+"`n";$tmp=$summaryPath+'.tmp-'+[Guid]::NewGuid().ToString('N');[IO.File]::WriteAllText($tmp,$json,(New-Object Text.UTF8Encoding($false,$true)));$backup=$summaryPath+'.replace-backup-'+[Guid]::NewGuid().ToString('N');[IO.File]::Replace($tmp,$summaryPath,$backup);if(Test-Path -LiteralPath $backup){[IO.File]::Delete($backup)}
    if(Test-Path -LiteralPath $failurePath){throw 'Unexpected canonical-storage failure receipt exists.'}
    Write-Host ("Gate12R v5 memory-amended block passed; exact upstream canonical references removed {0} duplicated bytes."-f$result.removedLocalCanonicalRawBytes) -ForegroundColor Green
    exit 0
}catch{
    $failure=[ordered]@{schemaVersion=1;receiptKind='gate12r-canonical-input-reference-failure-v3-memory-aggregation';failedAtUtc=[DateTime]::UtcNow.ToString('o');blockId=[string]$plan.blockId;message=$_.Exception.ToString();baseBlockPassed=$true;canonicalExternalizationPassed=$false;memoryGatePolicyId='gate12r-sample-128mib-block-128mib-per-sample-v1';sampleThresholdChanged=$false;blockAggregationRuleChanged=$true;formalCampaign=$false;automaticRetryAttempted=$false;automaticResumeAttempted=$false;passed=$false};$json=($failure|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($failurePath,$json,(New-Object Text.UTF8Encoding($false,$true)));Write-Error "Gate12R canonical input reference transformation failed: $($_.Exception.Message)";exit 1
}
