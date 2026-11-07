$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = 'H:\DDM_Final_Project'
$python = 'C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$pythonSha256 = 'ceabb31054d429f57cb3825775677eeaf0db35fdabbc5ff6aef661c037154b00'
$tool = 'H:\DDM_Final_Project\Research\Gate14Re-ME\Tools\gate14re_me_formal_st_analysis_v1_3.py'
$toolSha256 = '6e217d371fa725ee544c02d24dd895dba58b09193cba02045016580075ea5858'
$pyarrowRoot = 'H:\DDM_Final_Project\Research\Gate14Re-ME\Runtime\v1\python-packages'
$outputRoot = 'H:\DDM_Final_Project\Research\Analysis\Gate14Re-ME\formal-st\v5\attempt-004'
$analysisContract = 'H:\DDM_Final_Project\Research\Gate14Re-ME\AnalysisContracts\any-four-of-five-domain-rule-v1\formal-st-analysis-contract.v5_2.json'
$analysisContractSha256 = '8e0715cbad6de4a1af10ea4cddd11dd1ef8497bd3e15c6db72996dfe951ec746'
$authorizationReceipt = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\formal-st-analysis-attempt-004\formal-analysis-authorization.v1.json'
$authorizationReceiptSha256 = 'adb4fa0c5f214c2b40a0fb2a1e831c43124f6a28dc70cced36bec8bea48001f8'
$interpretationCorrection = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\formal-st-analysis-attempt-004\attempt-003-interpretation-correction.v1.json'
$interpretationCorrectionSha256 = '106759dbf72b7fb03ebc498fcbccb3729f9935951af6caa46dc666fae3a4e062'
$executionContract = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\formal-st-analysis-attempt-004\formal-analysis-execution-contract.v1.json'
$executionContractSha256 = 'e2b61eccfc274a7eba0e8784c817ac089bd42f5a4f727685fab2fa1ba62067b1'

if (Test-Path -LiteralPath $outputRoot) {
    throw "Fresh formal-analysis output root already exists: $outputRoot"
}

$checks = @(
    @{ Path = $python; Expected = $pythonSha256; Label = 'Python executable' },
    @{ Path = $tool; Expected = $toolSha256; Label = 'formal analysis tool' },
    @{ Path = $analysisContract; Expected = $analysisContractSha256; Label = 'any-four-of-five analysis contract' },
    @{ Path = $authorizationReceipt; Expected = $authorizationReceiptSha256; Label = 'authorization receipt' },
    @{ Path = $interpretationCorrection; Expected = $interpretationCorrectionSha256; Label = 'attempt-003 interpretation correction receipt' },
    @{ Path = $executionContract; Expected = $executionContractSha256; Label = 'execution contract' }
)
foreach ($check in $checks) {
    $actual = (Get-FileHash -LiteralPath $check.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $check.Expected) {
        throw "$($check.Label) SHA-256 mismatch: $actual"
    }
}

$runtimeProbe = & $python -c "import sys; sys.path.insert(0, sys.argv[1]); import pyarrow; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}|{pyarrow.__version__}')" $pyarrowRoot
if ($LASTEXITCODE -ne 0 -or $runtimeProbe -ne '3.12.14|25.0.1') {
    throw "Compatible runtime probe failed: $runtimeProbe"
}

$env:PYTHONHASHSEED = '0'
$env:OMP_NUM_THREADS = '1'
$env:OPENBLAS_NUM_THREADS = '1'
$env:MKL_NUM_THREADS = '1'
$env:NUMEXPR_NUM_THREADS = '1'

$arguments = @(
    $tool,
    '--project-root', $projectRoot,
    '--package-root', 'H:\DDM_Final_Project\Research\FormalDataPackages\Gate14Re-ME\formal-st\v5\attempt-002',
    '--output-root', $outputRoot,
    '--pyarrow-root', $pyarrowRoot,
    '--runtime-manifest', 'H:\DDM_Final_Project\Research\Gate14Re-ME\Runtime\v1\typed-parquet-runtime-manifest.v1.json',
    '--runtime-manifest-sha256', '254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e',
    '--terminal-final', 'H:\DDM_Final_Project\Research\FormalDataPackages\Gate14Re-ME\formal-st\v5\attempt-002\terminal-final.v5.json',
    '--terminal-final-sha256', '2f12db25a27c023ef786251f7400546417883af639b3d405cc31ee5f5c681823',
    '--terminal-receipt-sha256', '35397eee59ec151faf6988babe2aa83676a3c03ed226e299e2a85c10e6081b7f',
    '--acceptance-manifest-sha256', '9f6470e399fd00469a444959753e4fd07670c193cd0cd76331d88965dfa832f0',
    '--file-manifest-sha256', '02eefd2cffe1f611f0523cbb7f94c1e15ab60f4bfd86488cdcf4e2cabf348329',
    '--schedule', 'H:\DDM_Final_Project\Research\FormalInputs\Gate14Re-ME\formal-st\v5\attempt-001\schedule\formal-st-williams-schedule.v5.jsonl',
    '--schedule-sha256', '45293f6d6eea879f5c54e23fd144dc97ef3a5e4b4d130bff4b944fcb2b1882f3',
    '--identity-binding', 'H:\DDM_Final_Project\Research\Gate14Re-ME\Execution\v5_1\formal-st-algorithm-identity-binding.reused.v5_1.json',
    '--identity-binding-sha256', 'c3d8623560f9162de858ac01b2e861395b92953896e922413fababd0298db5b3',
    '--analysis-contract', $analysisContract,
    '--analysis-contract-sha256', $analysisContractSha256,
    '--endpoint-contract', 'H:\DDM_Final_Project\Research\Gate14Re-ME\Execution\v5\formal-st-endpoint-mipe-contract.v5_0.json',
    '--endpoint-contract-sha256', '6b38e152c8a17c0bedcd2e700aa8274167e2e0831b33c13cdfbb5227b1354132',
    '--scientific-design', 'H:\DDM_Final_Project\Research\Gate14Re-ME\Execution\v5\formal-st-scientific-design.v5_0.json',
    '--scientific-design-sha256', '78b77db9346aca9f993af8c470ac685662d192a589afb6312c0e18c8dda73708',
    '--authorization-receipt', $authorizationReceipt,
    '--authorization-receipt-sha256', $authorizationReceiptSha256,
    '--execution-contract', $executionContract,
    '--execution-contract-sha256', $executionContractSha256,
    '--tool-sha256', $toolSha256
)

Set-Location -LiteralPath $projectRoot
& $python @arguments
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "Formal analysis attempt-004 failed closed with exit code $exitCode. No retry was performed."
}
