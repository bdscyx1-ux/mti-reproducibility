[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ProjectPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-AtomicUtf8NoBomJson {
    param([string]$LiteralPath, $Value)
    $temporary = $LiteralPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = ($Value | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false, $true)))
    Move-Item -LiteralPath $temporary -Destination $LiteralPath
}

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'ProjectPath must be an explicit absolute path.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$source = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate10RProcessReuseBatchCommand.cs'
$destination = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate12RProcessReuseBatchCommandV2.cs'
$receiptPath = Join-Path $ProjectPath 'Research\Gate12R_ProcessReuse_CommandV2_Derivation.v1.json'
$expectedSourceSha256 = '9218c72b7e4d1d289feef9a367e376a497b06f048099572ac73042f28d482407'

if (Test-Path -LiteralPath $destination) { throw "Create-new destination exists: $destination" }
if (Test-Path -LiteralPath $receiptPath) { throw "Create-new receipt exists: $receiptPath" }
$actualSourceSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSourceSha256 -ne $expectedSourceSha256) { throw "Frozen source hash mismatch: $actualSourceSha256" }

$text = [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8)
$classFrom = 'public static class Gate10RProcessReuseBatchCommand'
$classTo = 'public static class Gate12RProcessReuseBatchCommandV2'
$telemetryFrom = '            ProcessTelemetry rawAfter = CaptureTelemetry(process);'
$telemetryTo = $telemetryFrom + "`r`n            planner.Reset();"
$classCount = $text.Split([string[]]@($classFrom), [StringSplitOptions]::None).Count - 1
$telemetryCount = $text.Split([string[]]@($telemetryFrom), [StringSplitOptions]::None).Count - 1
if ($classCount -ne 1) { throw "Class replacement count is $classCount, expected 1." }
if ($telemetryCount -ne 1) { throw "Telemetry/reset insertion count is $telemetryCount, expected 1." }
if ($text.Contains('planner.Reset();')) { throw 'Frozen source unexpectedly already contains planner.Reset().' }

$derived = $text.Replace($classFrom, $classTo).Replace($telemetryFrom, $telemetryTo)
[IO.File]::WriteAllText($destination, $derived, (New-Object Text.UTF8Encoding($false, $true)))

$derivedText = [IO.File]::ReadAllText($destination, [Text.Encoding]::UTF8)
if (($derivedText.Split([string[]]@('planner.Reset();'), [StringSplitOptions]::None).Count - 1) -ne 1) { throw 'Derived command must contain exactly one planner.Reset() call.' }
$rawIndex = $derivedText.IndexOf($telemetryFrom, [StringComparison]::Ordinal)
$resetIndex = $derivedText.IndexOf('planner.Reset();', [StringComparison]::Ordinal)
if ($rawIndex -lt 0 -or $resetIndex -le $rawIndex) { throw 'planner.Reset() is not after the frozen raw-after-workload telemetry capture.' }
$sourceAfterSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceAfterSha256 -ne $expectedSourceSha256) { throw 'Frozen source changed during derivation.' }

$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate12r-process-reuse-command-v2-mechanical-derivation-receipt-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    sourceRelativePath = 'Assets/_Scripts/Research/Editor/Gate10RProcessReuseBatchCommand.cs'
    sourceSha256Before = $actualSourceSha256
    sourceSha256After = $sourceAfterSha256
    destinationRelativePath = 'Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV2.cs'
    destinationSha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    mechanicalChanges = @(
        [ordered]@{ kind = 'class-rename'; occurrenceCount = $classCount; from = $classFrom; to = $classTo },
        [ordered]@{ kind = 'post-raw-telemetry-planner-reset'; occurrenceCount = $telemetryCount; from = $telemetryFrom; to = $telemetryTo }
    )
    rawTelemetryCapturedBeforePlannerReset = $true
    timedWorkloadBoundaryChanged = $false
    rawTelemetrySemanticsChanged = $false
    frozenMemoryThresholdsChanged = $false
    algorithmImplementationChanged = $false
    resetContractCorrected = $true
    passed = $true
}
Write-AtomicUtf8NoBomJson -LiteralPath $receiptPath -Value $receipt
Write-Host "Gate12R process-reuse command v2 derived: $destination" -ForegroundColor Green

