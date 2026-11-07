[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [Parameter(Mandatory=$true)][string]$TelemetryResultPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R validation-only v2 wrapper requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RValidationOnlyPrePilotAuditV2|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath)
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RValidationOnlyPrePilotAudit.ps1';$expectedSourceSha256='f2969e132124443c45c24c09b6a294c64e28f97815466b19d3d8603a99de1eea';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen validation-only source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8);$oldHash='68f32ee7acdeaa4c43a4f4932825e40e552bb5df473a96c66a9dcffef45d8ff3';$newHash='c76a0a1dc2ecc4efbc4f5419bee9890cf275c9b1fec7e4c64b22d8e2688849cf';$oldKind="summaryKind='gate12r-validation-only-pre-pilot-audit-v1'";$newKind="summaryKind='gate12r-validation-only-pre-pilot-audit-v2-plan-v2'"
foreach($route in @([pscustomobject]@{old=$oldHash;new=$newHash},[pscustomobject]@{old=$oldKind;new=$newKind})){$actual=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($actual-ne1){throw "Validation-only v2 replacement count is $actual, expected 1: $($route.old)"};$text=$text.Replace([string]$route.old,[string]$route.new)}
$derivedRoot=Join-Path $VerificationRoot '_DerivedHarness\ValidationOnlyV2';if(Test-Path $derivedRoot){throw "Create-new validation derived root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derivedPath=Join-Path $derivedRoot 'Run-Gate12RValidationOnlyPrePilotAuditV2.derived.ps1';[IO.File]::WriteAllText($derivedPath,$text,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-validation-only-plan-v2-wrapper-v2';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();planHashFrom=$oldHash;planHashTo=$newHash;replacementCount=2;researchSemanticsChanged=$false};$json=($receipt|ConvertTo-Json -Depth 10).Replace("`r`n","`n").Replace("`r","`n");[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json+"`n",(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$stdout=Join-Path $derivedRoot 'child.stdout.log';$stderr=Join-Path $derivedRoot 'child.stderr.log';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -VerificationRoot $VerificationRoot -PilotPlanPath $PilotPlanPath -ProvenancePath $ProvenancePath -TelemetryResultPath $TelemetryResultPath 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R validation-only v2 child failed: exit=$exit stderr=$stderr";exit $exit};Write-Host 'Gate12R validation-only v2 child passed.' -ForegroundColor Green;exit 0

