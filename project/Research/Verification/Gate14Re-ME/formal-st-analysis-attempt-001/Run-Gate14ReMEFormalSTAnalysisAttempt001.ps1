$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = 'H:\DDM_Final_Project'
$python = 'C:\Users\bdscy\AppData\Local\Python\pythoncore-3.14-64\python.exe'
$tool = 'H:\DDM_Final_Project\Research\Gate14Re-ME\Tools\gate14re_me_formal_st_analysis_v1.py'
$outputRoot = 'H:\DDM_Final_Project\Research\Analysis\Gate14Re-ME\formal-st\v5\attempt-001'

if (Test-Path -LiteralPath $outputRoot) {
    throw "Fresh formal-analysis output root already exists: $outputRoot"
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
    '--pyarrow-root', 'H:\DDM_Final_Project\Research\Gate14Re-ME\Runtime\v1\python-packages',
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
    '--authorization-receipt', 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\formal-st-analysis-attempt-001\formal-analysis-authorization.v1.json',
    '--authorization-receipt-sha256', 'fdf0e4219508dd4d461d2ce5315f726af8c2ba894b075914f3d164f6a6c94a50',
    '--execution-contract', 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\formal-st-analysis-attempt-001\formal-analysis-execution-contract.v1.json',
    '--execution-contract-sha256', '9ce7ce0ebd9dafb4adeeef0cf6b4093f39c0c4089e5e5ac09b59f00e94472de4',
    '--tool-sha256', '5d33f87ba51b67ea2b6bf72bc32c5a7845f14b549d3c30f58b7fb085468c9c9d'
)

Set-Location -LiteralPath $projectRoot
& $python @arguments
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "Formal analysis failed closed with exit code $exitCode. No retry was performed."
}
