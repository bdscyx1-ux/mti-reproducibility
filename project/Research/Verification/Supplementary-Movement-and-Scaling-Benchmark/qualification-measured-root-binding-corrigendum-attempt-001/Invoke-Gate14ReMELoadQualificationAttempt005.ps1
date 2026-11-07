param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Get-Sha256Lower {
    param([string]$Path)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required file is missing: $Path"
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-TextSha256Lower {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite evidence: $Path"
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$evidenceRoot = Join-Path $root 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-005'
$launchContractPath = Join-Path $evidenceRoot 'launch-contract.v1.json'
$externalLaunchReceiptPath = Join-Path $evidenceRoot 'external-launch-receipt.v1.json'
$terminalObservationPath = Join-Path $evidenceRoot 'external-terminal-observation.v1.json'
$launcherFailurePath = Join-Path $evidenceRoot 'external-launcher-failure-receipt.v1.json'
$process = $null

try {
    Require-Condition (Test-Path -LiteralPath $evidenceRoot -PathType Container) 'Execution evidence root is missing.'
    Require-Condition (-not (Test-Path -LiteralPath $externalLaunchReceiptPath)) 'External launch receipt already exists.'
    Require-Condition (-not (Test-Path -LiteralPath $terminalObservationPath)) 'External terminal observation already exists.'
    $contract = Get-Content -LiteralPath $launchContractPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
    Require-Condition ($contract.status -eq 'FROZEN_EXTERNAL_LAUNCH_CONTRACT' -and $contract.attemptId -eq 'load-qualification-execution-attempt-005') 'Launch contract header is invalid.'
    $hostPath = [IO.Path]::GetFullPath([string]$contract.executable.path)
    Require-Condition ((Get-Sha256Lower -Path $hostPath) -ceq [string]$contract.executable.sha256) 'PowerShell host hash mismatch.'
    $hostVersion = (& $hostPath -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()').Trim()
    Require-Condition ($hostVersion -ceq [string]$contract.executable.version) 'PowerShell host version mismatch.'
    $arguments = @($contract.argumentVector | ForEach-Object { [string]$_ })
    Require-Condition ($arguments.Count -eq [int]$contract.argumentCount) 'Argument count mismatch.'
    $canonicalArguments = $arguments | ConvertTo-Json -Compress
    Require-Condition ((Get-TextSha256Lower -Text $canonicalArguments) -ceq [string]$contract.argumentVectorSha256) 'Argument vector digest mismatch.'
    Require-Condition (-not (Test-Path -LiteralPath ([string]$contract.measuredRoot))) 'Measured root already exists.'
    Require-Condition (-not (Test-Path -LiteralPath ([string]$contract.deliveryRoot))) 'Delivery root already exists.'
    Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'Unity is already active.'
    $existingSupervisor = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'pwsh.exe' -and [string]$_.CommandLine -like '*Run-Gate14ReMELoadQualification.v3_3.ps1*' })
    Require-Condition ($existingSupervisor.Count -eq 0) 'A matching qualification supervisor is already active.'
    $stdoutPath = Join-Path $root ([string]$contract.stdoutRelativePath)
    $stderrPath = Join-Path $root ([string]$contract.stderrRelativePath)
    Require-Condition (-not (Test-Path -LiteralPath $stdoutPath) -and -not (Test-Path -LiteralPath $stderrPath)) 'Supervisor logs already exist.'

    $process = Start-Process -FilePath $hostPath -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $metadata = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ($null -eq $metadata -and [DateTime]::UtcNow -lt $deadline) {
        $metadata = Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)" -ErrorAction SilentlyContinue
        if ($null -eq $metadata) { Start-Sleep -Milliseconds 100 }
    }
    Require-Condition ($null -ne $metadata) 'Unable to capture supervisor process metadata.'
    Require-Condition ([IO.Path]::GetFullPath([string]$metadata.ExecutablePath) -ieq $hostPath) 'Supervisor executable path mismatch.'
    $commandLine = [string]$metadata.CommandLine
    Require-Condition ($commandLine.Contains('Run-Gate14ReMELoadQualification.v3_3.ps1') -and $commandLine.Contains('attempt-003') -and $commandLine.Contains([string]$contract.executionAuthorization.sha256)) 'Supervisor command line is not bound to the frozen launch contract.'
    $creationValue = $metadata.CreationDate
    $creationDateTime = if ($creationValue -is [DateTime]) { [DateTime]$creationValue } else { [Management.ManagementDateTimeConverter]::ToDateTime([string]$creationValue) }
    Write-JsonExclusive -Path $externalLaunchReceiptPath -Value ([ordered]@{
        schema = 'gate14re-me-load-qualification-external-launch-receipt-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = [string]$contract.authorizationId
        attemptId = [string]$contract.attemptId
        status = 'SUPERVISOR_LAUNCHED_EXACT_FROZEN_COMMAND'
        processId = [int]$metadata.ProcessId
        creationTimeUtc = $creationDateTime.ToUniversalTime().ToString('o')
        executablePath = ([string]$metadata.ExecutablePath).Replace('\', '/')
        executableSha256 = Get-Sha256Lower -Path $hostPath
        commandLine = $commandLine
        argumentVectorSha256 = [string]$contract.argumentVectorSha256
        launchContractSha256 = Get-Sha256Lower -Path $launchContractPath
        signalOrForcedTerminationAuthorized = $false
        launchedAtUtc = [DateTime]::UtcNow.ToString('o')
    })

    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $controlRoot = Join-Path ([string]$contract.measuredRoot) '_control'
    $candidateFiles = @('execution-status.v2.json','qualification-complete.v2.json','failure-receipt.v1.json','acquisition-complete.v2.json','structural-complete-receipt.v1.json','delivery-complete-receipt.v1.json')
    $terminalFiles = @($candidateFiles | ForEach-Object {
        $path = Join-Path $controlRoot $_
        if (Test-Path -LiteralPath $path -PathType Leaf) { [ordered]@{ name = $_; sha256 = Get-Sha256Lower -Path $path; bytes = [int64](Get-Item -LiteralPath $path).Length } }
    })
    Write-JsonExclusive -Path $terminalObservationPath -Value ([ordered]@{
        schema = 'gate14re-me-load-qualification-external-terminal-observation-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = [string]$contract.authorizationId
        attemptId = [string]$contract.attemptId
        status = if ($exitCode -eq 0) { 'SUPERVISOR_NATURAL_EXIT_ZERO' } else { 'SUPERVISOR_NATURAL_EXIT_NONZERO' }
        processId = [int]$metadata.ProcessId
        exitCode = $exitCode
        naturalExitObserved = $true
        signalOrForcedTerminationSent = $false
        measuredRootExists = Test-Path -LiteralPath ([string]$contract.measuredRoot) -PathType Container
        deliveryRootExists = Test-Path -LiteralPath ([string]$contract.deliveryRoot) -PathType Container
        terminalControlFiles = $terminalFiles
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    exit $exitCode
}
catch {
    if ($null -ne $process -and -not $process.HasExited) {
        $process.WaitForExit()
    }
    if (-not (Test-Path -LiteralPath $launcherFailurePath)) {
        Write-JsonExclusive -Path $launcherFailurePath -Value ([ordered]@{
            schema = 'gate14re-me-load-qualification-external-launcher-failure-receipt-v1'
            studyId = 'Gate14Re-ME'
            attemptId = 'load-qualification-execution-attempt-005'
            status = 'FAIL_CLOSED_EXTERNAL_LAUNCHER'
            exactFailure = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
            supervisorProcessId = if ($null -ne $process) { $process.Id } else { $null }
            supervisorNaturalExitObserved = if ($null -ne $process) { $process.HasExited } else { $false }
            signalOrForcedTerminationSent = $false
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
        })
    }
    throw
}
