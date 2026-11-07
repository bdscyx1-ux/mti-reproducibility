$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = 'H:\DDM_Final_Project'
$python = 'C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$pythonSha256 = 'ceabb31054d429f57cb3825775677eeaf0db35fdabbc5ff6aef661c037154b00'
$tool = 'H:\DDM_Final_Project\Research\Gate14Re-ME\Tools\gate14re_me_formal_st_analysis_v1_1.py'
$toolSha256 = 'fb10ed4d52a9aad557a041a4909c21f561e176979e7668fcd06b9048f84379c9'
$pyarrowRoot = 'H:\DDM_Final_Project\Research\Gate14Re-ME\Runtime\v1\python-packages'
$outputRoot = 'H:\DDM_Final_Project\Research\Analysis\Gate14Re-ME\formal-st\v5\attempt-002'
$authorizationReceipt = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\formal-st-analysis-attempt-002\formal-analysis-authorization.v1.json'
$authorizationReceiptSha256 = '594aecffc5276fe39e613e2afba67527deb20e6cd2a266f4c46bb1e957fb3700'
$executionContract = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\formal-st-analysis-attempt-002\formal-analysis-execution-contract.v1.json'
$executionContractSha256 = 'db011bc64b6bbf7d9c9a8eb3aae871498e5a511c20912e1473f8bb87d892938f'

if (Test-Path -LiteralPath $outputRoot) {
    throw "Fresh formal-analysis output root already exists: $outputRoot"
}

$actualPythonSha256 = (Get-FileHash -LiteralPath $python -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualPythonSha256 -ne $pythonSha256) {
    throw "Python executable SHA-256 mismatch: $actualPythonSha256"
}

$actualToolSha256 = (Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualToolSha256 -ne $toolSha256) {
    throw "Formal analysis tool SHA-256 mismatch: $actualToolSha256"
}

$actualAuthorizationSha256 = (Get-FileHash -LiteralPath $authorizationReceipt -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualAuthorizationSha256 -ne $authorizationReceiptSha256) {
    throw "Authorization receipt SHA-256 mismatch: $actualAuthorizationSha256"
}

$actualExecutionContractSha256 = (Get-FileHash -LiteralPath $executionContract -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualExecutionContractSha256 -ne $executionContractSha256) {
    throw "Execution contract SHA-256 mismatch: $actualExecutionContractSha256"
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
    '--analysis-contract', 'H:\DDM_Final_Project\Research\Gate14Re-ME\Execution\v5\formal-st-analysis-contract.v5_0.json',
    '--analysis-contract-sha256', 'ed884beebaabb05cc039c6e401169cb80659386558e6af95f3eaec9bfec519cd',
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
    throw "Formal analysis failed closed with exit code $exitCode. No retry was performed."
}
