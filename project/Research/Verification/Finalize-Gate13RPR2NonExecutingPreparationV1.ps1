[CmdletBinding()]
param(
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}
else {
    $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
}

$researchRoot = Join-Path $ProjectPath 'Research'
$formalRoot = Join-Path $researchRoot 'FormalRuns\Gate13R_RQAligned_S48H48\v1'
$auditPath = Join-Path $researchRoot 'Gate13R_PR2_NonExecuting_Final_Audit.v1.json'
$manifestPath = Join-Path $researchRoot 'Gate13R_PR2_NonExecuting_Evidence_Manifest.v1.json'
$prewritePath = Join-Path $researchRoot 'Gate13R_PR2_PreWrite_Preservation_Audit.v2.json'

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-TreeIdentity([string]$Path) {
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
    $rows = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $rows.Add("$relative`t$($file.Length)`t$(Get-LowerSha256 $file.FullName)")
    }
    $rows.Sort([StringComparer]::Ordinal)
    return [pscustomobject][ordered]@{
        resolvedAbsolutePath = $root.Replace('\', '/')
        fileCount = $files.Count
        rawBytes = [long](($files | Measure-Object Length -Sum).Sum)
        canonicalOrdinalTreeSha256 = Get-StringSha256 ($rows.ToArray() -join "`n")
    }
}

