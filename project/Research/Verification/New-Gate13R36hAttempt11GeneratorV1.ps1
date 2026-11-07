[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest;$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$utf8=New-Object Text.UTF8Encoding($false,$true)
$source=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt10ArtifactsV1.ps1';$destination=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt11ArtifactsV1.ps1';$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt11_Generator_Derivation_Receipt.v1.json'
foreach($path in @($destination,$receiptPath)){if(Test-Path $path){throw "Create-new target exists: $path"}}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function ReplaceRequired([string]$Text,[string]$From,[string]$To,[int]$Minimum=1){$count=[regex]::Matches($Text,[regex]::Escape($From)).Count;if($count-lt$Minimum){throw "Required attempt-11 route missing: $From"};[pscustomobject]@{text=$Text.Replace($From,$To);count=$count;from=$From;to=$To}}
function ApplyRoute([string]$From,[string]$To,[int]$Minimum=1){$script:r=ReplaceRequired $script:text $From $To $Minimum;$script:text=$script:r.text;$script:routes.Add([pscustomobject]@{from=$script:r.from;to=$script:r.to;count=$script:r.count})}
$text=[IO.File]::ReadAllText($source);$routes=New-Object Collections.Generic.List[object]
ApplyRoute 'Attempt10' 'Attempt11';ApplyRoute 'attempt10' 'attempt11';ApplyRoute 'V10' 'V11';ApplyRoute 'v10' 'v11';ApplyRoute '$plan.pilotAttempt=10' '$plan.pilotAttempt=11'
ApplyRoute 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v11\StaticUnitV7' 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV7'

$overlapOld=@'
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v2' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v11'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v1' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v11'),
'@.Trim()
$overlapNew=@'
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v1' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v11'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v2' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v11'),
'@.Trim();ApplyRoute $overlapOld $overlapNew

$mapAnchor=@'
foreach($pair in $map){
    $extra=@()
    if([string]$pair[0]-eq'Research\Verification\Run-Gate13R36hStaticUnitV2.ps1'){$extra=@($(Route 'New-Gate13R36hPilotScheduleV1.ps1' 'New-Gate13R36hPilotScheduleV11.ps1'))}
    New-DerivedFile -SourceRelative ([string]$pair[0]) -DestinationRelative ([string]$pair[1]) -ExtraRoutes $extra
}
'@.Trim()
$mapTo=$mapAnchor+"`n`n"+@'
$derivedPreparationText=[IO.File]::ReadAllText((Join-Path $ProjectPath 'Research\Gate13R36hConcurrencyPreparationV11.psm1'))
if(-not$derivedPreparationText.Contains("`$script:G13PlanId = 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v11'")){throw 'Derived preparation plan identity is not exactly v11.'}
if($derivedPreparationText.Contains('pilot-plan-v110')){throw 'Overlapping plan identity route produced forbidden v110.'}
'@.Trim();ApplyRoute $mapAnchor $mapTo

$frozenAnchor="    'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Checkpoint.v1.json',"
$frozenInsert=@'
    'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Checkpoint.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v10.json',
    'Research\Verification\New-Gate13R36hAttempt10GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt10_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt10ArtifactsV1.ps1',
    'Research\Verification\Write-Gate13R36hAttempt10DerivationFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Checkpoint.v1.json',
    'Research\Gate13R36hConcurrencyPreparationV10.psm1',
    'Research\Run-Gate13R36hBlockV10.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV10.ps1',
    'Research\Initialize-Gate13R36hLaneCopiesV10.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV10.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV10.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV10.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV10.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV10.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV10.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV10.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v10.json',
'@.TrimEnd();ApplyRoute $frozenAnchor $frozenInsert
$upstreamAnchor='$plan.upstreamHashes|Add-Member -NotePropertyName attempt9DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Partial_Manifest.v1.json''))';$upstreamTo=$upstreamAnchor+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt10DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Failure.v1.json''))'+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt10DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Partial_Manifest.v1.json''))';ApplyRoute $upstreamAnchor $upstreamTo
$provAnchor="attempt9Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign=";$provTo="attempt9Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Checkpoint.v1.json';attempt10Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v10.json';attempt10GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt10GeneratorV1.ps1';attempt10GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt10_Generator_Derivation_Receipt.v1.json';attempt10DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt10ArtifactsV1.ps1';attempt10PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Partial_Manifest.v1.json';attempt10FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Failure.v1.json';attempt10Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign=";ApplyRoute $provAnchor $provTo
ApplyRoute 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;attempt8EvidencePreserved=$true;attempt9EvidencePreserved=$true;pilotRootCreated=$false' 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;attempt8EvidencePreserved=$true;attempt9EvidencePreserved=$true;attempt10EvidencePreserved=$true;pilotRootCreated=$false'
ApplyRoute 'Frozen v1-v9 evidence changed during v11 derivation' 'Frozen v1-v10 evidence changed during v11 derivation'
$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e);if(@($e).Count){throw "Attempt-11 generator parse failure: $(@($e|% Message)-join'; ')"};[IO.File]::WriteAllText($destination,$text,$utf8)
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt11-generator-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/New-Gate13R36hAttempt10ArtifactsV1.ps1';sourceSha256=Hash $source;destinationRelativePath='Research/Verification/New-Gate13R36hAttempt11ArtifactsV1.ps1';destinationSha256=Hash $destination;amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v11.json';amendmentSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v11.json');attempt10FailureReceiptSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Failure.v1.json');routes=$routes.ToArray();windowsPowerShell51ParsePassed=$true;verificationRootCreated=$false;pilotRootCreated=$false;formalCampaign=$false;pilotStarted=$false;passed=$true}
$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,$utf8);$receipt|ConvertTo-Json -Depth 7
