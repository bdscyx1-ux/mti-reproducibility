[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$VerificationRoot,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'Gate 13R-PR2 formal Unity self-tests require an explicit absolute ProjectPath.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2FormalUnitySelfTestsV3|$ProjectPath"
    exit 0
}

$VerificationRoot = [IO.Path]::GetFullPath($VerificationRoot)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Prelaunch'))
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v1'
$formalReceipt = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v1.json'

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV3.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force

if (-not (Test-G13RPR2PathWithin -BasePath $verificationBase -CandidatePath $VerificationRoot)) {
    throw 'VerificationRoot is outside the Gate 13R-PR2 formal-prelaunch verification base.'
}
if (Test-Path -LiteralPath $VerificationRoot) {
    throw "Create-new Unity self-test verification root exists: $VerificationRoot"
}
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) {
    throw "Unity executable is absent: $UnityPath"
}
if ((Test-Path -LiteralPath $formalRoot) -or (Test-Path -LiteralPath $formalReceipt)) {
    throw 'Formal root and formal receipt must remain absent during Unity self-tests.'
}
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) {
    throw 'Unity must be quiescent before Gate 13R-PR2 formal Unity self-tests.'
}

New-Item -ItemType Directory -Path $VerificationRoot | Out-Null

function Invoke-Gate13RPR2UnitySelfTestProcess {
    param(
        [Parameter(Mandatory = $true)][string]$TestId,
        [Parameter(Mandatory = $true)][string]$ExecuteMethod,
        [Parameter(Mandatory = $true)][string]$OptionName,
        [Parameter(Mandatory = $true)][string]$ResultFileName
    )

    $outputDirectory = Join-Path $VerificationRoot $TestId
    $unityLog = $outputDirectory + '.Unity.log'
    $stdoutPath = $outputDirectory + '.stdout.log'
    $stderrPath = $outputDirectory + '.stderr.log'
    $summaryPath = $outputDirectory + '.wrapper-summary.json'
    $started = [DateTime]::UtcNow
    $arguments = @(
        '-batchmode', '-nographics', '-quit',
        '-projectPath', ('"' + $ProjectPath + '"'),
        '-executeMethod', $ExecuteMethod,
        $OptionName, ('"' + $outputDirectory + '"'),
        '-logFile', ('"' + $unityLog + '"')
    )

    $process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $timedOut = $false
    while (-not $process.HasExited) {
        if ([DateTime]::UtcNow -ge $deadline) {
            $timedOut = $true
            break
        }
        Start-Sleep -Milliseconds 250
        $process.Refresh()
    }
    if ($timedOut) {
        & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
        try { Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue } catch { }
    }
    try { $process.Refresh() } catch { }
    $processId = [int]$process.Id
    $exitCode = if ($timedOut) { 124 } elseif ($process.HasExited) { [int]$process.ExitCode } else { 125 }
    $completed = [DateTime]::UtcNow

    $lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $processId -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'positive' -EvidenceDirectory ($outputDirectory + '.lock-hygiene') -ContextId ("gate13r-pr2-formal-self-test-$TestId") -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
    $logText = if (Test-Path -LiteralPath $unityLog -PathType Leaf) { Read-G13RPR2TextWithRetry -Path $unityLog -TimeoutMilliseconds 30000 -PollMilliseconds 250 } else { '' }
    $compilerMatches = if ($logText.Length -gt 0) { @($logText | Select-String -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -AllMatches -CaseSensitive:$false) } else { @() }
    $serialAssigned = $logText.Contains('Serial number assigned to:')
    $noValidLicense = $logText.Contains('No valid Unity Editor license found')
    $inactiveHeadless = $logText.Contains('License is not active (com.unity.editor.headless)')
    $resultPath = Join-Path $outputDirectory $ResultFileName
    $result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Read-G13RPR2Json $resultPath } else { $null }
    $errors = New-Object Collections.Generic.List[string]
    if ($timedOut) { $errors.Add('timeout') }
    if ($exitCode -ne 0) { $errors.Add("unity-exit-$exitCode") }
    if (@($compilerMatches).Count -gt 0) { $errors.Add("compiler-$(@($compilerMatches).Count)") }
    if (-not $serialAssigned -or $noValidLicense -or $inactiveHeadless) { $errors.Add('license-entitlement') }
    if ($null -eq $lock -or $lock.passed -ne $true -or [string]$lock.mode -ne 'natural-lock-absence') { $errors.Add('lock-hygiene') }
    if ($null -eq $result) { $errors.Add('result-missing') }

    if ($TestId -eq 'MemoryPolicySelfTest' -and $null -ne $result) {
        if ($result.passed -ne $true -or [int]$result.testCount -ne 12 -or [int]$result.passedTestCount -ne 12 -or [int]$result.telemetryValidationTestCount -ne 8 -or [int]$result.telemetryValidationPassedTestCount -ne 8) {
            $errors.Add('memory-policy-fixtures')
        }
    }
    if ($TestId -eq 'PathSafeAtomicSelfTest' -and $null -ne $result) {
        if ($result.passed -ne $true -or [int]$result.testCount -lt 14 -or [int]$result.testCount -ne [int]$result.passedTestCount -or [int]$result.residualOwnedTemporaryFileCount -ne 0) {
            $errors.Add('path-safe-atomic-fixtures')
        }
        $idff = @($result.tests | Where-Object id -eq 'idff-v6-legacy-temp-260')
        $cff = @($result.tests | Where-Object id -eq 'cff-position-legacy-temp-259')
        $long = @($result.tests | Where-Object id -eq 'legacy-temp-280')
        if ($idff.Count -ne 1 -or [int]$idff[0].legacyTemporaryPathLength -ne 260 -or $idff[0].actualLegacySuccess -ne $false -or $idff[0].pathSafeSuccess -ne $true -or [int]$idff[0].pathSafeTemporaryPathLength -ge 260) { $errors.Add('path-safe-260-boundary') }
        if ($cff.Count -ne 1 -or [int]$cff[0].legacyTemporaryPathLength -ne 259 -or $cff[0].actualLegacySuccess -ne $true -or $cff[0].pathSafeSuccess -ne $true) { $errors.Add('path-safe-259-boundary') }
        if ($long.Count -ne 1 -or $long[0].pathSafeSuccess -ne $true) { $errors.Add('path-safe-long-boundary') }
    }

    $summary = [ordered]@{
        schemaVersion = 1
        summaryKind = 'gate13r-pr2-formal-unity-self-test-wrapper-v3'
        testId = $TestId
        executeMethod = $ExecuteMethod
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        unityProcessId = $processId
        exitCode = $exitCode
        timedOut = $timedOut
        wallSeconds = ($completed - $started).TotalSeconds
        resultRelativePath = if ($null -ne $result) { Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $resultPath } else { $null }
        resultSha256 = if ($null -ne $result) { Get-G13RPR2Sha256 $resultPath } else { $null }
        unityLogSha256 = if (Test-Path -LiteralPath $unityLog -PathType Leaf) { Get-G13RPR2Sha256 $unityLog } else { $null }
        lockHygieneMode = if ($null -ne $lock) { [string]$lock.mode } else { $null }
        licenseSerialAssigned = $serialAssigned
        noValidLicenseError = $noValidLicense
        inactiveHeadlessLicenseError = $inactiveHeadless
        formalCampaign = $false
        measuredSampleCreated = $false
        excludedFromFormalAnalysis = $true
        errors = $errors.ToArray()
        passed = $errors.Count -eq 0
    }
    Write-G13RPR2AtomicJson -Path $summaryPath -Value $summary -Depth 30
    return [pscustomobject]@{ Passed = ($errors.Count -eq 0); Summary = $summary; SummaryPath = $summaryPath }
}

