[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$source=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt5ArtifactsV1.ps1'
$destination=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt6ArtifactsV1.ps1'
$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Generator_Derivation_Receipt.v1.json'
foreach($path in @($destination,$receiptPath)){if(Test-Path -LiteralPath $path){throw "Create-new target exists: $path"}}
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Replace-Required([string]$Text,[string]$From,[string]$To,[int]$Minimum=1){$count=[regex]::Matches($Text,[regex]::Escape($From)).Count;if($count-lt$Minimum){throw "Required attempt-6 route missing: $From"};[pscustomobject]@{text=$Text.Replace($From,$To);count=$count;from=$From;to=$To}}
function Apply-Route([string]$From,[string]$To,[int]$Minimum=1){$script:result=Replace-Required $script:text $From $To $Minimum;$script:text=$script:result.text;$script:routes.Add([pscustomobject]@{from=$script:result.from;to=$script:result.to;count=$script:result.count})}

$text=[IO.File]::ReadAllText($source)
$routes=New-Object Collections.Generic.List[object]
Apply-Route 'Attempt5' 'Attempt6'
Apply-Route 'attempt5' 'attempt6'
Apply-Route 'V5' 'V6'
Apply-Route 'v5' 'v6'
Apply-Route '$plan.pilotAttempt=5' '$plan.pilotAttempt=6'

Apply-Route 'Research\Verification\Run-Gate13R36hLockHygieneUnitV6.ps1' 'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1'
Apply-Route 'Research\Gate13R_36h_10pct_4Lane_ExpectedNegative_LockHygiene_Test_Design.v6.md' 'Research\Gate13R_36h_10pct_4Lane_ExpectedNegative_LockHygiene_Test_Design.v5.md'
Apply-Route 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV6\summary.json' 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV5\summary.json'
Apply-Route 'Research\Verification\Gate13R36hAttempt6AuthorizedOverlayTemplateV1.ps1.txt' 'Research\Verification\Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt'
Apply-Route 'attempt6OverlayTemplate=Bound' 'attempt5OverlayTemplate=Bound'

$bugFrom=@'
$staticSmokeTo=$staticSmokeFrom+"`n      "+"@{name='lock-hygiene-unit';script='Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1';arguments=@('-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $preImplementationRoot 'BindingSmokeLockHygiene'),'-BindingSmokeOnly')},"
'@.Trim()
$bugTo=@'
$staticSmokeTo=$staticSmokeFrom+"`n      "+"@{name='lock-hygiene-unit';script='Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1';arguments=@('-ProjectPath',`$ProjectPath,'-OutputDirectory',(Join-Path `$preImplementationRoot 'BindingSmokeLockHygiene'),'-BindingSmokeOnly')},"
'@.Trim()
Apply-Route $bugFrom $bugTo

$frozenAnchor="    'Research\Verification\Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt',"
$frozenInsert=@'
    'Research\Verification\Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt',
    'Research\Gate13R_36h_10pct_4Lane_ExpectedNegative_LockHygiene_Test_Design.v5.md',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v5.json',
    'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV5\summary.json',
    'Research\Verification\New-Gate13R36hAttempt5GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt5_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt5ArtifactsV1.ps1',
    'Research\Verification\Write-Gate13R36hAttempt5DerivationFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Checkpoint.v1.json',
    'Research\Gate13R36hConcurrencyPreparationV5.psm1',
    'Research\Initialize-Gate13R36hLaneCopiesV5.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV5.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV5.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV5.ps1',
    'Research\Run-Gate13R36hBlockV5.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV5.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV5.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV5.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV5.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV5.ps1',
'@.TrimEnd()
Apply-Route $frozenAnchor $frozenInsert

$upstreamAnchor=@'
$plan.upstreamHashes|Add-Member -NotePropertyName attempt4LockDiagnosis -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_v4_Lock_Failure_Diagnosis.v1.json'))
'@.Trim()
$upstreamTo=$upstreamAnchor+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt5DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json''))'+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt5DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json''))'
Apply-Route $upstreamAnchor $upstreamTo

$provenanceAnchor="attempt4LockDiagnosis=Bound 'Research\Gate13R_36h_10pct_4Lane_v4_Lock_Failure_Diagnosis.v1.json';expectedNegativeLockTestDesign="
$provenanceTo="attempt4LockDiagnosis=Bound 'Research\Gate13R_36h_10pct_4Lane_v4_Lock_Failure_Diagnosis.v1.json';attempt5Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v5.json';attempt5GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt5GeneratorV1.ps1';attempt5GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Generator_Derivation_Receipt.v1.json';attempt5DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt5ArtifactsV1.ps1';attempt5PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json';attempt5FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json';attempt5Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign="
Apply-Route $provenanceAnchor $provenanceTo

Apply-Route 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;pilotRootCreated=$false' 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;pilotRootCreated=$false'
Apply-Route 'Frozen v1/v2 evidence changed during v6 derivation' 'Frozen v1-v5 evidence changed during v6 derivation'

$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if(@($errors).Count-ne0){throw "Attempt-6 generator parse failure: $(@($errors|ForEach-Object Message)-join'; ')"}
[IO.File]::WriteAllText($destination,$text,$utf8)
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt6-generator-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/New-Gate13R36hAttempt5ArtifactsV1.ps1';sourceSha256=Hash $source;destinationRelativePath='Research/Verification/New-Gate13R36hAttempt6ArtifactsV1.ps1';destinationSha256=Hash $destination;amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v6.json';amendmentSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v6.json');attempt5FailureReceiptSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json');attempt5PartialManifestSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json');routes=$routes.ToArray();windowsPowerShell51ParsePassed=$true;verificationRootCreated=$false;pilotRootCreated=$false;formalCampaign=$false;pilotStarted=$false;passed=$true}
$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,$utf8)
$receipt|ConvertTo-Json -Depth 8
