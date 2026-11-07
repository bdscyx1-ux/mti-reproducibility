[CmdletBinding()]
param(
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$ProjectPath,
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$ArtifactName = 'Gate1_Unity'
)

$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..'))
}

$logPath = Join-Path $scriptDirectory ($ArtifactName + '.log')
$summaryPath = Join-Path $scriptDirectory ($ArtifactName + '.summary.json')
$assemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp.dll'
$editorAssemblyPath = Join-Path $ProjectPath 'Library\ScriptAssemblies\Assembly-CSharp-Editor.dll'
$projectLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'

if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) {
    throw "Unity executable not found: $UnityPath"
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Assets') -PathType Container)) {
    throw "Unity project Assets directory not found: $ProjectPath"
}

$runningUnity = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
if ($runningUnity.Count -gt 0 -or (Test-Path -LiteralPath $projectLockPath)) {
    throw 'Close Unity before running this verification. A Unity process or project lock is present.'
}

Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue

Write-Host "Running Unity compilation verification in batch mode ($ArtifactName)..."
Write-Host "Log: $logPath"

$unityArguments = @(
    '-batchmode'
    '-nographics'
    '-quit'
    '-projectPath'
    ('"{0}"' -f $ProjectPath)
    '-logFile'
    ('"{0}"' -f $logPath)
)

$unityProcess = Start-Process `
    -FilePath $UnityPath `
    -ArgumentList $unityArguments `
    -WorkingDirectory (Split-Path -Parent $UnityPath) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

$unityExitCode = $unityProcess.ExitCode
$logExists = Test-Path -LiteralPath $logPath -PathType Leaf

$compilerErrorPatterns = @(
    'error CS\d{4}',
    'Scripts have compiler errors',
    'Compilation failed'
)

$compilerErrorMatches = @()
if ($logExists) {
    $compilerErrorMatches = @(
        Select-String -LiteralPath $logPath -Pattern $compilerErrorPatterns -AllMatches |
            ForEach-Object {
                [pscustomobject]@{
                    LineNumber = $_.LineNumber
                    Line = $_.Line.Trim()
                }
            }
    )
}

$researchSources = @(
    Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Assets\_Scripts\Research') `
        -Filter '*.cs' `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue
)
$editorSegment = [System.IO.Path]::DirectorySeparatorChar + 'Editor' + [System.IO.Path]::DirectorySeparatorChar
$runtimeResearchSources = @($researchSources | Where-Object { $_.FullName -notlike "*$editorSegment*" })
$editorResearchSources = @($researchSources | Where-Object { $_.FullName -like "*$editorSegment*" })
$newestRuntimeResearchSource = $runtimeResearchSources | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$newestEditorResearchSource = $editorResearchSources | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$assembly = Get-Item -LiteralPath $assemblyPath -ErrorAction SilentlyContinue
$editorAssembly = Get-Item -LiteralPath $editorAssemblyPath -ErrorAction SilentlyContinue
$runtimeAssemblyIsCurrent = (
    $null -ne $assembly -and
    ($null -eq $newestRuntimeResearchSource -or $assembly.LastWriteTimeUtc -ge $newestRuntimeResearchSource.LastWriteTimeUtc)
)
$editorAssemblyIsCurrent = (
    $null -ne $editorAssembly -and
    ($null -eq $newestEditorResearchSource -or $editorAssembly.LastWriteTimeUtc -ge $newestEditorResearchSource.LastWriteTimeUtc)
)
$assemblyIsCurrent = $runtimeAssemblyIsCurrent -and $editorAssemblyIsCurrent

$passed = (
    $unityExitCode -eq 0 -and
    $logExists -and
    $compilerErrorMatches.Count -eq 0 -and
    $assemblyIsCurrent
)

$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    unityPath = $UnityPath
    projectPath = $ProjectPath
    exitCode = $unityExitCode
    logPath = $logPath
    logExists = $logExists
    compilerErrorMatchCount = $compilerErrorMatches.Count
    compilerErrorMatches = $compilerErrorMatches
    assemblyCSharpPath = $assemblyPath
    assemblyCSharpExists = ($null -ne $assembly)
    assemblyCSharpLength = if ($null -ne $assembly) { $assembly.Length } else { $null }
    assemblyCSharpLastWriteUtc = if ($null -ne $assembly) { $assembly.LastWriteTimeUtc.ToString('o') } else { $null }
    newestRuntimeResearchSource = if ($null -ne $newestRuntimeResearchSource) { $newestRuntimeResearchSource.FullName } else { $null }
    newestRuntimeResearchSourceLastWriteUtc = if ($null -ne $newestRuntimeResearchSource) { $newestRuntimeResearchSource.LastWriteTimeUtc.ToString('o') } else { $null }
    runtimeAssemblyIsCurrent = $runtimeAssemblyIsCurrent
    assemblyCSharpEditorPath = $editorAssemblyPath
    assemblyCSharpEditorExists = ($null -ne $editorAssembly)
    assemblyCSharpEditorLength = if ($null -ne $editorAssembly) { $editorAssembly.Length } else { $null }
    assemblyCSharpEditorLastWriteUtc = if ($null -ne $editorAssembly) { $editorAssembly.LastWriteTimeUtc.ToString('o') } else { $null }
    newestEditorResearchSource = if ($null -ne $newestEditorResearchSource) { $newestEditorResearchSource.FullName } else { $null }
    newestEditorResearchSourceLastWriteUtc = if ($null -ne $newestEditorResearchSource) { $newestEditorResearchSource.LastWriteTimeUtc.ToString('o') } else { $null }
    editorAssemblyIsCurrent = $editorAssemblyIsCurrent
    assemblyIsCurrent = $assemblyIsCurrent
    passed = $passed
}

$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 5

if (-not $passed) {
    Write-Error "Unity compilation verification failed. Review $summaryPath and $logPath."
    exit 1
}

Write-Host "Unity compilation verification passed ($ArtifactName)." -ForegroundColor Green
exit 0
