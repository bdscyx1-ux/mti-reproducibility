[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$source=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt3ArtifactsV1.ps1'
$destination=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt4ArtifactsV1.ps1'
$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt4_Generator_Derivation_Receipt.v1.json'
foreach($path in @($destination,$receiptPath)){if(Test-Path -LiteralPath $path){throw "Create-new target exists: $path"}}
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Replace-Required([string]$Text,[string]$From,[string]$To,[int]$Minimum=1){
    $count=[regex]::Matches($Text,[regex]::Escape($From)).Count
    if($count-lt$Minimum){throw "Required generator route missing: $From"}
    return [pscustomobject]@{text=$Text.Replace($From,$To);count=$count;from=$From;to=$To}
}
$text=[IO.File]::ReadAllText($source)
$routes=New-Object Collections.Generic.List[object]
foreach($route in @(
    @('Attempt3','Attempt4'),
    @('attempt3','attempt4'),
    @('V3','V4'),
    @('v3','v4'),
    @('$plan.pilotAttempt=3','$plan.pilotAttempt=4')
)){
    $result=Replace-Required $text ([string]$route[0]) ([string]$route[1])
    $text=$result.text;$routes.Add([pscustomobject]@{from=$result.from;to=$result.to;count=$result.count})
}

$generic='    $(Route "-v2''" "-v4''")'
$exact=@'
    $(Route 'gate13r-36h-four-lane-block-wrapper-summary-v2' 'gate13r-36h-four-lane-block-wrapper-summary-v4'),
    $(Route 'gate13r-36h-four-lane-block-wrapper-failure-v2' 'gate13r-36h-four-lane-block-wrapper-failure-v4'),
    $(Route 'gate13r-36h-four-lane-telemetry-wrapper-v2' 'gate13r-36h-four-lane-telemetry-wrapper-v4'),
    $(Route 'gate13r-36h-isolated-lane-copy-manifest-v2' 'gate13r-36h-isolated-lane-copy-manifest-v4'),
    $(Route 'gate13r-36h-four-isolated-project-copies-v2' 'gate13r-36h-four-isolated-project-copies-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-execution-receipt-v2' 'gate13r-36h-four-lane-nonformal-pilot-execution-receipt-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-checkpoint-v2' 'gate13r-36h-four-lane-nonformal-pilot-checkpoint-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-execution-manifest-v2' 'gate13r-36h-four-lane-nonformal-pilot-execution-manifest-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-failure-v2' 'gate13r-36h-four-lane-nonformal-pilot-failure-v4'),
    $(Route 'gate13r-36h-four-lane-pilot-partial-output-manifest-v1' 'gate13r-36h-four-lane-pilot-partial-output-manifest-v4'),
    $(Route 'gate13r-36h-four-lane-post-pilot-readiness-v2' 'gate13r-36h-four-lane-post-pilot-readiness-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-manifest-v2' 'gate13r-36h-four-lane-nonformal-pilot-manifest-v4'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-schedule-v2' 'gate13r-36h-10pct-four-lane-nonformal-pilot-schedule-v4'),
    $(Route 'gate13r-36h-four-lane-pilot-schedule-generation-v2' 'gate13r-36h-four-lane-pilot-schedule-generation-v4'),
    $(Route 'gate13r-36h-four-lane-static-unit-summary-v2' 'gate13r-36h-four-lane-static-unit-summary-v4'),
    $(Route 'gate13r-36h-retained-regression-mechanical-file-scope-derivation-v2' 'gate13r-36h-retained-regression-mechanical-file-scope-derivation-v4'),
    $(Route 'gate13r-36h-four-lane-verification-checkpoint-v2' 'gate13r-36h-four-lane-verification-checkpoint-v4'),
    $(Route 'gate13r-36h-four-lane-nonexecuting-verification-receipt-v2' 'gate13r-36h-four-lane-nonexecuting-verification-receipt-v4'),
    $(Route 'gate13r-36h-four-lane-block-verification-v2' 'gate13r-36h-four-lane-block-verification-v4'),
    $(Route 'gate13r-36h-verification-partial-output-manifest-v2' 'gate13r-36h-verification-partial-output-manifest-v4'),
    $(Route 'gate13r-36h-nonexecuting-verification-failure-v2' 'gate13r-36h-nonexecuting-verification-failure-v4'),
    $(Route 'gate13r-36h-four-lane-validation-only-pre-pilot-audit-v2' 'gate13r-36h-four-lane-validation-only-pre-pilot-audit-v4')
'@.TrimEnd()
$result=Replace-Required $text $generic $exact
$text=$result.text;$routes.Add([pscustomobject]@{from=$result.from;to='exact-non-overlapping-kind-routes';count=$result.count})

$frozenAnchor='$frozen=@('
$frozenInsert=@'
$frozen=@(
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v3.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt1_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Partial_Manifest.v1.json',
    'Research\Gate13R36hConcurrencyPreparationV3.psm1',
    'Research\Initialize-Gate13R36hLaneCopiesV3.ps1',
    'Research\Run-Gate13R36hBlockV3.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV3.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV3.ps1',
'@
$result=Replace-Required $text $frozenAnchor $frozenInsert
$text=$result.text;$routes.Add([pscustomobject]@{from='frozen-array-anchor';to='frozen-v3-evidence-prefix';count=$result.count})

$upstreamAnchor=@'
$plan.upstreamHashes|Add-Member -NotePropertyName attempt2StaticFailureSummary -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\summary.json'))
'@.Trim()
$upstreamReplacement=@'
$plan.upstreamHashes|Add-Member -NotePropertyName attempt2StaticFailureSummary -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\summary.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt3DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json'))
'@.Trim()
$result=Replace-Required $text $upstreamAnchor $upstreamReplacement
$text=$result.text;$routes.Add([pscustomobject]@{from='attempt2-upstream-anchor';to='attempt2-plus-attempt3-upstream-bindings';count=$result.count})

$provenanceAnchor="attempt2StaticCheckpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\checkpoint.json';attempt4DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt4ArtifactsV1.ps1'"
$provenanceReplacement="attempt2StaticCheckpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\checkpoint.json';attempt3Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v3.json';attempt3PrewriteFailure=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt1_Failure.v1.json';attempt3ReverseFailure=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json';attempt3PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Partial_Manifest.v1.json';attempt4GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt4GeneratorV1.ps1';attempt4GeneratorDerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt4_Generator_Derivation_Receipt.v1.json';attempt4DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt4ArtifactsV1.ps1'"
$result=Replace-Required $text $provenanceAnchor $provenanceReplacement
$text=$result.text;$routes.Add([pscustomobject]@{from='v4-provenance-anchor';to='v3-failure-and-v4-generator-bindings';count=$result.count})

$tokens=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$parseErrors)
if(@($parseErrors).Count-ne0){throw "Attempt4 generator parse failure: $(@($parseErrors|ForEach-Object Message)-join'; ')"}
[IO.File]::WriteAllText($destination,$text,$utf8)
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt4-generator-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/New-Gate13R36hAttempt3ArtifactsV1.ps1';sourceSha256=Hash $source;destinationRelativePath='Research/Verification/New-Gate13R36hAttempt4ArtifactsV1.ps1';destinationSha256=Hash $destination;routes=$routes.ToArray();windowsPowerShell51ParsePassed=$true;formalCampaign=$false;pilotStarted=$false;passed=$true}
$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n"
[IO.File]::WriteAllText($receiptPath,$json,$utf8)
$receipt|ConvertTo-Json -Depth 8
