[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$source=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt4ArtifactsV1.ps1'
$destination=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt5ArtifactsV1.ps1'
$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Generator_Derivation_Receipt.v1.json'
foreach($path in @($destination,$receiptPath)){if(Test-Path -LiteralPath $path){throw "Create-new target exists: $path"}}
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Replace-Required([string]$Text,[string]$From,[string]$To,[int]$Minimum=1){$count=[regex]::Matches($Text,[regex]::Escape($From)).Count;if($count-lt$Minimum){throw "Required generator route missing: $From"};return [pscustomobject]@{text=$Text.Replace($From,$To);count=$count;from=$From;to=$To}}

$text=[IO.File]::ReadAllText($source)
$routes=New-Object Collections.Generic.List[object]
foreach($route in @(
    @('Attempt4','Attempt5'),
    @('attempt4','attempt5'),
    @('V4','V5'),
    @('v4','v5'),
    @('$plan.pilotAttempt=4','$plan.pilotAttempt=5')
)){$result=Replace-Required $text ([string]$route[0]) ([string]$route[1]);$text=$result.text;$routes.Add([pscustomobject]@{from=$result.from;to=$result.to;count=$result.count})}

$derivationAnchor='$derivations=New-Object Collections.Generic.List[object]'
$derivationReplacement=$derivationAnchor+"`n"+'$authorizedOverlays=New-Object Collections.Generic.List[object]'
$result=Replace-Required $text $derivationAnchor $derivationReplacement
$text=$result.text;$routes.Add([pscustomobject]@{from='derivation-list-anchor';to='derivation-plus-overlay-lists';count=$result.count})

$frozenAnchor='$frozen=@('
$frozenInsert=@'
$frozen=@(
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt4_Derivation_Receipt.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt4_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt4GeneratorV1.ps1',
    'Research\Verification\New-Gate13R36hAttempt4ArtifactsV1.ps1',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v8\StaticUnitV4\summary.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\execution-receipt.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\verification-checkpoint.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\failure-receipt.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\partial-output-manifest.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\LaneCopies\summary.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\BlockVerification\negative-fail-closed.wrapper-summary.json',
    'Research\Gate13R_36h_10pct_4Lane_v4_Lock_Failure_Diagnosis.v1.json',
    'Research\Verification\Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt',
'@
$result=Replace-Required $text $frozenAnchor $frozenInsert
$text=$result.text;$routes.Add([pscustomobject]@{from='frozen-array-anchor';to='frozen-v4-failure-prefix';count=$result.count})

$upstreamAnchor=@'
$plan.upstreamHashes|Add-Member -NotePropertyName attempt3DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json'))
'@.Trim()
$upstreamReplacement=@'
$plan.upstreamHashes|Add-Member -NotePropertyName attempt3DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt4VerificationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\failure-receipt.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt4LockDiagnosis -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_v4_Lock_Failure_Diagnosis.v1.json'))
'@.Trim()
$result=Replace-Required $text $upstreamAnchor $upstreamReplacement
$text=$result.text;$routes.Add([pscustomobject]@{from='v4-upstream-anchor';to='v4-failure-and-lock-diagnosis-bindings';count=$result.count})

$provenanceAnchor="attempt3PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Partial_Manifest.v1.json';attempt5GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt5GeneratorV1.ps1'"
$provenanceReplacement="attempt3PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Partial_Manifest.v1.json';attempt4Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v4.json';attempt4Plan=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v4.json';attempt4Provenance=Bound 'Research\Gate13R_36h_10pct_4Lane_Provenance.v4.json';attempt4DerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt4_Derivation_Receipt.v1.json';attempt4VerificationReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\execution-receipt.json';attempt4VerificationCheckpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\verification-checkpoint.json';attempt4VerificationFailure=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\failure-receipt.json';attempt4VerificationManifest=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\partial-output-manifest.json';attempt4LockDiagnosis=Bound 'Research\Gate13R_36h_10pct_4Lane_v4_Lock_Failure_Diagnosis.v1.json';expectedNegativeLockTestDesign=Bound 'Research\Gate13R_36h_10pct_4Lane_ExpectedNegative_LockHygiene_Test_Design.v5.md';lockHygieneSpecification=Bound 'Research\Gate10R_Attempt3_Lock_Hygiene_Specification.v1.md';lockHygieneModule=Bound 'Research\Gate10RLockHygieneV3.psm1';lockHygieneUnitRunner=Bound 'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1';preImplementationLockHygieneUnitSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV5\summary.json';attempt5OverlayTemplate=Bound 'Research\Verification\Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt';attempt5GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt5GeneratorV1.ps1'"
$result=Replace-Required $text $provenanceAnchor $provenanceReplacement
$text=$result.text;$routes.Add([pscustomobject]@{from='v5-provenance-anchor';to='v4-failure-lock-policy-and-v5-generator-bindings';count=$result.count})

$overlayAnchor=@'
}

$amendmentPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v5.json'
'@
$overlayTemplatePath=Join-Path $ProjectPath 'Research\Verification\Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt'
$overlayReplacement=[IO.File]::ReadAllText($overlayTemplatePath).TrimEnd("`r","`n")
$result=Replace-Required $text $overlayAnchor $overlayReplacement
$text=$result.text;$routes.Add([pscustomobject]@{from='post-derivation-anchor';to='authorized-v5-lock-hygiene-overlays';count=$result.count})

$receiptAnchor='derivations=$derivations.ToArray();planV2Sha256='
$receiptReplacement='derivations=$derivations.ToArray();authorizedOverlays=$authorizedOverlays.ToArray();planV2Sha256='
$result=Replace-Required $text $receiptAnchor $receiptReplacement
$text=$result.text;$routes.Add([pscustomobject]@{from='receipt-derivations-anchor';to='receipt-derivations-plus-overlays';count=$result.count})

$preservedAnchor='attempt2EvidencePreserved=$true;pilotRootCreated=$false'
$preservedReplacement='attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;pilotRootCreated=$false'
$result=Replace-Required $text $preservedAnchor $preservedReplacement
$text=$result.text;$routes.Add([pscustomobject]@{from='prior-evidence-anchor';to='attempt2-and-attempt4-preservation';count=$result.count})

$tokens=$null;$parseErrors=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$parseErrors)
if(@($parseErrors).Count-ne0){throw "Attempt5 generator parse failure: $(@($parseErrors|ForEach-Object Message)-join'; ')"}
[IO.File]::WriteAllText($destination,$text,$utf8)
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt5-generator-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/New-Gate13R36hAttempt4ArtifactsV1.ps1';sourceSha256=Hash $source;overlayTemplateRelativePath='Research/Verification/Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt';overlayTemplateSha256=Hash $overlayTemplatePath;destinationRelativePath='Research/Verification/New-Gate13R36hAttempt5ArtifactsV1.ps1';destinationSha256=Hash $destination;routes=$routes.ToArray();windowsPowerShell51ParsePassed=$true;formalCampaign=$false;pilotStarted=$false;passed=$true}
$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,$utf8)
$receipt|ConvertTo-Json -Depth 8
