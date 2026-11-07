[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = 'H:\DDM_Final_Project'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Lower {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$proposalRoot = Join-Path $ProjectRoot 'Research\Gate14Re-MQ-CFF-IDFF\FormalDesignProposal\v1'
$proposalPath = Join-Path $proposalRoot 'formal-mq-design-recommendation.v1.json'
$readmePath = Join-Path $proposalRoot 'README.md'
$proposal = Get-Content -LiteralPath $proposalPath -Raw | ConvertFrom-Json -Depth 100
$errors = [System.Collections.Generic.List[string]]::new()

if ($proposal.schema -ne 'gate14re-mq-cff-idff-formal-design-recommendation-v1') {
    $errors.Add('proposal schema mismatch')
}
if ($proposal.status -ne 'PROPOSAL_ONLY_AWAITING_EXPLICIT_USER_SCIENTIFIC_AUTHORIZATION') {
    $errors.Add('proposal status mismatch')
}

$falseBoundaryNames = @(
    'formalDesignFrozen',
    'formalInputsDrawn',
    'formalScheduleGenerated',
    'formalCollectionAuthorized',
    'formalCollectionLaunched',
    'formalAnalysisAuthorized',
    'formalAnalysisLaunched'
)
foreach ($name in $falseBoundaryNames) {
    if ([bool]$proposal.authorityBoundary.$name) {
        $errors.Add("authority boundary must remain false: $name")
    }
}

$hypotheses = @($proposal.recommendedPrimaryFamily.hypotheses)
if ($hypotheses.Count -ne 6) {
    $errors.Add("expected 6 primary hypotheses, found $($hypotheses.Count)")
}
$hypothesisIds = @($hypotheses | ForEach-Object { [string]$_.id })
if (@($hypothesisIds | Sort-Object -Unique).Count -ne $hypothesisIds.Count) {
    $errors.Add('primary hypothesis IDs are not unique')
}

$candidateB = @($proposal.recommendedPowerAndSampleSize.candidateB | ForEach-Object { [int]$_ })
$expectedB = @(36, 72, 108, 144)
if (($candidateB -join ',') -ne ($expectedB -join ',')) {
    $errors.Add("candidate B mismatch: $($candidateB -join ',')")
}

$ratio = [double]$proposal.recommendedPrimaryFamily.recommendedMipe.wallTimeRatio
$logThreshold = [double]$proposal.recommendedPrimaryFamily.recommendedMipe.logScaleExact
if ([Math]::Abs([Math]::Log($ratio) - $logThreshold) -gt 1e-12) {
    $errors.Add('MIPE ratio and log threshold are inconsistent')
}

$runtimeGate = $proposal.runtimeGate
$stressBudgets = @(
    [double]$runtimeGate.candidateBudgetsStressHours.B36,
    [double]$runtimeGate.candidateBudgetsStressHours.B72,
    [double]$runtimeGate.candidateBudgetsStressHours.B108,
    [double]$runtimeGate.candidateBudgetsStressHours.B144
)
if (@($stressBudgets | Where-Object { $_ -ge [double]$runtimeGate.sevenDayGateHours }).Count -ne 0) {
    $errors.Add('at least one current candidate reaches the seven-day gate')
}
if ([bool]$runtimeGate.triggeredByAnyCurrentCandidate) {
    $errors.Add('runtime gate trigger flag must be false')
}

$bindingResults = @()
foreach ($binding in @($proposal.evidenceBindings)) {
    $absolutePath = Join-Path $ProjectRoot ([string]$binding.relativePath)
    $exists = Test-Path -LiteralPath $absolutePath -PathType Leaf
    $actualSha = if ($exists) { Get-Sha256Lower -Path $absolutePath } else { $null }
    $matches = $exists -and ($actualSha -eq [string]$binding.sha256)
    if (-not $matches) {
        $errors.Add("evidence binding mismatch: $($binding.relativePath)")
    }
    $bindingResults += [ordered]@{
        role = [string]$binding.role
        relativePath = [string]$binding.relativePath
        exists = $exists
        expectedSha256 = [string]$binding.sha256
        actualSha256 = $actualSha
        matches = $matches
    }
}

$result = [ordered]@{
    schema = 'gate14re-mq-cff-idff-formal-design-proposal-validation-result-v1'
    status = if ($errors.Count -eq 0) { 'PASS_PROPOSAL_ARTIFACT_ONLY_NOT_A_FORMAL_DESIGN_FREEZE' } else { 'FAIL_PROPOSAL_VALIDATION' }
    proposalSha256 = Get-Sha256Lower -Path $proposalPath
    readmeSha256 = Get-Sha256Lower -Path $readmePath
    validatorSha256 = Get-Sha256Lower -Path $PSCommandPath
    primaryHypothesisCount = $hypotheses.Count
    candidateB = $candidateB
    maximumStressBudgetHours = ($stressBudgets | Measure-Object -Maximum).Maximum
    evidenceBindings = $bindingResults
    errorCount = $errors.Count
    errors = @($errors)
    formalDesignFrozen = $false
    formalCollectionLaunched = $false
    formalAnalysisLaunched = $false
}

$result | ConvertTo-Json -Depth 20
if ($errors.Count -ne 0) {
    exit 1
}
