[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=1200
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R compile v2 wrapper requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RCompileV2|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RCompile.ps1';$expectedSourceSha256='76ab2ede0c58f9b6da33404547851652299133b221e303fce28a87b5224472f3';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen compile v1 source changed: $actualSourceSha256"}
$oldLine=@'
$matches=if(Test-Path -LiteralPath $log){@(Select-String -LiteralPath $log -Pattern 'error CS\d+|Scripts have compiler errors|Compilation failed|executeMethod.+could not be found' -CaseSensitive:$false)}else{@()}
'@.TrimEnd("`r","`n")
$newLine=@'
$matches=@();if(Test-Path -LiteralPath $log){$matches=@(Select-String -LiteralPath $log -Pattern 'error CS\d+|Scripts have compiler errors|Compilation failed|executeMethod.+could not be found' -CaseSensitive:$false)}
'@.TrimEnd("`r","`n")
$lines=@([IO.File]::ReadAllLines($source,[Text.Encoding]::UTF8));$indices=@(for($i=0;$i-lt$lines.Count;$i++){if($lines[$i]-ceq$oldLine){$i}});if($indices.Count-ne1){throw "Compile v2 mechanical replacement count is $($indices.Count), expected 1."};$lines[$indices[0]]=$newLine
$derivedRoot=Join-Path $VerificationRoot '_DerivedHarness\CompileV2';if(Test-Path $derivedRoot){throw "Create-new compile v2 derived root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derivedPath=Join-Path $derivedRoot 'Run-Gate12RCompileV2.derived.ps1';[IO.File]::WriteAllLines($derivedPath,$lines,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-compile-empty-array-compatibility-wrapper-v2';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();replacementCount=1;repair='initialize-empty-array-before-conditional-select-string';researchSemanticsChanged=$false};$json=($receipt|ConvertTo-Json -Depth 10).Replace("`r`n","`n").Replace("`r","`n");[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json+"`n",(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -VerificationRoot $VerificationRoot -UnityPath $UnityPath -TimeoutSeconds $TimeoutSeconds;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R compile v2 derived child failed: exit=$exit";exit $exit};Write-Host 'Gate12R compile v2 compatibility child passed.' -ForegroundColor Green;exit 0

