[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest;$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$utf8=New-Object Text.UTF8Encoding($false,$true)
$source=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt9ArtifactsV1.ps1';$destination=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt10ArtifactsV1.ps1';$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt10_Generator_Derivation_Receipt.v1.json'
foreach($path in @($destination,$receiptPath)){if(Test-Path $path){throw "Create-new target exists: $path"}}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function RR([string]$Text,[string]$From,[string]$To,[int]$Minimum=1){$count=[regex]::Matches($Text,[regex]::Escape($From)).Count;if($count-lt$Minimum){throw "Required attempt-10 route missing: $From"};[pscustomobject]@{text=$Text.Replace($From,$To);count=$count;from=$From;to=$To}}
function AR([string]$From,[string]$To,[int]$Minimum=1){$script:r=RR $script:text $From $To $Minimum;$script:text=$script:r.text;$script:routes.Add([pscustomobject]@{from=$script:r.from;to=$script:r.to;count=$script:r.count})}
$text=[IO.File]::ReadAllText($source);$routes=New-Object Collections.Generic.List[object]
AR 'Attempt9' 'Attempt10';AR 'attempt9' 'attempt10';AR 'V9' 'V10';AR 'v9' 'v10';AR '$plan.pilotAttempt=9' '$plan.pilotAttempt=10'
AR 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV4' 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v8\StaticUnitV4'
AR 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\LockHygieneUnitV5' 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV5'

$frozenAnchor="    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Checkpoint.v1.json',"
$frozenInsert=@'
    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Checkpoint.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v9.json',
    'Research\Verification\New-Gate13R36hAttempt9GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt9_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt9ArtifactsV1.ps1',
    'Research\Verification\Write-Gate13R36hAttempt9DerivationFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Checkpoint.v1.json',
'@.TrimEnd();AR $frozenAnchor $frozenInsert
$upstreamAnchor='$plan.upstreamHashes|Add-Member -NotePropertyName attempt8DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Partial_Manifest.v1.json''))';$upstreamTo=$upstreamAnchor+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt9DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Failure.v1.json''))'+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt9DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Partial_Manifest.v1.json''))';AR $upstreamAnchor $upstreamTo
$provAnchor="attempt8Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign=";$provTo="attempt8Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Checkpoint.v1.json';attempt9Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v9.json';attempt9GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt9GeneratorV1.ps1';attempt9GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Generator_Derivation_Receipt.v1.json';attempt9DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt9ArtifactsV1.ps1';attempt9PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Partial_Manifest.v1.json';attempt9FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Failure.v1.json';attempt9Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign=";AR $provAnchor $provTo
AR 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;attempt8EvidencePreserved=$true;pilotRootCreated=$false' 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;attempt8EvidencePreserved=$true;attempt9EvidencePreserved=$true;pilotRootCreated=$false'
AR 'Frozen v1-v8 evidence changed during v10 derivation' 'Frozen v1-v9 evidence changed during v10 derivation'
$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e);if(@($e).Count){throw "Attempt-10 generator parse failure: $(@($e|% Message)-join'; ')"};[IO.File]::WriteAllText($destination,$text,$utf8)
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt10-generator-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/New-Gate13R36hAttempt9ArtifactsV1.ps1';sourceSha256=Hash $source;destinationRelativePath='Research/Verification/New-Gate13R36hAttempt10ArtifactsV1.ps1';destinationSha256=Hash $destination;amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v10.json';amendmentSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v10.json');attempt9FailureReceiptSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Failure.v1.json');routes=$routes.ToArray();windowsPowerShell51ParsePassed=$true;verificationRootCreated=$false;pilotRootCreated=$false;formalCampaign=$false;pilotStarted=$false;passed=$true}
$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,$utf8);$receipt|ConvertTo-Json -Depth 7
