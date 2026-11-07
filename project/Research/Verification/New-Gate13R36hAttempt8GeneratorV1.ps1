[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$utf8=New-Object Text.UTF8Encoding($false,$true)
$source=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt7ArtifactsV1.ps1';$destination=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt8ArtifactsV1.ps1';$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Generator_Derivation_Receipt.v1.json'
foreach($path in @($destination,$receiptPath)){if(Test-Path $path){throw "Create-new target exists: $path"}}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Replace-Required([string]$Text,[string]$From,[string]$To,[int]$Minimum=1){$count=[regex]::Matches($Text,[regex]::Escape($From)).Count;if($count-lt$Minimum){throw "Required attempt-8 route missing: $From"};[pscustomobject]@{text=$Text.Replace($From,$To);count=$count;from=$From;to=$To}}
function Apply-Route([string]$From,[string]$To,[int]$Minimum=1){$script:r=Replace-Required $script:text $From $To $Minimum;$script:text=$script:r.text;$script:routes.Add([pscustomobject]@{from=$script:r.from;to=$script:r.to;count=$script:r.count})}
$text=[IO.File]::ReadAllText($source);$routes=New-Object Collections.Generic.List[object]
Apply-Route 'Attempt7' 'Attempt8';Apply-Route 'attempt7' 'attempt8';Apply-Route 'V7' 'V8';Apply-Route 'v7' 'v8';Apply-Route '$plan.pilotAttempt=7' '$plan.pilotAttempt=8'

$listOld=@'
$staticListFrom="'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV8.ps1'"
$staticListTo="'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV8.ps1','Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1'"
'@.Trim()
$listNew=@'
$staticListFrom="'Research\Verification\Run-Gate13R36hVerificationV8.ps1','Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV8.ps1'"
$staticListTo=$staticListFrom+",'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1'"
'@.Trim()
Apply-Route $listOld $listNew

$frozenAnchor="    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV6.ps1',"
$frozenInsert=@'
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV6.ps1',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v7.json',
    'Research\Verification\New-Gate13R36hAttempt7GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt7ArtifactsV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_Derivation_Receipt.v1.json',
    'Research\Verification\Write-Gate13R36hAttempt7StaticFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Checkpoint.v1.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV7\summary.json',
    'Research\Gate13R36hConcurrencyPreparationV7.psm1',
    'Research\Initialize-Gate13R36hLaneCopiesV7.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV7.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV7.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV7.ps1',
    'Research\Run-Gate13R36hBlockV7.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV7.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV7.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV7.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV7.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV7.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v7.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v7.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v7.json',
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v7.json',
'@.TrimEnd()
Apply-Route $frozenAnchor $frozenInsert

$upstreamAnchor='$plan.upstreamHashes|Add-Member -NotePropertyName attempt6DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json''))'
$upstreamTo=$upstreamAnchor+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt7StaticFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Failure.v1.json''))'+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt7StaticSummary -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV7\summary.json''))'
Apply-Route $upstreamAnchor $upstreamTo

$provenanceAnchor="attempt6Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign="
$provenanceTo="attempt6Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Checkpoint.v1.json';attempt7Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v7.json';attempt7GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt7GeneratorV1.ps1';attempt7GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_Generator_Derivation_Receipt.v1.json';attempt7DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt7ArtifactsV1.ps1';attempt7DerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_Derivation_Receipt.v1.json';attempt7StaticSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV7\summary.json';attempt7PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Partial_Manifest.v1.json';attempt7FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Failure.v1.json';attempt7Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Checkpoint.v1.json';expectedNegativeLockTestDesign="
Apply-Route $provenanceAnchor $provenanceTo
Apply-Route 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;pilotRootCreated=$false' 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;pilotRootCreated=$false'
Apply-Route 'Frozen v1-v6 evidence changed during v8 derivation' 'Frozen v1-v7 evidence changed during v8 derivation'

$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e);if(@($e).Count){throw "Attempt-8 generator parse failure: $(@($e|ForEach-Object Message)-join'; ')"};[IO.File]::WriteAllText($destination,$text,$utf8)
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt8-generator-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/New-Gate13R36hAttempt7ArtifactsV1.ps1';sourceSha256=Hash $source;destinationRelativePath='Research/Verification/New-Gate13R36hAttempt8ArtifactsV1.ps1';destinationSha256=Hash $destination;amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v8.json';amendmentSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v8.json');attempt7FailureReceiptSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Failure.v1.json');attempt7StaticSummarySha256=Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV7\summary.json');routes=$routes.ToArray();windowsPowerShell51ParsePassed=$true;verificationRootCreated=$false;pilotRootCreated=$false;formalCampaign=$false;pilotStarted=$false;passed=$true}
$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,$utf8);$receipt|ConvertTo-Json -Depth 8