$memory = Invoke-Gate13RPR2UnitySelfTestProcess -TestId 'MemoryPolicySelfTest' -ExecuteMethod 'DDM.Research.Editor.Gate13RPR2FormalBatchCommandV2.RunMemoryPolicySelfTest' -OptionName '-ddmGate13RPR1BMemoryPolicyTestDirectory' -ResultFileName 'memory-policy-self-test.json'
if (-not $memory.Passed) {
    Write-Error ('Gate 13R-PR2 formal memory-policy self-test failed: ' + ($memory.Summary.errors -join '; '))
    exit 1
}

$pathSafe = Invoke-Gate13RPR2UnitySelfTestProcess -TestId 'PathSafeAtomicSelfTest' -ExecuteMethod 'DDM.Research.Editor.Gate13RPR2FormalBatchCommandV2.RunPathSafeAtomicSelfTest' -OptionName '-ddmGate13RPR1BPathSafeTestDirectory' -ResultFileName 'path-safe-atomic-self-test.json'
if (-not $pathSafe.Passed) {
    Write-Error ('Gate 13R-PR2 formal path-safe atomic self-test failed: ' + ($pathSafe.Summary.errors -join '; '))
    exit 1
}

$combined = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-formal-unity-self-tests-v3'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    formalCampaign = $false
    measuredSampleCreated = $false
    testCount = 2
    passedTestCount = 2
    memoryPolicySummarySha256 = Get-G13RPR2Sha256 $memory.SummaryPath
    pathSafeAtomicSummarySha256 = Get-G13RPR2Sha256 $pathSafe.SummaryPath
    passed = $true
}
Write-G13RPR2AtomicJson -Path (Join-Path $VerificationRoot 'unity-self-tests-summary.json') -Value $combined -Depth 20
Write-Host 'Gate 13R-PR2 formal Unity self-tests passed.' -ForegroundColor Green
exit 0
