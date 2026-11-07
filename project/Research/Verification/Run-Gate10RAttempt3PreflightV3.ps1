[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [System.IO.Path]::IsPathRooted($ProjectPath)) { throw 'Attempt 3 requires an explicit absolute ProjectPath.' }
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RAttempt3PreflightV3|' + $ProjectPath); exit 0 }

$researchPath = Join-Path $ProjectPath 'Research'
$verificationPath = Join-Path $researchPath 'Verification'
$root = Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v3'
$modulePath = Join-Path $researchPath 'Gate10RProcessReusePreparation.psm1'
$lockModulePath = Join-Path $researchPath 'Gate10RLockHygieneV3.psm1'
$configPath = Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt3_Config.v3.json'
$provenancePath = Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt3_Provenance.v3.json'
$authorizationPath = Join-Path $researchPath 'Gate10R_Attempt3_Execution_Authorization.v1.json'
$preservationPath = Join-Path $researchPath 'Gate10R_Attempt3_PreWrite_Preservation_Audit.v1.json'
$attempt2NegativeSummaryPath = Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v2\Fixtures\v1\negative-fail-closed.summary.json'
$lockPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Temp\UnityLockfile'))
$formalRoot = Join-Path $researchPath 'FormalRuns\Gate13R_ProcessReuse_5pct\v1'
$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$nativePowerShellModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules', 'C:\Program Files\WindowsPowerShell\Modules', 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'

