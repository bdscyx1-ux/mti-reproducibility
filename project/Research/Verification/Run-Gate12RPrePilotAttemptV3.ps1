[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R v3 pre-pilot wrapper requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RPrePilotAttemptV3|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RPrePilotAttempt.ps1';$expectedSourceSha256='ca7fb7566aae8382793adbc16cdc60dd3010f0157803f3bd275973cc4f4441d3';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen v1 pre-pilot source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$routes=@(
 [pscustomobject]@{old='Run-Gate12RStaticUnitAudit.ps1';new='Run-Gate12RStaticUnitAuditV2.ps1';count=3},
 [pscustomobject]@{old='Run-Gate12RCompile.ps1';new='Run-Gate12RCompileV2.ps1';count=3},
 [pscustomobject]@{old='Run-Gate12RTelemetryProbe.ps1';new='Run-Gate12RTelemetryProbeV2.ps1';count=3},
 [pscustomobject]@{old='Run-Gate12RColdReference.ps1';new='Run-Gate12RColdReferenceV2.ps1';count=2},
 [pscustomobject]@{old='Run-Gate12RPilot.ps1';new='Run-Gate12RPilotV2.ps1';count=2},
 [pscustomobject]@{old='Run-Gate12RBlockAndRegressionGates.ps1';new='Run-Gate12RBlockAndRegressionGatesV2.ps1';count=3},
 [pscustomobject]@{old='attempt=[int]$plan.attempt';new='attempt=[int]$provenance.attempt';count=1},
 [pscustomobject]@{old="receiptKind='gate12r-pre-pilot-gates-execution-receipt-v1'";new="receiptKind='gate12r-pre-pilot-gates-execution-receipt-v3'";count=1},
 [pscustomobject]@{old="checkpointKind='gate12r-pre-pilot-verification-checkpoint-v1'";new="checkpointKind='gate12r-pre-pilot-verification-checkpoint-v3'";count=1},
 [pscustomobject]@{old="manifestKind='gate12r-pre-pilot-partial-output-manifest-v1'";new="manifestKind='gate12r-pre-pilot-partial-output-manifest-v3'";count=1},
 [pscustomobject]@{old="receiptKind='gate12r-pre-pilot-gates-failure-receipt-v1'";new="receiptKind='gate12r-pre-pilot-gates-failure-receipt-v3'";count=1}
)
$routeEvidence=New-Object Collections.Generic.List[object]
foreach($route in $routes){$actual=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($actual-ne[int]$route.count){throw "Pre-pilot v3 replacement count for '$($route.old)' is $actual, expected $($route.count)."};$text=$text.Replace([string]$route.old,[string]$route.new);$routeEvidence.Add([pscustomobject]@{from=$route.old;to=$route.new;replacementCount=$actual})}
$derivedRoot=Join-Path $ProjectPath 'Research\Verification\Gate12R_PrePilotDerived\v3';if(Test-Path $derivedRoot){throw "Create-new v3 derived pre-pilot root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derivedPath=Join-Path $derivedRoot 'Run-Gate12RPrePilotAttemptV3.derived.ps1';[IO.File]::WriteAllText($derivedPath,$text,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-pre-pilot-file-scope-route-wrapper-v3';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();routes=$routeEvidence.ToArray();researchSemanticsChanged=$false;pilotRootCreatedBeforeChild=$false;formalRootCreatedBeforeChild=$false};$json=($receipt|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n");[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json+"`n",(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$stdout=Join-Path $derivedRoot 'child.stdout.log';$stderr=Join-Path $derivedRoot 'child.stderr.log';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -VerificationRoot $VerificationRoot -PilotPlanPath $PilotPlanPath -ProvenancePath $ProvenancePath -UnityPath $UnityPath 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R v3 pre-pilot wrapper child failed: exit=$exit stderr=$stderr";exit $exit};Write-Host 'Gate12R v3 pre-pilot wrapper child passed.' -ForegroundColor Green;exit 0

