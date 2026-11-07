[CmdletBinding()]
param([string]$ProjectPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$researchPath = Join-Path $ProjectPath 'Research'
$modulePath = Join-Path $researchPath 'Gate13R2V2Preparation.psm1'
Import-Module $modulePath -Force
$summaryPath = Join-Path $PSScriptRoot 'Gate13R2_v2_PrePilotAudit.summary.json'
if (Test-Path -LiteralPath $summaryPath) { throw 'V2 pre-pilot audit summary already exists; refusing retry/overwrite.' }
$failures = New-Object System.Collections.Generic.List[string]
$assertions = New-Object System.Collections.Generic.List[object]
function Assert-V2([bool]$Condition, [string]$Name, [string]$Detail) { $script:assertions.Add([pscustomobject][ordered]@{ name=$Name; passed=$Condition; detail=$Detail }); if (-not $Condition) { $script:failures.Add("$Name`: $Detail") } }

$planPath = Join-Path $researchPath 'Gate13R2_v2_Pilot_Plan.v1.json'; $plan = Read-G13R2V2Json $planPath
$provenancePath = Join-Path $researchPath 'Gate13R2_v2_Provenance.v1.json'; $provenance = Read-G13R2V2Json $provenancePath
$planCheck = Test-G13R2V2PilotPlan -ProjectPath $ProjectPath -Plan $plan -PlanPath $planPath
Assert-V2 ([bool]$planCheck.passed) 'pilot-plan' ($planCheck.errors -join '; ')
Assert-V2 ([string]$provenance.provenanceId -eq 'gate13-r2-v2-provenance-v1' -and $provenance.formalExecutionAuthorized -eq $false) 'provenance-identity' 'V2 provenance must be non-formal and versioned.'
foreach ($property in $provenance.PSObject.Properties | Where-Object { $_.Value -is [pscustomobject] -and $_.Value.PSObject.Properties.Name -contains 'relativePath' -and $_.Value.PSObject.Properties.Name -contains 'sha256' }) {
    $ok = $true; $detail = ''
    try { [void](Assert-G13R2V2BoundFile -ProjectPath $ProjectPath -RelativePath ([string]$property.Value.relativePath) -ExpectedSha256 ([string]$property.Value.sha256) -Label ('Provenance ' + $property.Name)) } catch { $ok = $false; $detail = $_.Exception.Message }
    Assert-V2 $ok ('provenance-' + $property.Name) $detail
}

$preservation = Read-G13R2V2Json (Join-Path $PSScriptRoot 'Gate13R2_v2_PreservationAudit.summary.json')
Assert-V2 ($preservation.status -eq 'passed') 'preservation-summary' 'Initial preservation audit must pass.'
$coldRoot = Join-Path $researchPath 'FormalRuns\Gate13\v1'; $coldFiles = @(Get-ChildItem -LiteralPath $coldRoot -File -Recurse)
Assert-V2 ($coldFiles.Count -eq 891 -and [long](($coldFiles | Measure-Object Length -Sum).Sum) -eq 129667391 -and @($coldFiles | Where-Object { -not $_.IsReadOnly }).Count -eq 0) 'cold-root-preserved' 'Cold root count/bytes/read-only state changed.'
$v1Root = Join-Path $researchPath 'PilotRuns\Gate13_ProcessReuse\v1'; $v1Files = @(Get-ChildItem -LiteralPath $v1Root -File -Recurse)
Assert-V2 ($v1Files.Count -eq 838 -and [long](($v1Files | Measure-Object Length -Sum).Sum) -eq 91219643 -and @($v1Files | Where-Object { -not $_.IsReadOnly }).Count -eq 0) 'v1-root-preserved' 'Process-reuse v1 count/bytes/read-only state changed.'
$v1FailureManifest = Read-G13R2V2Json (Join-Path $researchPath 'Gate13_ProcessReuse_Pilot_v1_Failure_Output_Manifest.json')
$v1Mismatches = 0
foreach ($record in @($v1FailureManifest.files)) { $path = Join-Path $v1Root ([string]$record.relativePath).Replace('/', '\'); if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [long](Get-Item $path).Length -ne [long]$record.byteCount -or (Get-G13R2V2LowerSha256 $path) -ne [string]$record.sha256) { $v1Mismatches++ } }
Assert-V2 ($v1Mismatches -eq 0 -and [string]$v1FailureManifest.aggregateSha256 -eq 'c467cd4ca179f6e919fe9cbfdeee3cd2b4a32c19931bcdc285ca705555a59b38') 'v1-manifest-hashes' "V1 manifest mismatches: $v1Mismatches."

$baselineMismatches = New-Object System.Collections.Generic.List[string]
foreach ($row in @(Import-Csv -LiteralPath (Join-Path $researchPath 'Baseline_SHA256.csv') | Where-Object { $_.scope -in @('working_copy','external_archive') })) {
    if (-not (Test-Path -LiteralPath $row.path -PathType Leaf) -or (Get-G13R2V2LowerSha256 $row.path) -ne [string]$row.sha256) { $baselineMismatches.Add([string]$row.path) }
}
Assert-V2 ($baselineMismatches.Count -eq 0) 'original-baseline-hashes' ($baselineMismatches -join '; ')
Assert-V2 ((Get-G13R2V2LowerSha256 (Join-Path $researchPath 'FormalScenarios\v1\bundle-manifest.json')) -eq 'ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e') 'gate11-bundle' 'Gate 11 retained manifest changed.'
Assert-V2 ((Get-G13R2V2LowerSha256 (Join-Path $researchPath 'PilotRuns\Gate12\v1\pilot-manifest.json')) -eq '638ac2e3fe243212ef031bdbed4c06394447e055c4d080be370357c41122e18a') 'gate12-v1' 'Gate 12 success manifest changed.'

$pilotRoot = Join-Path $researchPath 'PilotRuns\Gate13_ProcessReuse\v2'; $formalRoot = Join-Path $researchPath 'FormalRuns\Gate13_ProcessReuse\v1'
$rootChildren = if (Test-Path -LiteralPath $pilotRoot) { @(Get-ChildItem -LiteralPath $pilotRoot -Force) } else { @() }
Assert-V2 ((Test-Path -LiteralPath $pilotRoot -PathType Container) -and $rootChildren.Count -eq 2 -and (@($rootChildren.Name | Sort-Object) -join '|') -eq 'preparation-checkpoint.json|root-initialization-receipt.json') 'v2-root-preparation-only' 'V2 root must contain only its two initialization files.'
if (Test-Path -LiteralPath (Join-Path $pilotRoot 'preparation-checkpoint.json')) { $prep = Read-G13R2V2Json (Join-Path $pilotRoot 'preparation-checkpoint.json'); Assert-V2 ([string]$prep.status -eq 'PREPARATION-ONLY-PILOT-NOT-STARTED' -and $prep.pilotExecutionStarted -eq $false) 'v2-root-not-started' 'V2 pilot was already started.' }
Assert-V2 (-not (Test-Path -LiteralPath $formalRoot)) 'formal-root-absent' 'Process-reuse formal root exists.'
$formalV2Files = @(Get-ChildItem -LiteralPath $researchPath -File | Where-Object { $_.Name -match 'Gate13R2_v2.*Formal.*(Config|Receipt)|Gate13_ProcessReuse.*Formal.*Receipt' })
Assert-V2 ($formalV2Files.Count -eq 0) 'formal-receipt-config-absent' ('Unexpected files: ' + ($formalV2Files.Name -join ', '))

$unitPath = Join-Path $PSScriptRoot 'Gate13R2_v2_UnitTests.summary.json'; $unit = if (Test-Path $unitPath) { Read-G13R2V2Json $unitPath } else { $null }
Assert-V2 ($null -ne $unit -and $unit.passed -eq $true -and [int]$unit.failedAssertionCount -eq 0) 'unit-static-tests' 'V2 unit/static summary missing or failed.'
$compilePath = Join-Path $PSScriptRoot 'Gate13R2_v2\Compile\v1.summary.json'; $compile = if (Test-Path $compilePath) { Read-G13R2V2Json $compilePath } else { $null }
Assert-V2 ($null -ne $compile -and $compile.passed -eq $true -and [int]$compile.exitCode -eq 0 -and [int]$compile.compilerErrorMatchCount -eq 0) 'unity-compilation' 'V2 Unity compilation summary missing or failed.'
$probePath = Join-Path $PSScriptRoot 'Gate13R2_v2\TelemetryProbe\v1\telemetry-probe-result.json'; $probeSummaryPath = Join-Path $PSScriptRoot 'Gate13R2_v2\TelemetryProbe\v1.summary.json'
$probe = if (Test-Path $probePath) { Read-G13R2V2Json $probePath } else { $null }; $probeSummary = if (Test-Path $probeSummaryPath) { Read-G13R2V2Json $probeSummaryPath } else { $null }
Assert-V2 ($null -ne $probe -and $null -ne $probeSummary -and $probe.passed -eq $true -and $probeSummary.passed -eq $true -and [long]$probe.nativeBefore.workingSetBytes -gt 0 -and [long]$probe.nativeBefore.privateMemoryBytes -gt 0 -and [long]$probe.externalQuery.workingSetBytes -gt 0 -and [long]$probe.externalQuery.privateMemoryBytes -gt 0) 'telemetry-probe' 'V2 native/CIM telemetry probe missing or failed.'
$blockPath = Join-Path $PSScriptRoot 'Gate13R2_v2_BlockVerification.summary.json'; $block = if (Test-Path $blockPath) { Read-G13R2V2Json $blockPath } else { $null }
Assert-V2 ($null -ne $block -and $block.passed -eq $true -and [int]$block.structuralMismatchCount -eq 0 -and $block.independentProcessRepeatabilityPassed -eq $true -and $block.negativeFailClosedPassed -eq $true) 'block-verification' 'V2 positive/negative/repeatability block verification missing or failed.'
$regressionPath = Join-Path $PSScriptRoot 'Gate13R2_v2_RetainedRegression63.summary.json'; $regression = if (Test-Path $regressionPath) { Read-G13R2V2Json $regressionPath } else { $null }
Assert-V2 ($null -ne $regression -and $regression.passed -eq $true -and [int]$regression.assertionCount -eq 63) 'retained-regression-63' 'Retained regression is not 63/63.'

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue); $lockPresent = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
Assert-V2 ($unityProcesses.Count -eq 0 -and -not $lockPresent) 'unity-idle' 'Unity process or project lock remains.'
$powerRaw = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim(); $powerMatch = [regex]::Match($powerRaw, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
Assert-V2 ($powerMatch.Success -and $powerMatch.Value.ToLowerInvariant() -eq [string]$plan.environmentPreflight.requiredActivePowerSchemeGuid) 'power-scheme' $powerRaw
$os = Get-CimInstance Win32_OperatingSystem; $freeMemory = [long]([double]$os.FreePhysicalMemory * 1KB)
Assert-V2 ($freeMemory -ge [long]$plan.environmentPreflight.minimumFreePhysicalMemoryBytes) 'free-memory' "Free bytes: $freeMemory"
$drive = New-Object System.IO.DriveInfo -ArgumentList @([System.IO.Path]::GetPathRoot($pilotRoot)); Assert-V2 ($drive.AvailableFreeSpace -ge 10GB) 'storage' "Free bytes: $($drive.AvailableFreeSpace)"
$battery = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue); $acOnline = if ($battery.Count -eq 0) { $true } else { @($battery | Where-Object { [int]$_.BatteryStatus -in @(2,6,7,8,9,11) }).Count -eq $battery.Count }
Assert-V2 $acOnline 'ac-power' $(if ($battery.Count -eq 0) { 'Desktop/no battery device; treated as mains-powered.' } else { 'Battery status must report AC/charging.' })
$cpuSamples = New-Object System.Collections.Generic.List[double]
for ($i=0;$i -lt [int]$plan.environmentPreflight.cpuLoadSampleCount;$i++){ $cpuSamples.Add([double]((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average)); if($i -lt [int]$plan.environmentPreflight.cpuLoadSampleCount-1){Start-Sleep -Seconds ([int]$plan.environmentPreflight.cpuLoadSampleIntervalSeconds)}}
$meanCpu=[double](($cpuSamples|Measure-Object -Average).Average); Assert-V2 ($meanCpu -le [double]$plan.environmentPreflight.maximumMeanCpuLoadPercent) 'cpu-load' "Mean load: $meanCpu"

$passed = $failures.Count -eq 0
$summary = [ordered]@{ schemaVersion = 1; summaryKind = 'gate13-r2-v2-validation-only-pre-pilot-audit-v1'; savedAtUtc = [DateTime]::UtcNow.ToString('o'); projectPath = $ProjectPath; assertionCount = $assertions.Count; passedAssertionCount = @($assertions | Where-Object passed).Count; failedAssertionCount = @($assertions | Where-Object { -not $_.passed }).Count; assertions = $assertions.ToArray(); failures = $failures.ToArray(); pilotPlanSha256 = Get-G13R2V2LowerSha256 $planPath; provenanceSha256 = Get-G13R2V2LowerSha256 $provenancePath; telemetryProbeResultSha256 = if(Test-Path $probePath){Get-G13R2V2LowerSha256 $probePath}else{$null}; unitSummarySha256 = if(Test-Path $unitPath){Get-G13R2V2LowerSha256 $unitPath}else{$null}; compileSummarySha256 = if(Test-Path $compilePath){Get-G13R2V2LowerSha256 $compilePath}else{$null}; blockVerificationSummarySha256 = if(Test-Path $blockPath){Get-G13R2V2LowerSha256 $blockPath}else{$null}; retainedRegressionSummarySha256 = if(Test-Path $regressionPath){Get-G13R2V2LowerSha256 $regressionPath}else{$null}; environment = [ordered]@{ powerSchemeRaw=$powerRaw; freePhysicalMemoryBytes=$freeMemory; storageFreeBytes=[long]$drive.AvailableFreeSpace; acOnline=$acOnline; cpuLoadSamplesPercent=$cpuSamples.ToArray(); meanCpuLoadPercent=$meanCpu; unityProcessCount=$unityProcesses.Count; unityLockfilePresent=$lockPresent }; pilotExecutionAuthorizedByAudit = $passed; authorizedPilotExecutionCount = if($passed){1}else{0}; formalCampaign=$false; formalExecutionAuthorized=$false; formalRootCreated=$false; automaticRetryAuthorized=$false; automaticResumeAuthorized=$false; passed=$passed }
Write-G13R2V2AtomicUtf8NoBomJson $summaryPath $summary 50
if (-not $passed) { Write-Error "Gate 13-R2 v2 validation-only pre-pilot audit failed: $($failures -join '; ')"; exit 1 }
Write-Host "Gate 13-R2 v2 pre-pilot audit passed ($($assertions.Count) assertions plus retained 63/63). Exactly one non-formal pilot may start; formal execution remains unauthorized." -ForegroundColor Green
exit 0