if (Test-Path -LiteralPath $root) { throw "Attempt-3 verification root already exists before preflight; refusing retry/overwrite: $root" }
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf) -or -not (Test-Path -LiteralPath $lockModulePath -PathType Leaf)) { throw 'Gate 10R attempt-3 modules are missing.' }
Import-Module $modulePath -Force
Import-Module $lockModulePath -Force

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) { $script:checks.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail}) }
function Get-TreeIdentity([string]$Path) {
    $treeRoot = [System.IO.Path]::GetFullPath($Path)
    $files = @(Get-ChildItem -LiteralPath $treeRoot -Recurse -File -Force | Sort-Object FullName)
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($treeRoot.Length).TrimStart('\').Replace('\', '/')
        $rows.Add(("{0}`t{1}`t{2}" -f $relative, $file.Length, (Get-Gate10RLowerSha256 $file.FullName)))
    }
    [pscustomobject][ordered]@{fileCount=$files.Count;rawBytes=[long](($files | Measure-Object Length -Sum).Sum);treeSha256=Get-Gate10RStringSha256 ($rows -join "`n")}
}
function Get-TempIdentityExcludingLock {
    $tempRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Temp'))
    $files = @(Get-ChildItem -LiteralPath $tempRoot -Recurse -File -Force | Where-Object {-not [string]::Equals($_.FullName, $lockPath, [System.StringComparison]::OrdinalIgnoreCase)} | Sort-Object FullName)
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) { $rows.Add(("{0}`t{1}`t{2}" -f $file.FullName.Substring($tempRoot.Length).TrimStart('\').Replace('\','/'), $file.Length, (Get-Gate10RLowerSha256 $file.FullName))) }
    [pscustomobject][ordered]@{fileCount=$files.Count;rawBytes=[long](($files | Measure-Object Length -Sum).Sum);treeSha256=Get-Gate10RStringSha256 ($rows -join "`n")}
}

$entryPoints = @(
    [pscustomobject]@{relativePath='Research/Verification/Run-Gate10RAttempt3PreflightV3.ps1';arguments=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RAttempt3PreflightV3'},
    [pscustomobject]@{relativePath='Research/Verification/Run-Gate10RUnitTestsV3.ps1';arguments=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RUnitTestsV3'},
    [pscustomobject]@{relativePath='Research/Verification/Run-Gate10RCompileV3.ps1';arguments=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RCompileV3'},
    [pscustomobject]@{relativePath='Research/Verification/Run-Gate10RBlockVerificationV3.ps1';arguments=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RBlockVerificationV3'},
    [pscustomobject]@{relativePath='Research/Verification/Run-Gate10RRetainedRegressionV3.ps1';arguments=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RRetainedRegressionV3'},
    [pscustomobject]@{relativePath='Research/Verification/Run-Gate10RFinalAuditV3.ps1';arguments=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RFinalAuditV3'},
    [pscustomobject]@{relativePath='Research/Run-Gate10RTelemetryProbeV3.ps1';arguments=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RTelemetryProbeV3'},
    [pscustomobject]@{relativePath='Research/Run-Gate10RProcessReuseBlockV3.ps1';arguments=@('-ProjectPath',$ProjectPath,'-BlockPlanPath','binding-smoke.block-plan.json','-OutputDirectory','H:\DDM_Final_Project\Research\Verification\Gate10R_ProcessReuse_5pct\v3\Fixtures\binding-smoke-block','-BindingSmokeOnly');marker='Run-Gate10RProcessReuseBlockV3'},
    [pscustomobject]@{relativePath='Research/Run-Gate10RColdReferenceV3.ps1';arguments=@('-ProjectPath',$ProjectPath,'-ScenarioPath','H:\DDM_Final_Project\binding-smoke.scenario.json','-OutputDirectory','H:\DDM_Final_Project\Research\Verification\Gate10R_ProcessReuse_5pct\v3\Fixtures\binding-smoke-cold','-RunId','binding-smoke','-Algorithm','A*-R','-BindingSmokeOnly');marker='Run-Gate10RColdReferenceV3'}
)

Add-Check 'project-path-explicit-absolute' ([System.IO.Path]::IsPathRooted($ProjectPath) -and $ProjectPath -eq [System.IO.Path]::GetFullPath($ProjectPath)) $ProjectPath
Add-Check 'v3-root-absent-before-smoke' (-not (Test-Path -LiteralPath $root)) $root
Add-Check 'unity-zero-before-smoke' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) ([string]@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count)
Add-Check 'preexisting-lock-present-before-controlled-cleanup' (Test-Path -LiteralPath $lockPath -PathType Leaf) $lockPath
Add-Check 'formal-root-absent' (-not (Test-Path -LiteralPath $formalRoot)) $formalRoot
Add-Check 'windows-powershell-5.1-exists' (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf) $windowsPowerShell

$parseTargets = @($modulePath, $lockModulePath) + @($entryPoints | ForEach-Object { Join-Path $ProjectPath ([string]$_.relativePath).Replace('/', '\') })
foreach ($path in $parseTargets) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    Add-Check ('parser-' + [IO.Path]::GetFileName($path)) ($parseErrors.Count -eq 0) ($parseErrors -join '; ')
    $text = [IO.File]::ReadAllText($path)
    $forbiddenDefault = [regex]::IsMatch($text, '(?im)ProjectPath\s*=.*PSScriptRoot')
    Add-Check ('no-psscriptroot-param-default-' + [IO.Path]::GetFileName($path)) (-not $forbiddenDefault) $(if ($forbiddenDefault) {'forbidden default found'} else {'none'})
}

$previousModulePath = $env:PSModulePath
try {
    $env:PSModulePath = $nativePowerShellModulePath
    foreach ($entry in $entryPoints) {
        $path = Join-Path $ProjectPath ([string]$entry.relativePath).Replace('/', '\')
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path) + @($entry.arguments)
        $output = @(& $windowsPowerShell @arguments 2>&1 | ForEach-Object {[string]$_})
        $exitCode = [int]$LASTEXITCODE
        $joined = $output -join "`n"
        $markerFound = $joined.Contains('BINDING-SMOKE-PASSED|' + [string]$entry.marker + '|' + $ProjectPath)
        Add-Check ('binding-smoke-' + [IO.Path]::GetFileName($path)) ($exitCode -eq 0 -and $markerFound) ("exit={0};marker={1}" -f $exitCode, $markerFound)
        Add-Check ('v3-root-absent-after-smoke-' + [IO.Path]::GetFileName($path)) (-not (Test-Path -LiteralPath $root)) $root
    }
} finally { $env:PSModulePath = $previousModulePath }

$preservation = Read-Gate10RJson $preservationPath
$attempt1TreeBefore = Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v1')
$attempt2TreeBefore = Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v2')
Add-Check 'attempt1-tree-byte-identical' ($attempt1TreeBefore.fileCount -eq 4 -and $attempt1TreeBefore.rawBytes -eq 9577 -and $attempt1TreeBefore.treeSha256 -eq '2baa66eb6ee95ecf0f68667b2790fba2a30ce8a24f54e8f9fe477cdc716b9e3d') ($attempt1TreeBefore | ConvertTo-Json -Compress)
Add-Check 'attempt2-tree-byte-identical' ($attempt2TreeBefore.fileCount -eq 101 -and $attempt2TreeBefore.rawBytes -eq 9375526 -and $attempt2TreeBefore.treeSha256 -eq 'da9e6312e74db1bc1207660cf90eef28321ecda0abf1297be6c9298e6270dbce') ($attempt2TreeBefore | ConvertTo-Json -Compress)
Add-Check 'preservation-audit-status' ([string]$preservation.status -eq 'PASSED' -and [int]$preservation.attempt -eq 3) ([string]$preservation.status)

$config = Read-Gate10RJson $configPath
$provenance = Read-Gate10RJson $provenancePath
$authorization = Read-Gate10RJson $authorizationPath
Add-Check 'attempt3-config-identity' ([int]$config.attempt -eq 3 -and [string]$config.verificationRoot -eq 'Research/Verification/Gate10R_ProcessReuse_5pct/v3' -and [string]$config.changeClass -eq 'ORCHESTRATION-LOCK-HYGIENE-ONLY') ([string]$config.configId)
Add-Check 'attempt3-provenance-identity' ([int]$provenance.attempt -eq 3 -and [string]$provenance.designId -eq [string]$config.designId -and $provenance.formalCampaign -eq $false) ([string]$provenance.provenanceId)
Add-Check 'attempt3-authorization-identity' ([int]$authorization.attempt -eq 3 -and [string]$authorization.status -eq 'AUTHORIZED-GATE10R-ONLY-ONE-ATTEMPT' -and $authorization.gate11RConditionalContinuationAuthorized -eq $false -and $authorization.gate12RConditionalContinuationAuthorized -eq $false) ([string]$authorization.authorizationId)

$boundRefs = @($provenance.specification, $provenance.testDesign, $provenance.baseConfig, $provenance.attempt3Specification, $provenance.attempt3TestDesign, $provenance.config, $provenance.executionAuthorization, $provenance.authorizationSource, $provenance.preWritePreservationAudit, $provenance.unityCommand, $provenance.unityCommandMeta, $provenance.preparationModule, $provenance.lockHygieneModule, $provenance.blockRunner, $provenance.telemetryProbeRunner, $provenance.coldReferenceRunner, $provenance.preflightRunner, $provenance.unitTestRunner, $provenance.compileRunner, $provenance.blockVerificationRunner, $provenance.retainedRegressionRunner, $provenance.finalAuditRunner)
$bindingErrors = New-Object System.Collections.Generic.List[string]
foreach ($reference in $boundRefs) {
    $path = Join-Path $ProjectPath ([string]$reference.relativePath).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $bindingErrors.Add('missing:' + [string]$reference.relativePath) }
    elseif ((Get-Gate10RLowerSha256 -Path $path) -ne [string]$reference.sha256) { $bindingErrors.Add('hash:' + [string]$reference.relativePath) }
}
Add-Check 'attempt3-provenance-file-bindings' ($bindingErrors.Count -eq 0) ($bindingErrors -join '; ')
Add-Check 'unity-binary-bound' ((Get-Gate10RLowerSha256 -Path ([string]$config.unityExecutable).Replace('/', '\')) -eq [string]$provenance.unity.sha256) ([string]$provenance.unity.sha256)
Add-Check 'gate11r-root-absent' (-not (Test-Path -LiteralPath (Join-Path $researchPath 'FormalScenarios\Gate11R_5pct\v1'))) 'absent'
Add-Check 'gate12r-root-absent' (-not (Test-Path -LiteralPath (Join-Path $researchPath 'PilotRuns\Gate12R_ProcessReuse_5pct\v1'))) 'absent'
Add-Check 'gate13r-root-absent' (-not (Test-Path -LiteralPath $formalRoot)) 'absent'

$lockModuleSource = [IO.File]::ReadAllText($lockModulePath)
Add-Check 'lock-module-no-recursive-delete' (-not $lockModuleSource.Contains('Remove-Item -Recurse') -and -not $lockModuleSource.Contains('-Recurse -Force')) 'absent'
Add-Check 'lock-module-literal-delete' $lockModuleSource.Contains('Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop') 'present'
$preSnapshot = Get-Gate10RLockSnapshotV3 -ProjectPath $ProjectPath -LockPath $lockPath
$preEligibility = Test-Gate10RLockCleanupEligibilityV3 -Snapshot $preSnapshot -Role 'pre-existing-attempt2-negative' -OwnedProcessStartedAt ([DateTimeOffset]'2026-10-06T21:09:14.5903019+08:00') -OwnedProcessCompletedAt ([DateTimeOffset]'2026-10-06T21:09:26.2233236+08:00') -OwnedProcessAlive $false -UnityProcessCount (@(Get-Process Unity -ErrorAction SilentlyContinue).Count) -TimestampToleranceSeconds 2
Add-Check 'preexisting-lock-snapshot-exact' ($preSnapshot.pathMatchesExpected -and $preSnapshot.isLeaf -and -not $preSnapshot.isReparsePoint -and $preSnapshot.bytes -eq 0 -and $preSnapshot.sha256 -eq 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' -and $preSnapshot.exclusiveReadWriteAvailable) ($preSnapshot | ConvertTo-Json -Compress)
Add-Check 'preexisting-lock-cleanup-eligible' $preEligibility.eligible ($preEligibility.errors -join ',')
Add-Check 'attempt2-negative-summary-bound' ((Get-Gate10RLowerSha256 $attempt2NegativeSummaryPath) -eq '747680ff2a6ef0146799f658a4a92024bdb5915ed32616e0ce9b4a2f9cb827b4') (Get-Gate10RLowerSha256 $attempt2NegativeSummaryPath)

$staticFailed = @($checks | Where-Object {-not $_.passed})
[void](New-Item -ItemType Directory -Path $root)
$tempBefore = Get-TempIdentityExcludingLock
$cleanupResult = $null
$cleanupError = $null
if ($staticFailed.Count -eq 0) {
    try {
        $cleanupResult = Invoke-Gate10RControlledLockCleanupV3 -ProjectPath $ProjectPath -OwnedProcessId 19936 -OwnedProcessStartedAt ([DateTimeOffset]'2026-10-06T21:09:14.5903019+08:00') -OwnedProcessCompletedAt ([DateTimeOffset]'2026-10-06T21:09:26.2233236+08:00') -Role 'pre-existing-attempt2-negative' -EvidenceDirectory (Join-Path $root 'Preflight\PreExistingLockCleanup') -ContextId 'attempt2-negative-stale-lock' -TimestampToleranceSeconds 2
    } catch { $cleanupError = $_.Exception.Message }
} else { $cleanupError = 'cleanup skipped because a prior static preflight assertion failed' }
$tempAfter = Get-TempIdentityExcludingLock
$attempt1TreeAfter = Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v1')
$attempt2TreeAfter = Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v2')
Add-Check 'preexisting-lock-cleanup-completed' ($null -ne $cleanupResult -and $cleanupResult.passed -eq $true -and -not (Test-Path -LiteralPath $lockPath)) $(if ($null -ne $cleanupResult) {[string]$cleanupResult.mode} else {$cleanupError})
Add-Check 'temp-nonlock-content-unchanged' ($tempBefore.fileCount -eq $tempAfter.fileCount -and $tempBefore.rawBytes -eq $tempAfter.rawBytes -and $tempBefore.treeSha256 -eq $tempAfter.treeSha256) ("before={0};after={1}" -f ($tempBefore | ConvertTo-Json -Compress), ($tempAfter | ConvertTo-Json -Compress))
Add-Check 'attempt1-tree-unchanged-after-lock-cleanup' ($attempt1TreeAfter.treeSha256 -eq $attempt1TreeBefore.treeSha256 -and $attempt1TreeAfter.fileCount -eq $attempt1TreeBefore.fileCount -and $attempt1TreeAfter.rawBytes -eq $attempt1TreeBefore.rawBytes) ($attempt1TreeAfter | ConvertTo-Json -Compress)
Add-Check 'attempt2-tree-unchanged-after-lock-cleanup' ($attempt2TreeAfter.treeSha256 -eq $attempt2TreeBefore.treeSha256 -and $attempt2TreeAfter.fileCount -eq $attempt2TreeBefore.fileCount -and $attempt2TreeAfter.rawBytes -eq $attempt2TreeBefore.rawBytes) ($attempt2TreeAfter | ConvertTo-Json -Compress)
Add-Check 'unity-zero-after-lock-cleanup' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) ([string]@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count)

$failed = @($checks | Where-Object {-not $_.passed})
$summaryPath = Join-Path $root 'Gate10R_Attempt3_Preflight.summary.v3.json'
$checkpointPath = Join-Path $root 'gate10r-preflight-checkpoint.v3.json'
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate10r-attempt3-lock-hygiene-preflight-v3'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    attempt = 3
    designId = [string]$config.designId
    entryPointCount = $entryPoints.Count
    assertionCount = $checks.Count
    passedCount = $checks.Count - $failed.Count
    failedCount = $failed.Count
    checks = $checks.ToArray()
    preExistingLockCleanup = $cleanupResult
    unityStarted = $false
    gate11RAuthorized = $false
    gate12RAuthorized = $false
    formalCampaign = $false
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    passed = $failed.Count -eq 0
}
Write-Gate10RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 60
$checkpoint = [ordered]@{
    schemaVersion = 1
    checkpointKind = 'gate10r-attempt3-preflight-checkpoint-v3'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = if ($summary.passed) {'GATE10R-ATTEMPT3-PREFLIGHT-PASSED-READY-FOR-ONE-OFFICIAL-EXECUTION'} else {'GATE10R-ATTEMPT3-PREFLIGHT-FAILED-NO-AUTO-RETRY'}
    attempt = 3
    summaryRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $summaryPath
    summarySha256 = Get-Gate10RLowerSha256 -Path $summaryPath
    unityStarted = $false
    officialExecutionCount = 0
    gate11RAuthorized = $false
    gate12RAuthorized = $false
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    gate13RFormalCampaignAuthorized = $false
}
Write-Gate10RAtomicUtf8NoBomJson -Path $checkpointPath -Value $checkpoint -Depth 20
if (-not $summary.passed) { Write-Error "Gate 10R attempt-3 preflight failed: $($failed.name -join ', ')"; exit 1 }
Write-Host "Gate 10R attempt-3 preflight passed: $($checks.Count)/$($checks.Count); stale lock was evidence-captured and removed; Unity was not started." -ForegroundColor Green
exit 0
