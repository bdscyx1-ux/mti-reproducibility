[CmdletBinding()]
param(
    [string]$ProjectPath = '',
    [string]$PythonPath = 'C:\Users\bdscy\AppData\Local\Python\bin\python3.exe',
    [string]$VerificationRoot = '',
    [string]$StageProvenancePath = ''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)){$ProjectPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
if([string]::IsNullOrWhiteSpace($VerificationRoot)){$VerificationRoot=Join-Path $ProjectPath 'Research\Verification\Gate13R_PR1B_CompositeProcessIdentity_Recovery\v2'}
if([string]::IsNullOrWhiteSpace($StageProvenancePath)){$StageProvenancePath=Join-Path $ProjectPath 'Research\Gate13R_PR1B_v4_CompositeProcessIdentity_Provenance.v2.json'}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot)
$StageProvenancePath=[IO.Path]::GetFullPath($StageProvenancePath)

$pilotRoot=Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v7-gate13r-pr1b-order-effect-pathsafe-v4'
$failedV1Root=Join-Path $ProjectPath 'Research\Verification\Gate13R_PR1B_CompositeProcessIdentity_Recovery\v1'
$recoveryRoot=Join-Path $ProjectPath 'Research\Analysis\Gate13R_PR1B_CompositeProcessIdentity_Recovery\v1'
$formalRoot=Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned\v1'
$analyzer=Join-Path $ProjectPath 'Research\Analyze-Gate13RPR1BCompositeProcessIdentityRecoveryV1.py'
$plan=Join-Path $ProjectPath 'Research\Gate13R_PR1B_OrderEffect_Pilot_Plan.v9.json'
$sourceProvenance=Join-Path $ProjectPath 'Research\Gate13R_PR1B_OrderEffect_Provenance.v10.json'
$schema=Join-Path $ProjectPath 'Research\Gate13R_PR1B_v4_AnalysisRecovery_Output_Schema.v1.json'
$fixture=Join-Path $ProjectPath 'Research\Verification\Fixtures\Gate13R_PR1B_CompositeProcessIdentity\v1\expected-results.json'
$expectedSourceTree='4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed'
$expectedFailedV1Tree='1e66f43d80887cd30dc5b33652b599763fad25c15e84d1c329504430f6d0f4e3'

