[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [System.IO.Path]::IsPathRooted($ProjectPath)) { throw 'Attempt 2 requires an explicit absolute ProjectPath.' }
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RAttempt2PreflightV2|' + $ProjectPath); exit 0 }

$researchPath = Join-Path $ProjectPath 'Research'
$verificationPath = Join-Path $researchPath 'Verification'
$root = Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v2'
$modulePath = Join-Path $researchPath 'Gate10RProcessReusePreparation.psm1'
$configPath = Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt2_Config.v2.json'
$provenancePath = Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt2_Provenance.v2.json'
$authorizationPath = Join-Path $researchPath 'Gate10R_Attempt2_Execution_Authorization.v1.json'
$attempt1ManifestPath = Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v1\Gate10R_Attempt1_Partial_Output_Manifest.v1.json'
$formalRoot = Join-Path $researchPath 'FormalRuns\Gate13R_ProcessReuse_5pct\v1'
$lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$nativePowerShellModulePath = @(
    'C:\Users\bdscy\Documents\WindowsPowerShell\Modules',
    'C:\Program Files\WindowsPowerShell\Modules',
    'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
) -join ';'

if (Test-Path -LiteralPath $root) { throw "Attempt-2 verification root already exists before preflight; refusing retry/overwrite: $root" }
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw 'Gate 10R preparation module is missing.' }
Import-Module $modulePath -Force

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:checks.Add([pscustomobject][ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
}

$entryPoints = @(
    [pscustomobject]@{ relativePath = 'Research/Verification/Run-Gate10RAttempt2PreflightV2.ps1'; arguments = @('-ProjectPath', $ProjectPath, '-BindingSmokeOnly'); marker = 'Run-Gate10RAttempt2PreflightV2' },
    [pscustomobject]@{ relativePath = 'Research/Verification/Run-Gate10RUnitTestsV2.ps1'; arguments = @('-ProjectPath', $ProjectPath, '-BindingSmokeOnly'); marker = 'Run-Gate10RUnitTestsV2' },
    [pscustomobject]@{ relativePath = 'Research/Verification/Run-Gate10RCompileV2.ps1'; arguments = @('-ProjectPath', $ProjectPath, '-BindingSmokeOnly'); marker = 'Run-Gate10RCompileV2' },
    [pscustomobject]@{ relativePath = 'Research/Verification/Run-Gate10RBlockVerificationV2.ps1'; arguments = @('-ProjectPath', $ProjectPath, '-BindingSmokeOnly'); marker = 'Run-Gate10RBlockVerificationV2' },
    [pscustomobject]@{ relativePath = 'Research/Verification/Run-Gate10RRetainedRegressionV2.ps1'; arguments = @('-ProjectPath', $ProjectPath, '-BindingSmokeOnly'); marker = 'Run-Gate10RRetainedRegressionV2' },
    [pscustomobject]@{ relativePath = 'Research/Verification/Run-Gate10RFinalAuditV2.ps1'; arguments = @('-ProjectPath', $ProjectPath, '-BindingSmokeOnly'); marker = 'Run-Gate10RFinalAuditV2' },
    [pscustomobject]@{ relativePath = 'Research/Run-Gate10RTelemetryProbeV2.ps1'; arguments = @('-ProjectPath', $ProjectPath, '-BindingSmokeOnly'); marker = 'Run-Gate10RTelemetryProbeV2' },
    [pscustomobject]@{ relativePath = 'Research/Run-Gate10RProcessReuseBlockV2.ps1'; arguments = @('-ProjectPath', $ProjectPath, '-BlockPlanPath', 'binding-smoke.block-plan.json', '-OutputDirectory', 'H:\DDM_Final_Project\Research\Verification\binding-smoke-block', '-BindingSmokeOnly'); marker = 'Run-Gate10RProcessReuseBlockV2' },
    [pscustomobject]@{ relativePath = 'Research/Run-Gate10RColdReferenceV2.ps1'; arguments = @('-ProjectPath', $ProjectPath, '-ScenarioPath', 'H:\DDM_Final_Project\binding-smoke.scenario.json', '-OutputDirectory', 'H:\DDM_Final_Project\Research\Verification\binding-smoke-cold', '-RunId', 'binding-smoke', '-Algorithm', 'A*-R', '-BindingSmokeOnly'); marker = 'Run-Gate10RColdReferenceV2' }
)

Add-Check 'project-path-explicit-absolute' ([System.IO.Path]::IsPathRooted($ProjectPath) -and $ProjectPath -eq [System.IO.Path]::GetFullPath($ProjectPath)) $ProjectPath
Add-Check 'v2-root-absent-before-smoke' (-not (Test-Path -LiteralPath $root)) $root
Add-Check 'unity-zero-before-smoke' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) ([string]@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count)
Add-Check 'project-lock-absent-before-smoke' (-not (Test-Path -LiteralPath $lockPath)) $lockPath
Add-Check 'formal-root-absent' (-not (Test-Path -LiteralPath $formalRoot)) $formalRoot
Add-Check 'windows-powershell-5.1-exists' (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf) $windowsPowerShell

