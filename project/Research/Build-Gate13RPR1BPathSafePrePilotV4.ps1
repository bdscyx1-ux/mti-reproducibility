[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Explicit absolute ProjectPath required.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$utf8=New-Object Text.UTF8Encoding($false,$true)

function Read-Text([string]$Relative){[IO.File]::ReadAllText((Join-Path $ProjectPath $Relative),[Text.Encoding]::UTF8)}
function Write-NewText([string]$Relative,[string]$Text){
    $path=Join-Path $ProjectPath $Relative
    if(Test-Path -LiteralPath $path){
        $existing=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
        if($existing-ceq$Text){return}
        throw "Generated file exists with different bytes: $path"
    }
    [IO.File]::WriteAllText($path,$Text,$utf8)
}
function Derive([string]$Source,[string]$Destination,[object[]]$Pairs){
    $text=Read-Text $Source
    foreach($pair in $Pairs){
        $count=([regex]::Matches($text,[regex]::Escape([string]$pair.old))).Count
        if($count-ne[int]$pair.count){throw "Mechanical transform count mismatch for ${Source}: '$($pair.old)' expected=$($pair.count) actual=$count"}
        $text=$text.Replace([string]$pair.old,[string]$pair.new)
    }
    Write-NewText $Destination $text
}

$moduleSource='Research/Gate13RPR1BOrderEffectPreparationV3.psm1'
$moduleText=Read-Text $moduleSource
$moduleText=$moduleText.Replace("`$script:PlanId='gate13r-pr1b-balanced-mirrored-order-effect-pathsafe-v3-pilot-v1'","`$script:PlanId='gate13r-pr1b-balanced-mirrored-order-effect-pathsafe-v4-pilot-v1'")
$old=@'
    $tmp=Join-Path $parent ('.g13tmp-'+[Guid]::NewGuid().ToString('N'));$owned=$false
    try{
        $json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")+"`n"
        $stream=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$owned=$true
        try{$writer=New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($false,$true)));try{$writer.Write($json);$writer.Flush()}finally{$writer.Dispose()}}finally{if($stream){$stream.Dispose()}}
        if(Test-Path -LiteralPath $full -PathType Container){throw "Atomic JSON target is a directory: $full"}
        if(Test-Path -LiteralPath $full -PathType Leaf){[IO.File]::Replace($tmp,$full,$null)}else{[IO.File]::Move($tmp,$full)}
        $owned=$false
    }finally{if($owned-and(Test-Path -LiteralPath $tmp -PathType Leaf)){[IO.File]::Delete($tmp)}}
'@
$new=@'
    $tmp=Join-Path $parent ('.g13tmp-'+[Guid]::NewGuid().ToString('N'))
    $backup=Join-Path $parent ('.g13bak-'+[Guid]::NewGuid().ToString('N'))
    if((Test-Path -LiteralPath $tmp)-or(Test-Path -LiteralPath $backup)){throw 'Atomic JSON helper leaf collision.'}
    $temporaryOwned=$false;$backupMayBeOwned=$true
    try{
        $json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")+"`n"
        $stream=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$temporaryOwned=$true
        try{$writer=New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($false,$true)));try{$writer.Write($json);$writer.Flush()}finally{$writer.Dispose()}}finally{if($stream){$stream.Dispose()}}
        $parentNow=Get-Item -LiteralPath $parent -Force
        if(($parentNow.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Atomic JSON parent became a reparse point: $parent"}
        if(Test-Path -LiteralPath $full -PathType Container){throw "Atomic JSON target is a directory: $full"}
        if(Test-Path -LiteralPath $full -PathType Leaf){
            [IO.File]::Replace($tmp,$full,$backup,$true);$temporaryOwned=$false
        }else{
            [IO.File]::Move($tmp,$full);$temporaryOwned=$false
        }
    }finally{
        if($temporaryOwned-and(Test-Path -LiteralPath $tmp -PathType Leaf)){[IO.File]::Delete($tmp)}
        if($backupMayBeOwned-and(Test-Path -LiteralPath $backup -PathType Leaf)){[IO.File]::Delete($backup)}
    }
'@
if(([regex]::Matches($moduleText,[regex]::Escape($old))).Count-ne1){throw 'V3 atomic-helper source block identity mismatch.'}
$moduleText=$moduleText.Replace($old,$new)
Write-NewText 'Research/Gate13RPR1BOrderEffectPreparationV4.psm1' $moduleText

$globalPairs=@(
    [pscustomobject]@{old='Gate13RPR1BOrderEffectPreparationV3.psm1';new='Gate13RPR1BOrderEffectPreparationV4.psm1'},
    [pscustomobject]@{old='Run-Gate13RPR1BMemoryAwareBlockV3';new='Run-Gate13RPR1BMemoryAwareBlockV4'},
    [pscustomobject]@{old='Run-Gate13RPR1BMemoryTelemetryProbeV3';new='Run-Gate13RPR1BMemoryTelemetryProbeV4'},
    [pscustomobject]@{old='Run-Gate13RPR1BOrderEffectPilotV3';new='Run-Gate13RPR1BOrderEffectPilotV4'},
    [pscustomobject]@{old='Analyze-Gate13RPR1BOrderEffectPilotV3';new='Analyze-Gate13RPR1BOrderEffectPilotV4'},
    [pscustomobject]@{old='Run-Gate13RPR1BStaticUnitV3';new='Run-Gate13RPR1BStaticUnitV4'},
    [pscustomobject]@{old='Run-Gate13RPR1BPathSafeAtomicSelfTestV3';new='Run-Gate13RPR1BPathSafeAtomicSelfTestV4'},
    [pscustomobject]@{old='Run-Gate13RPR1BMemoryPolicySelfTestV4';new='Run-Gate13RPR1BMemoryPolicySelfTestV5'},
    [pscustomobject]@{old='Run-Gate13RPR1BBlockVerificationV4';new='Run-Gate13RPR1BBlockVerificationV5'},
    [pscustomobject]@{old='Run-Gate13RPR1BValidationOnlyPrePilotAuditV3';new='Run-Gate13RPR1BValidationOnlyPrePilotAuditV4'},
    [pscustomobject]@{old='Run-Gate13RPR1BPrePilotV5';new='Run-Gate13RPR1BPrePilotV6'},
    [pscustomobject]@{old='gate13r-pr1b-balanced-mirrored-order-effect-pathsafe-v3-pilot-v1';new='gate13r-pr1b-balanced-mirrored-order-effect-pathsafe-v4-pilot-v1'}
)
function Derive-WithGlobal([string]$Source,[string]$Destination,[object[]]$Extra){
    $text=Read-Text $Source
    foreach($pair in @($globalPairs)+@($Extra)){$text=$text.Replace([string]$pair.old,[string]$pair.new)}
    if($text-eq(Read-Text $Source)){throw "No mechanical changes made: $Source"}
    Write-NewText $Destination $text
}
Derive-WithGlobal 'Research/Run-Gate13RPR1BMemoryAwareBlockV3.ps1' 'Research/Run-Gate13RPR1BMemoryAwareBlockV4.ps1' @()
Derive-WithGlobal 'Research/Run-Gate13RPR1BMemoryTelemetryProbeV3.ps1' 'Research/Run-Gate13RPR1BMemoryTelemetryProbeV4.ps1' @()
Derive-WithGlobal 'Research/Run-Gate13RPR1BOrderEffectPilotV3.ps1' 'Research/Run-Gate13RPR1BOrderEffectPilotV4.ps1' @([pscustomobject]@{old='PilotV3';new='PilotV4'})
Derive-WithGlobal 'Research/Analyze-Gate13RPR1BOrderEffectPilotV3.py' 'Research/Analyze-Gate13RPR1BOrderEffectPilotV4.py' @()
Derive-WithGlobal 'Research/Verification/Run-Gate13RPR1BStaticUnitV3.ps1' 'Research/Verification/Run-Gate13RPR1BStaticUnitV4.ps1' @()
Derive-WithGlobal 'Research/Verification/Run-Gate13RPR1BPathSafeAtomicSelfTestV3.ps1' 'Research/Verification/Run-Gate13RPR1BPathSafeAtomicSelfTestV4.ps1' @()
Derive-WithGlobal 'Research/Verification/Run-Gate13RPR1BMemoryPolicySelfTestV4.ps1' 'Research/Verification/Run-Gate13RPR1BMemoryPolicySelfTestV5.ps1' @()
Derive-WithGlobal 'Research/Verification/Run-Gate13RPR1BBlockVerificationV4.ps1' 'Research/Verification/Run-Gate13RPR1BBlockVerificationV5.ps1' @([pscustomobject]@{old='BlockVerificationV4';new='BlockVerificationV5'})
Derive-WithGlobal 'Research/Verification/Run-Gate13RPR1BValidationOnlyPrePilotAuditV3.ps1' 'Research/Verification/Run-Gate13RPR1BValidationOnlyPrePilotAuditV4.ps1' @()
Derive-WithGlobal 'Research/Verification/Run-Gate13RPR1BPrePilotV5.ps1' 'Research/Verification/Run-Gate13RPR1BPrePilotV6.ps1' @(
    [pscustomobject]@{old='pre-pilot v5';new='pre-pilot v6'},
    [pscustomobject]@{old="operationalRepair='windows-mono-pathsafe-atomic-persistence-v1'";new="operationalRepair='winps51-same-directory-backup-leaf-atomic-replace-v1'"}
)

$planPath=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v6.json'
if(Test-Path -LiteralPath $planPath){throw "Create-new plan already exists: $planPath"}
$plan=(Read-Text 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v5.json')|ConvertFrom-Json
$plan.planId='gate13r-pr1b-balanced-mirrored-order-effect-pathsafe-v4-pilot-v1'
$plan.specificationId='gate13r-pr1b-v4-winps51-atomic-replace-specification-v1'
$plan.testDesignId='gate13r-pr1b-v4-winps51-atomic-replace-test-design-v1'
$plan.amendmentId='gate13r-pr1b-v4-winps51-atomic-replace-backup-leaf-compatibility-v1'
$plan.attemptNumber=4
$plan.operationalVerificationRevision=6
$plan.paths.pilotRootRelativePath='Research/PilotRuns/Gate12R_ProcessReuse_5pct/v7-gate13r-pr1b-order-effect-pathsafe-v4'
$plan.paths.verificationRootRelativePath='Research/Verification/Gate12R_ProcessReuse_5pct/v13-gate13r-pr1b-order-effect-pathsafe-v4'
$plan.paths|Add-Member -NotePropertyName verificationAttempt4RootRelativePath -NotePropertyValue 'Research/Verification/Gate12R_ProcessReuse_5pct/v12-gate13r-pr1b-order-effect-pathsafe-v3'
$plan.paths|Add-Member -NotePropertyName verificationAttempt4TerminalPreservationRelativePath -NotePropertyValue 'Research/Gate13R_PR1B_v3_PrePilot_v12_Terminal_Preservation.v1.json'
$plan.pathSafeAtomicPersistence.helperId='gate13r-pr1b-v4-winps51-same-directory-short-temp-backup-atomic-json-v1'
$plan.pathSafeAtomicPersistence|Add-Member -NotePropertyName backupLeafPattern -NotePropertyValue '.g13bak-<32-lowercase-hex-guid>'
$plan.pathSafeAtomicPersistence|Add-Member -NotePropertyName backupLeafLengthCharacters -NotePropertyValue 40
$plan.pathSafeAtomicPersistence|Add-Member -NotePropertyName windowsPowerShell51NullBackupPathForbidden -NotePropertyValue $true
$planJson=($plan|ConvertTo-Json -Depth 60).Replace("`r`n","`n").Replace("`r","`n")+"`n"
[IO.File]::WriteAllText($planPath,$planJson,$utf8)

$parentProvenance='Research/Gate13R_PR1B_OrderEffect_Provenance.v5.json'
$parentObj=(Read-Text $parentProvenance)|ConvertFrom-Json
$developmentOld=@(
 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Amendment.v3.json',
 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Specification.v3.md',
 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Test_Design.v3.md',
 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v5.json',
 'Research/Gate13RPR1BOrderEffectPreparationV3.psm1',
 'Research/Analyze-Gate13RPR1BOrderEffectPilotV3.py',
 'Research/Run-Gate13RPR1BMemoryAwareBlockV3.ps1',
 'Research/Run-Gate13RPR1BMemoryTelemetryProbeV3.ps1',
 'Research/Run-Gate13RPR1BOrderEffectPilotV3.ps1',
 'Research/Verification/Run-Gate13RPR1BStaticUnitV3.ps1',
 'Research/Verification/Run-Gate13RPR1BPathSafeAtomicSelfTestV3.ps1',
 'Research/Verification/Run-Gate13RPR1BMemoryPolicySelfTestV4.ps1',
 'Research/Verification/Run-Gate13RPR1BBlockVerificationV4.ps1',
 'Research/Verification/Run-Gate13RPR1BValidationOnlyPrePilotAuditV3.ps1',
 'Research/Verification/Run-Gate13RPR1BPrePilotV5.ps1'
)
$newFiles=@(
 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Amendment.v4.json',
 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Specification.v4.md',
 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Test_Design.v4.md',
 'Research/Gate13R_PR1B_v3_PrePilot_v12_Terminal_Preservation.v1.json',
 'Research/Gate13R_PR1B_v3_PrePilot_v12_Failure_Diagnosis.v1.md',
 'Research/Gate13R_PR1B_v3_PrePilot_v12_Failure_Checkpoint.v1.json',
 'Research/Build-Gate13RPR1BPathSafePrePilotV4.ps1',
 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v6.json',
 'Research/Gate13RPR1BOrderEffectPreparationV4.psm1',
 'Research/Analyze-Gate13RPR1BOrderEffectPilotV4.py',
 'Research/Run-Gate13RPR1BMemoryAwareBlockV4.ps1',
 'Research/Run-Gate13RPR1BMemoryTelemetryProbeV4.ps1',
 'Research/Run-Gate13RPR1BOrderEffectPilotV4.ps1',
 'Research/Verification/Run-Gate13RPR1BStaticUnitV4.ps1',
 'Research/Verification/Run-Gate13RPR1BPathSafeAtomicSelfTestV4.ps1',
 'Research/Verification/Run-Gate13RPR1BMemoryPolicySelfTestV5.ps1',
 'Research/Verification/Run-Gate13RPR1BBlockVerificationV5.ps1',
 'Research/Verification/Run-Gate13RPR1BValidationOnlyPrePilotAuditV4.ps1',
 'Research/Verification/Run-Gate13RPR1BPrePilotV6.ps1'
)
$bound=New-Object Collections.Generic.List[object]
foreach($entry in @($parentObj.boundFiles)){
    if($developmentOld-notcontains[string]$entry.relativePath){$bound.Add([pscustomobject][ordered]@{relativePath=[string]$entry.relativePath;rawBytes=[long](Get-Item -LiteralPath (Join-Path $ProjectPath ([string]$entry.relativePath).Replace('/','\'))).Length;sha256=[string]$entry.sha256})}
}
foreach($relative in $newFiles){
    $path=Join-Path $ProjectPath $relative.Replace('/','\')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Provenance input missing: $relative"}
    $bound.Add([pscustomobject][ordered]@{relativePath=$relative;rawBytes=[long](Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()})
}
$parentPath=Join-Path $ProjectPath $parentProvenance.Replace('/','\')
$configItem=Get-Item -LiteralPath $planPath
$specPath=Join-Path $ProjectPath 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Specification.v4.md'
$testPath=Join-Path $ProjectPath 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Test_Design.v4.md'
$provenance=[ordered]@{
 schemaVersion=6
 provenanceId='gate13r-pr1b-v4-winps51-pathsafe-balanced-mirrored-pilot-provenance-v1'
 createdAtUtc=[DateTime]::UtcNow.ToString('o')
 createdAtAsiaShanghai=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow,'China Standard Time').ToString('o')+'+08:00'
 status='FROZEN-BEFORE-V13-VERIFICATION-AND-ONE-NON-FORMAL-PILOT'
 authorizationBasis='User-authorized Gate13R PR1B v3 path-safe scope with versioned pre-pilot repair; v12 failed before Unity/pilot creation. Gate13R formal and Gate14R remain unauthorized.'
 parentProvenance=[ordered]@{relativePath=$parentProvenance;rawBytes=[long](Get-Item $parentPath).Length;sha256=(Get-FileHash $parentPath -Algorithm SHA256).Hash.ToLowerInvariant()}
 executionDesignId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
 memoryGatePolicyId='gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1'
 operationalRepairId='gate13r-pr1b-v4-winps51-same-directory-backup-leaf-atomic-replace-v1'
 scientificContractChanged=$false
 config=[ordered]@{id='gate13rPr1bPilotPlanV6';relativePath='Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v6.json';rawBytes=[long]$configItem.Length;sha256=(Get-FileHash $planPath -Algorithm SHA256).Hash.ToLowerInvariant()}
 specification=[ordered]@{id='gate13rPr1bPathSafeSpecificationV4';relativePath='Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Specification.v4.md';rawBytes=[long](Get-Item $specPath).Length;sha256=(Get-FileHash $specPath -Algorithm SHA256).Hash.ToLowerInvariant()}
 testDesign=[ordered]@{id='gate13rPr1bPathSafeTestDesignV4';relativePath='Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Test_Design.v4.md';rawBytes=[long](Get-Item $testPath).Length;sha256=(Get-FileHash $testPath -Algorithm SHA256).Hash.ToLowerInvariant()}
 failedV12=[ordered]@{relativePath='Research/Verification/Gate12R_ProcessReuse_5pct/v12-gate13r-pr1b-order-effect-pathsafe-v3';fileCount=7;rawBytes=25700;treeIdentitySha256='4ae0c0ea30e65b0cf5e15bbdffeffd8155e7e5de341c262f4ad3d2e00c4f12fe';status='FAILED-NO-PILOT-UNITY-NOT-INVOKED'}
 frozenV6Root=$parentObj.frozenV6Root
 frozenVerificationRoots=$parentObj.frozenVerificationRoots
 boundFiles=@($bound.ToArray())
 nonFormal=$true
 excludedFromFormalAnalysis=$true
 formalCampaign=$false
 gate13rFormalAuthorized=$false
 gate14rAuthorized=$false
 pilotRetryAfterRootCreationAllowed=$false
}
$provenancePath=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Provenance.v6.json'
if(Test-Path -LiteralPath $provenancePath){throw "Create-new provenance already exists: $provenancePath"}
$provenanceJson=($provenance|ConvertTo-Json -Depth 80).Replace("`r`n","`n").Replace("`r","`n")+"`n"
[IO.File]::WriteAllText($provenancePath,$provenanceJson,$utf8)

[pscustomobject]@{passed=$true;generatedFileCount=21;plan=$planPath;provenance=$provenancePath;boundFileCount=$bound.Count}|ConvertTo-Json -Depth 5
