[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$utf8=New-Object Text.UTF8Encoding($false,$true)
$source=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt6ArtifactsV1.ps1';$destination=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt7ArtifactsV1.ps1';$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt7_Generator_Derivation_Receipt.v1.json'
foreach($path in @($destination,$receiptPath)){if(Test-Path -LiteralPath $path){throw "Create-new target exists: $path"}}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Replace-Required([string]$Text,[string]$From,[string]$To,[int]$Minimum=1){$count=[regex]::Matches($Text,[regex]::Escape($From)).Count;if($count-lt$Minimum){throw "Required attempt-7 route missing: $From"};[pscustomobject]@{text=$Text.Replace($From,$To);count=$count;from=$From;to=$To}}
function Apply-Route([string]$From,[string]$To,[int]$Minimum=1){$script:r=Replace-Required $script:text $From $To $Minimum;$script:text=$script:r.text;$script:routes.Add([pscustomobject]@{from=$script:r.from;to=$script:r.to;count=$script:r.count})}
$text=[IO.File]::ReadAllText($source);$routes=New-Object Collections.Generic.List[object]
Apply-Route 'Attempt6' 'Attempt7';Apply-Route 'attempt6' 'attempt7';Apply-Route 'V6' 'V7';Apply-Route 'v6' 'v7';Apply-Route '$plan.pilotAttempt=6' '$plan.pilotAttempt=7'

$smokeFromOld=@'
$staticSmokeFrom="@{name='analysis';script='Research\Analyze-Gate13R36hConcurrencyPilotV7.ps1';arguments=@('-ProjectPath',$ProjectPath,'-PilotRoot',(Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v7'),'-BindingSmokeOnly')},"
'@.Trim()
$smokeFromNew=@'
$staticSmokeFrom="@{name='analysis';script='Research\Analyze-Gate13R36hConcurrencyPilotV7.ps1';arguments=@('-ProjectPath',`$ProjectPath,'-PilotRoot',(Join-Path `$ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v7'),'-BindingSmokeOnly')},"
'@.Trim()
Apply-Route $smokeFromOld $smokeFromNew

$frozenAnchor="    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV5.ps1',"
$frozenInsert=@'
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV5.ps1',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v6.json',
    'Research\Verification\New-Gate13R36hAttempt6GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt6_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt6ArtifactsV1.ps1',
    'Research\Verification\Write-Gate13R36hAttempt6DerivationFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Checkpoint.v1.json',
    'Research\Gate13R36hConcurrencyPreparationV6.psm1',
    'Research\Initialize-Gate13R36hLaneCopiesV6.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV6.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV6.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV6.ps1',
    'Research\Run-Gate13R36hBlockV6.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV6.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV6.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV6.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV6.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV6.ps1',
'@.TrimEnd()
Apply-Route $frozenAnchor $frozenInsert

$upstreamAnchor='$plan.upstreamHashes|Add-Member -NotePropertyName attempt5DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json''))'
$upstreamTo=$upstreamAnchor+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt6DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Failure.v1.json''))'+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt6DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json''))'
Apply-Route $upstreamAnchor $upstreamTo

$provenanceAnchor="attempt5Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign="
$provenanceTo="attempt5Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Checkpoint.v1.json';attempt6Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v6.json';attempt6GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt6GeneratorV1.ps1';attempt6GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Generator_Derivation_Receipt.v1.json';attempt6DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt6ArtifactsV1.ps1';attempt6PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json';attempt6FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Failure.v1.json';attempt6Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign="
Apply-Route $provenanceAnchor $provenanceTo
Apply-Route 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;pilotRootCreated=$false' 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;pilotRootCreated=$false'
Apply-Route 'Frozen v1-v5 evidence changed during v7 derivation' 'Frozen v1-v6 evidence changed during v7 derivation'

$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors);if(@($errors).Count){throw "Attempt-7 generator parse failure: $(@($errors|ForEach-Object Message)-join'; ')"}
[IO.File]::WriteAllText($destination,$text,$utf8)
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt7-generator-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/New-Gate13R36hAttempt6ArtifactsV1.ps1';sourceSha256=Hash $source;destinationRelativePath='Research/Verification/New-Gate13R36hAttempt7ArtifactsV1.ps1';destinationSha256=Hash $destination;amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v7.json';amendmentSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v7.json');attempt6FailureReceiptSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Failure.v1.json');attempt6PartialManifestSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json');routes=$routes.ToArray();windowsPowerShell51ParsePassed=$true;verificationRootCreated=$false;pilotRootCreated=$false;formalCampaign=$false;pilotStarted=$false;passed=$true}
$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,$utf8);$receipt|ConvertTo-Json -Depth 8
