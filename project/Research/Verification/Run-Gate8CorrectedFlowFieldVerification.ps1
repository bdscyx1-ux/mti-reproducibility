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

$logPath = Join-Path $scriptDirectory 'Gate8_CorrectedFlowField_Unity.log'
$resultPath = Join-Path $scriptDirectory 'Gate8_CorrectedFlowField.json'
$summaryPath = Join-Path $scriptDirectory 'Gate8_CorrectedFlowField.summary.json'
$projectLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$runtimeAssemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp.dll'
$editorAssemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp-Editor.dll'
$researchSourceRoot = Join-Path $ProjectPath 'Assets\_Scripts\Research'

if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath $projectLockPath)) {
    throw 'Close Unity before running the Gate 8 C-FF verification.'
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
    'DDM.Research.Editor.Gate8CorrectedFlowFieldVerification.Run'
    '-logFile'
    ('"{0}"' -f $logPath)
)

Write-Host 'Running Gate 8 C-FF verification...'
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

$passed = (
    $process.ExitCode -eq 0 -and
    $compilerMatches.Count -eq 0 -and
    $null -ne $verificationResult -and
    $verificationResult.passed -eq $true -and
    $verificationResult.staticReferenceFieldCount -eq 24 -and
    $verificationResult.dynamicReferenceFieldCount -eq 72 -and
    $verificationResult.comparedCellCount -eq 2880 -and
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
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
if (-not $passed) { Write-Error "Gate 8 C-FF verification failed. Review $summaryPath and $logPath."; exit 1 }
Write-Host 'Gate 8 C-FF verification passed.' -ForegroundColor Green
exit 0
