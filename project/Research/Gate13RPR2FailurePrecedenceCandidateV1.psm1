Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function Read-G13RPR2CandidateJson {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Resolve-G13RPR2FailurePrecedenceCandidateV1 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$BlockFailurePath,
        [Parameter(Mandatory=$true)][string]$QuiescenceFailurePath,
        [string]$QuiescenceExceptionMessage,
        [int]$UnityExitCode = 0,
        [bool]$TimedOut = $false
    )

    $blockFailure = Read-G13RPR2CandidateJson -Path $BlockFailurePath
    $quiescenceFailure = Read-G13RPR2CandidateJson -Path $QuiescenceFailurePath
    $primary = $null
    $secondary = New-Object Collections.Generic.List[object]

    if ($null -ne $blockFailure) {
        $primary = [ordered]@{
            kind = 'DURABLE-UNITY-BLOCK-FAILURE'
            failedAtUtc = [string]$blockFailure.failedAtUtc
            blockId = [string]$blockFailure.blockId
            runId = [string]$blockFailure.failedRunId
            reasonCode = [string]$blockFailure.memoryGateReasonCode
            source = $BlockFailurePath
        }
    } elseif ($TimedOut) {
        $primary = [ordered]@{ kind='HARD-TIMEOUT'; reasonCode='HARD-TIMEOUT'; source=$null }
    } elseif ($UnityExitCode -ne 0) {
        $primary = [ordered]@{ kind='NONZERO-UNITY-EXIT'; reasonCode=('UNITY-EXIT-' + $UnityExitCode); source=$null }
    }

    if ($null -ne $quiescenceFailure -or -not [string]::IsNullOrWhiteSpace($QuiescenceExceptionMessage)) {
        $quiescenceCause = [ordered]@{
            kind = 'POST-EXIT-QUIESCENCE-FAILURE'
            savedAtUtc = if ($null -ne $quiescenceFailure) { [string]$quiescenceFailure.savedAtUtc } else { $null }
            reasonCode = 'POST-EXIT-QUIESCENCE-FAILURE'
            exceptionMessage = $QuiescenceExceptionMessage
            source = if ($null -ne $quiescenceFailure) { $QuiescenceFailurePath } else { $null }
        }
        if ($null -eq $primary) { $primary = $quiescenceCause }
        else { $secondary.Add($quiescenceCause) }
    }

    $failed = $null -ne $primary
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        resultKind = 'gate13r-pr2-candidate-failure-precedence-resolution-v1'
        candidateOnly = $true
        activeWrapperModified = $false
        failed = $failed
        primaryCause = $primary
        secondaryCauses = $secondary.ToArray()
        failClosed = $failed
        nextBlockAllowed = $false
        automaticRetryAllowed = $false
        automaticResumeAllowed = $false
        topUpAllowed = $false
        partialMergeAllowed = $false
        lockCleanupAuthorizesContinuation = $false
    }
}

Export-ModuleMember -Function Resolve-G13RPR2FailurePrecedenceCandidateV1
