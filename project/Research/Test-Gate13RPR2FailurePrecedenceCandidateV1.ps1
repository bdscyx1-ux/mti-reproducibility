[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$modulePath = Join-Path $ProjectPath 'Research\Gate13RPR2FailurePrecedenceCandidateV1.psm1'
$fixtureRoot = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Attempt2_Failure_Diagnosis\v1\FailurePrecedenceFixtures'
$blockFailure = Join-Path $fixtureRoot 'block-failure.json'
$quiescenceFailure = Join-Path $fixtureRoot 'quiescence-failure.json'
Import-Module -Name $modulePath -Force

$tests = New-Object Collections.Generic.List[object]
function Assert-Candidate {
    param([string]$Name,[bool]$Condition)
    if (-not $Condition) { throw "Candidate precedence test failed: $Name" }
    $tests.Add([ordered]@{name=$Name;passed=$true})
}

$both = Resolve-G13RPR2FailurePrecedenceCandidateV1 -BlockFailurePath $blockFailure -QuiescenceFailurePath $quiescenceFailure -QuiescenceExceptionMessage 'Post-exit quiescence failed.' -UnityExitCode 1
Assert-Candidate 'durable-block-is-primary' ([string]$both.primaryCause.kind -eq 'DURABLE-UNITY-BLOCK-FAILURE')
Assert-Candidate 'quiescence-is-secondary' (@($both.secondaryCauses).Count -eq 1 -and [string]$both.secondaryCauses[0].kind -eq 'POST-EXIT-QUIESCENCE-FAILURE')
Assert-Candidate 'primary-reason-preserved' ([string]$both.primaryCause.reasonCode -eq 'HARD-FAIL-BLOCK-WORKING-SET-512MIB+HARD-FAIL-BLOCK-PRIVATE-MEMORY-512MIB')
Assert-Candidate 'fail-closed' ($both.failClosed -eq $true -and $both.nextBlockAllowed -eq $false)
Assert-Candidate 'no-retry-resume-topup-merge' ($both.automaticRetryAllowed -eq $false -and $both.automaticResumeAllowed -eq $false -and $both.topUpAllowed -eq $false -and $both.partialMergeAllowed -eq $false)
Assert-Candidate 'cleanup-does-not-authorize-continuation' ($both.lockCleanupAuthorizesContinuation -eq $false)

$missing = Join-Path $fixtureRoot 'does-not-exist.json'
$onlyQuiescence = Resolve-G13RPR2FailurePrecedenceCandidateV1 -BlockFailurePath $missing -QuiescenceFailurePath $quiescenceFailure -QuiescenceExceptionMessage 'Post-exit quiescence failed.'
Assert-Candidate 'quiescence-primary-when-alone' ([string]$onlyQuiescence.primaryCause.kind -eq 'POST-EXIT-QUIESCENCE-FAILURE' -and @($onlyQuiescence.secondaryCauses).Count -eq 0)

$onlyExit = Resolve-G13RPR2FailurePrecedenceCandidateV1 -BlockFailurePath $missing -QuiescenceFailurePath $missing -UnityExitCode 2
Assert-Candidate 'nonzero-exit-primary-when-no-durable-record' ([string]$onlyExit.primaryCause.kind -eq 'NONZERO-UNITY-EXIT')

$moduleText = Get-Content -LiteralPath $modulePath -Raw
Assert-Candidate 'no-unity-launch-token' (-not $moduleText.Contains('Unity.exe') -and -not $moduleText.Contains('Start-Process'))
Assert-Candidate 'no-lock-deletion-token' (-not $moduleText.Contains('Remove-Item'))

$result = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-candidate-failure-precedence-test-summary-v1'
    passed = $true
    passedCount = $tests.Count
    failedCount = 0
    tests = $tests.ToArray()
    unityInvoked = $false
    lockDeleted = $false
    activeWrapperModified = $false
    attempt3Created = $false
}

$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
$json = $result | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
$result | ConvertTo-Json -Depth 20
