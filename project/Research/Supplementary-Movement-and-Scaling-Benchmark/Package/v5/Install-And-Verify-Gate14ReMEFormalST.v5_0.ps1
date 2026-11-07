[CmdletBinding()]
param(
    [string]$UnityExecutable,
    [string]$ReceiptRoot,
    [switch]$InstallUnityIfMissing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedUnitySha256 = '0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'
$expectedInstallerSha256 = 'f0d449732ac48e5058fb34b8fdc260daf90e15ef6c6b418d635796da0a448eaa'
$expectedPythonSha256 = '7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1'
$expectedPowerShellSha256 = '362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139'

function Require-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Get-Sha256Lower([string]$Path) {
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required file is missing: $Path"
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Hash([string]$Path, [string]$Expected, [string]$Label) {
    $actual = Get-Sha256Lower $Path
    Require-Condition ($actual -ceq $Expected) "$Label SHA-256 mismatch: expected=$Expected actual=$actual"
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Write-JsonExclusive([string]$Path, [object]$Value) {
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite receipt: $Path"
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent }
    $json = $Value | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Test-CredentialLikeRelativePath([string]$RelativePath) {
    $normalized = $RelativePath.Replace('\', '/')
    if ($normalized.EndsWith('/CREDENTIALS-NOT-INCLUDED.md', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    if ($normalized -in @(
        'MigrationRuntime/Python/Lib/secrets.py',
        'MigrationRuntime/Python/Lib/token.py',
        'MigrationRuntime/Python/Lib/lib2to3/pgen2/token.py'
    )) { return $false }
    if ($normalized -match '(?i)(^|/)(credentials?|secrets?|tokens?|passwords?|id_rsa|id_ed25519)([._/-]|$)') { return $true }
    if ($normalized -match '(?i)(^|/)\.env($|\.)') { return $true }
    if ($normalized -match '(?i)unity账号') { return $true }
    if ($normalized -match '(?i)\.(pem|key|pfx|p12|ulf|alf)$') { return $true }
    return $false
}

function Resolve-UnityExecutable([string]$ProjectRoot, [string]$Requested, [bool]$MayInstall) {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Requested)) { $candidates.Add($Requested) }
    if (-not [string]::IsNullOrWhiteSpace($env:GATE14RE_ME_UNITY)) { $candidates.Add($env:GATE14RE_ME_UNITY) }
    $candidates.Add((Join-Path $ProjectRoot 'UnityEditor/2022.3.30f1c1/Editor/Unity.exe'))
    $candidates.Add('H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe')
    $candidates.Add('C:/Program Files/Unity/Hub/Editor/2022.3.30f1c1/Editor/Unity.exe')
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $full = [System.IO.Path]::GetFullPath($candidate)
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                Assert-Hash $full $expectedUnitySha256 'Unity 2022.3.30f1c1 executable'
                return $full
            }
        }
    }

    Require-Condition $MayInstall 'The exact Unity editor is not installed. Re-run START-HERE.cmd or pass -InstallUnityIfMissing.'
    $installer = Join-Path $ProjectRoot 'installers/UnitySetup64-2022.3.30f1c1.exe'
    Assert-Hash $installer $expectedInstallerSha256 'bundled Unity installer'
    $installRoot = Join-Path $ProjectRoot 'UnityEditor/2022.3.30f1c1'
    Require-Condition (-not (Test-Path -LiteralPath $installRoot)) "Unity install target already exists but is incomplete: $installRoot"
    $process = Start-Process -FilePath $installer -ArgumentList @('/S', "/D=$installRoot") -Wait -PassThru
    Require-Condition ($process.ExitCode -eq 0) "Unity installer exited with code $($process.ExitCode)."
    $installed = Join-Path $installRoot 'Editor/Unity.exe'
    Assert-Hash $installed $expectedUnitySha256 'newly installed Unity executable'
    return $installed
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$manifestPath = Join-Path $projectRoot 'Research/Gate14Re-ME/Package/v5/package-manifest.v1.json'
$manifest = Read-Json $manifestPath
Require-Condition ($manifest.schema -eq 'gate14re-me-formal-st-v5-migration-package-manifest-v1' -and $manifest.status -eq 'FROZEN_PACKAGE_PAYLOAD_READY_FOR_VALIDATION_FORMAL_ST_NOT_STARTED') 'Package manifest header is invalid.'
Require-Condition ($manifest.formalCollectionStarted -eq $false -and $manifest.formalAnalysisStarted -eq $false -and $manifest.mqStarted -eq $false -and $manifest.mtStarted -eq $false) 'Package manifest exceeds the authorized boundary.'

$verifiedFiles = 0
$verifiedBytes = [int64]0
foreach ($entry in @($manifest.files)) {
    $relative = [string]$entry.relativePath
    Require-Condition (-not (Test-CredentialLikeRelativePath $relative)) "Credential-like path is prohibited: $relative"
    $full = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
    $prefix = $projectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    Require-Condition ($full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) "Manifest path escapes package root: $relative"
    Require-Condition (Test-Path -LiteralPath $full -PathType Leaf) "Manifest file is missing: $relative"
    Require-Condition ((Get-Item -LiteralPath $full).Length -eq [int64]$entry.bytes) "Manifest byte count mismatch: $relative"
    Assert-Hash $full ([string]$entry.sha256) "package file $relative"
    $verifiedFiles++
    $verifiedBytes += [int64]$entry.bytes
}
Require-Condition ($verifiedFiles -eq [int]$manifest.fileCount -and $verifiedBytes -eq [int64]$manifest.totalBytes) 'Package manifest aggregate mismatch.'

$credentialHits = @(
    Get-ChildItem -LiteralPath $projectRoot -Recurse -File | ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($projectRoot, $_.FullName).Replace('\', '/')
        if (Test-CredentialLikeRelativePath $relative) { $relative }
    }
)
Require-Condition ($credentialHits.Count -eq 0) "Credential-like files are present in the extracted package: $($credentialHits -join ', ')"

$python = Join-Path $projectRoot 'MigrationRuntime/Python/python.exe'
$bundledPowerShell = Join-Path $projectRoot 'MigrationRuntime/PowerShell/pwsh.exe'
$installerPath = Join-Path $projectRoot 'installers/UnitySetup64-2022.3.30f1c1.exe'
Assert-Hash $python $expectedPythonSha256 'bundled Python runtime'
Assert-Hash $bundledPowerShell $expectedPowerShellSha256 'bundled PowerShell runtime'
Assert-Hash $installerPath $expectedInstallerSha256 'bundled Unity installer'

$formalRuns = Join-Path $projectRoot 'Research/FormalRuns/Gate14Re-ME/formal-st/v5'
$formalInputs = Join-Path $projectRoot 'Research/FormalInputs/Gate14Re-ME/formal-st/v5'
Require-Condition (-not (Test-Path -LiteralPath $formalRuns)) 'Formal measured material exists before readiness.'
Require-Condition (-not (Test-Path -LiteralPath $formalInputs)) 'Formal input material exists before readiness.'
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process is already active; readiness requires an idle editor.'

if ([string]::IsNullOrWhiteSpace($ReceiptRoot)) {
    $ReceiptRoot = Join-Path $projectRoot ('PackageReadiness/attempt-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
}
$receiptRootFull = [System.IO.Path]::GetFullPath($ReceiptRoot)
Require-Condition (-not (Test-Path -LiteralPath $receiptRootFull)) 'Readiness receipt root must be fresh.'
$null = New-Item -ItemType Directory -Path $receiptRootFull

$knownAnswerRoot = Join-Path $receiptRootFull 'known-answer'
$knownAnswerTool = Join-Path $projectRoot 'Research/Gate14Re-ME/Tools/gate14re_me_formal_st_known_answer_v5.py'
$pyArrowRoot = Join-Path $projectRoot 'Research/Gate14Re-ME/Runtime/v1/python-packages'
& $python $knownAnswerTool --project-root $projectRoot --output-root $knownAnswerRoot --pyarrow-root $pyArrowRoot
Require-Condition ($LASTEXITCODE -eq 0) "Package known-answer test exited with code $LASTEXITCODE."
$knownAnswerTerminal = Join-Path $knownAnswerRoot 'terminal-receipt.v5.json'
$knownAnswer = Read-Json $knownAnswerTerminal
Require-Condition ($knownAnswer.status -eq 'PASS_FORMAL_ST_V5_PACKAGE_KNOWN_ANSWER_NO_FORMAL_EXECUTION') 'Package known-answer terminal is not PASS.'

$unity = Resolve-UnityExecutable -ProjectRoot $projectRoot -Requested $UnityExecutable -MayInstall $InstallUnityIfMissing.IsPresent
$unityLog = Join-Path $receiptRootFull 'unity-package-readiness.log'
$unityReceipt = Join-Path $receiptRootFull 'unity-package-readiness-terminal.v1.json'
$freezeIndex = Join-Path $projectRoot 'Research/Gate14Re-ME/Execution/v5/formal-st-freeze-index.v5_0.json'
$implementationManifest = Join-Path $projectRoot 'Research/Gate14Re-ME/Execution/v5/formal-st-implementation-manifest.v5_0.json'
$acquisitionContract = Join-Path $projectRoot 'Research/Gate14Re-ME/Execution/v5/formal-st-acquisition-contract.v5_0.json'
$acceptanceContract = Join-Path $projectRoot 'Research/Gate14Re-ME/Execution/v5/formal-st-independent-acceptance-contract.v5_0.json'
$buildAuthorization = Join-Path $projectRoot 'Research/Verification/Gate14Re-ME/formal-st-migration-package-build-attempt-003/package-build-authorization.v1.json'

$unityArguments = @(
    '-batchmode', '-nographics', '-quit', '-projectPath', $projectRoot,
    '-executeMethod', 'DDM.Research.Editor.Gate14ReMEFormalSTPackageReadinessV5.Run',
    '-logFile', $unityLog,
    '--g14me-readiness-output', $unityReceipt,
    '--g14me-package-manifest', $manifestPath,
    '--g14me-package-manifest-sha256', (Get-Sha256Lower $manifestPath),
    '--g14me-formal-freeze-index', $freezeIndex,
    '--g14me-formal-freeze-index-sha256', (Get-Sha256Lower $freezeIndex),
    '--g14me-implementation-manifest', $implementationManifest,
    '--g14me-implementation-manifest-sha256', (Get-Sha256Lower $implementationManifest),
    '--g14me-acquisition-contract', $acquisitionContract,
    '--g14me-acquisition-contract-sha256', (Get-Sha256Lower $acquisitionContract),
    '--g14me-acceptance-contract', $acceptanceContract,
    '--g14me-acceptance-contract-sha256', (Get-Sha256Lower $acceptanceContract),
    '--g14me-package-build-authorization', $buildAuthorization,
    '--g14me-package-build-authorization-sha256', (Get-Sha256Lower $buildAuthorization)
)
$unityProcess = Start-Process -FilePath $unity -ArgumentList $unityArguments -Wait -PassThru -WindowStyle Hidden
Require-Condition ($unityProcess.ExitCode -eq 0) "Unity package readiness did not exit naturally with code zero: $($unityProcess.ExitCode). See $unityLog"
Require-Condition (Test-Path -LiteralPath $unityReceipt -PathType Leaf) 'Unity package readiness terminal receipt is missing.'
$unityTerminal = Read-Json $unityReceipt
Require-Condition ($unityTerminal.status -eq 'PASS_ALGORITHM_FREE_PACKAGE_READINESS_FORMAL_ST_NOT_STARTED' -and [int]$unityTerminal.algorithmsInstantiated -eq 0) 'Unity package readiness terminal is not an algorithm-free PASS.'
Require-Condition (-not (Test-Path -LiteralPath $formalRuns) -and -not (Test-Path -LiteralPath $formalInputs)) 'Readiness created prohibited formal material.'

$terminal = [ordered]@{
    schema = 'gate14re-me-formal-st-v5-deployment-readiness-terminal-v1'
    status = 'PASS_MIGRATION_PACKAGE_INSTALL_AND_ALGORITHM_FREE_READINESS'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    packageRoot = $projectRoot.Replace('\', '/')
    packageManifestSha256 = Get-Sha256Lower $manifestPath
    verifiedFiles = $verifiedFiles
    verifiedBytes = $verifiedBytes
    credentialLikeFiles = 0
    credentialsReadOrCopied = $false
    unityExecutable = $unity.Replace('\', '/')
    unitySha256 = $expectedUnitySha256
    unityNaturalExitCode = 0
    pythonSha256 = $expectedPythonSha256
    powerShellSha256 = $expectedPowerShellSha256
    installerSha256 = $expectedInstallerSha256
    knownAnswerTerminalSha256 = Get-Sha256Lower $knownAnswerTerminal
    unityReadinessTerminalSha256 = Get-Sha256Lower $unityReceipt
    formalInputsCreated = 0
    formalScheduleRowsCreated = 0
    formalCollectionStarted = $false
    formalAnalysisStarted = $false
    mqStarted = $false
    mtStarted = $false
}
$terminalPath = Join-Path $receiptRootFull 'deployment-readiness-terminal.v1.json'
Write-JsonExclusive -Path $terminalPath -Value $terminal
Write-Output ($terminal | ConvertTo-Json -Depth 100 -Compress)
