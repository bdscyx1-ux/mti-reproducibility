[CmdletBinding()]
param(
    [string]$ProjectPath = '',
    [string]$PythonPath = 'C:\Users\bdscy\AppData\Local\Python\bin\python3.exe',
    [string]$VerificationRoot = '',
    [string]$StageProvenancePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')) }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($VerificationRoot)) { $VerificationRoot = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR1B_CompositeProcessIdentity_Recovery\v1' }
if ([string]::IsNullOrWhiteSpace($StageProvenancePath)) { $StageProvenancePath = Join-Path $ProjectPath 'Research\Gate13R_PR1B_v4_CompositeProcessIdentity_Provenance.v1.json' }
$VerificationRoot = [IO.Path]::GetFullPath($VerificationRoot)
$StageProvenancePath = [IO.Path]::GetFullPath($StageProvenancePath)

$pilotRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v7-gate13r-pr1b-order-effect-pathsafe-v4'
$recoveryRoot = Join-Path $ProjectPath 'Research\Analysis\Gate13R_PR1B_CompositeProcessIdentity_Recovery\v1'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned\v1'
$analyzer = Join-Path $ProjectPath 'Research\Analyze-Gate13RPR1BCompositeProcessIdentityRecoveryV1.py'
$plan = Join-Path $ProjectPath 'Research\Gate13R_PR1B_OrderEffect_Pilot_Plan.v9.json'
$sourceProvenance = Join-Path $ProjectPath 'Research\Gate13R_PR1B_OrderEffect_Provenance.v10.json'
$schema = Join-Path $ProjectPath 'Research\Gate13R_PR1B_v4_AnalysisRecovery_Output_Schema.v1.json'
$fixture = Join-Path $ProjectPath 'Research\Verification\Fixtures\Gate13R_PR1B_CompositeProcessIdentity\v1\expected-results.json'
$expectedTree = '4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed'

