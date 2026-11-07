[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$utf8=New-Object Text.UTF8Encoding($false,$true);$records=New-Object Collections.Generic.List[object]
function New-RemainingWrapper([string]$SourceRelative,[string]$ExpectedSha,[string]$OutputRelative,[object[]]$Routes){$source=Join-Path $ProjectPath $SourceRelative.Replace('/','\');$output=Join-Path $ProjectPath $OutputRelative.Replace('/','\');if(Test-Path $output){throw "Create-new wrapper exists: $output"};$actual=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actual-ne$ExpectedSha){throw "Source hash mismatch: $SourceRelative"};$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8);$changes=New-Object Collections.Generic.List[object];foreach($route in $Routes){$count=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($count-ne[int]$route.count){throw "Route count $count, expected $($route.count), for $($route.old)"};$text=$text.Replace([string]$route.old,[string]$route.new);$changes.Add([pscustomobject]@{from=$route.old;to=$route.new;count=$count})};[IO.File]::WriteAllText($output,$text,$utf8);$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($output,[ref]$tokens,[ref]$errors)|Out-Null;if(@($errors).Count){throw "Parser errors: $($errors.Message-join'; ')"};$records.Add([pscustomobject]@{sourceRelativePath=$SourceRelative;sourceSha256=$actual;outputRelativePath=$OutputRelative;outputSha256=(Get-FileHash $output -Algorithm SHA256).Hash.ToLowerInvariant();routes=$changes.ToArray()})}

foreach($existing in @(
 [pscustomobject]@{p='Research/Verification/Run-Gate12RStaticUnitAuditV4.ps1';h='cb167ff68f430625dfc02af409fda01909ad9aff41f082ffbefc4f90b6b2a699'},
 [pscustomobject]@{p='Research/Verification/Run-Gate12RValidationOnlyPrePilotAuditV3.ps1';h='8f7fc37336095f42e1ac489ce685a49435b40649cf198858cd99fa9b6b9b734b'},
 [pscustomobject]@{p='Research/Verification/Run-Gate12RBlockAndRegressionGatesV5.ps1';h='909529e2e078e187101dce65e419b6bf778b914889bd0e02dff4fddd103fa417'}
)){$p=Join-Path $ProjectPath $existing.p.Replace('/','\');if(-not(Test-Path $p)-or(Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant()-ne$existing.h){throw "Attempt-1 generated wrapper changed: $($existing.p)"}}

New-RemainingWrapper 'Research/Run-Gate12RPilotV4.ps1' '2ed5d7dd6b620746c7548b8153c9892e0e69ac61098b46724d6aa714134a3839' 'Research/Run-Gate12RPilotV5.ps1' @(
 [pscustomobject]@{old='Run-Gate12RPilotV4';new='Run-Gate12RPilotV5';count=2},
 [pscustomobject]@{old='Run-Gate12RProcessReuseBlockV2.ps1';new='Run-Gate12RProcessReuseBlockV4.ps1';count=1},
 [pscustomobject]@{old='Gate12R_PilotDerived\v4';new='Gate12R_PilotDerived\v5';count=1},
 [pscustomobject]@{old='pilot v4';new='pilot v5';count=4},
 [pscustomobject]@{old='reset-contract-route-wrapper-v4';new='canonical-reference-route-wrapper-v5';count=1}
)

New-RemainingWrapper 'Research/Verification/Run-Gate12RPrePilotAttemptV5.ps1' '4b122800e1457e04ce46e3c8af8e888a3784e008a5c610878c3adc863cb5397a' 'Research/Verification/Run-Gate12RPrePilotAttemptV6.ps1' @(
 [pscustomobject]@{old='Run-Gate12RPrePilotAttemptV5';new='Run-Gate12RPrePilotAttemptV6';count=2},
 [pscustomobject]@{old='Run-Gate12RProcessReuseBlockV2.ps1';new='Run-Gate12RProcessReuseBlockV4.ps1';count=1},
 [pscustomobject]@{old='Run-Gate12RStaticUnitAuditV3.ps1';new='Run-Gate12RStaticUnitAuditV4.ps1';count=1},
 [pscustomobject]@{old='Run-Gate12RPilotV4.ps1';new='Run-Gate12RPilotV5.ps1';count=1},
 [pscustomobject]@{old='Run-Gate12RBlockAndRegressionGatesV4.ps1';new='Run-Gate12RBlockAndRegressionGatesV5.ps1';count=1},
 [pscustomobject]@{old='Run-Gate12RValidationOnlyPrePilotAuditV2.ps1';new='Run-Gate12RValidationOnlyPrePilotAuditV3.ps1';count=1},
 [pscustomobject]@{old='Gate12R_PrePilotDerived\v5';new='Gate12R_PrePilotDerived\v6';count=1},
 [pscustomobject]@{old='New-Gate12RPilotAttempt1PreservationManifest.ps1';new='Test-Gate12RFailedPilotPreservationV2.ps1';count=1},
 [pscustomobject]@{old='pilot-attempt1-preservation-reaudit.json';new='failed-pilot-attempts-preservation-reaudit.json';count=1},
 [pscustomobject]@{old='pilotAttempt1PreservationReauditSha256';new='failedPilotPreservationReauditSha256';count=1},
 [pscustomobject]@{old='pilotAttempt1RootModified';new='failedPilotRootsModified';count=1},
 [pscustomobject]@{old='pilotAttempt1ResumeAttempted';new='failedPilotResumeAttempted';count=1},
 [pscustomobject]@{old='v5 pre-pilot';new='v6 pre-pilot';count=3},
 [pscustomobject]@{old="receiptKind='gate12r-pre-pilot-reset-contract-route-wrapper-v5'";new="receiptKind='gate12r-pre-pilot-canonical-reference-route-wrapper-v6'";count=1},
 [pscustomobject]@{old="receiptKind='gate12r-pre-pilot-gates-execution-receipt-v5'";new="receiptKind='gate12r-pre-pilot-gates-execution-receipt-v6'";count=1},
 [pscustomobject]@{old="checkpointKind='gate12r-pre-pilot-verification-checkpoint-v5'";new="checkpointKind='gate12r-pre-pilot-verification-checkpoint-v6'";count=1},
 [pscustomobject]@{old="manifestKind='gate12r-pre-pilot-partial-output-manifest-v5'";new="manifestKind='gate12r-pre-pilot-partial-output-manifest-v6'";count=1},
 [pscustomobject]@{old="receiptKind='gate12r-pre-pilot-gates-failure-receipt-v5'";new="receiptKind='gate12r-pre-pilot-gates-failure-receipt-v6'";count=1}
)

$all=@(
 [pscustomobject]@{relativePath='Research/Verification/Run-Gate12RStaticUnitAuditV4.ps1';sha256='cb167ff68f430625dfc02af409fda01909ad9aff41f082ffbefc4f90b6b2a699'},
 [pscustomobject]@{relativePath='Research/Verification/Run-Gate12RValidationOnlyPrePilotAuditV3.ps1';sha256='8f7fc37336095f42e1ac489ce685a49435b40649cf198858cd99fa9b6b9b734b'},
 [pscustomobject]@{relativePath='Research/Verification/Run-Gate12RBlockAndRegressionGatesV5.ps1';sha256='909529e2e078e187101dce65e419b6bf778b914889bd0e02dff4fddd103fa417'}
)+@($records|ForEach-Object{[pscustomobject]@{relativePath=$_.outputRelativePath;sha256=$_.outputSha256}})
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-storage-reference-wrapper-generation-v2-complete';createdAtUtc=[DateTime]::UtcNow.ToString('o');attempt1Status='FAILED-DURING-GENERATION-AFTER-THREE-COMPLETE-WRAPPERS';attempt1CompletedWrapperCount=3;attempt2Generated=$records.ToArray();activeWrappers=$all;planV3Sha256='498f0bac34f5ba98c946efab5577f1feed5631a4766fdd8817c74f445b150c98';thresholdsChanged=$false;matrixChanged=$false;williamsChanged=$false;algorithmSemanticsChanged=$false;gate13rAuthorized=$false};$receiptPath=Join-Path $ProjectPath 'Research\Gate12R_StorageReference_Wrapper_Derivation.v2.json';if(Test-Path $receiptPath){throw "Create-new V2 wrapper receipt exists: $receiptPath"};$json=($receipt|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,$utf8);$receipt|ConvertTo-Json -Depth 30
