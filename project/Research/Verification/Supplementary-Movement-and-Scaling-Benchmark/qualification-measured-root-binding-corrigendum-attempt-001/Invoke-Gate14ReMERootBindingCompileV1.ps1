param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$UnityExecutable,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$RunnerSha256
)

$ErrorActionPreference = 'Stop'
$expectedUnitySha256 = '0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'
$attemptId = 'qualification-measured-root-binding-corrigendum-attempt-001'
$authorizationId = 'gate14re-me-qualification-measured-root-binding-corrigendum-attempt-001'

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Get-Sha256Lower {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Test-ReservedAttemptPath {
    param([string]$RelativePath)
    $prefix = 'Research/PilotRuns/Gate14Re-ME/load-qualification/'
    $normalized = ([string]$RelativePath).Replace('\', '/').TrimEnd('/')
    if (-not $normalized.StartsWith($prefix, [StringComparison]::Ordinal)) { return $false }
    $leaf = $normalized.Substring($prefix.Length)
    if (-not $leaf.StartsWith('attempt-', [StringComparison]::Ordinal)) { return $false }
    if ($leaf.Length -eq 'attempt-'.Length -or $leaf.Contains('/')) { return $false }
    return $leaf.Substring('attempt-'.Length) -cmatch '^[0-9]+$'
}

$projectRootFull = [IO.Path]::GetFullPath($ProjectRoot)
$unityFull = [IO.Path]::GetFullPath($UnityExecutable)
$attemptRoot = Join-Path $projectRootFull 'Research/Verification/Gate14Re-ME/qualification-measured-root-binding-corrigendum-attempt-001'
$runnerPath = Join-Path $projectRootFull 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs'
$logPath = Join-Path $attemptRoot 'unity-compile.log'
$receiptPath = Join-Path $attemptRoot 'unity-compile-identity-receipt.v1.json'
$knownAnswerPath = Join-Path $attemptRoot 'root-binding-known-answer.v1.json'

Require-Condition (Test-Path -LiteralPath $attemptRoot -PathType Container) 'Corrigendum evidence directory is missing.'
Require-Condition (-not (Test-Path -LiteralPath $logPath)) 'Compile log already exists; this compile invocation is single-use.'
Require-Condition (-not (Test-Path -LiteralPath $receiptPath)) 'Compile receipt already exists; this compile invocation is single-use.'
Require-Condition (-not (Test-Path -LiteralPath $knownAnswerPath)) 'Known-answer receipt already exists.'
Require-Condition ((Get-Sha256Lower -Path $unityFull) -ceq $expectedUnitySha256) 'Unity executable hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $runnerPath) -ceq $RunnerSha256) 'Runner source hash mismatch.'
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process is already active.'

$cases = @(
    [ordered]@{ id = 'allowed-attempt-003'; value = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003'; expected = $true },
    [ordered]@{ id = 'allowed-attempt-004'; value = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-004'; expected = $true },
    [ordered]@{ id = 'allowed-attempt-10'; value = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-10'; expected = $true },
    [ordered]@{ id = 'reject-parent'; value = 'Research/PilotRuns/Gate14Re-ME/load-qualification'; expected = $false },
    [ordered]@{ id = 'reject-empty-leaf'; value = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-'; expected = $false },
    [ordered]@{ id = 'reject-nondigit'; value = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-x'; expected = $false },
    [ordered]@{ id = 'reject-nested'; value = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003/nested'; expected = $false },
    [ordered]@{ id = 'reject-formal-root'; value = 'Research/FormalRuns/Gate14Re-ME/attempt-003'; expected = $false }
)
foreach ($case in $cases) {
    $case['observed'] = Test-ReservedAttemptPath -RelativePath ([string]$case.value)
    $case['passed'] = ([bool]$case.observed -eq [bool]$case.expected)
}
Require-Condition (@($cases | Where-Object { -not [bool]$_.passed }).Count -eq 0) 'Root-binding offline known-answer failed.'
$knownAnswer = [ordered]@{
    schema = 'gate14re-me-qualification-measured-root-binding-known-answer-v1'
    studyId = 'Gate14Re-ME'
    authorizationId = $authorizationId
    attemptId = $attemptId
    status = 'PASS_ROOT_BINDING_SCOPE_KNOWN_ANSWER'
    passed = $true
    cases = $cases
    runnerSha256 = $RunnerSha256
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($knownAnswerPath, ($knownAnswer | ConvertTo-Json -Depth 20) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

$preUnitySha = Get-Sha256Lower -Path $unityFull
$arguments = @('-batchmode', '-nographics', '-quit', '-projectPath', $projectRootFull, '-logFile', $logPath)
$process = Start-Process -FilePath $unityFull -ArgumentList $arguments -WindowStyle Hidden -PassThru
$metadata = $null
$metadataDeadline = [DateTime]::UtcNow.AddSeconds(30)
while ($null -eq $metadata -and [DateTime]::UtcNow -lt $metadataDeadline) {
    $metadata = Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)" -ErrorAction SilentlyContinue
    if ($null -eq $metadata) { Start-Sleep -Milliseconds 100 }
}
Require-Condition ($null -ne $metadata) 'Unable to capture Unity process metadata.'
Require-Condition ([IO.Path]::GetFullPath([string]$metadata.ExecutablePath) -ieq $unityFull) 'Live Unity executable path mismatch.'
$commandLine = [string]$metadata.CommandLine
Require-Condition ($commandLine.Contains($projectRootFull) -and $commandLine.Contains($logPath) -and $commandLine.Contains('-batchmode')) 'Unity command line is not the exact compile-only invocation.'
Require-Condition (-not $commandLine.Contains('-executeMethod')) 'Compile-only invocation unexpectedly contains an execute method.'

$creationValue = $metadata.CreationDate
$creationDateTime = if ($creationValue -is [DateTime]) {
    [DateTime]$creationValue
} else {
    [Management.ManagementDateTimeConverter]::ToDateTime([string]$creationValue)
}
$creationUtc = $creationDateTime.ToUniversalTime().ToString('o')
$process.WaitForExit()
$exitCode = $process.ExitCode
Require-Condition ($exitCode -eq 0) "Unity compile-only invocation exited with code $exitCode."
$postUnitySha = Get-Sha256Lower -Path $unityFull
Require-Condition ($postUnitySha -ceq $preUnitySha -and $postUnitySha -ceq $expectedUnitySha256) 'Unity executable changed during compilation.'

$editorAssembly = Join-Path $projectRootFull 'Library/ScriptAssemblies/Assembly-CSharp-Editor.dll'
$runtimeAssembly = Join-Path $projectRootFull 'Library/ScriptAssemblies/Assembly-CSharp.dll'
Require-Condition (Test-Path -LiteralPath $editorAssembly -PathType Leaf) 'Compiled editor assembly is missing.'
Require-Condition (Test-Path -LiteralPath $runtimeAssembly -PathType Leaf) 'Compiled runtime assembly is missing.'

$receipt = [ordered]@{
    schema = 'gate14re-me-qualification-root-binding-compile-identity-receipt-v1'
    studyId = 'Gate14Re-ME'
    authorizationId = $authorizationId
    attemptId = $attemptId
    status = 'PASS_COMPILE_ONLY_NATURAL_EXIT'
    passed = $true
    algorithmCodeInvoked = $false
    qualificationObservationProduced = $false
    formalObservationProduced = $false
    unity = [ordered]@{
        path = $unityFull.Replace('\', '/')
        sha256 = $postUnitySha
        processId = [int]$metadata.ProcessId
        creationTimeUtc = $creationUtc
        executablePath = ([string]$metadata.ExecutablePath).Replace('\', '/')
        commandLine = $commandLine
        exitCode = $exitCode
        naturalExitObserved = $true
        signalOrForcedTerminationSent = $false
    }
    runner = [ordered]@{
        relativePath = 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs'
        sha256 = $RunnerSha256
        bytes = [int64](Get-Item -LiteralPath $runnerPath).Length
    }
    compiledAssemblies = @(
        [ordered]@{ relativePath = 'Library/ScriptAssemblies/Assembly-CSharp-Editor.dll'; sha256 = Get-Sha256Lower -Path $editorAssembly; bytes = [int64](Get-Item -LiteralPath $editorAssembly).Length },
        [ordered]@{ relativePath = 'Library/ScriptAssemblies/Assembly-CSharp.dll'; sha256 = Get-Sha256Lower -Path $runtimeAssembly; bytes = [int64](Get-Item -LiteralPath $runtimeAssembly).Length }
    )
    rootBindingKnownAnswerSha256 = Get-Sha256Lower -Path $knownAnswerPath
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 20) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output ($receipt | ConvertTo-Json -Depth 20 -Compress)
