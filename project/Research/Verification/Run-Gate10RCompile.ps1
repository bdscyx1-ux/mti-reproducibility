[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe'
)

$ErrorActionPreference='Stop'
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$modulePath=Join-Path $ProjectPath 'Research\Gate10RProcessReusePreparation.psm1'
Import-Module $modulePath -Force
$outputDirectory=Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v1\Compile'
$logPath=Join-Path $outputDirectory 'v1.Unity.log'
$summaryPath=Join-Path $outputDirectory 'v1.summary.json'
if(Test-Path -LiteralPath $outputDirectory){throw "Gate 10R compile evidence exists; refusing retry/overwrite: $outputDirectory"}
if(-not(Test-Path -LiteralPath $UnityPath -PathType Leaf)){throw "Unity executable missing: $UnityPath"}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')){throw 'Gate 13R formal root must remain absent.'}
if(@(Get-Process Unity -ErrorAction SilentlyContinue).Count-gt 0-or(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and the project lock absent before compilation.'}
New-Item -ItemType Directory -Path $outputDirectory|Out-Null
$startedAt=Get-Date
$arguments=@('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-logFile',('"'+$logPath+'"'))
$process=Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
Wait-Process -Id $process.Id
$process.Refresh();$completedAt=Get-Date;$exitCode=[int]$process.ExitCode
$matches=if(Test-Path -LiteralPath $logPath){@(Select-String -LiteralPath $logPath -Pattern 'error CS\d{4}|Scripts have compiler errors|Compilation failed|executeMethod.+could not be found' -CaseSensitive:$false)}else{@()}
$errors=New-Object System.Collections.Generic.List[string]
if($exitCode-ne 0){$errors.Add("Unity exited with code $exitCode.")}
if(-not(Test-Path -LiteralPath $logPath -PathType Leaf)){$errors.Add('Unity compile log is missing.')}
if($matches.Count-gt 0){$errors.Add("Compiler-error pattern count: $($matches.Count).")}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate10r-unity-compilation-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');unityPath=$UnityPath;unitySha256=Get-Gate10RLowerSha256 $UnityPath;unityProcessId=[int]$process.Id;startedAt=$startedAt.ToString('o');completedAt=$completedAt.ToString('o');wallSeconds=($completedAt-$startedAt).TotalSeconds;exitCode=$exitCode;compilerErrorMatchCount=$matches.Count;logSha256=if(Test-Path -LiteralPath $logPath){Get-Gate10RLowerSha256 $logPath}else{$null};commandSourceSha256=Get-Gate10RLowerSha256 (Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate10RProcessReuseBatchCommand.cs');errors=$errors.ToArray();formalCampaign=$false;passed=$errors.Count-eq 0}
Write-Gate10RAtomicUtf8NoBomJson $summaryPath $summary 20
if(-not $summary.passed){Write-Error "Gate 10R compilation failed: $($errors -join '; ')";exit 1}
Write-Host 'Gate 10R Unity compilation passed.' -ForegroundColor Green
exit 0

