[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$utf8=New-Object Text.UTF8Encoding($false,$true)

function Get-LowerHash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-AtomicJson([string]$Path,[object]$Value){
    if(Test-Path -LiteralPath $Path){throw "Create-new evidence target exists: $Path"}
    $directory=[IO.Path]::GetDirectoryName($Path);if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory|Out-Null}
    $json=($Value|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n"
    $temporary=$Path+'.tmp.'+[Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,$json,$utf8)
    [IO.File]::Move($temporary,$Path)
}

$relativeFiles=@(
    'Research\Gate13R_36h_10pct_4Lane_ExpectedNegative_LockHygiene_Test_Design.v5.md',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v5.json',
    'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV5\summary.json',
    'Research\Verification\Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt',
    'Research\Verification\New-Gate13R36hAttempt5GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt5_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt5ArtifactsV1.ps1',
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
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV5.ps1'
)
$files=New-Object Collections.Generic.List[object]
foreach($relative in $relativeFiles){
    $absolute=Join-Path $ProjectPath $relative
    if(-not(Test-Path -LiteralPath $absolute -PathType Leaf)){throw "Expected attempt-5 evidence file is absent: $relative"}
    $item=Get-Item -LiteralPath $absolute
    $files.Add([pscustomobject][ordered]@{relativePath=$relative.Replace('\','/');bytes=[int64]$item.Length;lastWriteTimeUtc=$item.LastWriteTimeUtc.ToString('o');sha256=Get-LowerHash $absolute})
}

$formalRelative='Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1'
$verificationRelative='Research\Verification\Gate13R_36h_10pct_4Lane\v5'
$pilotRelative='Research\PilotRuns\Gate13R_36h_10pct_4Lane\v5'
$cloneAbsolute='H:\DDM_Final_Project_Gate13R36H\v5'
$manifestPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json'
$failurePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json'
$checkpointPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Checkpoint.v1.json'

$manifest=[ordered]@{schemaVersion=1;manifestKind='gate13r-36h-attempt5-derivation-partial-manifest-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-PRE-ROOT';files=$files.ToArray();verificationRootCreated=Test-Path -LiteralPath (Join-Path $ProjectPath $verificationRelative);pilotRootCreated=Test-Path -LiteralPath (Join-Path $ProjectPath $pilotRelative);cloneRootCreated=Test-Path -LiteralPath $cloneAbsolute;formalRootCreated=Test-Path -LiteralPath (Join-Path $ProjectPath $formalRelative);unityProcessCount=@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count;pilotStarted=$false;formalCampaign=$false;passed=$false}
Write-AtomicJson $manifestPath $manifest
$failure=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt5-derivation-failure-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-PRE-ROOT';phase='authorized-overlay-construction';errorType='StrictModeVariableIsUndefined';errorMessage='The variable ''$preImplementationRoot'' cannot be retrieved because it has not been set.';cause='The attempt-5 artifact generator interpolated a generated-script variable while the derivation generator itself was executing.';allowedRepair='A new versioned attempt may preserve the literal generated-script variable by escaping it or by using a non-interpolating string. Attempt 5 remains immutable.';partialManifestRelativePath='Research/Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json';partialManifestSha256=Get-LowerHash $manifestPath;verificationRootCreated=$manifest.verificationRootCreated;pilotRootCreated=$manifest.pilotRootCreated;cloneRootCreated=$manifest.cloneRootCreated;formalRootCreated=$manifest.formalRootCreated;unityProcessCount=$manifest.unityProcessCount;automaticRetry=$false;automaticResume=$false;pilotStarted=$false;formalCampaign=$false;passed=$false}
Write-AtomicJson $failurePath $failure
$checkpoint=[ordered]@{schemaVersion=1;checkpointKind='gate13r-36h-attempt5-derivation-checkpoint-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='failed-no-resume';attempt=5;lastCompletedPhase='mechanical-derivation-of-v5-scripts';failedPhase='authorized-overlay-construction';failureReceiptRelativePath='Research/Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json';failureReceiptSha256=Get-LowerHash $failurePath;partialManifestRelativePath='Research/Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json';partialManifestSha256=Get-LowerHash $manifestPath;nextAllowedAction='Create a new versioned attempt; do not modify, resume, or reinterpret attempt 5.';pilotStarted=$false;formalCampaign=$false;passed=$false}
Write-AtomicJson $checkpointPath $checkpoint
[pscustomobject]@{manifest=$manifestPath;manifestSha256=Get-LowerHash $manifestPath;failure=$failurePath;failureSha256=Get-LowerHash $failurePath;checkpoint=$checkpointPath;checkpointSha256=Get-LowerHash $checkpointPath}|ConvertTo-Json -Depth 5
