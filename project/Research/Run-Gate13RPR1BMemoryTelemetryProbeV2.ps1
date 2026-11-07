[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=300
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate13R-PR1B memory telemetry v2 wrapper requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BMemoryTelemetryProbeV2|$ProjectPath");exit 0}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot=[IO.Path]::GetFullPath($AllowedRoot)
$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$source=Join-Path $ProjectPath 'Research\Run-Gate12RTelemetryProbe.ps1'
$expectedSourceSha256='dad26465e5c0fc349806b98fea965f46abf670ef2b5b720cee36665839a3b3b3'
$actualSourceSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen telemetry source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$routes=@(
    [pscustomobject]@{old='$compiler=if(Test-Path -LiteralPath $unityLog){@(Select-String -LiteralPath $unityLog -Pattern ''error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found'' -CaseSensitive:$false)}else{@()}';new='$compiler=@();if(Test-Path -LiteralPath $unityLog){$compiler=@(Select-String -LiteralPath $unityLog -Pattern ''error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found'' -CaseSensitive:$false)}';count=1},
    [pscustomobject]@{old="Import-Module (Join-Path `$PSScriptRoot 'Gate12RProcessReusePreparation.psm1') -Force";new="Import-Module (Join-Path `$ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force";count=1},
    [pscustomobject]@{old="Import-Module (Join-Path `$PSScriptRoot 'Gate10RLockHygieneV3.psm1') -Force";new="Import-Module (Join-Path `$ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force";count=1},
    [pscustomobject]@{old='DDM.Research.Editor.Gate10RProcessReuseBatchCommand.ProbeTelemetry';new='DDM.Research.Editor.Gate13RPR1BMemoryAwareProcessReuseBatchCommandV2.ProbeTelemetry';count=1},
    [pscustomobject]@{old="Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1";new="Research\FormalRuns\Gate13R_RQAligned\v1";count=1},
    [pscustomobject]@{old="'gate12r-telemetry-probe'";new="'gate13r-pr1b-v2-telemetry-probe'";count=1},
    [pscustomobject]@{old="summaryKind='gate12r-telemetry-probe-wrapper-v1'";new="summaryKind='gate13r-pr1b-v2-telemetry-probe-wrapper-v1'";count=1}
)
$evidence=New-Object Collections.Generic.List[object]
foreach($route in $routes){
    $actual=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1
    if($actual-ne[int]$route.count){throw "Telemetry v2 replacement count for '$($route.old)' is $actual, expected $($route.count)."}
    $text=$text.Replace([string]$route.old,[string]$route.new)
    $evidence.Add([pscustomobject]@{from=$route.old;to=$route.new;replacementCount=$actual})
}
$derivedRoot=$OutputDirectory+'.DerivedHarnessPR1BV2'
if(Test-Path -LiteralPath $derivedRoot){throw "Create-new telemetry v2 derived root exists: $derivedRoot"}
New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null
$derivedPath=Join-Path $derivedRoot 'Run-Gate13RPR1BMemoryTelemetryProbeV2.derived.ps1'
[IO.File]::WriteAllText($derivedPath,$text,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-pr1b-v2-telemetry-derived-wrapper-receipt-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash -LiteralPath $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();routes=$evidence.ToArray();researchSemanticsChanged=$false;memoryObservabilityCommandChanged=$true;formalCampaign=$false}
[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),(($receipt|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n"),(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
$stdout=Join-Path $derivedRoot 'child.stdout.log'
$stderr=Join-Path $derivedRoot 'child.stderr.log'
$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -OutputDirectory $OutputDirectory -AllowedRoot $AllowedRoot -UnityPath $UnityPath -TimeoutSeconds $TimeoutSeconds 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate13R-PR1B telemetry v2 derived child failed: exit=$exit stderr=$stderr";exit $exit}
$result=Get-Content -LiteralPath (Join-Path $OutputDirectory 'telemetry-probe-result.json') -Raw -Encoding UTF8|ConvertFrom-Json
if([string]$result.resultKind-ne'gate13r-pr1b-v2-native-telemetry-probe-result-v1'-or$result.passed-ne$true){Write-Error 'Gate13R-PR1B telemetry result identity/pass mismatch.';exit 1}
Write-Host 'Gate13R-PR1B telemetry v2 compatibility child passed.' -ForegroundColor Green
exit 0
