[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R v2 pre-pilot wrapper requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RPrePilotAttemptV2|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RPrePilotAttempt.ps1';$expectedSourceSha256='ca7fb7566aae8382793adbc16cdc60dd3010f0157803f3bd275973cc4f4441d3';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen v1 pre-pilot source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8);$old='Run-Gate12RStaticUnitAudit.ps1';$new='Run-Gate12RStaticUnitAuditV2.ps1';$occurrences=$text.Split([string[]]@($old),[StringSplitOptions]::None).Count-1;if($occurrences-ne3){throw "Expected exactly three static-audit route occurrences, found $occurrences."};$derived=$text.Replace($old,$new)
$derivedRoot=Join-Path $ProjectPath 'Research\Verification\Gate12R_PrePilotDerived\v2';if(-not(Test-Path $derivedRoot)){New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null};$derivedPath=Join-Path $derivedRoot 'Run-Gate12RPrePilotAttemptV2.derived.ps1';if(Test-Path $derivedPath){throw "Create-new derived pre-pilot harness exists: $derivedPath"};[IO.File]::WriteAllText($derivedPath,$derived,(New-Object Text.UTF8Encoding($false,$true)))
$wrapperReceipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-pre-pilot-file-scope-route-wrapper-v2';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Verification/Run-Gate12RPrePilotAttempt.ps1';sourceSha256=$actualSourceSha256;derivedRelativePath='Research/Verification/Gate12R_PrePilotDerived/v2/Run-Gate12RPrePilotAttemptV2.derived.ps1';derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();replacementFrom=$old;replacementTo=$new;replacementCount=$occurrences;researchSemanticsChanged=$false;pilotRootCreatedBeforeChild=$false;formalRootCreatedBeforeChild=$false}
$json=($wrapperReceipt|ConvertTo-Json -Depth 10).Replace("`r`n","`n").Replace("`r","`n");if(-not$json.EndsWith("`n")){$json+="`n"};[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json,(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$stdout=Join-Path $derivedRoot 'child.stdout.log';$stderr=Join-Path $derivedRoot 'child.stderr.log';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -VerificationRoot $VerificationRoot -PilotPlanPath $PilotPlanPath -ProvenancePath $ProvenancePath -UnityPath $UnityPath 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R v2 pre-pilot wrapper child failed: exit=$exit stderr=$stderr";exit $exit}
Write-Host 'Gate12R v2 pre-pilot wrapper child passed.' -ForegroundColor Green
exit 0
