[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$TimestampUtc
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$research = Join-Path $ProjectPath 'Research'
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)

function Get-Sha256Lower([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$top = @(Get-ChildItem -LiteralPath $research -File | Where-Object {
    $_.Name -like 'Gate13R_PR2_Attempt2_Failure*' -or
    $_.Name -like 'Gate13R_PR2_Attempt2_Partial*' -or
    $_.Name -like 'Gate13R_PR2_Attempt2_Stale*' -or
    $_.Name -like 'Analyze-Gate13RPR2Attempt2FailureV*.py' -or
    $_.Name -like 'Test-Gate13RPR2Attempt2FailureDiagnosisV*.py' -or
    $_.Name -eq 'Test-Gate13RPR2Attempt2FailureDiagnosisFinalAuditV1.py' -or
    $_.Name -eq 'Remove-Gate13RPR2Attempt2StaleLockV1.ps1' -or
    $_.Name -like 'Gate13RPR2FailurePrecedenceCandidateV*.psm1' -or
    $_.Name -like 'Test-Gate13RPR2FailurePrecedenceCandidateV*.ps1' -or
    $_.Name -eq 'Gate13R_PR2_Attempt2_Memory_Enforcement_Boundary_Amendment.v2.md' -or
    $_.Name -eq 'Gate13R_PR2_Attempt2_Failure_Precedence_Candidate_Specification.v1.md' -or
    $_.Name -eq 'Gate13R_PR2_MemoryPolicy_Targeted_Pilot_Next_Authorization_Prompt.md' -or
    $_.Name -eq 'New-Gate13RPR2Attempt2FailureDiagnosisArtifactManifestV1.ps1'
})
$recursive = @(
    Get-ChildItem -LiteralPath (Join-Path $research 'Analysis\Gate13R_PR2_Attempt2_Failure_Diagnosis') -Recurse -File
    Get-ChildItem -LiteralPath (Join-Path $research 'Verification\Gate13R_PR2_Attempt2_Failure_Diagnosis\v1') -Recurse -File
)
$modifiedPlans = @(
    Get-Item -LiteralPath (Join-Path $research 'Overall_Project_Plan.md')
    Get-Item -LiteralPath (Join-Path $research 'Next_Session_Checkpoint.md')
)
$pathMap = @{}
foreach ($item in @($top + $recursive + $modifiedPlans)) {
    $full = [IO.Path]::GetFullPath($item.FullName)
    if ($full -ne $resolvedOutput) { $pathMap[$full] = $item }
}
$paths = [string[]]@($pathMap.Keys)
[Array]::Sort($paths, [StringComparer]::Ordinal)
$records = New-Object Collections.Generic.List[object]
[long]$rawBytes = 0
foreach ($path in $paths) {
    $item = Get-Item -LiteralPath $path
    $relative = $path.Substring($ProjectPath.Length).TrimStart('\').Replace('\','/')
    $records.Add([ordered]@{
        relativePath = $relative
        bytes = [long]$item.Length
        sha256 = Get-Sha256Lower $path
    })
    $rawBytes += [long]$item.Length
}
$payload = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13r-pr2-attempt2-failure-diagnosis-stage-artifact-manifest-v1'
    generatedAtUtc = $TimestampUtc
    statusTokens = @(
        'ATTEMPT2-EVIDENCE-FROZEN',
        'PRIMARY-MEMORY-FAILURE-DIAGNOSED',
        'SECONDARY-QUIESCENCE-FAILURE-DIAGNOSED',
        'MEMORY-POLICY-UNFROZEN',
        'FORMAL-ATTEMPT3-NOT-AUTHORIZED',
        'FORMAL-ANALYSIS-NOT-AUTHORIZED',
        'GATE14R-NOT-AUTHORIZED'
    )
    outputExcludesSelf = $true
    artifactCount = $records.Count
    artifactRawBytes = $rawBytes
    failedFormalRoot = [ordered]@{
        absolutePath = 'H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v2'
        fileCount = 28020
        rawBytes = 8536611302
        canonicalTreeSha256 = 'aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e'
        allFilesReadOnly = $true
    }
    artifacts = $records.ToArray()
}
$parent = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
$temporary = $resolvedOutput + '.tmp-' + [Guid]::NewGuid().ToString('N')
try {
    $json = $payload | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $resolvedOutput
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}
$payload | ConvertTo-Json -Depth 4