foreach ($entry in $entryPoints) {
    $path = Join-Path $ProjectPath ([string]$entry.relativePath).Replace('/', '\')
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    Add-Check ('parser-' + [IO.Path]::GetFileName($path)) ($parseErrors.Count -eq 0) ($parseErrors -join '; ')
    $text = [IO.File]::ReadAllText($path)
    $forbiddenDefault = [regex]::IsMatch($text, '(?im)ProjectPath\s*=.*PSScriptRoot')
    Add-Check ('no-psscriptroot-param-default-' + [IO.Path]::GetFileName($path)) (-not $forbiddenDefault) $(if ($forbiddenDefault) { 'forbidden default found' } else { 'none' })
}

$previousModulePath = $env:PSModulePath
try {
    $env:PSModulePath = $nativePowerShellModulePath
    foreach ($entry in $entryPoints) {
        $path = Join-Path $ProjectPath ([string]$entry.relativePath).Replace('/', '\')
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path) + @($entry.arguments)
        $output = @(& $windowsPowerShell @arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = [int]$LASTEXITCODE
        $joined = $output -join "`n"
        $markerFound = $joined.Contains('BINDING-SMOKE-PASSED|' + [string]$entry.marker + '|' + $ProjectPath)
        Add-Check ('binding-smoke-' + [IO.Path]::GetFileName($path)) ($exitCode -eq 0 -and $markerFound) ("exit={0};marker={1}" -f $exitCode, $markerFound)
        Add-Check ('v2-root-absent-after-smoke-' + [IO.Path]::GetFileName($path)) (-not (Test-Path -LiteralPath $root)) $root
    }
}
finally {
    $env:PSModulePath = $previousModulePath
}

$outputIsolationChecks = @(
    [pscustomobject]@{ path = Join-Path $researchPath 'Run-Gate10RProcessReuseBlockV2.ps1'; required = 'Research\Verification\Gate10R_ProcessReuse_5pct\v2\Fixtures'; forbidden = 'Research\Verification\Gate10R_ProcessReuse_5pct\v1\Fixtures' },
    [pscustomobject]@{ path = Join-Path $researchPath 'Run-Gate10RTelemetryProbeV2.ps1'; required = 'Research\Verification\Gate10R_ProcessReuse_5pct\v2'; forbidden = 'Research\Verification\Gate10R_ProcessReuse_5pct\v1' },
    [pscustomobject]@{ path = Join-Path $researchPath 'Run-Gate10RColdReferenceV2.ps1'; required = 'Research\Verification\Gate10R_ProcessReuse_5pct\v2\Fixtures'; forbidden = 'Research\Verification\Gate10R_ProcessReuse_5pct\v1\Fixtures' },
    [pscustomobject]@{ path = Join-Path $verificationPath 'Run-Gate10RUnitTestsV2.ps1'; required = 'Gate10R_ProcessReuse_5pct\v2'; forbidden = "Join-Path `$PSScriptRoot 'Gate10R_ProcessReuse_5pct\v1'" },
    [pscustomobject]@{ path = Join-Path $verificationPath 'Run-Gate10RCompileV2.ps1'; required = 'Gate10R_ProcessReuse_5pct\v2\Compile'; forbidden = 'Gate10R_ProcessReuse_5pct\v1\Compile' },
    [pscustomobject]@{ path = Join-Path $verificationPath 'Run-Gate10RBlockVerificationV2.ps1'; required = 'Gate10R_ProcessReuse_5pct\v2\Fixtures'; forbidden = 'Gate10R_ProcessReuse_5pct\v1\Fixtures' },
    [pscustomobject]@{ path = Join-Path $verificationPath 'Run-Gate10RRetainedRegressionV2.ps1'; required = 'Gate10R_ProcessReuse_5pct\v2\RetainedRegression'; forbidden = 'Gate10R_ProcessReuse_5pct\v1\RetainedRegression' },
    [pscustomobject]@{ path = Join-Path $verificationPath 'Run-Gate10RFinalAuditV2.ps1'; required = 'Gate10R_ProcessReuse_5pct\v2'; forbidden = "Join-Path `$PSScriptRoot 'Gate10R_ProcessReuse_5pct\v1'" }
)
foreach ($isolation in $outputIsolationChecks) {
    $text = [IO.File]::ReadAllText([string]$isolation.path)
    Add-Check ('output-isolation-' + [IO.Path]::GetFileName([string]$isolation.path)) ($text.Contains([string]$isolation.required) -and -not $text.Contains([string]$isolation.forbidden)) ([string]$isolation.required)
}

$attempt1Manifest = Read-Gate10RJson -Path $attempt1ManifestPath
$attempt1Mismatch = New-Object System.Collections.Generic.List[string]
foreach ($artifact in @($attempt1Manifest.artifacts)) {
    $path = Join-Path $ProjectPath ([string]$artifact.relativePath).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $attempt1Mismatch.Add('missing:' + [string]$artifact.relativePath) }
    elseif ((Get-Gate10RLowerSha256 -Path $path) -ne [string]$artifact.sha256) { $attempt1Mismatch.Add('hash:' + [string]$artifact.relativePath) }
}
Add-Check 'attempt1-manifest-artifacts-byte-identical' ($attempt1Mismatch.Count -eq 0 -and [int]$attempt1Manifest.artifactCount -eq 18) ($attempt1Mismatch -join '; ')
$attempt1Root = Split-Path -Parent $attempt1ManifestPath
$attempt1Expected = [ordered]@{
    'Attempt1-UnitGate-Failure.stderr.log' = 'ed11b29ab0e7331007a1ec30f1471fb28cf185924de006981ca7895db954f479'
    'Gate10R_Attempt1_Failure_Receipt.v1.json' = 'a1d501c72fa1e1a21f041c9cb7c73967b85e0dafbe2b74fe1cf83d003613917a'
    'Gate10R_Attempt1_Partial_Output_Manifest.v1.json' = '9dc16acfc7bab0f72d621fd6620f83235411e3afa6d9138fbde1445f87ff138e'
    'gate10r-checkpoint.json' = '069272d95443a4e4ef1aa2ddf8fe15147150e6d811ee95fa5e64f8d10dfda65a'
}
$attempt1RootPassed = @(Get-ChildItem -LiteralPath $attempt1Root -File -Force).Count -eq 4
foreach ($name in $attempt1Expected.Keys) {
    $path = Join-Path $attempt1Root $name
    $attempt1RootPassed = $attempt1RootPassed -and (Test-Path -LiteralPath $path -PathType Leaf) -and ((Get-Gate10RLowerSha256 -Path $path) -eq [string]$attempt1Expected[$name])
}
Add-Check 'attempt1-root-byte-identical' $attempt1RootPassed 'four frozen evidence files'

$config = Read-Gate10RJson -Path $configPath
$provenance = Read-Gate10RJson -Path $provenancePath
$authorization = Read-Gate10RJson -Path $authorizationPath
Add-Check 'attempt2-config-identity' ([int]$config.attempt -eq 2 -and [string]$config.designId -eq 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1' -and [string]$config.verificationRoot -eq 'Research/Verification/Gate10R_ProcessReuse_5pct/v2') ([string]$config.configId)
Add-Check 'attempt2-provenance-identity' ([int]$provenance.attempt -eq 2 -and [string]$provenance.designId -eq [string]$config.designId -and $provenance.formalCampaign -eq $false) ([string]$provenance.provenanceId)
Add-Check 'attempt2-authorization-identity' ([int]$authorization.attempt -eq 2 -and [string]$authorization.status -eq 'AUTHORIZED-ONE-ATTEMPT' -and $authorization.gate13RFormalCampaignAuthorized -eq $false) ([string]$authorization.authorizationId)

$boundRefs = @(
    $provenance.specification, $provenance.testDesign, $provenance.baseConfig, $provenance.config,
    $provenance.executionAuthorization, $provenance.authorizationSource, $provenance.preWritePreservationAudit,
    $provenance.unityCommand, $provenance.unityCommandMeta, $provenance.preparationModule,
    $provenance.blockRunner, $provenance.telemetryProbeRunner, $provenance.coldReferenceRunner,
    $provenance.preflightRunner, $provenance.unitTestRunner, $provenance.compileRunner,
    $provenance.blockVerificationRunner, $provenance.retainedRegressionRunner, $provenance.finalAuditRunner
)
$bindingErrors = New-Object System.Collections.Generic.List[string]
foreach ($reference in $boundRefs) {
    $path = Join-Path $ProjectPath ([string]$reference.relativePath).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $bindingErrors.Add('missing:' + [string]$reference.relativePath) }
    elseif ((Get-Gate10RLowerSha256 -Path $path) -ne [string]$reference.sha256) { $bindingErrors.Add('hash:' + [string]$reference.relativePath) }
}
Add-Check 'attempt2-provenance-file-bindings' ($bindingErrors.Count -eq 0) ($bindingErrors -join '; ')
Add-Check 'unity-binary-bound' ((Get-Gate10RLowerSha256 -Path ([string]$config.unityExecutable).Replace('/', '\')) -eq [string]$provenance.unity.sha256) ([string]$provenance.unity.sha256)
Add-Check 'unity-zero-after-smoke' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) ([string]@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count)
Add-Check 'project-lock-absent-after-smoke' (-not (Test-Path -LiteralPath $lockPath)) $lockPath
Add-Check 'gate11-root-still-absent' (-not (Test-Path -LiteralPath (Join-Path $researchPath 'FormalScenarios\Gate11R_5pct\v1'))) 'absent'
Add-Check 'gate12-root-still-absent' (-not (Test-Path -LiteralPath (Join-Path $researchPath 'PilotRuns\Gate12R_ProcessReuse_5pct\v1'))) 'absent'
Add-Check 'gate13-root-still-absent' (-not (Test-Path -LiteralPath $formalRoot)) 'absent'

$failed = @($checks | Where-Object { -not $_.passed })
[void](New-Item -ItemType Directory -Path $root)
$summaryPath = Join-Path $root 'Gate10R_Attempt2_Preflight.summary.v2.json'
$checkpointPath = Join-Path $root 'gate10r-preflight-checkpoint.v2.json'
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate10r-attempt2-windows-powershell51-preflight-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    attempt = 2
    designId = [string]$config.designId
    entryPointCount = $entryPoints.Count
    assertionCount = $checks.Count
    passedCount = $checks.Count - $failed.Count
    failedCount = $failed.Count
    checks = $checks.ToArray()
    unityStarted = $false
    formalCampaign = $false
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    passed = $failed.Count -eq 0
}
Write-Gate10RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 50
$checkpoint = [ordered]@{
    schemaVersion = 1
    checkpointKind = 'gate10r-attempt2-preflight-checkpoint-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = if ($summary.passed) { 'GATE10R-ATTEMPT2-PREFLIGHT-PASSED-READY-FOR-ONE-OFFICIAL-EXECUTION' } else { 'GATE10R-ATTEMPT2-PREFLIGHT-FAILED-NO-AUTO-RETRY' }
    attempt = 2
    summaryRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $summaryPath
    summarySha256 = Get-Gate10RLowerSha256 -Path $summaryPath
    unityStarted = $false
    officialExecutionCount = 0
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    gate13RFormalCampaignAuthorized = $false
}
Write-Gate10RAtomicUtf8NoBomJson -Path $checkpointPath -Value $checkpoint -Depth 20
if (-not $summary.passed) { Write-Error "Gate 10R attempt-2 preflight failed: $($failed.name -join ', ')"; exit 1 }
Write-Host "Gate 10R attempt-2 preflight passed: $($checks.Count)/$($checks.Count); Unity was not started." -ForegroundColor Green
exit 0
