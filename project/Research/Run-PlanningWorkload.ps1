[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScenarioPath,
    [string]$OutputDirectory,
    [string]$RunId,
    [ValidateSet('A*-R', 'D*L', 'C-FF', 'IDFF')]
    [string]$Algorithm = 'A*-R',
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..'))
} else {
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
}

if (-not [System.IO.Path]::IsPathRooted($ScenarioPath)) { $ScenarioPath = Join-Path (Get-Location).Path $ScenarioPath }
$ScenarioPath = [System.IO.Path]::GetFullPath($ScenarioPath)
if (-not (Test-Path -LiteralPath $ScenarioPath -PathType Leaf)) { throw "Scenario file not found: $ScenarioPath" }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Assets') -PathType Container)) { throw "Unity project not found: $ProjectPath" }

if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = 'run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') }
if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') { throw 'RunId must be 1-128 file-safe ASCII characters and begin with an alphanumeric character.' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $ProjectPath (Join-Path 'Research\Runs' $RunId) }
elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $ProjectPath $OutputDirectory }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output path is not a directory: $OutputDirectory" }
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) { throw "Output directory is not empty; refusing to overwrite: $OutputDirectory" }
}

$projectLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath $projectLockPath)) {
    throw 'Close Unity before running the headless planning workload.'
}

$unityLogPath = $OutputDirectory + '.Unity.log'
$summaryPath = $OutputDirectory + '.summary.json'
Remove-Item -LiteralPath $unityLogPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
$parentDirectory = Split-Path -Parent $OutputDirectory
if (-not [string]::IsNullOrEmpty($parentDirectory)) { New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null }

$arguments = @(
    '-batchmode'
    '-nographics'
    '-quit'
    '-projectPath'
    ('"{0}"' -f $ProjectPath)
    '-executeMethod'
    'DDM.Research.Editor.ResearchPlanningBatchCommand.Run'
    '-ddmScenarioPath'
    ('"{0}"' -f $ScenarioPath)
    '-ddmOutputDirectory'
    ('"{0}"' -f $OutputDirectory)
    '-ddmRunId'
    ('"{0}"' -f $RunId)
    '-ddmAlgorithm'
    ('"{0}"' -f $Algorithm)
    '-logFile'
    ('"{0}"' -f $unityLogPath)
)

Write-Host "Running $Algorithm planning workload..."
Write-Host "Scenario: $ScenarioPath"
Write-Host "Output: $OutputDirectory"
$process = Start-Process `
    -FilePath $UnityPath `
    -ArgumentList $arguments `
    -WorkingDirectory (Split-Path -Parent $UnityPath) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

$compilerPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found')
$compilerMatches = if (Test-Path -LiteralPath $unityLogPath) { @(Select-String -LiteralPath $unityLogPath -Pattern $compilerPatterns -AllMatches) } else { @() }
$manifestPath = Join-Path $OutputDirectory 'manifest.json'
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$passed = $process.ExitCode -eq 0 -and $compilerMatches.Count -eq 0 -and $null -ne $manifest -and $manifest.completed -eq $true

$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    exitCode = $process.ExitCode
    unityLogPath = $unityLogPath
    compilerErrorMatchCount = $compilerMatches.Count
    compilerErrorMatches = @($compilerMatches | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() })
    scenarioPath = $ScenarioPath
    outputDirectory = $OutputDirectory
    manifestPath = $manifestPath
    manifest = $manifest
    passed = $passed
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
if (-not $passed) { Write-Error "Planning workload failed. Review $summaryPath and $unityLogPath."; exit 1 }
Write-Host 'Planning workload completed.' -ForegroundColor Green
exit 0
