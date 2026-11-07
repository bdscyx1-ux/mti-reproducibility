[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest;$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$utf8=New-Object Text.UTF8Encoding($false,$true)
$source=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt8ArtifactsV1.ps1';$destination=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt9ArtifactsV1.ps1';$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Generator_Derivation_Receipt.v1.json'
foreach($path in @($destination,$receiptPath)){if(Test-Path $path){throw "Create-new target exists: $path"}}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Replace-Required([string]$Text,[string]$From,[string]$To,[int]$Minimum=1){$count=[regex]::Matches($Text,[regex]::Escape($From)).Count;if($count-lt$Minimum){throw "Required attempt-9 route missing: $From"};[pscustomobject]@{text=$Text.Replace($From,$To);count=$count;from=$From;to=$To}}
function Apply-Route([string]$From,[string]$To,[int]$Minimum=1){$script:r=Replace-Required $script:text $From $To $Minimum;$script:text=$script:r.text;$script:routes.Add([pscustomobject]@{from=$script:r.from;to=$script:r.to;count=$script:r.count})}
$text=[IO.File]::ReadAllText($source);$routes=New-Object Collections.Generic.List[object]
Apply-Route 'Attempt8' 'Attempt9';Apply-Route 'attempt8' 'attempt9';Apply-Route 'V8' 'V9';Apply-Route 'v8' 'v9';Apply-Route '$plan.pilotAttempt=8' '$plan.pilotAttempt=9'
Apply-Route 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\StaticUnitV2' 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2'

$frozenAnchor="    'Research\Gate13R_36h_10pct_4Lane_Provenance.v7.json',"
$frozenInsert=@'
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v7.json',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v8.json',
    'Research\Verification\New-Gate13R36hAttempt8GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt8ArtifactsV1.ps1',
    'Research\Verification\Write-Gate13R36hAttempt8DerivationFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Checkpoint.v1.json',
'@.TrimEnd()
Apply-Route $frozenAnchor $frozenInsert

$upstreamAnchor='$plan.upstreamHashes|Add-Member -NotePropertyName attempt7StaticSummary -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV7\summary.json''))'
$upstreamTo=$upstreamAnchor+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt8DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Failure.v1.json''))'+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt8DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Partial_Manifest.v1.json''))'
Apply-Route $upstreamAnchor $upstreamTo

$provenanceAnchor="attempt7Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Checkpoint.v1.json';expectedNegativeLockTestDesign="
$provenanceTo="attempt7Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Checkpoint.v1.json';attempt8Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v8.json';attempt8GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt8GeneratorV1.ps1';attempt8GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Generator_Derivation_Receipt.v1.json';attempt8DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt8ArtifactsV1.ps1';attempt8PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Partial_Manifest.v1.json';attempt8FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Failure.v1.json';attempt8Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign="
Apply-Route $provenanceAnchor $provenanceTo
Apply-Route 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;pilotRootCreated=$false' 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;attempt8EvidencePreserved=$true;pilotRootCreated=$false'
Apply-Route 'Frozen v1-v7 evidence changed during v9 derivation' 'Frozen v1-v8 evidence changed during v9 derivation'

$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e);if(@($e).Count){throw "Attempt-9 generator parse failure: $(@($e|ForEach-Object Message)-join'; ')"};[IO.File]::WriteAllText($destination,$text,$utf8)
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt9-generator-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/New-Gate13R36hAttempt8ArtifactsV1.ps1';sourceSha256=Hash $source;destinationRelativePath='Research/Verification/New-Gate13R36hAttempt9ArtifactsV1.ps1';destinationSha256=Hash $destination;amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v9.json';amendmentSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v9.json');attempt8FailureReceiptSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Failure.v1.json');attempt8PartialManifestSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Partial_Manifest.v1.json');routes=$routes.ToArray();windowsPowerShell51ParsePassed=$true;verificationRootCreated=$false;pilotRootCreated=$false;formalCampaign=$false;pilotStarted=$false;passed=$true}
$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,$utf8);$receipt|ConvertTo-Json -Depth 8
