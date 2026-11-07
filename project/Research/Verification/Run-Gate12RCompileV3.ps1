[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=1200
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R compile v3 wrapper requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RCompileV3|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RCompile.ps1';$expectedSourceSha256='76ab2ede0c58f9b6da33404547851652299133b221e303fce28a87b5224472f3';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen compile v1 source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$oldArray="`$matches=if(Test-Path -LiteralPath `$log){@(Select-String -LiteralPath `$log -Pattern 'error CS\d+|Scripts have compiler errors|Compilation failed|executeMethod.+could not be found' -CaseSensitive:`$false)}else{@()}"
$newArray="`$matches=@();if(Test-Path -LiteralPath `$log){`$matches=@(Select-String -LiteralPath `$log -Pattern 'error CS\d+|Scripts have compiler errors|Compilation failed|executeMethod.+could not be found' -CaseSensitive:`$false)}"
$oldCommand='Assets\_Scripts\Research\Editor\Gate10RProcessReuseBatchCommand.cs';$newCommand='Assets\_Scripts\Research\Editor\Gate12RProcessReuseBatchCommandV2.cs'
$oldKind="summaryKind='gate12r-unity-compilation-v1'";$newKind="summaryKind='gate12r-unity-compilation-v2-reset-contract-command'"
$routes=@([pscustomobject]@{old=$oldArray;new=$newArray;count=1},[pscustomobject]@{old=$oldCommand;new=$newCommand;count=1},[pscustomobject]@{old=$oldKind;new=$newKind;count=1});$evidence=New-Object Collections.Generic.List[object]
foreach($route in $routes){$actual=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($actual-ne[int]$route.count){throw "Compile v3 replacement count is $actual, expected $($route.count): $($route.old)"};$text=$text.Replace([string]$route.old,[string]$route.new);$evidence.Add([pscustomobject]@{from=$route.old;to=$route.new;replacementCount=$actual})}
$derivedRoot=Join-Path $VerificationRoot '_DerivedHarness\CompileV3';if(Test-Path $derivedRoot){throw "Create-new compile v3 derived root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derivedPath=Join-Path $derivedRoot 'Run-Gate12RCompileV3.derived.ps1';[IO.File]::WriteAllText($derivedPath,$text,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-compile-v3-reset-command-and-empty-array-wrapper';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();routes=$evidence.ToArray();researchAlgorithmSemanticsChanged=$false;resetCommandCompiled=$true};$json=($receipt|ConvertTo-Json -Depth 12).Replace("`r`n","`n").Replace("`r","`n");[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json+"`n",(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -VerificationRoot $VerificationRoot -UnityPath $UnityPath -TimeoutSeconds $TimeoutSeconds;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R compile v3 derived child failed: exit=$exit";exit $exit};Write-Host 'Gate12R compile v3 reset-command child passed.' -ForegroundColor Green;exit 0
