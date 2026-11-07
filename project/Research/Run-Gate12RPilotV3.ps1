[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [Parameter(Mandatory=$true)][string]$PrePilotAuditPath,
    [Parameter(Mandatory=$true)][string]$TelemetryResultPath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R pilot v3 wrapper requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RPilotV3|$ProjectPath");exit 0}
$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$PrePilotAuditPath=[IO.Path]::GetFullPath($PrePilotAuditPath);$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$source=Join-Path $ProjectPath 'Research\Run-Gate12RPilot.ps1';$expectedSourceSha256='7788e459b2fcb7b63f33a3cf16e8fcc8f81723381c73ed3b3e3c65df4e9305d8';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen pilot v1 source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8);$old='Research\Run-Gate12RColdReference.ps1';$new='Research\Run-Gate12RColdReferenceV3.ps1';$count=$text.Split([string[]]@($old),[StringSplitOptions]::None).Count-1;if($count-ne1){throw "Pilot v3 cold-route replacement count is $count, expected 1."};$derived=$text.Replace($old,$new)
$derivedRoot=Join-Path $ProjectPath 'Research\Verification\Gate12R_PilotDerived\v3';if(Test-Path $derivedRoot){throw "Create-new pilot v3 derived root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derivedPath=Join-Path $derivedRoot 'Run-Gate12RPilotV3.derived.ps1';[IO.File]::WriteAllText($derivedPath,$derived,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-pilot-cold-route-wrapper-v3';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();replacementCount=$count;replacementFrom=$old;replacementTo=$new;researchSemanticsChanged=$false;formalRootCreated=$false;gate13rAuthorized=$false};$json=($receipt|ConvertTo-Json -Depth 10).Replace("`r`n","`n").Replace("`r","`n");[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json+"`n",(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$stdout=Join-Path $derivedRoot 'child.stdout.log';$stderr=Join-Path $derivedRoot 'child.stderr.log';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -PilotPlanPath $PilotPlanPath -ProvenancePath $ProvenancePath -PrePilotAuditPath $PrePilotAuditPath -TelemetryResultPath $TelemetryResultPath -UnityPath $UnityPath 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R pilot v3 derived child failed: exit=$exit stderr=$stderr";exit $exit};Write-Host 'Gate12R pilot v3 route child passed.' -ForegroundColor Green;exit 0

