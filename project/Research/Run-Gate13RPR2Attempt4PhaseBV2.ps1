[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AuthorizationPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedFullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "$Label SHA-256 mismatch."
    }
}

$projectRoot = [System.IO.Path]::GetFullPath($ProjectPath)
if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
    throw "ProjectPath does not exist: $projectRoot"
}

$contractPath = Join-Path -Path $projectRoot -ChildPath 'Research\Gate13R_PR2_Attempt4_PhaseB_Execution_Contract.v2.json'
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    throw "Frozen Phase B contract is missing: $contractPath"
}

$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($contract.contractKind -ne 'GATE13R-PR2-ATTEMPT4-PHASEB-FROZEN-EXECUTION-CONTRACT') {
    throw 'Unexpected Phase B contract kind.'
}
if ($contract.contractStatus -ne 'FROZEN-AWAITING-SEPARATE-EXECUTION-AUTHORIZATION') {
    throw 'Phase B contract is not in the frozen awaiting-authorization state.'
}
if ($contract.authorizationBoundary.phaseBExecutionAuthorizedByThisContract -ne $false) {
    throw 'The preparation contract must not self-authorize Phase B execution.'
}
if ($contract.authorizationBoundary.gate14RAuthorized -ne $false) {
    throw 'Gate 14R must remain unauthorized.'
}

$authorizationFullPath = Get-NormalizedFullPath -Path $AuthorizationPath -BasePath $projectRoot
$expectedAuthorizationPath = Get-NormalizedFullPath -Path $contract.separateExecutionAuthorization.expectedRelativePath -BasePath $projectRoot
if ($authorizationFullPath -ne $expectedAuthorizationPath) {
    throw 'AuthorizationPath does not equal the separately frozen expected authorization path.'
}
if (-not (Test-Path -LiteralPath $authorizationFullPath -PathType Leaf)) {
    throw 'Separate Phase B formal-analysis execution authorization is absent. Analysis was not executed.'
}

$authorization = Get-Content -LiteralPath $authorizationFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($authorization.authorizationKind -ne 'GATE13R-PR2-ATTEMPT4-PHASEB-FORMAL-ANALYSIS-EXECUTION') {
    throw 'Wrong execution authorization kind.'
}
if ($authorization.phaseBFormalStatisticalAnalysisAuthorized -ne $true) {
    throw 'Phase B formal statistical analysis is not explicitly authorized.'
}
if ($authorization.formalOutcomeDataLoadingAuthorized -ne $true) {
    throw 'Formal outcome-data loading is not explicitly authorized.'
}
if ($authorization.gate14RAuthorized -ne $false) {
    throw 'Gate 14R authorization must remain false.'
}
if ($authorization.rawRootMutationAuthorized -ne $false) {
    throw 'Raw-root mutation authorization must remain false.'
}
if ($authorization.unityLaunchOrControlAuthorized -ne $false) {
    throw 'Unity launch/control authorization must remain false.'
}
if ([string]::IsNullOrWhiteSpace([string]$authorization.exactUserExecutionAuthorization)) {
    throw 'Exact user execution authorization text is missing.'
}

$contractSha256 = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($authorization.contractSha256.ToLowerInvariant() -ne $contractSha256) {
    throw 'Execution authorization does not bind the frozen Phase B contract SHA-256.'
}

foreach ($property in $contract.implementationBindings.PSObject.Properties) {
    $binding = $property.Value
    $bindingPath = Get-NormalizedFullPath -Path $binding.relativePath -BasePath $projectRoot
    Assert-FileHash -Path $bindingPath -ExpectedSha256 $binding.sha256 -Label "Implementation binding $($property.Name)"
}

$outputRoot = Get-NormalizedFullPath -Path $contract.output.rootRelativePath -BasePath $projectRoot
if (Test-Path -LiteralPath $outputRoot) {
    throw 'The frozen Phase B output root already exists; overwrite is forbidden.'
}

$analyzerPath = Get-NormalizedFullPath -Path $contract.implementationBindings.analyzer.relativePath -BasePath $projectRoot
$pythonCommand = Get-Command -Name 'py' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$pythonArguments = @('-3')
if ($null -eq $pythonCommand) {
    $pythonCommand = Get-Command -Name 'python' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $pythonArguments = @()
}
if ($null -eq $pythonCommand) {
    throw 'Python 3 executable was not found.'
}

$pythonArguments += @(
    $analyzerPath,
    '--project-root', $projectRoot,
    '--contract', $contractPath,
    '--authorization', $authorizationFullPath
)

& $pythonCommand.Source @pythonArguments
if ($LASTEXITCODE -ne 0) {
    throw "Phase B analyzer refused or failed closed with exit code $LASTEXITCODE."
}