function Get-LowerSha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-StringSha256([string]$Value){$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Get-TreeIdentity([string]$Path){$root=[IO.Path]::GetFullPath($Path).TrimEnd('\');$files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force|Sort-Object FullName);$rows=@($files|ForEach-Object{$rel=$_.FullName.Substring($root.Length).TrimStart('\').Replace('\','/');"$rel`t$($_.Length)`t$(Get-LowerSha256 $_.FullName)"});[pscustomobject][ordered]@{resolvedAbsolutePath=$root.Replace('\','/');fileCount=$files.Count;rawBytes=[long](($files|Measure-Object Length -Sum).Sum);canonicalTreeSha256=Get-StringSha256($rows-join"`n")}}
function Write-AtomicJson([string]$Path,[object]$Value){$parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$temp=Join-Path $parent ('.g13v4-'+[Guid]::NewGuid().ToString('N')+'.tmp');try{[IO.File]::WriteAllText($temp,(($Value|ConvertTo-Json -Depth 100)+"`n"),(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath $temp -Destination $Path -Force}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}}
function Add-Check([System.Collections.Generic.List[object]]$Checks,[string]$Id,[bool]$Passed,[object]$Detail){$Checks.Add([pscustomobject][ordered]@{id=$Id;passed=$Passed;detail=$Detail})}
function Get-EvidenceFiles([string]$Root,[string[]]$Exclude){$items=@();foreach($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File|Sort-Object FullName)){if($Exclude-contains$f.Name){continue};$items+=[pscustomobject][ordered]@{relativePath=$f.FullName.Substring(([IO.Path]::GetFullPath($Root).TrimEnd('\')).Length).TrimStart('\').Replace('\','/');rawBytes=$f.Length;sha256=Get-LowerSha256 $f.FullName}};return $items}

if(Test-Path -LiteralPath $VerificationRoot){throw "verification v2 root already exists: $VerificationRoot"}
if(Test-Path -LiteralPath $recoveryRoot){throw 'recovery root must be absent before validation v2'}
New-Item -ItemType Directory -Path $VerificationRoot -Force|Out-Null
$checks=New-Object 'System.Collections.Generic.List[object]'
$started=[DateTimeOffset]::UtcNow
try{
    $sourceBefore=Get-TreeIdentity $pilotRoot
    $v1Before=Get-TreeIdentity $failedV1Root
    Add-Check $checks 'source-tree-before' ($sourceBefore.canonicalTreeSha256-eq$expectedSourceTree-and$sourceBefore.fileCount-eq9118-and$sourceBefore.rawBytes-eq253513394) $sourceBefore
    Add-Check $checks 'failed-validation-v1-preserved-before' ($v1Before.canonicalTreeSha256-eq$expectedFailedV1Tree-and$v1Before.fileCount-eq8-and$v1Before.rawBytes-eq327250) $v1Before
    Add-Check $checks 'recovery-root-absent' (-not(Test-Path -LiteralPath $recoveryRoot)) $recoveryRoot
    Add-Check $checks 'formal-root-absent' (-not(Test-Path -LiteralPath $formalRoot)) $formalRoot
    Add-Check $checks 'unity-lockfile-absent' (-not(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'Temp/UnityLockfile'
    $unityBefore=@(Get-Process -Name Unity,UnityEditor -ErrorAction SilentlyContinue).Count
    Add-Check $checks 'no-active-unity-before' ($unityBefore-eq0) $unityBefore

    $stage=Get-Content -LiteralPath $StageProvenancePath -Raw|ConvertFrom-Json
    $mismatches=@();foreach($bound in $stage.boundFiles){$path=Join-Path $ProjectPath ([string]$bound.relativePath-replace'/','\');if(-not(Test-Path -LiteralPath $path)){$mismatches+="missing:$($bound.relativePath)";continue};$sha=Get-LowerSha256 $path;$bytes=(Get-Item -LiteralPath $path).Length;if($sha-ne[string]$bound.sha256-or$bytes-ne[long]$bound.rawBytes){$mismatches+="mismatch:$($bound.relativePath)"}}
    Add-Check $checks 'stage-provenance-15-of-15' ($stage.boundFiles.Count-eq15-and$mismatches.Count-eq0) ([pscustomobject]@{count=$stage.boundFiles.Count;mismatches=$mismatches})
    $source=Get-Content -LiteralPath $analyzer -Raw;$forbidden=@('subprocess.Popen','os.system(','Start-Process','-executeMethod');$hits=@($forbidden|Where-Object{$source.Contains($_)})
    Add-Check $checks 'zero-unity-launch-static-proof' ($hits.Count-eq0) ($hits-join',')
    & $PythonPath -c "import ast,pathlib; ast.parse(pathlib.Path(r'$analyzer').read_text(encoding='utf-8')); print('AST-PASS')" *> (Join-Path $VerificationRoot 'python-ast.log');Add-Check $checks 'python-ast' ($LASTEXITCODE-eq0) $LASTEXITCODE
    & $PythonPath -c "import json,pathlib; json.loads(pathlib.Path(r'$schema').read_text(encoding='utf-8')); print('SCHEMA-PASS')" *> (Join-Path $VerificationRoot 'schema-parse.log');Add-Check $checks 'schema-parse' ($LASTEXITCODE-eq0) $LASTEXITCODE
    $selfPath=Join-Path $VerificationRoot 'synthetic-self-test.json';& $PythonPath $analyzer --project $ProjectPath --self-test --expected-fixture $fixture --output $selfPath *> (Join-Path $VerificationRoot 'synthetic-self-test.log');$self=Get-Content -LiteralPath $selfPath -Raw|ConvertFrom-Json
    Add-Check $checks 'synthetic-17-of-17' ($LASTEXITCODE-eq0-and$self.passed-and$self.checkCount-eq17-and$self.passedCheckCount-eq17) ([pscustomobject]@{count=$self.checkCount;passed=$self.passedCheckCount})
    Add-Check $checks 'bootstrap-20000-deterministic' ($self.bootstrap.replicates-eq20000-and$self.bootstrap.seed-eq13012026-and$self.bootstrap.byteIdentical) $self.bootstrap
    $auditPath=Join-Path $VerificationRoot 'pilot-structural-preanalysis-audit.json';& $PythonPath $analyzer --project $ProjectPath --audit-structure --pilot-root $pilotRoot --plan $plan --provenance $sourceProvenance --expected-tree-sha256 $expectedSourceTree --output $auditPath *> (Join-Path $VerificationRoot 'pilot-structural-preanalysis-audit.log');$audit=Get-Content -LiteralPath $auditPath -Raw|ConvertFrom-Json
    Add-Check $checks 'structural-audit-passed' ($LASTEXITCODE-eq0-and$audit.passed-and-not$audit.workloadMetricValuesReadForAnalysis) $audit.status
    Add-Check $checks 'identity-cardinality' ($audit.processIdentityAudit.uniqueOsProcessIdentityCount-eq396-and$audit.processIdentityAudit.uniqueBlockEvidenceIdentityCount-eq396) $audit.processIdentityAudit
    Add-Check $checks 'run-cardinality' ($audit.counts.measuredSamples-eq768-and$audit.counts.totalSamples-eq792) $audit.counts
    Add-Check $checks 'pid-reuse-nonoverlap' ($audit.numericPidReuse.reuseGroupCount-eq19-and$audit.numericPidReuse.samePidLifetimeOverlapCount-eq0) $audit.numericPidReuse
    Add-Check $checks 'source-provenance-77-of-77' ($audit.provenanceAudit.boundFileCount-eq77-and$audit.provenanceAudit.mismatchCount-eq0) ([pscustomobject]@{count=$audit.provenanceAudit.boundFileCount;mismatches=$audit.provenanceAudit.mismatchCount})
    $sourceAfter=Get-TreeIdentity $pilotRoot;$v1After=Get-TreeIdentity $failedV1Root
    Add-Check $checks 'source-tree-after' ($sourceAfter.canonicalTreeSha256-eq$sourceBefore.canonicalTreeSha256-and$sourceAfter.fileCount-eq$sourceBefore.fileCount-and$sourceAfter.rawBytes-eq$sourceBefore.rawBytes) $sourceAfter
    Add-Check $checks 'failed-validation-v1-preserved-after' ($v1After.canonicalTreeSha256-eq$v1Before.canonicalTreeSha256-and$v1After.fileCount-eq$v1Before.fileCount-and$v1After.rawBytes-eq$v1Before.rawBytes) $v1After
    $unityAfter=@(Get-Process -Name Unity,UnityEditor -ErrorAction SilentlyContinue).Count;Add-Check $checks 'no-active-unity-after' ($unityAfter-eq0) $unityAfter
    Add-Check $checks 'formal-root-still-absent' (-not(Test-Path -LiteralPath $formalRoot)) $formalRoot
    Add-Check $checks 'recovery-root-still-absent' (-not(Test-Path -LiteralPath $recoveryRoot)) $recoveryRoot
    $passed=@($checks|Where-Object{-not$_.passed}).Count-eq0
    $summary=[pscustomobject][ordered]@{schemaVersion=2;summaryKind='gate13r-pr1b-v4-composite-process-identity-validation-summary-v2';startedAtUtc=$started.ToString('o');completedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');status=if($passed){'PASSED / VALIDATION-ONLY / RECOVERY-ELIGIBLE'}else{'FAILED / RECOVERY-NOT-ELIGIBLE'};passed=$passed;checkCount=$checks.Count;passedCheckCount=@($checks|Where-Object{$_.passed}).Count;failedCheckCount=@($checks|Where-Object{-not$_.passed}).Count;sourceTreeBefore=$sourceBefore;sourceTreeAfter=$sourceAfter;failedV1TreeBefore=$v1Before;failedV1TreeAfter=$v1After;stageProvenanceSha256=Get-LowerSha256 $StageProvenancePath;unityInvoked=$false;newSamplesGenerated=0;recoveryExecuted=$false;checks=$checks}
    $summaryPath=Join-Path $VerificationRoot 'validation-summary.json';Write-AtomicJson $summaryPath $summary
    $roundTrip=Get-Content -LiteralPath $summaryPath -Raw|ConvertFrom-Json;Add-Check $checks 'atomic-json-roundtrip' ($roundTrip.passed-and$roundTrip.schemaVersion-eq2) 'valid-json-with-real-lf'
    $summary.checkCount=$checks.Count;$summary.passedCheckCount=@($checks|Where-Object{$_.passed}).Count;$summary.failedCheckCount=@($checks|Where-Object{-not$_.passed}).Count;$summary.checks=$checks;$summary.passed=@($checks|Where-Object{-not$_.passed}).Count-eq0;Write-AtomicJson $summaryPath $summary
    Write-AtomicJson (Join-Path $VerificationRoot 'validation-receipt.json') ([pscustomobject][ordered]@{schemaVersion=1;receiptKind='gate13r-pr1b-v4-validation-v2-receipt-v1';completedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');passed=$summary.passed;status=$summary.status;automaticRetryCount=0;recoveryExecuted=$false;unityInvoked=$false})
    Write-AtomicJson (Join-Path $VerificationRoot 'checkpoint.json') ([pscustomobject][ordered]@{schemaVersion=2;status=if($summary.passed){'VALIDATION-V2-PASSED-RECOVERY-ELIGIBLE'}else{'VALIDATION-V2-FAILED'};passed=$summary.passed;recoveryExecuted=$false;unityInvoked=$false})
    $evidence=Get-EvidenceFiles $VerificationRoot @('evidence-manifest.json');Write-AtomicJson (Join-Path $VerificationRoot 'evidence-manifest.json') ([pscustomobject][ordered]@{schemaVersion=1;manifestKind='gate13r-pr1b-v4-validation-v2-evidence-manifest-v1';fileCount=$evidence.Count;files=$evidence})
    if(-not$summary.passed){throw 'validation v2 hard gate failed'}
    Write-Output ($summary|ConvertTo-Json -Depth 8)
}catch{
    Write-AtomicJson (Join-Path $VerificationRoot 'failure-receipt.json') ([pscustomobject][ordered]@{schemaVersion=1;status='FAILED-VALIDATION-V2 / RECOVERY-NOT-STARTED';failedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');message=$_.Exception.Message;recoveryExecuted=$false;unityInvoked=$false;checks=$checks})
    $partial=Get-EvidenceFiles $VerificationRoot @('partial-output-manifest.json');Write-AtomicJson (Join-Path $VerificationRoot 'partial-output-manifest.json') ([pscustomobject][ordered]@{schemaVersion=1;fileCount=$partial.Count;files=$partial;status='FAILED-VALIDATION-V2'})
    throw
}
