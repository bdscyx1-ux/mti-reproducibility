[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|New-Gate13RPR2Attempt2RehearsalEvidenceManifestV1|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV5.psm1') -Force
$root = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\ContractRehearsal')).TrimEnd('\', '/')
$manifestPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\contract-rehearsal-evidence-manifest.v1.json'
$dryRunPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\campaign-validation-only-dry-run-summary.v1.json'
$negativePath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\NegativeNoReceiptAttempt2\summary.json'
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Contract rehearsal root is missing.' }
if (Test-Path -LiteralPath $manifestPath) { throw 'Create-new rehearsal evidence manifest exists.' }
foreach ($required in @($dryRunPath,$negativePath,(Join-Path $root 'rehearsal-contract-audit.json'))) { if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required rehearsal evidence is missing: $required" } }
$audit = Read-G13RPR2Json (Join-Path $root 'rehearsal-contract-audit.json')
$dryRun = Read-G13RPR2Json $dryRunPath
$negative = Read-G13RPR2Json $negativePath
if ($audit.passed -ne $true -or [int]$audit.sampleCount -ne 4 -or [int]$audit.embeddedFormalCampaignTrueCount -ne 4 -or [int]$audit.sampleSummaryFormalCampaignTrueCount -ne 4 -or [int]$audit.childManifestFormalCampaignTrueCount -ne 4 -or [int]$audit.memoryEvaluationFormalCampaignTrueCount -ne 4 -or $dryRun.passed -ne $true -or $negative.passed -ne $true) { throw 'Rehearsal evidence does not satisfy the frozen pass contract.' }
$files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Sort-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
$records = New-Object Collections.Generic.List[object]
$builder = New-Object Text.StringBuilder
$bytes = 0L
foreach ($file in $files) {
    $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
    $hash = Get-G13RPR2Sha256 $file.FullName
    $bytes += [long]$file.Length
    [void]$builder.Append($relative).Append("`t").Append([string]$file.Length).Append("`t").Append($hash).Append("`n")
    $records.Add([ordered]@{ relativePath = $relative; rawBytes = [long]$file.Length; sha256 = $hash })
}
$treeHash = Get-G13RPR2StringSha256 $builder.ToString()
foreach ($file in $files) { $file.IsReadOnly = $true }
$notReadOnly = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object { -not $_.IsReadOnly })
if ($notReadOnly.Count -ne 0) { throw 'Not all rehearsal files became read-only.' }
$postFiles = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Sort-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
$postBuilder = New-Object Text.StringBuilder
foreach ($file in $postFiles) { [void]$postBuilder.Append($file.FullName.Substring($root.Length + 1).Replace('\', '/')).Append("`t").Append([string]$file.Length).Append("`t").Append((Get-G13RPR2Sha256 $file.FullName)).Append("`n") }
$postHash = Get-G13RPR2StringSha256 $postBuilder.ToString()
if ($postHash -ne $treeHash -or $postFiles.Count -ne $files.Count) { throw 'Rehearsal tree changed during read-only freeze.' }
$manifest = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13r-pr2-attempt2-validation-only-contract-rehearsal-evidence-manifest-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'VALIDATION-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS / IMMUTABLE / PASSED'
    rehearsalRoot = $root
    fileCount = $files.Count
    rawBytes = $bytes
    canonicalTreeSha256 = $treeHash
    allFilesReadOnly = $true
    files = $records.ToArray()
    rehearsalAuditSha256 = Get-G13RPR2Sha256 (Join-Path $root 'rehearsal-contract-audit.json')
    campaignValidationOnlyDryRunSha256 = Get-G13RPR2Sha256 $dryRunPath
    negativeNoReceiptSha256 = Get-G13RPR2Sha256 $negativePath
    formalRootV2Created = Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v2')
    formalReceiptV2Created = Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v2.json')
    formalStatusV2Created = Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v2.json')
    unityProcessCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
    projectLockExists = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
    passed = $true
}
Write-G13RPR2AtomicJson -Path $manifestPath -Value $manifest -Depth 80
(Get-Item -LiteralPath $dryRunPath -Force).IsReadOnly = $true
(Get-Item -LiteralPath $negativePath -Force).IsReadOnly = $true
(Get-Item -LiteralPath $manifestPath -Force).IsReadOnly = $true
Write-Output "GATE13R-PR2-ATTEMPT2-REHEARSAL-EVIDENCE-FROZEN|$($files.Count)|$bytes|$treeHash"
exit 0

