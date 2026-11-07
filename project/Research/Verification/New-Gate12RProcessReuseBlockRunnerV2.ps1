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
$source = Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlock.ps1'
$destination = Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlockV2.ps1'
$receiptPath = Join-Path $ProjectPath 'Research\Gate12R_ProcessReuse_BlockRunnerV2_Derivation.v1.json'
$expectedSourceSha256 = '560a91a25f812a6df3a750071fdcd2d63da304feaae60f80709ca8eadbe14ca5'

if (Test-Path -LiteralPath $destination) { throw "Create-new destination exists: $destination" }
if (Test-Path -LiteralPath $receiptPath) { throw "Create-new receipt exists: $receiptPath" }
$actualSourceSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSourceSha256 -ne $expectedSourceSha256) { throw "Frozen block runner hash mismatch: $actualSourceSha256" }
$text = [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8)
$from = 'DDM.Research.Editor.Gate10RProcessReuseBatchCommand.Run'
$to = 'DDM.Research.Editor.Gate12RProcessReuseBatchCommandV2.Run'
$count = $text.Split([string[]]@($from), [StringSplitOptions]::None).Count - 1
if ($count -ne 1) { throw "Execute-method route count is $count, expected 1." }
$derived = $text.Replace($from, $to)
[IO.File]::WriteAllText($destination, $derived, (New-Object Text.UTF8Encoding($false, $true)))
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedSourceSha256) { throw 'Frozen block runner changed during derivation.' }

$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate12r-process-reuse-block-runner-v2-route-derivation-receipt-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    sourceRelativePath = 'Research/Run-Gate12RProcessReuseBlock.ps1'
    sourceSha256 = $actualSourceSha256
    destinationRelativePath = 'Research/Run-Gate12RProcessReuseBlockV2.ps1'
    destinationSha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    replacementFrom = $from
    replacementTo = $to
    replacementCount = $count
    orchestrationSemanticsChanged = $false
    commandRouteChanged = $true
    passed = $true
}
Write-AtomicUtf8NoBomJson -LiteralPath $receiptPath -Value $receipt
Write-Host "Gate12R block runner v2 derived: $destination" -ForegroundColor Green

