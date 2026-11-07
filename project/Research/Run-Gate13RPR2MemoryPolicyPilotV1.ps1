[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$PilotRoot,
    [Parameter(Mandatory = $true)][string]$ExecutionReceiptPath,
    [string]$ConfigPath,
    [string]$SchedulePath,
    [string]$ProvenancePath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$BlockTimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotV1|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force

$expectedModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
if ($PSVersionTable.PSVersion.Major -ne 5 -or [string]$env:PSModulePath -ne $expectedModulePath) { throw 'MP1 measured orchestration requires native Windows PowerShell 5.1 and the verified native PSModulePath.' }
$PilotRoot = [IO.Path]::GetFullPath($PilotRoot).TrimEnd('\','/')
$expectedPilotRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v1')).TrimEnd('\','/')
if (-not $PilotRoot.Equals($expectedPilotRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Pilot root identity mismatch.' }
$rawRoot = [IO.Path]::GetFullPath((Join-Path $PilotRoot 'raw')).TrimEnd('\','/')
$ExecutionReceiptPath = [IO.Path]::GetFullPath($ExecutionReceiptPath)
$ConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Config.v1.json' } else { [IO.Path]::GetFullPath($ConfigPath) }
$SchedulePath = if ([string]::IsNullOrWhiteSpace($SchedulePath)) { Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl' } else { [IO.Path]::GetFullPath($SchedulePath) }
$ProvenancePath = if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Provenance.v1.json' } else { [IO.Path]::GetFullPath($ProvenancePath) }
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$wrapperPath = Join-Path $ProjectPath 'Research\Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1'
$commandPath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs'
$specificationPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Specification.v1.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Test_Design.v1.md'
$twoStagePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json'
$checkpointPath = Join-Path $PilotRoot 'pilot-checkpoint.json'

foreach ($path in @($ExecutionReceiptPath,$ConfigPath,$SchedulePath,$ProvenancePath,$UnityPath,$wrapperPath,$commandPath,$specificationPath,$testDesignPath,$twoStagePath,$checkpointPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required MP1 input is missing: $path" }
}
if (-not (Test-Path -LiteralPath $rawRoot -PathType Container)) { throw 'Committed MP1 raw root is missing.' }
$receipt = Read-G13RPR2MP1Json $ExecutionReceiptPath
$config = Read-G13RPR2MP1Json $ConfigPath
$checkpoint = Read-G13RPR2MP1Json $checkpointPath
if ([string]$receipt.receiptKind -ne 'gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v1' -or $receipt.measuredPilotAuthorized -ne $true -or $receipt.formalCampaignAuthorized -ne $false) { throw 'Pilot execution receipt mismatch.' }
if ([string]$config.configId -ne 'gate13r-pr2-mp1-targeted-memory-pilot-config-v1' -or [int]$config.matrix.measuredProcesses -ne 96 -or [int]$config.matrix.measuredSamples -ne 384 -or [int]$config.matrix.warmupProcesses -ne 0) { throw 'Pilot config identity/cardinality mismatch.' }
if ([string]$checkpoint.status -ne 'AUTHORIZED-NOT-STARTED' -or [int]$checkpoint.completedBlockCount -ne 0) { throw 'MP1 measured acquisition is one-shot and cannot resume.' }
if ((Get-G13RPR2MP1Sha256 $ConfigPath) -ne [string]$receipt.configSha256 -or (Get-G13RPR2MP1Sha256 $SchedulePath) -ne [string]$receipt.scheduleSha256 -or (Get-G13RPR2MP1Sha256 $ProvenancePath) -ne [string]$receipt.provenanceSha256) { throw 'Receipt/input SHA-256 mismatch.' }
if ((Get-G13RPR2MP1Sha256 $SchedulePath) -ne [string]$config.schedule.sha256) { throw 'Config/schedule SHA-256 mismatch.' }
if (@(Get-ChildItem -LiteralPath $rawRoot -Force).Count -ne 0) { throw 'MP1 raw root must be empty at measured start.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent at measured start.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3')) { throw 'Formal attempt-3 root must remain absent.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json')) { throw 'Formal attempt-3 receipt must remain absent.' }

$schedule = @(Get-Content -LiteralPath $SchedulePath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
if ($schedule.Count -ne 96 -or @($schedule | Where-Object { $_.measured -ne $true -or $_.warmup -ne $false }).Count -ne 0) { throw 'Schedule measured/warm-up boundary mismatch.' }
for ($i=0;$i -lt $schedule.Count;$i++) { if ([int]$schedule[$i].globalProcessOrdinal -ne $i+1) { throw 'Schedule global ordinals are not contiguous.' } }

$plansRoot = Join-Path $rawRoot 'plans'
$blocksRoot = Join-Path $rawRoot 'blocks'
New-Item -ItemType Directory -Path $plansRoot,$blocksRoot -Force | Out-Null
$checkpoint.status = 'MEASURED-ACQUISITION-RUNNING'
$checkpoint.startedAtUtc = [DateTime]::UtcNow.ToString('o')
Write-G13RPR2MP1AtomicJson -Path $checkpointPath -Value $checkpoint -Depth 40 -Replace

$powershellExe = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$completedBlocks = 0
foreach ($row in $schedule) {
    $blockPlanPath = Join-Path $plansRoot (([string]$row.blockId) + '.json')
    $blockOutput = [IO.Path]::GetFullPath((Join-Path $rawRoot ([string]$row.outputRelativePath).Replace('/','\')))
    $plan = [ordered]@{
        schemaVersion = 2
        planId = 'gate13r-pr2-mp1-block-plan-v1'
        designId = 'gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1'
        globalProcessOrdinal = [int]$row.globalProcessOrdinal
        blockId = [string]$row.blockId
        campaignId = [string]$row.campaignId
        scenarioId = [string]$row.scenarioId
        scenarioRelativePath = [string]$row.scenarioRelativePath
        scenarioSourceSha256 = [string]$row.scenarioSourceSha256
        comparisonCohortId = [string]$row.comparisonCohortId
        block = [int]$row.blockOrdinalWithinScenario
        williamsRowIndex = [int]$row.williamsRowIndex
        formalCampaign = $false
        validationOnly = $false
        excludedFromFormalAnalysis = $true
        analysisRole = 'memory-diagnostic-only'
        verificationInjectedFailurePosition = 0
        formalConfigRelativePath = 'Research/Gate13R_PR2_MP1_Pilot_Config.v1.json'
        formalConfigSha256 = Get-G13RPR2MP1Sha256 $ConfigPath
        specificationRelativePath = 'Research/Gate13R_PR2_MP1_Specification.v1.md'
        specificationSha256 = Get-G13RPR2MP1Sha256 $specificationPath
        testDesignRelativePath = 'Research/Gate13R_PR2_MP1_Test_Design.v1.md'
        testDesignSha256 = Get-G13RPR2MP1Sha256 $testDesignPath
        amendmentRelativePath = 'Research/Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json'
        amendmentSha256 = Get-G13RPR2MP1Sha256 $twoStagePath
        commandRelativePath = 'Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs'
        commandSha256 = Get-G13RPR2MP1Sha256 $commandPath
        provenanceRelativePath = 'Research/Gate13R_PR2_MP1_Provenance.v1.json'
        provenanceSha256 = Get-G13RPR2MP1Sha256 $ProvenancePath
        executionReceiptRelativePath = 'Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v1/pilot-execution-receipt.json'
        executionReceiptSha256 = Get-G13RPR2MP1Sha256 $ExecutionReceiptPath
        entries = @($row.entries)
    }
    Write-G13RPR2MP1AtomicJson -Path $blockPlanPath -Value $plan -Depth 40
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $wrapperPath -ProjectPath $ProjectPath -BlockPlanPath $blockPlanPath -OutputDirectory $blockOutput -AllowedRoot $rawRoot -ExecutionReceiptPath $ExecutionReceiptPath -UnityPath $UnityPath -TimeoutSeconds $BlockTimeoutSeconds
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        $files = @(Get-ChildItem -LiteralPath $rawRoot -Recurse -File -Force | Sort-Object FullName)
        $partial = [ordered]@{
            schemaVersion=1; manifestKind='gate13r-pr2-mp1-partial-output-manifest-v1'; savedAtUtc=[DateTime]::UtcNow.ToString('o')
            status='FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE'; failedGlobalProcessOrdinal=[int]$row.globalProcessOrdinal; failedBlockId=[string]$row.blockId
            completedBlockCount=$completedBlocks; expectedBlockCount=96; fileCount=$files.Count; rawBytes=[long](($files | Measure-Object Length -Sum).Sum)
            files=@($files | ForEach-Object { [ordered]@{relativePath=$_.FullName.Substring($rawRoot.Length+1).Replace('\','/');bytes=[long]$_.Length;sha256=Get-G13RPR2MP1Sha256 $_.FullName} })
        }
        Write-G13RPR2MP1AtomicJson -Path (Join-Path $PilotRoot 'pilot-partial-output-manifest.json') -Value $partial -Depth 60
        $failure = [ordered]@{schemaVersion=1;receiptKind='gate13r-pr2-mp1-pilot-failure-receipt-v1';failedAtUtc=[DateTime]::UtcNow.ToString('o');failedGlobalProcessOrdinal=[int]$row.globalProcessOrdinal;failedBlockId=[string]$row.blockId;wrapperExitCode=$exit;status='FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE';formalCampaign=$false;formalAnalysisAuthorized=$false;gate14RAuthorized=$false}
        Write-G13RPR2MP1AtomicJson -Path (Join-Path $PilotRoot 'pilot-failure-receipt.json') -Value $failure -Depth 30
        $checkpoint.status='FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE';$checkpoint.savedAtUtc=[DateTime]::UtcNow.ToString('o');$checkpoint.completedBlockCount=$completedBlocks;$checkpoint.currentGlobalProcessOrdinal=[int]$row.globalProcessOrdinal;$checkpoint.currentBlockId=[string]$row.blockId
        Write-G13RPR2MP1AtomicJson -Path $checkpointPath -Value $checkpoint -Depth 40 -Replace
        throw "MP1 measured block failed at global ordinal $($row.globalProcessOrdinal); no retry/resume/top-up/merge is authorized."
    }
    $completedBlocks++
    $checkpoint.savedAtUtc=[DateTime]::UtcNow.ToString('o');$checkpoint.completedBlockCount=$completedBlocks;$checkpoint.currentGlobalProcessOrdinal=[int]$row.globalProcessOrdinal;$checkpoint.currentBlockId=[string]$row.blockId
    Write-G13RPR2MP1AtomicJson -Path $checkpointPath -Value $checkpoint -Depth 40 -Replace
}

$environmentEndPath = Join-Path $PilotRoot 'pilot-environment-end-snapshot.json'
$os = Get-CimInstance Win32_OperatingSystem
$environmentEnd = [ordered]@{
    schemaVersion=1;snapshotKind='gate13r-pr2-mp1-environment-end-v1';capturedAtUtc=[DateTime]::UtcNow.ToString('o')
    unityProcessCount=@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count;projectLockExists=Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
    availablePhysicalMemoryBytes=[long]$os.FreePhysicalMemory*1024L;totalVisibleMemoryBytes=[long]$os.TotalVisibleMemorySize*1024L
    hDriveFreeBytes=[long](Get-PSDrive -Name H).Free;powerScheme=(& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
}
Write-G13RPR2MP1AtomicJson -Path $environmentEndPath -Value $environmentEnd -Depth 30
if ($environmentEnd.unityProcessCount -ne 0 -or $environmentEnd.projectLockExists) { throw 'End-of-acquisition Unity quiescence failed before raw commit.' }
$freezeScript = Join-Path $ProjectPath 'Research\Freeze-Gate13RPR2MemoryPolicyPilotRawV1.py'
$freezeOutput = & py -3 $freezeScript --pilot-root $PilotRoot --raw-root $rawRoot --schedule $SchedulePath --config $ConfigPath --receipt $ExecutionReceiptPath --environment-end $environmentEndPath
if ($LASTEXITCODE -ne 0) { throw 'MP1 raw freeze failed; measured data will not be rerun automatically.' }
$freezeResult = $freezeOutput | ConvertFrom-Json
if ($freezeResult.passed -ne $true) { throw 'MP1 raw freeze did not report passed.' }
$checkpoint.status='PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE';$checkpoint.savedAtUtc=[DateTime]::UtcNow.ToString('o');$checkpoint.completedBlockCount=96;$checkpoint.currentGlobalProcessOrdinal=96;$checkpoint.currentBlockId=[string]$schedule[-1].blockId;$checkpoint.rawTreeSha256=[string]$freezeResult.rawTreeSha256
Write-G13RPR2MP1AtomicJson -Path $checkpointPath -Value $checkpoint -Depth 40 -Replace
Write-Host "Gate13R-PR2-MP1 raw acquisition committed: $($freezeResult.rawTreeSha256)" -ForegroundColor Green
exit 0
