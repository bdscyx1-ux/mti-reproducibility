[CmdletBinding()]
param(
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }

$logPath = Join-Path $scriptDirectory 'Gate11_ScenarioMatrixVerification.Unity.log'
$resultPath = Join-Path $scriptDirectory 'Gate11_ScenarioMatrixVerification.json'
$summaryPath = Join-Path $scriptDirectory 'Gate11_ScenarioMatrixVerification.summary.json'
$bundlePath = Join-Path $ProjectPath 'Research\FormalScenarios\v1'
$manifestPath = Join-Path $bundlePath 'bundle-manifest.json'
$projectLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$runtimeAssemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp.dll'
$editorAssemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp-Editor.dll'
$researchSourceRoot = Join-Path $ProjectPath 'Assets\_Scripts\Research'

if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Gate 11 bundle manifest not found: $manifestPath" }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath $projectLockPath)) {
    throw 'Close Unity before running Gate 11 retained-bundle verification.'
}

Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
$manifestHashBefore = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$bundleSnapshotBefore = @(
    Get-ChildItem -LiteralPath $bundlePath -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{ relativePath = $_.FullName.Substring($bundlePath.Length).TrimStart('\').Replace('\','/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
)

$arguments = @(
    '-batchmode'
    '-nographics'
    '-quit'
    '-projectPath'
    ('"{0}"' -f $ProjectPath)
    '-executeMethod'
    'DDM.Research.Editor.Gate11FormalScenarioMatrixCommand.Verify'
    '-logFile'
    ('"{0}"' -f $logPath)
)

Write-Host 'Running read-only Gate 11 retained-bundle verification...'
$process = Start-Process `
    -FilePath $UnityPath `
    -ArgumentList $arguments `
    -WorkingDirectory (Split-Path -Parent $UnityPath) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

$compilerPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found')
$compilerMatches = if (Test-Path -LiteralPath $logPath) { @(Select-String -LiteralPath $logPath -Pattern $compilerPatterns -AllMatches) } else { @() }
$verificationResult = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$runtimeAssembly = Get-Item -LiteralPath $runtimeAssemblyPath -ErrorAction SilentlyContinue
$editorAssembly = Get-Item -LiteralPath $editorAssemblyPath -ErrorAction SilentlyContinue
$allResearchSources = @(Get-ChildItem -LiteralPath $researchSourceRoot -Filter '*.cs' -File -Recurse)
$newestRuntimeSource = $allResearchSources | Where-Object { $_.FullName -notmatch '\\Editor\\' } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$newestEditorSource = $allResearchSources | Where-Object { $_.FullName -match '\\Editor\\' } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$runtimeAssemblyCurrent = $null -ne $runtimeAssembly -and ($null -eq $newestRuntimeSource -or $runtimeAssembly.LastWriteTimeUtc -ge $newestRuntimeSource.LastWriteTimeUtc)
$editorAssemblyCurrent = $null -ne $editorAssembly -and ($null -eq $newestEditorSource -or $editorAssembly.LastWriteTimeUtc -ge $newestEditorSource.LastWriteTimeUtc)
$manifestHashAfter = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$bundleSnapshotAfter = @(
    Get-ChildItem -LiteralPath $bundlePath -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{ relativePath = $_.FullName.Substring($bundlePath.Length).TrimStart('\').Replace('\','/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
)
$bundleUnchanged = (($bundleSnapshotBefore | ConvertTo-Json -Depth 4 -Compress) -ceq ($bundleSnapshotAfter | ConvertTo-Json -Depth 4 -Compress))

$passed = (
    $process.ExitCode -eq 0 -and
    $compilerMatches.Count -eq 0 -and
    $null -ne $verificationResult -and
    $verificationResult.passed -eq $true -and
    $verificationResult.mode -eq 'verify' -and
    $verificationResult.scenarioCount -eq 53 -and
    $verificationResult.eligibilityCount -eq 212 -and
    $verificationResult.sharedScenarioCount -eq 32 -and
    $verificationResult.heterogeneousScenarioCount -eq 21 -and
    $verificationResult.plannerInitializationCount -eq 212 -and
    $verificationResult.negativeTestCount -eq 11 -and
    $verificationResult.pilotExecuted -eq $false -and
    $verificationResult.formalCampaignExecuted -eq $false -and
    $manifestHashBefore -eq $manifestHashAfter -and
    $verificationResult.manifestSha256 -eq $manifestHashAfter -and
    $bundleUnchanged -and
    $runtimeAssemblyCurrent -and
    $editorAssemblyCurrent
)

$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    exitCode = $process.ExitCode
    logPath = $logPath
    compilerErrorMatchCount = $compilerMatches.Count
    compilerErrorMatches = @($compilerMatches | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() })
    verificationResultPath = $resultPath
    verificationResult = $verificationResult
    bundlePath = $bundlePath
    bundleFileCountBefore = $bundleSnapshotBefore.Count
    bundleFileCountAfter = $bundleSnapshotAfter.Count
    manifestSha256Before = $manifestHashBefore
    manifestSha256After = $manifestHashAfter
    bundleUnchanged = $bundleUnchanged
    runtimeAssemblyCurrent = $runtimeAssemblyCurrent
    editorAssemblyCurrent = $editorAssemblyCurrent
    passed = $passed
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 10
if (-not $passed) { Write-Error "Gate 11 retained-bundle verification failed. Review $summaryPath and $logPath."; exit 1 }
Write-Host 'Gate 11 retained-bundle verification passed.' -ForegroundColor Green
exit 0
