[CmdletBinding()]
param(
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..'))
} else {
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
}

$logPath = Join-Path $scriptDirectory 'Gate6_ReplicationStatistics_Unity.log'
$resultPath = Join-Path $scriptDirectory 'Gate6_ReplicationStatistics.json'
$summaryPath = Join-Path $scriptDirectory 'Gate6_ReplicationStatistics.summary.json'
$projectLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$runtimeAssemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp.dll'
$editorAssemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp-Editor.dll'
$researchSourceRoot = Join-Path $ProjectPath 'Assets\_Scripts\Research'

if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath $projectLockPath)) {
    throw 'Close Unity before running the Gate 6 replication-statistics verification.'
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
    'DDM.Research.Editor.Gate6ReplicationStatisticsVerification.Run'
    '-logFile'
    ('"{0}"' -f $logPath)
)

Write-Host 'Running Gate 6 replication-statistics verification...'
$process = Start-Process `
    -FilePath $UnityPath `
    -ArgumentList $arguments `
    -WorkingDirectory (Split-Path -Parent $UnityPath) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

$compilerPatterns = @(
    'error CS\d{4}'
    'Scripts have compiler errors'
    'Compilation failed'
    'executeMethod.+could not be found'
)
$compilerMatches = if (Test-Path -LiteralPath $logPath) {
    @(Select-String -LiteralPath $logPath -Pattern $compilerPatterns -AllMatches)
} else { @() }

$verificationResult = if (Test-Path -LiteralPath $resultPath) {
    Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $null }

$runtimeAssembly = Get-Item -LiteralPath $runtimeAssemblyPath -ErrorAction SilentlyContinue
$editorAssembly = Get-Item -LiteralPath $editorAssemblyPath -ErrorAction SilentlyContinue
$allResearchSources = @(Get-ChildItem -LiteralPath $researchSourceRoot -Filter '*.cs' -File -Recurse)
$runtimeSources = @($allResearchSources | Where-Object { $_.FullName -notmatch '\\Editor\\' })
$editorSources = @($allResearchSources | Where-Object { $_.FullName -match '\\Editor\\' })
$newestRuntimeSource = $runtimeSources | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$newestEditorSource = $editorSources | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$runtimeAssemblyCurrent = $null -ne $runtimeAssembly -and ($null -eq $newestRuntimeSource -or $runtimeAssembly.LastWriteTimeUtc -ge $newestRuntimeSource.LastWriteTimeUtc)
$editorAssemblyCurrent = $null -ne $editorAssembly -and ($null -eq $newestEditorSource -or $editorAssembly.LastWriteTimeUtc -ge $newestEditorSource.LastWriteTimeUtc)

$passed = (
    $process.ExitCode -eq 0 -and
    (Test-Path -LiteralPath $logPath -PathType Leaf) -and
    $compilerMatches.Count -eq 0 -and
    $null -ne $verificationResult -and
    $verificationResult.passed -eq $true -and
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
    runtimeAssemblyPath = $runtimeAssemblyPath
    runtimeAssemblyCurrent = $runtimeAssemblyCurrent
    runtimeAssemblyLastWriteUtc = if ($null -ne $runtimeAssembly) { $runtimeAssembly.LastWriteTimeUtc.ToString('o') } else { $null }
    editorAssemblyPath = $editorAssemblyPath
    editorAssemblyCurrent = $editorAssemblyCurrent
    editorAssemblyLastWriteUtc = if ($null -ne $editorAssembly) { $editorAssembly.LastWriteTimeUtc.ToString('o') } else { $null }
    passed = $passed
}

$summary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 7
if (-not $passed) { Write-Error "Gate 6 replication-statistics verification failed. Review $summaryPath and $logPath."; exit 1 }
Write-Host 'Gate 6 replication-statistics verification passed.' -ForegroundColor Green
exit 0
