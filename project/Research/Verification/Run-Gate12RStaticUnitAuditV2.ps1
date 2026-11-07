[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R v2 static wrapper requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RStaticUnitAuditV2|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath)
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RStaticUnitAudit.ps1'
$expectedSourceSha256='dfc8c94e3e2103946aa165c65beb58aa5b0aa744ba948984ac66766de9e8e049'
$actualSourceSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen v1 static source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$oldBaseline='Gate12R_PreWrite_Preservation_Baseline.v1.json';$newBaseline='Gate12R_PreWrite_Preservation_Baseline.v2.json'
$oldKind="summaryKind='gate12r-static-unit-audit-v1'";$newKind="summaryKind='gate12r-static-unit-audit-v2-tree-identity-compatibility'"
if(($text.Split([string[]]@($oldBaseline),[StringSplitOptions]::None).Count-1)-ne1){throw 'Mechanical baseline replacement occurrence count is not one.'}
if(($text.Split([string[]]@($oldKind),[StringSplitOptions]::None).Count-1)-ne1){throw 'Mechanical summary-kind replacement occurrence count is not one.'}
$derived=$text.Replace($oldBaseline,$newBaseline).Replace($oldKind,$newKind)
$derivedRoot=Join-Path $VerificationRoot '_DerivedHarness';if(-not(Test-Path $derivedRoot)){New-Item -ItemType Directory -Path $derivedRoot|Out-Null}
$derivedPath=Join-Path $derivedRoot 'Run-Gate12RStaticUnitAuditV2.derived.ps1';if(Test-Path $derivedPath){throw "Create-new derived static harness exists: $derivedPath"}
[IO.File]::WriteAllText($derivedPath,$derived,(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$stdout=Join-Path $derivedRoot 'StaticUnitV2.child.stdout.log';$stderr=Join-Path $derivedRoot 'StaticUnitV2.child.stderr.log';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -VerificationRoot $VerificationRoot -ProvenancePath $ProvenancePath 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
$summaryPath=Join-Path $VerificationRoot 'StaticUnit\summary.json';$summary=if(Test-Path $summaryPath){Get-Content -Raw -LiteralPath $summaryPath|ConvertFrom-Json}else{$null};$passed=$exit-eq0-and$null-ne$summary-and$summary.passed-eq$true-and[string]$summary.summaryKind-eq'gate12r-static-unit-audit-v2-tree-identity-compatibility'
$wrapper=[ordered]@{schemaVersion=1;wrapperKind='gate12r-static-unit-file-scope-compatibility-wrapper-v2';savedAtUtc=[DateTime]::UtcNow.ToString('o');executionMethod='Windows PowerShell 5.1 -File';sourceRelativePath='Research/Verification/Run-Gate12RStaticUnitAudit.ps1';sourceSha256=$actualSourceSha256;derivedRelativePath=$derivedPath.Substring($ProjectPath.TrimEnd('\').Length+1).Replace('\','/');derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();allowedMechanicalReplacements=@([ordered]@{from=$oldBaseline;to=$newBaseline},[ordered]@{from=$oldKind;to=$newKind});researchSemanticsChanged=$false;exitCode=$exit;summarySha256=if($null-ne$summary){(Get-FileHash $summaryPath -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null};passed=$passed}
$json=($wrapper|ConvertTo-Json -Depth 12).Replace("`r`n","`n").Replace("`r","`n");if(-not$json.EndsWith("`n")){$json+="`n"};[IO.File]::WriteAllText((Join-Path $derivedRoot 'StaticUnitV2.wrapper.json'),$json,(New-Object Text.UTF8Encoding($false,$true)))
if(-not$passed){Write-Error "Gate12R v2 static/unit wrapper failed: exit=$exit stderr=$stderr";exit 1}
Write-Host 'Gate12R v2 static/unit wrapper passed.' -ForegroundColor Green
exit 0

