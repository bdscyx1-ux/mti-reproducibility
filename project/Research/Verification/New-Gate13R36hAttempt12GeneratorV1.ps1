[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest;$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$utf8=New-Object Text.UTF8Encoding($false,$true)
$source=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt11ArtifactsV1.ps1';$destination=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hAttempt12ArtifactsV1.ps1';$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt12_Generator_Derivation_Receipt.v1.json'
foreach($p in @($destination,$receiptPath)){if(Test-Path $p){throw "Create-new target exists: $p"}}
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function RR([string]$Text,[string]$From,[string]$To,[int]$Minimum=1){$count=[regex]::Matches($Text,[regex]::Escape($From)).Count;if($count-lt$Minimum){throw "Required attempt-12 route missing: $From"};[pscustomobject]@{text=$Text.Replace($From,$To);count=$count;from=$From;to=$To}}
function AR([string]$From,[string]$To,[int]$Minimum=1){$script:r=RR $script:text $From $To $Minimum;$script:text=$script:r.text;$script:routes.Add([pscustomobject]@{from=$script:r.from;to=$script:r.to;count=$script:r.count})}
$text=[IO.File]::ReadAllText($source);$routes=New-Object Collections.Generic.List[object]
AR 'Attempt11' 'Attempt12';AR 'attempt11' 'attempt12';AR 'V11' 'V12';AR 'v11' 'v12';AR '$plan.pilotAttempt=11' '$plan.pilotAttempt=12'
$staticListOld='$staticListTo=$staticListFrom+",''Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1''"';$staticListNew='$staticListTo=$staticListFrom+",''Research\Verification\Run-Gate13R36hLockHygieneUnitV12.ps1''"';AR $staticListOld $staticListNew
$staticSmokeOld=@'
$staticSmokeTo=$staticSmokeFrom+"`n      "+"@{name='lock-hygiene-unit';script='Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1';arguments=@('-ProjectPath',`$ProjectPath,'-OutputDirectory',(Join-Path `$preImplementationRoot 'BindingSmokeLockHygiene'),'-BindingSmokeOnly')},"
'@.Trim();$staticSmokeNew=$staticSmokeOld.Replace('Run-Gate13R36hLockHygieneUnitV5.ps1','Run-Gate13R36hLockHygieneUnitV12.ps1');AR $staticSmokeOld $staticSmokeNew
$verifyOld="    [void](Invoke-Child '01b-lock-hygiene-unit' (Join-Path `$ProjectPath 'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1') @('-ProjectPath',`$ProjectPath,'-OutputDirectory',(Join-Path `$verificationRoot 'LockHygieneUnit')) 600)";$verifyNew=$verifyOld.Replace('Run-Gate13R36hLockHygieneUnitV5.ps1','Run-Gate13R36hLockHygieneUnitV12.ps1');AR $verifyOld $verifyNew

$frozenAnchor=@'
    'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV5\summary.json',
'@.TrimEnd()
$frozenTo=$frozenAnchor+"`n"+@'
    'Research\Verification\New-Gate13R36hLockHygieneUnitV12.ps1',
    'Research\Gate13R_36h_10pct_4Lane_LockHygieneUnitV12_Derivation_Receipt.v1.json',
    'Research\Verification\Run-Gate13R36hLockHygieneUnitV12.ps1',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v12\LockHygieneUnitV12\summary.json',
'@.TrimEnd();AR $frozenAnchor $frozenTo

$priorAnchor="    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v10.json',"
$priorTo=@'
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v10.json',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v11.json',
    'Research\Verification\New-Gate13R36hAttempt11GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt11_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt11ArtifactsV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt11_Derivation_Receipt.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v11.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v11.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v11.json',
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v11.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v11\StaticUnitV11\summary.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v11\execution-receipt.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v11\verification-checkpoint.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v11\failure-receipt.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v11\partial-output-manifest.json',
    'Research\Gate13R_36h_10pct_4Lane_v11_LockUnit_RootBoundary_Diagnosis.v1.json',
'@.TrimEnd();AR $priorAnchor $priorTo

$upstreamAnchor='$plan.upstreamHashes|Add-Member -NotePropertyName attempt10DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Partial_Manifest.v1.json''))';$upstreamTo=$upstreamAnchor+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt11VerificationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Verification\Gate13R_36h_10pct_4Lane\v11\failure-receipt.json''))'+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName attempt11LockUnitDiagnosis -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Gate13R_36h_10pct_4Lane_v11_LockUnit_RootBoundary_Diagnosis.v1.json''))'+"`n"+'$plan.upstreamHashes|Add-Member -NotePropertyName lockHygieneUnitV12 -NotePropertyValue (Get-Hash (Join-Path $ProjectPath ''Research\Verification\Run-Gate13R36hLockHygieneUnitV12.ps1''))';AR $upstreamAnchor $upstreamTo

