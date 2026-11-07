[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$VerificationRoot,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV1|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force
$VerificationRoot = [IO.Path]::GetFullPath($VerificationRoot)
$base = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1'))
if (-not (Test-G13RPR2MP1PathWithin -BasePath $base -CandidatePath $VerificationRoot)) { throw 'Block-validation root is outside the MP1 verification base.' }
if (Test-Path -LiteralPath $VerificationRoot) { throw 'Create-new block-validation root exists.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v1')) { throw 'Measured pilot root must remain absent during block validation.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent before block validation.' }
New-Item -ItemType Directory -Path (Join-Path $VerificationRoot 'plans') -Force | Out-Null
$receiptPath = Join-Path $VerificationRoot 'validation-execution-receipt.json'
$receipt = [ordered]@{schemaVersion=1;receiptKind='gate13r-pr2-mp1-validation-only-execution-receipt-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');verificationRoot=$VerificationRoot;measuredPilotAuthorized=$false;formalCampaignAuthorized=$false;formalAnalysisAuthorized=$false;gate14RAuthorized=$false;excludedFromFormalAnalysis=$true}
Write-G13RPR2MP1AtomicJson -Path $receiptPath -Value $receipt -Depth 20
$receiptSha = Get-G13RPR2MP1Sha256 $receiptPath
$schedulePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl'
$rows = @(Get-Content -LiteralPath $schedulePath -Encoding UTF8 | Select-Object -First 2 | ForEach-Object { $_ | ConvertFrom-Json })
if ($rows.Count -ne 2) { throw 'Two frozen schedule rows are required for validation.' }
$configPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Config.v1.json'
$specificationPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Specification.v1.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Test_Design.v1.md'
$twoStagePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json'
$commandPath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs'
$provenancePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Provenance.v1.json'
$wrapperPath = Join-Path $ProjectPath 'Research\Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1'
$powershellExe='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$results = New-Object Collections.Generic.List[object]
for ($index=0;$index -lt 2;$index++) {
    $row=$rows[$index];$negative=$index -eq 1;$id=if($negative){'negative-fail-closed'}else{'positive-complete-block'}
    $planPath=Join-Path (Join-Path $VerificationRoot 'plans') ($id+'.json');$output=Join-Path $VerificationRoot $id
    $plan=[ordered]@{
        schemaVersion=2;planId='gate13r-pr2-mp1-block-plan-v1';designId='gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1';globalProcessOrdinal=[int]$row.globalProcessOrdinal
        blockId=('mp1-validation-'+$id);campaignId=('mp1-validation-'+$id);scenarioId=[string]$row.scenarioId;scenarioRelativePath=[string]$row.scenarioRelativePath;scenarioSourceSha256=[string]$row.scenarioSourceSha256
        comparisonCohortId=[string]$row.comparisonCohortId;block=[int]$row.blockOrdinalWithinScenario;williamsRowIndex=[int]$row.williamsRowIndex;formalCampaign=$false;validationOnly=$true;excludedFromFormalAnalysis=$true
        analysisRole='memory-diagnostic-only';verificationInjectedFailurePosition=if($negative){2}else{0}
        formalConfigRelativePath='Research/Gate13R_PR2_MP1_Pilot_Config.v1.json';formalConfigSha256=Get-G13RPR2MP1Sha256 $configPath
        specificationRelativePath='Research/Gate13R_PR2_MP1_Specification.v1.md';specificationSha256=Get-G13RPR2MP1Sha256 $specificationPath
        testDesignRelativePath='Research/Gate13R_PR2_MP1_Test_Design.v1.md';testDesignSha256=Get-G13RPR2MP1Sha256 $testDesignPath
        amendmentRelativePath='Research/Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json';amendmentSha256=Get-G13RPR2MP1Sha256 $twoStagePath
        commandRelativePath='Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs';commandSha256=Get-G13RPR2MP1Sha256 $commandPath
        provenanceRelativePath='Research/Gate13R_PR2_MP1_Provenance.v1.json';provenanceSha256=Get-G13RPR2MP1Sha256 $provenancePath
        executionReceiptRelativePath=$receiptPath.Substring($ProjectPath.Length+1).Replace('\','/');executionReceiptSha256=$receiptSha
        entries=@($row.entries)
    }
    Write-G13RPR2MP1AtomicJson -Path $planPath -Value $plan -Depth 40
    $invoke=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$wrapperPath,'-ProjectPath',$ProjectPath,'-BlockPlanPath',$planPath,'-OutputDirectory',$output,'-AllowedRoot',$VerificationRoot,'-ExecutionReceiptPath',$receiptPath,'-UnityPath',$UnityPath,'-ValidationOnly')
    if($negative){$invoke+='-ExpectFailure'}
    & $powershellExe @invoke
    $exit=$LASTEXITCODE
    if($exit -ne 0){throw "MP1 $id validation wrapper failed with exit $exit."}
    $summary=Read-G13RPR2MP1Json (Join-Path $output 'wrapper-summary.json')
    $resolution=Read-G13RPR2MP1Json (Join-Path $output 'wrapper-failure-resolution.json')
    if($summary.passed -ne $true){throw "MP1 $id summary did not pass."}
    if($negative -and ($resolution.failed -ne $true -or [string]$resolution.primaryCause.kind -ne 'DURABLE-UNITY-BLOCK-FAILURE' -or $resolution.nextBlockAllowed -ne $false)){throw 'Negative failure-precedence validation failed.'}
    if(-not $negative -and $resolution.failed -ne $false){throw 'Positive block unexpectedly resolved as failure.'}
    $results.Add([ordered]@{testId=$id;wrapperSummarySha256=Get-G13RPR2MP1Sha256 (Join-Path $output 'wrapper-summary.json');failureResolutionSha256=Get-G13RPR2MP1Sha256 (Join-Path $output 'wrapper-failure-resolution.json');passed=$true})
}
$combined=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr2-mp1-positive-negative-block-validation-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');testCount=2;passedTestCount=2;results=$results.ToArray();measuredPilotStarted=$false;formalCampaign=$false;passed=$true}
Write-G13RPR2MP1AtomicJson -Path (Join-Path $VerificationRoot 'block-validation-summary.json') -Value $combined -Depth 30
Write-Host 'Gate13R-PR2-MP1 positive and negative block validation passed.' -ForegroundColor Green
exit 0
