[CmdletBinding()]
param(
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }

$logPath = Join-Path $scriptDirectory 'Gate11_ScenarioMatrixGeneration.Unity.log'
$resultPath = Join-Path $scriptDirectory 'Gate11_ScenarioMatrixGeneration.json'
$summaryPath = Join-Path $scriptDirectory 'Gate11_ScenarioMatrixGeneration.summary.json'
$bundlePath = Join-Path $ProjectPath 'Research\FormalScenarios\v1'
$manifestPath = Join-Path $bundlePath 'bundle-manifest.json'
$projectLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$runtimeAssemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp.dll'
$editorAssemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp-Editor.dll'
$researchSourceRoot = Join-Path $ProjectPath 'Assets\_Scripts\Research'

if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath $projectLockPath)) {
    throw 'Close Unity before running Gate 11 scenario-matrix generation.'
}

Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue

$arguments = @(
    '-batchmode'
    '-nographics'
    '-quit'
    '-projectPath'
    ('"{0}"' -f $ProjectPath)
    '-executeMethod'
    'DDM.Research.Editor.Gate11FormalScenarioMatrixCommand.Generate'
    '-logFile'
    ('"{0}"' -f $logPath)
)

Write-Host 'Running create-new Gate 11 formal scenario generation...'
$process = Start-Process `
    -FilePath $UnityPath `
    -ArgumentList $arguments `
    -WorkingDirectory (Split-Path -Parent $UnityPath) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

$compilerPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found')
$compilerMatches = if (Test-Path -LiteralPath $logPath) { @(Select-String -LiteralPath $logPath -Pattern $compilerPatterns -AllMatches) } else { @() }
$generationResult = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$runtimeAssembly = Get-Item -LiteralPath $runtimeAssemblyPath -ErrorAction SilentlyContinue
$editorAssembly = Get-Item -LiteralPath $editorAssemblyPath -ErrorAction SilentlyContinue
$allResearchSources = @(Get-ChildItem -LiteralPath $researchSourceRoot -Filter '*.cs' -File -Recurse)
$newestRuntimeSource = $allResearchSources | Where-Object { $_.FullName -notmatch '\\Editor\\' } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$newestEditorSource = $allResearchSources | Where-Object { $_.FullName -match '\\Editor\\' } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$runtimeAssemblyCurrent = $null -ne $runtimeAssembly -and ($null -eq $newestRuntimeSource -or $runtimeAssembly.LastWriteTimeUtc -ge $newestRuntimeSource.LastWriteTimeUtc)
$editorAssemblyCurrent = $null -ne $editorAssembly -and ($null -eq $newestEditorSource -or $editorAssembly.LastWriteTimeUtc -ge $newestEditorSource.LastWriteTimeUtc)
$scenarioFiles = if (Test-Path -LiteralPath (Join-Path $bundlePath 'Scenarios') -PathType Container) { @(Get-ChildItem -LiteralPath (Join-Path $bundlePath 'Scenarios') -Filter '*.scenario.json' -File) } else { @() }
$bundleFiles = if (Test-Path -LiteralPath $bundlePath -PathType Container) { @(Get-ChildItem -LiteralPath $bundlePath -File -Recurse) } else { @() }
$manifestHash = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }

$passed = (
    $process.ExitCode -eq 0 -and
    $compilerMatches.Count -eq 0 -and
    $null -ne $generationResult -and
    $generationResult.passed -eq $true -and
    $generationResult.mode -eq 'generate' -and
    $generationResult.scenarioCount -eq 53 -and
    $generationResult.eligibilityCount -eq 212 -and
    $generationResult.sharedScenarioCount -eq 32 -and
    $generationResult.heterogeneousScenarioCount -eq 21 -and
    $generationResult.secondGenerationRefused -eq $true -and
    $generationResult.pilotExecuted -eq $false -and
    $generationResult.formalCampaignExecuted -eq $false -and
    $scenarioFiles.Count -eq 53 -and
    $bundleFiles.Count -eq 57 -and
    $generationResult.manifestSha256 -eq $manifestHash -and
    $runtimeAssemblyCurrent -and
    $editorAssemblyCurrent
)

$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    exitCode = $process.ExitCode
    logPath = $logPath
    compilerErrorMatchCount = $compilerMatches.Count
    compilerErrorMatches = @($compilerMatches | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() })
    generationResultPath = $resultPath
    generationResult = $generationResult
    bundlePath = $bundlePath
    bundleFileCount = $bundleFiles.Count
    scenarioFileCount = $scenarioFiles.Count
    manifestPath = $manifestPath
    manifestSha256 = $manifestHash
    runtimeAssemblyCurrent = $runtimeAssemblyCurrent
    editorAssemblyCurrent = $editorAssemblyCurrent
    passed = $passed
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 10
if (-not $passed) { Write-Error "Gate 11 scenario generation failed. Preserve the partial bundle and review $summaryPath and $logPath."; exit 1 }
Write-Host 'Gate 11 formal scenario generation passed.' -ForegroundColor Green
exit 0
