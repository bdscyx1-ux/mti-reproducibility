[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R v3 static wrapper requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RStaticUnitAuditV4|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath)
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RStaticUnitAudit.ps1';$expectedSourceSha256='dfc8c94e3e2103946aa165c65beb58aa5b0aa744ba948984ac66766de9e8e049';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen static v1 source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$routes=@(
 [pscustomobject]@{old='Gate12R_PreWrite_Preservation_Baseline.v1.json';new='Gate12R_PreWrite_Preservation_Baseline.v2.json';count=1},
 [pscustomobject]@{old='Gate12R_5pct_ProcessReuse_Pilot_Plan.v1.json';new='Gate12R_5pct_ProcessReuse_Pilot_Plan.v3.json';count=1},
 [pscustomobject]@{old='68f32ee7acdeaa4c43a4f4932825e40e552bb5df473a96c66a9dcffef45d8ff3';new='498f0bac34f5ba98c946efab5577f1feed5631a4766fdd8817c74f445b150c98';count=1},
 [pscustomobject]@{old="summaryKind='gate12r-static-unit-audit-v1'";new="summaryKind='gate12r-static-unit-audit-v3-pilot-plan-v3-upstream-canonical-reference'";count=1}
)
$evidence=New-Object Collections.Generic.List[object];foreach($route in $routes){$actual=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($actual-ne[int]$route.count){throw "Static v3 replacement count for '$($route.old)' is $actual, expected $($route.count)."};$text=$text.Replace([string]$route.old,[string]$route.new);$evidence.Add([pscustomobject]@{from=$route.old;to=$route.new;replacementCount=$actual})}
$derivedRoot=Join-Path $VerificationRoot '_DerivedHarness\StaticV4';if(Test-Path $derivedRoot){throw "Create-new static v4 derived root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derivedPath=Join-Path $derivedRoot 'Run-Gate12RStaticUnitAuditV4.derived.ps1';[IO.File]::WriteAllText($derivedPath,$text,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-static-unit-plan-v2-wrapper-v3';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();routes=$evidence.ToArray();frozenDesignSemanticsChanged=$false};$json=($receipt|ConvertTo-Json -Depth 12).Replace("`r`n","`n").Replace("`r","`n");[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json+"`n",(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$stdout=Join-Path $derivedRoot 'child.stdout.log';$stderr=Join-Path $derivedRoot 'child.stderr.log';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -VerificationRoot $VerificationRoot -ProvenancePath $ProvenancePath 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R static v4 child failed: exit=$exit stderr=$stderr";exit $exit};Write-Host 'Gate12R static/unit v3 child passed.' -ForegroundColor Green;exit 0

