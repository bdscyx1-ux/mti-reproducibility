[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$utf8=New-Object Text.UTF8Encoding($false,$true)
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function AtomicJson([string]$Path,[object]$Value){if(Test-Path -LiteralPath $Path){throw "Create-new evidence target exists: $Path"};$json=($Value|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";$tmp=$Path+'.tmp.'+[Guid]::NewGuid().ToString('N');[IO.File]::WriteAllText($tmp,$json,$utf8);[IO.File]::Move($tmp,$Path)}
$relativeFiles=@(
 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v6.json',
 'Research\Verification\New-Gate13R36hAttempt6GeneratorV1.ps1',
 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Generator_Derivation_Receipt.v1.json',
 'Research\Verification\New-Gate13R36hAttempt6ArtifactsV1.ps1',
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
 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV6.ps1'
)
$files=New-Object Collections.Generic.List[object];foreach($relative in $relativeFiles){$absolute=Join-Path $ProjectPath $relative;if(-not(Test-Path -LiteralPath $absolute -PathType Leaf)){throw "Expected attempt-6 evidence absent: $relative"};$item=Get-Item -LiteralPath $absolute;$files.Add([pscustomobject][ordered]@{relativePath=$relative.Replace('\','/');bytes=[int64]$item.Length;lastWriteTimeUtc=$item.LastWriteTimeUtc.ToString('o');sha256=Hash $absolute})}
$verification=Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v6';$pilot=Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v6';$clone='H:\DDM_Final_Project_Gate13R36H\v6';$formal=Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1'
$manifestPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json';$failurePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Failure.v1.json';$checkpointPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Checkpoint.v1.json'
$manifest=[ordered]@{schemaVersion=1;manifestKind='gate13r-36h-attempt6-derivation-partial-manifest-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-PRE-ROOT';files=$files.ToArray();upstreamAttempt5FailureSha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json');verificationRootCreated=Test-Path -LiteralPath $verification;pilotRootCreated=Test-Path -LiteralPath $pilot;cloneRootCreated=Test-Path -LiteralPath $clone;formalRootCreated=Test-Path -LiteralPath $formal;unityProcessCount=@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count;pilotStarted=$false;formalCampaign=$false;passed=$false};AtomicJson $manifestPath $manifest
$failure=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-attempt6-derivation-failure-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-PRE-ROOT';phase='static-smoke-overlay-source-match';errorType='PrematureGeneratorScopeInterpolation';errorMessage='The staticSmokeFrom search text expanded $ProjectPath in the attempt-6 generator scope and therefore could not match the frozen derived script text, which correctly contains the literal $ProjectPath variable.';allowedRepair='Create a new versioned attempt that keeps both $ProjectPath and $preImplementationRoot literal in generated-script search and replacement strings.';partialManifestRelativePath='Research/Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json';partialManifestSha256=Hash $manifestPath;verificationRootCreated=$manifest.verificationRootCreated;pilotRootCreated=$manifest.pilotRootCreated;cloneRootCreated=$manifest.cloneRootCreated;formalRootCreated=$manifest.formalRootCreated;unityProcessCount=$manifest.unityProcessCount;automaticRetry=$false;automaticResume=$false;pilotStarted=$false;formalCampaign=$false;passed=$false};AtomicJson $failurePath $failure
$checkpoint=[ordered]@{schemaVersion=1;checkpointKind='gate13r-36h-attempt6-derivation-checkpoint-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='failed-no-resume';attempt=6;lastCompletedPhase='block-wrapper-authorized-overlay';failedPhase='static-smoke-overlay-source-match';failureReceiptRelativePath='Research/Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Failure.v1.json';failureReceiptSha256=Hash $failurePath;partialManifestRelativePath='Research/Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json';partialManifestSha256=Hash $manifestPath;nextAllowedAction='Create a new versioned attempt; do not modify or resume attempt 6.';pilotStarted=$false;formalCampaign=$false;passed=$false};AtomicJson $checkpointPath $checkpoint
[pscustomobject]@{manifestSha256=Hash $manifestPath;failureSha256=Hash $failurePath;checkpointSha256=Hash $checkpointPath}|ConvertTo-Json