$provAnchor="attempt10Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign=";$provTo="attempt10Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt10_Derivation_Checkpoint.v1.json';attempt11Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v11.json';attempt11DerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt11_Derivation_Receipt.v1.json';attempt11StaticSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v11\StaticUnitV11\summary.json';attempt11VerificationReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v11\execution-receipt.json';attempt11VerificationCheckpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v11\verification-checkpoint.json';attempt11VerificationFailure=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v11\failure-receipt.json';attempt11VerificationManifest=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v11\partial-output-manifest.json';attempt11LockUnitDiagnosis=Bound 'Research\Gate13R_36h_10pct_4Lane_v11_LockUnit_RootBoundary_Diagnosis.v1.json';expectedNegativeLockTestDesign=";AR $provAnchor $provTo
$unitProvOld="lockHygieneUnitRunner=Bound 'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1';preImplementationLockHygieneUnitSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV5\summary.json';attempt5OverlayTemplate=";$unitProvNew="lockHygieneUnitSourceRunner=Bound 'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1';lockHygieneUnitDerivationGenerator=Bound 'Research\Verification\New-Gate13R36hLockHygieneUnitV12.ps1';lockHygieneUnitDerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_LockHygieneUnitV12_Derivation_Receipt.v1.json';lockHygieneUnitRunner=Bound 'Research\Verification\Run-Gate13R36hLockHygieneUnitV12.ps1';preImplementationLockHygieneUnitSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v12\LockHygieneUnitV12\summary.json';attempt5OverlayTemplate=";AR $unitProvOld $unitProvNew
AR 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;attempt8EvidencePreserved=$true;attempt9EvidencePreserved=$true;attempt10EvidencePreserved=$true;pilotRootCreated=$false' 'attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;attempt8EvidencePreserved=$true;attempt9EvidencePreserved=$true;attempt10EvidencePreserved=$true;attempt11EvidencePreserved=$true;pilotRootCreated=$false'
AR 'Frozen v1-v10 evidence changed during v12 derivation' 'Frozen v1-v11 evidence changed during v12 derivation'

$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e);if(@($e).Count){throw "Attempt-12 generator parse failure: $(@($e|% Message)-join'; ')"};[IO.File]::WriteAllText($destination,$text,$utf8)
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt12-generator-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/New-Gate13R36hAttempt11ArtifactsV1.ps1';sourceSha256=Hash $source;destinationRelativePath='Research/Verification/New-Gate13R36hAttempt12ArtifactsV1.ps1';destinationSha256=Hash $destination;amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v12.json';amendmentSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v12.json');attempt11FailureReceiptSha256=Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v11\failure-receipt.json');routes=$routes.ToArray();windowsPowerShell51ParsePassed=$true;verificationRootCreated=$false;pilotRootCreated=$false;formalCampaign=$false;pilotStarted=$false;passed=$true}
$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,$utf8);$receipt|ConvertTo-Json -Depth 7
