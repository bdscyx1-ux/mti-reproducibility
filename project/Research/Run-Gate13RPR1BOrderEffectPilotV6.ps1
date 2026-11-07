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

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'PR1B v3 pilot requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BOrderEffectPilotV6|$ProjectPath");exit 0}
$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath)
$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath)
$PrePilotAuditPath=[IO.Path]::GetFullPath($PrePilotAuditPath)
$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath)
$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$source=Join-Path $ProjectPath 'Research\Run-Gate13RPR1BOrderEffectPilotV1.ps1'
$expectedSourceSha256='9f6ed211daddf5624f6b16eaf41ae82f53de6c5e08129e432ddc8323e6ca564c'
$actualSourceSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen PR1B v1 pilot orchestrator changed: $actualSourceSha256"}
$plan=Get-Content -LiteralPath $PilotPlanPath -Raw -Encoding UTF8|ConvertFrom-Json
if([int]$plan.schemaVersion-ne2-or[string]$plan.planId-ne'gate13r-pr1b-balanced-mirrored-order-effect-pathsafe-v4-pilot-v1'){throw 'PR1B v3 pilot-plan identity mismatch.'}
$pilotRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/','\')))
$verificationRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.verificationRootRelativePath).Replace('/','\')))
if(Test-Path -LiteralPath $pilotRoot){throw "Create-new PR1B v3 pilot root exists: $pilotRoot"}
if(-not(Test-Path -LiteralPath $verificationRoot -PathType Container)){throw 'Passing PR1B v3 verification root is missing.'}

$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$tokenCount=$text.Split([string[]]@('Gate13RPR1B'),[StringSplitOptions]::None).Count-1
if($tokenCount-lt20){throw "Unexpected PR1B v1 function-token count: $tokenCount"}
$text=$text.Replace('Gate13RPR1B','Gate13RPR1BV3')
$routes=@(
    [pscustomobject]@{old='Research\Gate13RPR1BV3OrderEffectPreparationV1.psm1';new='Research\Gate13RPR1BOrderEffectPreparationV4.psm1';count=1},
    [pscustomobject]@{old='Research\Run-Gate12RProcessReuseBlockV5.ps1';new='Research\Run-Gate13RPR1BMemoryAwareBlockV5.ps1';count=1},
    [pscustomobject]@{old='Research\Analyze-Gate13RPR1BV3OrderEffectPilotV1.py';new='Research\Analyze-Gate13RPR1BOrderEffectPilotV4.py';count=1},
    [pscustomobject]@{old="schemaVersion=1;snapshotKind='gate13r-pr1b-environment-power-thermal-storage-preflight-v1'";new="schemaVersion=3;snapshotKind='gate13r-pr1b-v3-pathsafe-environment-power-thermal-storage-preflight-v1'";count=1},
    [pscustomobject]@{old="schemaVersion=1;checkpointKind='gate13r-pr1b-order-effect-pilot-checkpoint-v1'";new="schemaVersion=3;checkpointKind='gate13r-pr1b-v3-pathsafe-order-effect-pilot-checkpoint-v1'";count=1},
    [pscustomobject]@{old="schemaVersion=1;manifestKind='gate13r-pr1b-pilot-partial-output-manifest-v1'";new="schemaVersion=3;manifestKind='gate13r-pr1b-v3-pathsafe-pilot-partial-output-manifest-v1'";count=1},
    [pscustomobject]@{old="schemaVersion=1;receiptKind='gate13r-pr1b-non-formal-order-effect-pilot-execution-receipt-v1'";new="schemaVersion=3;receiptKind='gate13r-pr1b-v3-pathsafe-non-formal-order-effect-pilot-execution-receipt-v1'";count=1},
    [pscustomobject]@{old="schemaVersion=1;manifestKind='gate13r-pr1b-order-effect-pilot-execution-manifest-v1'";new="schemaVersion=3;manifestKind='gate13r-pr1b-v3-pathsafe-order-effect-pilot-execution-manifest-v1'";count=1},
    [pscustomobject]@{old="schemaVersion=1;receiptKind='gate13r-pr1b-pilot-failure-receipt-v1'";new="schemaVersion=3;receiptKind='gate13r-pr1b-v3-pathsafe-pilot-failure-receipt-v1'";count=1}
)
$evidence=New-Object Collections.Generic.List[object]
foreach($route in $routes){$actual=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($actual-ne[int]$route.count){throw "Pilot v2 replacement count for '$($route.old)' is $actual, expected $($route.count)."};$text=$text.Replace([string]$route.old,[string]$route.new);$evidence.Add([pscustomobject]@{from=$route.old;to=$route.new;replacementCount=$actual})}

if($null-eq$plan.paths.PSObject.Properties['pilotLaunchHarnessRootRelativePath']){throw 'Pilot launch harness root is missing from the selected plan.'}
$derivedRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.pilotLaunchHarnessRootRelativePath).Replace('/','\')))
$launchBase=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))
if(-not$derivedRoot.StartsWith($launchBase.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Pilot launch harness root is outside versioned verification containment.'}
if($derivedRoot-eq$verificationRoot-or$derivedRoot-eq$pilotRoot){throw 'Pilot launch harness root aliases a protected execution root.'}
if(Test-Path -LiteralPath $derivedRoot){throw "Create-new PR1B v3 pilot launch harness root exists: $derivedRoot"}
New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null
$derivedPath=Join-Path $derivedRoot 'Run-Gate13RPR1BOrderEffectPilotV6.derived.ps1'
[IO.File]::WriteAllText($derivedPath,$text,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-pr1b-v3-pathsafe-pilot-derived-orchestrator-receipt-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash -LiteralPath $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();globalFunctionTokenReplacementCount=$tokenCount;routes=$evidence.ToArray();measuredRetryAuthorized=$false;measuredResumeAuthorized=$false;formalCampaign=$false}
[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),(($receipt|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n"),(New-Object Text.UTF8Encoding($false,$true)))
$winps='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$native=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
$stdout=Join-Path $derivedRoot 'child.stdout.log';$stderr=Join-Path $derivedRoot 'child.stderr.log';$old=$env:PSModulePath
try{$env:PSModulePath=$native;&$winps -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -PilotPlanPath $PilotPlanPath -ProvenancePath $ProvenancePath -PrePilotAuditPath $PrePilotAuditPath -TelemetryResultPath $TelemetryResultPath -UnityPath $UnityPath 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$old}
if($exit-ne0){Write-Error "PR1B v3 pilot child failed closed: exit=$exit stderr=$stderr";exit $exit}
Write-Host 'PR1B v3 pilot completed through the versioned derived orchestrator.' -ForegroundColor Green
exit 0


