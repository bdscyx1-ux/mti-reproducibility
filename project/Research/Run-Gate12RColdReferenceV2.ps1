[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$ScenarioPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][ValidateSet('A*-R','D*L','C-FF','IDFF')][string]$Algorithm,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=3600
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R cold-reference v2 wrapper requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RColdReferenceV2|$ProjectPath");exit 0}
$ScenarioPath=[IO.Path]::GetFullPath($ScenarioPath);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory);$AllowedRoot=[IO.Path]::GetFullPath($AllowedRoot);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$source=Join-Path $ProjectPath 'Research\Run-Gate12RColdReference.ps1';$expectedSourceSha256='f828437bb6b1a959d7341eb74ae315f4270da1666fb83fde5ac2848a8502757f';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen cold-reference v1 source changed: $actualSourceSha256"}
$oldLine=@'
$compiler=if(Test-Path -LiteralPath $unityLog){@(Select-String -LiteralPath $unityLog -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false)}else{@()}
'@.TrimEnd("`r","`n")
$newLine=@'
$compiler=@();if(Test-Path -LiteralPath $unityLog){$compiler=@(Select-String -LiteralPath $unityLog -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false)}
'@.TrimEnd("`r","`n")
$lines=@([IO.File]::ReadAllLines($source,[Text.Encoding]::UTF8));$indices=@(for($i=0;$i-lt$lines.Count;$i++){if($lines[$i]-ceq$oldLine){$i}});if($indices.Count-ne1){throw "Cold-reference v2 mechanical replacement count is $($indices.Count), expected 1."};$lines[$indices[0]]=$newLine
$derivedRoot=$OutputDirectory+'.DerivedHarnessV2';if(Test-Path $derivedRoot){throw "Create-new cold-reference v2 derived root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derivedPath=Join-Path $derivedRoot 'Run-Gate12RColdReferenceV2.derived.ps1';[IO.File]::WriteAllLines($derivedPath,$lines,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-cold-reference-empty-array-compatibility-wrapper-v2';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();replacementCount=1;repair='initialize-empty-array-before-conditional-select-string';researchSemanticsChanged=$false};$json=($receipt|ConvertTo-Json -Depth 10).Replace("`r`n","`n").Replace("`r","`n");[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json+"`n",(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -ScenarioPath $ScenarioPath -OutputDirectory $OutputDirectory -AllowedRoot $AllowedRoot -RunId $RunId -Algorithm $Algorithm -UnityPath $UnityPath -TimeoutSeconds $TimeoutSeconds;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R cold-reference v2 derived child failed: exit=$exit";exit $exit};Write-Host "Gate12R cold-reference v2 compatibility child passed: $RunId" -ForegroundColor Green;exit 0