function Write-AtomicJson([string]$Path, [object]$Value) {
    if (Test-Path -LiteralPath $Path) {
        throw "Refusing to overwrite final evidence: $Path"
    }
    $parent = Split-Path -Parent $Path
    $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = $Value | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($temporary, $json + "`n", [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function New-Check([string]$Id, [bool]$Passed, [object]$Expected, [object]$Actual, [string]$Detail = '') {
    return [pscustomobject][ordered]@{
        id = $Id
        passed = $Passed
        expected = $Expected
        actual = $Actual
        detail = $Detail
    }
}

if (-not (Test-Path -LiteralPath $prewritePath -PathType Leaf)) {
    throw "Ordinal pre-write audit missing: $prewritePath"
}
if ((Test-Path -LiteralPath $auditPath) -or (Test-Path -LiteralPath $manifestPath)) {
    throw 'Final PR2 evidence already exists; refusing to overwrite it.'
}

$checks = New-Object 'System.Collections.Generic.List[object]'
$prewrite = Get-Content -Raw -LiteralPath $prewritePath | ConvertFrom-Json

foreach ($expected in @($prewrite.frozenTrees)) {
    $treePath = Join-Path $ProjectPath ([string]$expected.relativePath).Replace('/', '\')
    $actual = Get-TreeIdentity $treePath
    $passed = (
        $actual.fileCount -eq [int]$expected.fileCount -and
        $actual.rawBytes -eq [long]$expected.rawBytes -and
        $actual.canonicalOrdinalTreeSha256 -eq [string]$expected.canonicalTreeSha256
    )
    $checks.Add((New-Check ('frozen-tree-' + ([IO.Path]::GetFileName($treePath))) $passed $expected $actual 'Frozen upstream tree must remain byte-identical under ordinal row sorting.'))
}

foreach ($expected in @($prewrite.keyFiles)) {
    $path = Join-Path $ProjectPath ([string]$expected.relativePath).Replace('/', '\')
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $actualSha = if ($exists) { Get-LowerSha256 $path } else { $null }
    $checks.Add((New-Check ('key-file-' + [IO.Path]::GetFileName($path)) ($exists -and $actualSha -eq [string]$expected.sha256) ([string]$expected.sha256) $actualSha 'Frozen key-file SHA-256.'))
}

$verificationRoots = @(
    [pscustomobject]@{ relativePath='Research/Verification/Gate13R_PR2_NonExecuting_Preparation/v1'; fileCount=6; rawBytes=18738L; sha256='be1493a4e73354dd8cd4d4f4d5d25cb7dd2105b72d740b89bc17c394c7bb98ea'; disposition='FAILED-RETAINED' },
    [pscustomobject]@{ relativePath='Research/Verification/Gate13R_PR2_NonExecuting_Preparation/v2'; fileCount=6; rawBytes=18744L; sha256='ac9c0ddca7ca97207b391732cc65d7ba8276ed9089af84e59252adf0dec67589'; disposition='FAILED-RETAINED' },
    [pscustomobject]@{ relativePath='Research/Verification/Gate13R_PR2_NonExecuting_Preparation/v3'; fileCount=14; rawBytes=11646896L; sha256='482e3a92fafec64866f4cf445d8f3052e638c1aa4c05b0009f277a31c63cfab3'; disposition='FAILED-RETAINED-62-OF-63' },
    [pscustomobject]@{ relativePath='Research/Verification/Gate13R_PR2_NonExecuting_Preparation/v4'; fileCount=14; rawBytes=11585336L; sha256='4c1262219f4923ba201de089b4bcf0b3be11c8c59c8dab2a9623bf53f4e38d29'; disposition='PASSED-63-OF-63' }
)
$verificationIdentities = @()
foreach ($expected in $verificationRoots) {
    $actual = Get-TreeIdentity (Join-Path $ProjectPath $expected.relativePath.Replace('/', '\'))
    $passed = (
        $actual.fileCount -eq $expected.fileCount -and
        $actual.rawBytes -eq $expected.rawBytes -and
        $actual.canonicalOrdinalTreeSha256 -eq $expected.sha256
    )
    $verificationIdentities += [pscustomobject][ordered]@{
        relativePath = $expected.relativePath
        disposition = $expected.disposition
        fileCount = $actual.fileCount
        rawBytes = $actual.rawBytes
        canonicalOrdinalTreeSha256 = $actual.canonicalOrdinalTreeSha256
        passed = $passed
    }
    $checks.Add((New-Check ('verification-root-v' + ($verificationIdentities.Count)) $passed $expected $actual $expected.disposition))
}

$expectedFiles = @(
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_NonExecuting_Formal_Preparation_Authorization.v1.json'; bytes=1708L; sha256='38a43ae2e29316648d34441bc3276c985b4119e9989343b78c48bb88c100c192' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Preparation_Amendment.v1.json'; bytes=2900L; sha256='65db60535b9ef80f92d48fc9d7427a7cd16af52c8757e6d9588d97a142a47d24' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Preparation_Specification.v1.md'; bytes=6326L; sha256='379a14dbe890531c3597597453abfef8f1d462aacd26868e40ee4bfcd51fff40' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Preparation_Test_Design.v1.md'; bytes=4337L; sha256='2384bbc18db86002c1cb65914c2621abf2f8f33e8b7dddfc015c4e4d23787dd9' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Campaign_Config.v2.json'; bytes=288367L; sha256='87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl'; bytes=11220567L; sha256='df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json'; bytes=32861L; sha256='b5763f1540c0193199201cd6bf025c43443d5bd2e67cb8808e0a2b86ef91b724' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Storage_WallClock_Preflight.v2.json'; bytes=2082L; sha256='c474499e647d5ad32efe01d199ede187b61f004e9487b8278e44109258cd0435' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Preparation_Provenance.v2.json'; bytes=5352L; sha256='9e81530bcf6d32dd1792c8bd693d72988bef6f37e59a1ad154019ca228908e56' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Preparation_Generation_Summary.v2.json'; bytes=1574L; sha256='535d2205ebd84dffa446048f42e4050657add746782487996fe24f177254fe1b' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Preparation_Schema.v2.json'; bytes=3611L; sha256='940bfca8cb3e677deadff2600471eeaec9e99ff6bab9a06a625a0f30365a9d1e' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_PreWrite_Preservation_Audit.v2.json'; bytes=5182L; sha256='d02d49773e6404e036e1d5c3d7c8851f5a39e8d9ba129091ad27552a9779d2eb' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json'; bytes=6315L; sha256='669a5291ab2e219461ca9797696ba29bce32e198c11a983f0f1f31f3f7799fbc' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.md'; bytes=5524L; sha256='9ad1d5a7183fd14ad5aa26b522089bce4dab7395ada636008b96bb8986e8e197' },
    [pscustomobject]@{ relativePath='Research/Gate13R_PR2_Formal_Campaign_Next_Authorization_Prompt.md'; bytes=7724L; sha256='0cdfa4dfe87ce5642be675a16653d9b8cb5cb29721bdda742a3cfd97ae566661' },
    [pscustomobject]@{ relativePath='Research/Overall_Project_Plan.md'; bytes=92924L; sha256='cf1dcc66eabe433f7bfdee3763f58310fb78e073ee4fe8127e26ca8ac491708a' },
    [pscustomobject]@{ relativePath='Research/Next_Session_Checkpoint.md'; bytes=6055L; sha256='20bad61307073c761d8d08a01f79589b3ffd79aa1bc1e7065ae86d3bb12d28e6' }
)

$officialFileIdentities = @()
foreach ($expected in $expectedFiles) {
    $path = Join-Path $ProjectPath $expected.relativePath.Replace('/', '\')
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $item = if ($exists) { Get-Item -LiteralPath $path } else { $null }
    $actual = [pscustomobject][ordered]@{
        exists = $exists
        rawBytes = if ($exists) { [long]$item.Length } else { $null }
        sha256 = if ($exists) { Get-LowerSha256 $path } else { $null }
    }
    $passed = $exists -and $actual.rawBytes -eq $expected.bytes -and $actual.sha256 -eq $expected.sha256
    $officialFileIdentities += [pscustomobject][ordered]@{
        relativePath = $expected.relativePath
        rawBytes = $actual.rawBytes
        sha256 = $actual.sha256
        passed = $passed
    }
    $checks.Add((New-Check ('official-file-' + [IO.Path]::GetFileName($path)) $passed $expected $actual 'Version-bound PR2 artifact identity.'))
}

$coreSummaryPath = Join-Path $researchRoot 'Verification\Gate13R_PR2_NonExecuting_Preparation\v4\core\core-validation-summary.json'
$validationAuditPath = Join-Path $researchRoot 'Verification\Gate13R_PR2_NonExecuting_Preparation\v4\validation-only-final-audit.json'
$coreSummary = Get-Content -Raw -LiteralPath $coreSummaryPath | ConvertFrom-Json
$validationAudit = Get-Content -Raw -LiteralPath $validationAuditPath | ConvertFrom-Json
$checks.Add((New-Check 'v4-core-validation-63-of-63' ($coreSummary.status -eq 'PASS' -and $coreSummary.checkCount -eq 63 -and $coreSummary.passedCheckCount -eq 63 -and $coreSummary.failedCheckCount -eq 0) 'PASS / 63 / 63 / 0' "$($coreSummary.status) / $($coreSummary.checkCount) / $($coreSummary.passedCheckCount) / $($coreSummary.failedCheckCount)" 'Successful validation attempt.'))
$checks.Add((New-Check 'v4-final-validation-audit-pass' ($validationAudit.status -eq 'PASS' -and $validationAudit.prePreservationPassed -and $validationAudit.postPreservationPassed -and -not $validationAudit.formalCampaignAuthorized -and -not $validationAudit.gate14rAuthorized) 'PASS / preservation PASS / authorization false' $validationAudit 'Validation-only final audit.'))

$jsonFailures = @()
$pr2JsonFiles = @(Get-ChildItem -LiteralPath $researchRoot -File -Filter 'Gate13R_PR2*.json')
foreach ($jsonFile in $pr2JsonFiles) {
    try {
        $null = Get-Content -Raw -LiteralPath $jsonFile.FullName | ConvertFrom-Json
    }
    catch {
        $jsonFailures += [pscustomobject]@{ relativePath=$jsonFile.FullName.Substring($ProjectPath.Length).TrimStart('\').Replace('\','/'); error=$_.Exception.Message }
    }
}
$checks.Add((New-Check 'all-root-pr2-json-parse' ($jsonFailures.Count -eq 0) 0 $jsonFailures.Count ($jsonFailures | ConvertTo-Json -Compress)))

$schedulePath = Join-Path $researchRoot 'Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl'
$scheduleLineCount = 0
foreach ($unusedLine in [IO.File]::ReadLines($schedulePath)) {
    $scheduleLineCount += 1
}
$checks.Add((New-Check 'schedule-jsonl-record-count' ($scheduleLineCount -eq 3552) 3552 $scheduleLineCount 'One record per fresh Unity block-process.'))

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$formalReceipts = @(Get-ChildItem -LiteralPath $researchRoot -File -Filter 'Gate13R_PR2*Formal*Execution*Receipt*' -ErrorAction SilentlyContinue)
$formalRootExists = Test-Path -LiteralPath $formalRoot
$checks.Add((New-Check 'unity-process-count-zero' ($unityProcesses.Count -eq 0) 0 $unityProcesses.Count 'No Unity Editor was launched by PR2.'))
$checks.Add((New-Check 'future-formal-root-absent' (-not $formalRootExists) $false $formalRootExists $formalRoot.Replace('\','/')))
$checks.Add((New-Check 'formal-execution-receipt-absent' ($formalReceipts.Count -eq 0) 0 $formalReceipts.Count (($formalReceipts | Select-Object -ExpandProperty FullName) -join '; ')))

$driveName = [IO.Path]::GetPathRoot($ProjectPath).TrimEnd('\').TrimEnd(':')
$drive = Get-PSDrive -Name $driveName
$minimumFreeBytes = 57397541440L
$checks.Add((New-Check 'launch-storage-preflight-currently-sufficient' ([long]$drive.Free -ge $minimumFreeBytes) $minimumFreeBytes ([long]$drive.Free) 'Informational preparation check only; must be rerun immediately before any separately authorized formal launch.'))

$failedChecks = @($checks | Where-Object { -not $_.passed })
$passed = $failedChecks.Count -eq 0
$nowUtc = [DateTimeOffset]::UtcNow
$localZone = [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
$nowLocal = [TimeZoneInfo]::ConvertTime($nowUtc, $localZone)

$finalAudit = [pscustomobject][ordered]@{
    schemaVersion = 1
    auditId = 'gate13r-pr2-nonexecuting-formal-preparation-final-audit-v1'
    completedAtUtc = $nowUtc.ToString('o')
    completedAtAsiaShanghai = $nowLocal.ToString('o')
    status = if ($passed) { 'PASS / PR2-NONEXECUTING-PREPARATION-VALIDATED / S48-H48-FROZEN / GATE13R-FORMAL-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED' } else { 'FAIL / FAIL-CLOSED / GATE13R-FORMAL-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED' }
    passed = $passed
    checkCount = $checks.Count
    passedCheckCount = @($checks | Where-Object { $_.passed }).Count
    failedCheckCount = $failedChecks.Count
    failedCheckIds = @($failedChecks | ForEach-Object { $_.id })
    checks = $checks.ToArray()
    frozenDesign = [pscustomobject][ordered]@{
        designId = 'gate13r-rq-aligned-s48-h48-strict-serial-v1'
        sharedCampaignCount = 32
        sharedBlocksPerCampaign = 48
        heterogeneousScenarioCount = 21
        heterogeneousMatchedSuperblocksPerScenario = 48
        ABPerHeterogeneousScenario = 24
        BAPerHeterogeneousScenario = 24
        totalProcessCount = 3552
        totalSampleCount = 10176
        strictSerial = $true
        maximumConcurrentUnityEditorProcesses = 1
    }
    resourceProjection = [pscustomobject][ordered]@{
        serialP50Hours = 20.808185450666667
        conservativeSummedP95Hours = 26.45538207066667
        projectedP95RawBytes = 9631912320L
        projectedSafetyBytes = 14447868480L
        reserveBytes = 42949672960L
        minimumLaunchFreeBytes = $minimumFreeBytes
        observedFreeBytesAtCloseout = [long]$drive.Free
        formalLaunchRecheckRequired = $true
    }
    verificationRootIdentities = $verificationIdentities
    officialFileIdentities = $officialFileIdentities
    authorizationBoundary = [pscustomobject][ordered]@{
        gate13RFormalCampaignAuthorized = $false
        gate14RAuthorized = $false
        unityEditorProcessCount = $unityProcesses.Count
        formalRootRelativePath = 'Research/FormalRuns/Gate13R_RQAligned_S48H48/v1'
        formalRootExists = $formalRootExists
        formalExecutionReceiptCount = $formalReceipts.Count
        nextAuthorizationPromptRelativePath = 'Research/Gate13R_PR2_Formal_Campaign_Next_Authorization_Prompt.md'
    }
}
Write-AtomicJson $auditPath $finalAudit

$evidenceRows = New-Object 'System.Collections.Generic.List[object]'
$rootFiles = @(Get-ChildItem -LiteralPath $researchRoot -File | Where-Object {
    ($_.Name -like 'Gate13R_PR2*' -or $_.Name -in @('Overall_Project_Plan.md','Next_Session_Checkpoint.md')) -and
    $_.FullName -ne $manifestPath -and
    $_.Name -ne 'Gate13R_PR2_NonExecuting_Formal_Preparation_Run_Passport_run_ledger.yaml'
})
$verificationScripts = @(Get-ChildItem -LiteralPath (Join-Path $researchRoot 'Verification') -File | Where-Object { $_.Name -like '*Gate13RPR2*' })
foreach ($file in @($rootFiles + $verificationScripts | Sort-Object FullName -Unique)) {
    $evidenceRows.Add([pscustomobject][ordered]@{
        relativePath = $file.FullName.Substring($ProjectPath.Length).TrimStart('\').Replace('\','/')
        rawBytes = [long]$file.Length
        sha256 = Get-LowerSha256 $file.FullName
    })
}

$manifest = [pscustomobject][ordered]@{
    schemaVersion = 1
    manifestId = 'gate13r-pr2-nonexecuting-formal-preparation-evidence-manifest-v1'
    createdAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    status = $finalAudit.status
    finalAudit = [pscustomobject][ordered]@{
        relativePath = 'Research/Gate13R_PR2_NonExecuting_Final_Audit.v1.json'
        rawBytes = (Get-Item -LiteralPath $auditPath).Length
        sha256 = Get-LowerSha256 $auditPath
    }
    fileCount = $evidenceRows.Count
    files = $evidenceRows.ToArray()
    verificationRoots = $verificationIdentities
    frozenUpstreamTrees = @($prewrite.frozenTrees)
    boundary = [pscustomobject][ordered]@{
        nonExecuting = $true
        formalCampaignAuthorized = $false
        gate14RAuthorized = $false
        unityEditorLaunched = $false
        formalRootCreated = $false
        formalExecutionReceiptCreated = $false
    }
}
Write-AtomicJson $manifestPath $manifest

$result = [pscustomobject][ordered]@{
    status = $finalAudit.status
    checkCount = $finalAudit.checkCount
    passedCheckCount = $finalAudit.passedCheckCount
    failedCheckCount = $finalAudit.failedCheckCount
    finalAuditPath = $auditPath.Replace('\','/')
    finalAuditSha256 = Get-LowerSha256 $auditPath
    evidenceManifestPath = $manifestPath.Replace('\','/')
    evidenceManifestSha256 = Get-LowerSha256 $manifestPath
}
$result | ConvertTo-Json -Depth 10

if (-not $passed) {
    exit 1
}