function Get-LowerSha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-StringSha256([string]$Value) { $sha=[Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() } }
function Get-TreeIdentity([string]$Path) {
    $treeRoot=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    $files=@(Get-ChildItem -LiteralPath $treeRoot -Recurse -File -Force | Sort-Object FullName)
    $rows=@($files | ForEach-Object { $relative=$_.FullName.Substring($treeRoot.Length).TrimStart('\').Replace('\','/'); "$relative`t$($_.Length)`t$(Get-LowerSha256 $_.FullName)" })
    [pscustomobject][ordered]@{ resolvedAbsolutePath=$treeRoot.Replace('\','/'); fileCount=$files.Count; rawBytes=[long](($files|Measure-Object Length -Sum).Sum); canonicalTreeSha256=Get-StringSha256 ($rows -join "`n") }
}
function Write-AtomicJson([string]$Path, [object]$Value) {
    $parent=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $temp=Join-Path $parent ('.g13v4-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    try { [IO.File]::WriteAllText($temp, (($Value|ConvertTo-Json -Depth 100)+'`n'), (New-Object Text.UTF8Encoding($false))); Move-Item -LiteralPath $temp -Destination $Path -Force } finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force} }
}
function Add-Check([System.Collections.Generic.List[object]]$Checks,[string]$Id,[bool]$Passed,[object]$Detail){$Checks.Add([pscustomobject][ordered]@{id=$Id;passed=$Passed;detail=$Detail})}

if(Test-Path -LiteralPath $VerificationRoot){throw "verification root already exists: $VerificationRoot"}
if(Test-Path -LiteralPath $recoveryRoot){throw "recovery root must be absent before validation: $recoveryRoot"}
New-Item -ItemType Directory -Path $VerificationRoot -Force | Out-Null
$checks=New-Object 'System.Collections.Generic.List[object]'
$started=[DateTimeOffset]::UtcNow

try {
    $treeBefore=Get-TreeIdentity $pilotRoot
    Add-Check $checks 'frozen-v7-tree-before' ($treeBefore.canonicalTreeSha256 -eq $expectedTree -and $treeBefore.fileCount -eq 9118 -and $treeBefore.rawBytes -eq 253513394) $treeBefore
    Add-Check $checks 'formal-root-absent' (-not (Test-Path -LiteralPath $formalRoot)) $formalRoot
    Add-Check $checks 'recovery-root-absent' (-not (Test-Path -LiteralPath $recoveryRoot)) $recoveryRoot
    Add-Check $checks 'unity-lockfile-absent' (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'Temp/UnityLockfile'
    $unityCount=@(Get-Process -Name Unity,UnityEditor -ErrorAction SilentlyContinue).Count
    Add-Check $checks 'no-active-unity-process-before' ($unityCount -eq 0) $unityCount
    Add-Check $checks 'stage-provenance-present' (Test-Path -LiteralPath $StageProvenancePath) $StageProvenancePath
    $stageProvenance=Get-Content -LiteralPath $StageProvenancePath -Raw|ConvertFrom-Json
    $stageMismatches=New-Object 'System.Collections.Generic.List[object]'
    foreach($bound in $stageProvenance.boundFiles){
        $boundPath=Join-Path $ProjectPath ([string]$bound.relativePath -replace '/','\')
        if(-not (Test-Path -LiteralPath $boundPath)){ $stageMismatches.Add([pscustomobject]@{path=$bound.relativePath;reason='missing'}); continue }
        $actualSha=Get-LowerSha256 $boundPath
        $actualBytes=(Get-Item -LiteralPath $boundPath).Length
        if($actualSha -ne [string]$bound.sha256 -or $actualBytes -ne [long]$bound.rawBytes){$stageMismatches.Add([pscustomobject]@{path=$bound.relativePath;reason='hash-or-size';actualSha=$actualSha;actualBytes=$actualBytes})}
    }
    Add-Check $checks 'stage-provenance-bound-files' ($stageProvenance.boundFiles.Count -eq 21 -and $stageMismatches.Count -eq 0) ([pscustomobject]@{count=$stageProvenance.boundFiles.Count;mismatches=$stageMismatches})

    $source=Get-Content -LiteralPath $analyzer -Raw
    $forbidden=@('subprocess.Popen','os.system(','Start-Process','-executeMethod')
    $hits=@($forbidden|Where-Object{$source.Contains($_)})
    Add-Check $checks 'analyzer-zero-unity-launch-static-proof' ($hits.Count -eq 0) ($hits -join ',')
    & $PythonPath -c "import ast,pathlib; ast.parse(pathlib.Path(r'$analyzer').read_text(encoding='utf-8')); print('AST-PASS')" *> (Join-Path $VerificationRoot 'python-ast.log')
    Add-Check $checks 'python-ast-parse' ($LASTEXITCODE -eq 0) $LASTEXITCODE
    & $PythonPath -c "import json,pathlib; json.loads(pathlib.Path(r'$schema').read_text(encoding='utf-8')); print('SCHEMA-PARSE-PASS')" *> (Join-Path $VerificationRoot 'schema-parse.log')
    Add-Check $checks 'schema-json-parse' ($LASTEXITCODE -eq 0) $LASTEXITCODE

    $selfTest=Join-Path $VerificationRoot 'synthetic-self-test.json'
    & $PythonPath $analyzer --project $ProjectPath --self-test --expected-fixture $fixture --output $selfTest *> (Join-Path $VerificationRoot 'synthetic-self-test.log')
    Add-Check $checks 'synthetic-self-test-exit' ($LASTEXITCODE -eq 0) $LASTEXITCODE
    $self=Get-Content -LiteralPath $selfTest -Raw|ConvertFrom-Json
    Add-Check $checks 'synthetic-self-test-all-passed' ($self.passed -and $self.checkCount -eq 17 -and $self.passedCheckCount -eq 17) ([pscustomobject]@{count=$self.checkCount;passed=$self.passedCheckCount})
    Add-Check $checks 'bootstrap-20000-deterministic' ($self.bootstrap.replicates -eq 20000 -and $self.bootstrap.seed -eq 13012026 -and $self.bootstrap.byteIdentical) $self.bootstrap

    $structural=Join-Path $VerificationRoot 'pilot-structural-preanalysis-audit.json'
    & $PythonPath $analyzer --project $ProjectPath --audit-structure --pilot-root $pilotRoot --plan $plan --provenance $sourceProvenance --expected-tree-sha256 $expectedTree --output $structural *> (Join-Path $VerificationRoot 'pilot-structural-preanalysis-audit.log')
    Add-Check $checks 'structural-audit-exit' ($LASTEXITCODE -eq 0) $LASTEXITCODE
    $audit=Get-Content -LiteralPath $structural -Raw|ConvertFrom-Json
    Add-Check $checks 'structural-audit-passed' ($audit.passed -and -not $audit.workloadMetricValuesReadForAnalysis) $audit.status
    Add-Check $checks 'all-396-os-identities-unique' ($audit.processIdentityAudit.uniqueOsProcessIdentityCount -eq 396) $audit.processIdentityAudit.uniqueOsProcessIdentityCount
    Add-Check $checks 'all-396-block-identities-unique' ($audit.processIdentityAudit.uniqueBlockEvidenceIdentityCount -eq 396) $audit.processIdentityAudit.uniqueBlockEvidenceIdentityCount
    Add-Check $checks 'all-768-measured-run-ids-unique' ($audit.counts.measuredSamples -eq 768) $audit.counts.measuredSamples
    Add-Check $checks 'pid-reuse-nonoverlapping' ($audit.numericPidReuse.reuseGroupCount -eq 19 -and $audit.numericPidReuse.samePidLifetimeOverlapCount -eq 0) $audit.numericPidReuse
    Add-Check $checks 'provenance-77-of-77' ($audit.provenanceAudit.boundFileCount -eq 77 -and $audit.provenanceAudit.mismatchCount -eq 0) ([pscustomobject]@{count=$audit.provenanceAudit.boundFileCount;mismatch=$audit.provenanceAudit.mismatchCount})

    $treeAfter=Get-TreeIdentity $pilotRoot
    Add-Check $checks 'frozen-v7-tree-after' ($treeAfter.canonicalTreeSha256 -eq $treeBefore.canonicalTreeSha256 -and $treeAfter.fileCount -eq $treeBefore.fileCount -and $treeAfter.rawBytes -eq $treeBefore.rawBytes) $treeAfter
    $unityAfter=@(Get-Process -Name Unity,UnityEditor -ErrorAction SilentlyContinue).Count
    Add-Check $checks 'no-active-unity-process-after' ($unityAfter -eq 0) $unityAfter
    Add-Check $checks 'formal-root-still-absent' (-not (Test-Path -LiteralPath $formalRoot)) $formalRoot
    Add-Check $checks 'recovery-root-still-absent' (-not (Test-Path -LiteralPath $recoveryRoot)) $recoveryRoot
    $passed=(@($checks|Where-Object{-not $_.passed}).Count -eq 0)
    $summary=[pscustomobject][ordered]@{schemaVersion=1;summaryKind='gate13r-pr1b-v4-composite-process-identity-validation-summary-v1';startedAtUtc=$started.ToString('o');completedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');status=if($passed){'PASSED / VALIDATION-ONLY / RECOVERY-ELIGIBLE'}else{'FAILED / RECOVERY-NOT-ELIGIBLE'};passed=$passed;checkCount=$checks.Count;passedCheckCount=@($checks|Where-Object{$_.passed}).Count;failedCheckCount=@($checks|Where-Object{-not $_.passed}).Count;sourceTreeBefore=$treeBefore;sourceTreeAfter=$treeAfter;stageProvenanceSha256=Get-LowerSha256 $StageProvenancePath;unityInvoked=$false;newSamplesGenerated=0;formalCampaignAuthorized=$false;gate14rAuthorized=$false;checks=$checks}
    Write-AtomicJson (Join-Path $VerificationRoot 'validation-summary.json') $summary
    Write-AtomicJson (Join-Path $VerificationRoot 'checkpoint.json') ([pscustomobject][ordered]@{schemaVersion=1;status=if($passed){'VALIDATION-PASSED-RECOVERY-AUTHORIZED-BY-USER'}else{'VALIDATION-FAILED-NO-RECOVERY'};passed=$passed;recoveryExecuted=$false;unityInvoked=$false})
    if(-not $passed){throw 'one or more validation hard gates failed'}
    Write-Output ($summary|ConvertTo-Json -Depth 8)
} catch {
    $failure=[pscustomobject][ordered]@{schemaVersion=1;receiptKind='gate13r-pr1b-v4-validation-failure-receipt-v1';failedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');status='FAILED-VALIDATION-ONLY / RECOVERY-NOT-STARTED';message=$_.Exception.Message;unityInvoked=$false;recoveryExecuted=$false;formalCampaignAuthorized=$false;checks=$checks}
    Write-AtomicJson (Join-Path $VerificationRoot 'failure-receipt.json') $failure
    Write-AtomicJson (Join-Path $VerificationRoot 'partial-output-manifest.json') ([pscustomobject][ordered]@{schemaVersion=1;fileCount=@(Get-ChildItem -LiteralPath $VerificationRoot -Recurse -File).Count;status='FAILED-VALIDATION-ONLY'})
    throw
}
