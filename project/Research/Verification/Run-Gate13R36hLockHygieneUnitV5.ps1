[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$officialRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v5'))
$preImplementationRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation'))
$allowed=$OutputDirectory.StartsWith($officialRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)-or$OutputDirectory.StartsWith($preImplementationRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
if(-not$allowed){throw 'Lock-hygiene unit output is outside an authorized verification root.'}
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13R36hLockHygieneUnitV5|$ProjectPath");exit 0}
if(Test-Path -LiteralPath $OutputDirectory){throw "Create-new lock-hygiene unit output exists: $OutputDirectory"}
if(@(Get-Process Unity -ErrorAction SilentlyContinue).Count-ne0){throw 'Lock-hygiene unit test requires zero Unity processes.'}
foreach($root in @('Research\PilotRuns\Gate13R_36h_10pct_4Lane\v5','Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){if(Test-Path -LiteralPath (Join-Path $ProjectPath $root)){throw "Forbidden experiment root exists: $root"}}

$modulePath=Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1'
$expectedModuleHash='9eba2284dc90fcf6dbbc59080301c1ac6db14c5029f8adab69db234c94f879d6'
$actualModuleHash=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualModuleHash-ne$expectedModuleHash){throw 'Frozen lock-hygiene module hash mismatch.'}
Import-Module $modulePath -Force
New-Item -ItemType Directory -Path $OutputDirectory|Out-Null
$assertions=New-Object Collections.Generic.List[object]
$failures=New-Object Collections.Generic.List[string]
function Add([string]$Name,[bool]$Passed,[string]$Detail){$script:assertions.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail});if(-not$Passed){$script:failures.Add("$Name`: $Detail")}}
function Clone-Snapshot($Source,[hashtable]$Changes){$copy=($Source|ConvertTo-Json -Depth 10|ConvertFrom-Json);foreach($key in $Changes.Keys){$copy.$key=$Changes[$key]};return $copy}
function Write-Summary([bool]$Passed,[string]$ErrorText,$Cleanup){
    $summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-36h-expected-negative-lock-hygiene-unit-v5';completedAtUtc=[DateTime]::UtcNow.ToString('o');moduleRelativePath='Research/Gate10RLockHygieneV3.psm1';moduleSha256=$actualModuleHash;assertionCount=$assertions.Count;passedAssertionCount=@($assertions|Where-Object passed).Count;failedAssertionCount=@($assertions|Where-Object{-not$_.passed}).Count;assertions=$assertions.ToArray();failures=$failures.ToArray();cleanupResult=$Cleanup;unityProcessCount=@(Get-Process Unity -ErrorAction SilentlyContinue).Count;pilotRootCreated=Test-Path (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v5');formalRootCreated=Test-Path (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1');error=$ErrorText;formalCampaign=$false;pilotExecuted=$false;passed=$Passed}
    $json=($summary|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText((Join-Path $OutputDirectory 'summary.json'),$json,(New-Object Text.UTF8Encoding($false,$true)))
}

$cleanup=$null
try{
    $synthetic=Join-Path $OutputDirectory 'SyntheticProject';$temp=Join-Path $synthetic 'Temp';$evidence=Join-Path $OutputDirectory 'Evidence';New-Item -ItemType Directory -Path $temp,$evidence|Out-Null
    $lock=Join-Path $temp 'UnityLockfile';[IO.File]::WriteAllBytes($lock,[byte[]]@())
    $now=[DateTimeOffset]::Now;$started=$now.AddSeconds(-2);$completed=$now.AddSeconds(2)
    $snapshot=Get-Gate10RLockSnapshotV3 -ProjectPath $synthetic
    $valid=Test-Gate10RLockCleanupEligibilityV3 -Snapshot $snapshot -Role expected-negative -OwnedProcessStartedAt $started -OwnedProcessCompletedAt $completed -OwnedProcessAlive $false -UnityProcessCount 0
    Add 'valid-expected-negative' $valid.eligible ($valid.errors-join',')
    $positive=Test-Gate10RLockCleanupEligibilityV3 -Snapshot $snapshot -Role positive -OwnedProcessStartedAt $started -OwnedProcessCompletedAt $completed -OwnedProcessAlive $false -UnityProcessCount 0
    Add 'positive-role-refused' (-not$positive.eligible-and$positive.errors-contains'cleanup-role-not-authorized') ($positive.errors-join',')
    $alive=Test-Gate10RLockCleanupEligibilityV3 -Snapshot $snapshot -Role expected-negative -OwnedProcessStartedAt $started -OwnedProcessCompletedAt $completed -OwnedProcessAlive $true -UnityProcessCount 0
    Add 'live-owner-refused' (-not$alive.eligible-and$alive.errors-contains'owned-process-still-alive') ($alive.errors-join',')
    $unity=Test-Gate10RLockCleanupEligibilityV3 -Snapshot $snapshot -Role expected-negative -OwnedProcessStartedAt $started -OwnedProcessCompletedAt $completed -OwnedProcessAlive $false -UnityProcessCount 1
    Add 'nonzero-unity-refused' (-not$unity.eligible-and$unity.errors-contains'unity-process-count-not-zero') ($unity.errors-join',')
    foreach($vector in @(
        @{name='wrong-path-refused';changes=@{pathMatchesExpected=$false};error='lock-path-not-exact'},
        @{name='reparse-refused';changes=@{isReparsePoint=$true};error='lock-is-reparse-point'},
        @{name='nonzero-bytes-refused';changes=@{bytes=[long]1};error='lock-is-not-zero-bytes'},
        @{name='nonempty-hash-refused';changes=@{sha256=('0'*64)};error='lock-sha256-is-not-empty-file-hash'},
        @{name='shared-open-refused';changes=@{exclusiveReadWriteAvailable=$false};error='lock-cannot-be-opened-exclusively'},
        @{name='timestamp-refused';changes=@{creationTimeUtc=$now.AddHours(-1).UtcDateTime.ToString('o')};error='lock-creation-outside-owned-window'}
    )){$candidate=Clone-Snapshot $snapshot $vector.changes;$result=Test-Gate10RLockCleanupEligibilityV3 -Snapshot $candidate -Role expected-negative -OwnedProcessStartedAt $started -OwnedProcessCompletedAt $completed -OwnedProcessAlive $false -UnityProcessCount 0;Add $vector.name (-not$result.eligible-and$result.errors-contains$vector.error) ($result.errors-join',')}
    $fakePid=2147483000
    $cleanup=Invoke-Gate10RControlledLockCleanupV3 -ProjectPath $synthetic -OwnedProcessId $fakePid -OwnedProcessStartedAt $started -OwnedProcessCompletedAt $completed -Role expected-negative -EvidenceDirectory $evidence -ContextId 'g13r36-v5-synthetic-negative'
    Add 'controlled-cleanup-passed' ($cleanup.passed-eq$true-and-not(Test-Path -LiteralPath $lock)) ([string]$cleanup.mode)
    Add 'capture-receipt-bound' ((Test-Path -LiteralPath $cleanup.captureReceiptPath)-and(Get-Gate10RLockFileSha256V3 $cleanup.captureReceiptPath)-eq[string]$cleanup.captureReceiptSha256) ([string]$cleanup.captureReceiptPath)
    Add 'completion-receipt-bound' ((Test-Path -LiteralPath $cleanup.completionReceiptPath)-and(Get-Gate10RLockFileSha256V3 $cleanup.completionReceiptPath)-eq[string]$cleanup.completionReceiptSha256) ([string]$cleanup.completionReceiptPath)
    Add 'unity-remained-zero' (@(Get-Process Unity -ErrorAction SilentlyContinue).Count-eq0) 'No Unity process was started.'
    $passed=$failures.Count-eq0-and@($assertions|Where-Object{-not$_.passed}).Count-eq0
    Write-Summary $passed '' $cleanup
    if(-not$passed){exit 1}
    Write-Host "Gate13R v5 lock-hygiene unit passed: $($assertions.Count)/$($assertions.Count)." -ForegroundColor Green
    exit 0
}catch{
    $failures.Add($_.Exception.ToString());Write-Summary $false $_.Exception.ToString() $cleanup;Write-Error "Gate13R v5 lock-hygiene unit failed: $($_.Exception.Message)";exit 1
}
