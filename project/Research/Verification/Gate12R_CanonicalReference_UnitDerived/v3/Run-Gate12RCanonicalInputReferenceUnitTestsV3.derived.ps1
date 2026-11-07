[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [string]$OutputRelativePath='Research/Verification/Gate12R_CanonicalInputReference/v3',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Canonical-reference tests require an absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RCanonicalInputReferenceUnitTestsV1|$ProjectPath");exit 0}
$output=Join-Path $ProjectPath $OutputRelativePath.Replace('/','\');if(Test-Path -LiteralPath $output){throw "Create-new canonical-reference test root exists: $output"};New-Item -ItemType Directory -Path $output|Out-Null
$module=Join-Path $ProjectPath 'Research\Gate12RCanonicalInputReferenceV2.psm1';Import-Module $module -Force
$sourceRoot=Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v2'
$sourceBlock=Join-Path $sourceRoot 'measured\01-core-r01-s1-shared--shared\b001'
$sourcePlan=Join-Path $sourceRoot 'plans\measured-non-formal-pilot\0045-core-r01-s1-shared--shared-b001.block-plan.json'
$preservation=Join-Path $ProjectPath 'Research\Gate12R_PilotAttempt2_Terminal_Preservation.v1.json'
$checks=New-Object Collections.Generic.List[object]
function Add-Check([string]$Name,[bool]$Passed,[string]$Evidence){$script:checks.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;evidence=$Evidence});if(-not$Passed){throw "Canonical-reference unit check failed: $Name ($Evidence)"}}
function Get-Hash([string]$Path){return(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-TrackedPayload($Root){$rows=New-Object Collections.Generic.List[object];foreach($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File|Where-Object{$_.Name-in@('operations.jsonl','workload-result.json')}|Sort-Object FullName)){$rows.Add([pscustomobject]@{relativePath=$file.FullName.Substring($Root.Length+1);sha256=Get-Hash $file.FullName})};return $rows.ToArray()}

try{
    Add-Check 'attempt2-preservation-present' (Test-Path -LiteralPath $preservation -PathType Leaf) $preservation
    Add-Check 'attempt2-partial-manifest-still-frozen' ((Get-Hash (Join-Path $sourceRoot 'partial-output-manifest.json'))-eq'ceee7b34eedb9d6cbd4053c138e8fc3c7da1526aeb8016d6ee00a3cd0089e0b7') 'attempt2 partial-output-manifest SHA-256'
    $planCopy=Join-Path $output 'source-plan.json';Copy-Item -LiteralPath $sourcePlan -Destination $planCopy
    $positive=Join-Path $output 'positive';Copy-Item -LiteralPath $sourceBlock -Destination $positive -Recurse
    $beforePayload=@(Get-TrackedPayload $positive);$beforeBytes=[long](Get-ChildItem -LiteralPath $positive -Recurse -File|Measure-Object Length -Sum).Sum
    $result=Invoke-Gate12RCanonicalInputExternalization -ProjectPath $ProjectPath -OutputDirectory $positive -BlockPlanPath $planCopy
    Add-Check 'positive-result-passed' ($result.passed-eq$true) ([string]$result.receiptSha256)
    Add-Check 'positive-four-references' ([int]$result.referenceCount-eq4) ([string]$result.referenceCount)
    Add-Check 'positive-local-copies-absent' (@(Get-ChildItem -LiteralPath $positive -Recurse -Filter scenario.canonical.json -File).Count-eq0) 'zero local canonical copies'
    $afterPayload=@(Get-TrackedPayload $positive);Add-Check 'operations-and-results-unchanged' ((ConvertTo-Json $beforePayload -Depth 5 -Compress)-eq(ConvertTo-Json $afterPayload -Depth 5 -Compress)) 'payload SHA list exact match'
    $afterBytes=[long](Get-ChildItem -LiteralPath $positive -Recurse -File|Measure-Object Length -Sum).Sum
    Add-Check 'raw-bytes-reduced' ($afterBytes-lt$beforeBytes) ("before=$beforeBytes after=$afterBytes removed=$($result.removedLocalCanonicalRawBytes)")
    $manifestFiles=@(Get-ChildItem -LiteralPath $positive -Recurse -Filter manifest.json -File);$resolved=0
    foreach($manifestFile in $manifestFiles){$m=Get-Content -LiteralPath $manifestFile.FullName -Raw|ConvertFrom-Json;$source=Join-Path $ProjectPath ([string]$m.canonicalScenarioProjectRelativePath).Replace('/','\');if([string]$m.canonicalScenarioStorageKind-eq'frozen-gate11r-upstream-reference-v1'-and(Test-Path $source)-and(Get-Hash $source)-eq[string]$m.canonicalScenarioSha256-and$m.canonicalScenarioLocalCopyPresent-eq$false){$resolved++}}
    Add-Check 'all-references-resolve-and-hash' ($resolved-eq4) ("resolved=$resolved")
    $block=Get-Content -LiteralPath (Join-Path $positive 'block-manifest.json') -Raw|ConvertFrom-Json;Add-Check 'block-reference-contract' ($block.canonicalScenarioReferenceValidationPassed-eq$true-and[int]$block.canonicalScenarioReferenceCount-eq4) 'block manifest reference fields'

    $negativeOutside=Join-Path $output 'negative-outside-root';Copy-Item -LiteralPath $sourceBlock -Destination $negativeOutside -Recurse;$first=Get-ChildItem -LiteralPath $negativeOutside -Recurse -Filter manifest.json -File|Select-Object -First 1;$m=Get-Content -LiteralPath $first.FullName -Raw|ConvertFrom-Json;$m.scenarioSourcePath=Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v2.json';$json=($m|ConvertTo-Json -Depth 40).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($first.FullName,$json,(New-Object Text.UTF8Encoding($false,$true)));$outsideRejected=$false;try{Invoke-Gate12RCanonicalInputExternalization -ProjectPath $ProjectPath -OutputDirectory $negativeOutside -BlockPlanPath $planCopy|Out-Null}catch{$outsideRejected=$true};Add-Check 'outside-source-rejected' $outsideRejected 'expected fail-closed rejection';Add-Check 'outside-negative-not-published' (-not(Test-Path (Join-Path $negativeOutside 'canonical-input-reference-receipt.json'))) 'no success receipt'

    $negativeHash=Join-Path $output 'negative-hash-mismatch';Copy-Item -LiteralPath $sourceBlock -Destination $negativeHash -Recurse;$canonical=Get-ChildItem -LiteralPath $negativeHash -Recurse -Filter scenario.canonical.json -File|Select-Object -First 1;[IO.File]::AppendAllText($canonical.FullName,"`n",(New-Object Text.UTF8Encoding($false,$true)));$hashRejected=$false;try{Invoke-Gate12RCanonicalInputExternalization -ProjectPath $ProjectPath -OutputDirectory $negativeHash -BlockPlanPath $planCopy|Out-Null}catch{$hashRejected=$true};Add-Check 'hash-mismatch-rejected' $hashRejected 'expected fail-closed rejection';Add-Check 'hash-negative-not-published' (-not(Test-Path (Join-Path $negativeHash 'canonical-input-reference-receipt.json'))) 'no success receipt'

    $summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-canonical-input-upstream-reference-unit-tests-v3-explicit-backup-atomic-replace';completedAtUtc=[DateTime]::UtcNow.ToString('o');sourceAttempt='Research/PilotRuns/Gate12R_ProcessReuse_5pct/v2';sourceAttemptModified=$false;checkCount=$checks.Count;checks=$checks.ToArray();positiveBeforeRawBytes=$beforeBytes;positiveAfterRawBytes=$afterBytes;positiveRemovedCanonicalRawBytes=[long]$result.removedLocalCanonicalRawBytes;thresholdsChanged=$false;matrixChanged=$false;williamsChanged=$false;algorithmSemanticsChanged=$false;passed=$true}
    $summaryPath=Join-Path $output 'summary.json';$summaryJson=($summary|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($summaryPath,$summaryJson,(New-Object Text.UTF8Encoding($false,$true)));$summary|ConvertTo-Json -Depth 30;exit 0
}catch{
    $failure=[ordered]@{schemaVersion=1;receiptKind='gate12r-canonical-reference-unit-failure-v3';failedAtUtc=[DateTime]::UtcNow.ToString('o');message=$_.Exception.ToString();checks=$checks.ToArray();passed=$false};$json=($failure|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText((Join-Path $output 'failure-receipt.json'),$json,(New-Object Text.UTF8Encoding($false,$true)));Write-Error $_.Exception.ToString();exit 1
}
