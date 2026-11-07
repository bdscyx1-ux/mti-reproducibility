[CmdletBinding()]
param(
    [string]$UnityExecutable,
    [switch]$InstallUnityIfMissing,
    [switch]$ConfirmFormalCollection,
    [switch]$ValidateAuthorizationChainOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$designId = 'gate14re-me-formal-st-bounded-gnf-v5'
$packageId = 'gate14re-me-formal-st-v5-end-to-end-package-attempt-004'
$expectedUserScopeSha256 = '0dafa5724cdea831a27d8490fc6f6f5df6b1d2815a1bd9ad2328d9f767a50409'
$expectedUnitySha256 = '0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'
$expectedPythonSha256 = '7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1'
$oracleBatchCount = 54
$phase = 'PREFLIGHT'

$relative = [ordered]@{
    packageManifest = 'Research/Gate14Re-ME/Package/v5/package-manifest.v1.json'
    umbrellaAuthorization = 'Research/Gate14Re-ME/Package/v5/Authorizations/end-to-end-through-data-package-authorization.v1.json'
    inputAuthorization = 'Research/Gate14Re-ME/Package/v5/Authorizations/formal-input-generation-authorization.end-to-end.v1.json'
    identityBinding = 'Research/Gate14Re-ME/Package/v5/Authorizations/formal-st-algorithm-identity-binding.reused.v5.json'
    readiness = 'Research/Gate14Re-ME/Package/v5/Install-And-Verify-Gate14ReMEFormalST.v5_0.ps1'
    generator = 'Research/Gate14Re-ME/Tools/gate14re_me_formal_st_material_generator_v5.py'
    supervisor = 'Research/Gate14Re-ME/Execution/v5/Run-Gate14ReMEFormalST.v5_0.ps1'
    implementationManifest = 'Research/Gate14Re-ME/Execution/v5/formal-st-implementation-manifest.v5_0.json'
    acquisitionContract = 'Research/Gate14Re-ME/Execution/v5/formal-st-acquisition-contract.v5_0.json'
    resourceBudget = 'Research/Gate14Re-ME/Execution/v5/formal-st-operational-resource-budget.v5_0.json'
    fairnessBinding = 'Research/Gate14Re-ME/Execution/v4/six-algorithm-fairness-binding.v4_1.json'
    trustedIdentityRule = 'Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json'
    timestampComparator = 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1'
    acceptanceLauncher = 'Research/Gate14Re-ME/Execution/v5/Run-Gate14ReMEFormalSTReadOnlyAcceptance.v5_0.ps1'
    acceptanceContract = 'Research/Gate14Re-ME/Execution/v5/formal-st-independent-acceptance-contract.v5_0.json'
    acceptanceTool = 'Research/Gate14Re-ME/Tools/gate14re_me_formal_st_acceptance_v5.py'
    rawOutputContract = 'Research/Gate14Re-ME/Execution/v5/formal-st-raw-output-contract.v5_0.json'
    typedParquetRuntimeManifest = 'Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json'
    pyArrowRoot = 'Research/Gate14Re-ME/Runtime/v1/python-packages'
    python = 'MigrationRuntime/Python/python.exe'
}

$expectedHashes = [ordered]@{
    inputAuthorization = '4d0c58eb4657ff77c4a88fc84b14ea4509d4e41415dee47e72f111894f0f06f8'
    identityBinding = '2a21042283b1197d2a66d7948aede3623b9c5e71ef2576c9f6534494c086dc5e'
    readiness = 'd9a4c54dd8f9fa80c555e1893254df8d13e5227428def0fd79400032d4d92e9a'
    generator = '6eff9c061601c158ecfe1eeed7137ebb30e21206b5394586dc071e462319563b'
    supervisor = '281c8eef6d2070ce96df12b3dd8fd1b320fb0c7dcd3caa7dbf09f1a7b16c7f17'
    implementationManifest = '161a12b9325ca9ef181b9673cd4c7e73b5fa68a016911afd694c1493c86af3e3'
    acquisitionContract = '0eebffd7560c06414e7990cf9cb95e80aeaa3993643719fffe507981fb58be58'
    resourceBudget = '5f8d3febcf774118f05e29bd668ee55544882893426bb21464d2ed3bfdd77533'
    fairnessBinding = '5a2ba89c08efa86f79c756ee3b0cc54a68c310e2414760f18f286e95095319ca'
    trustedIdentityRule = 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06'
    timestampComparator = 'd024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27'
    acceptanceLauncher = 'ae937579d000a1fc1dd56e98d8f30a77e04317b072f5279443cb67bccd2bea26'
    acceptanceContract = 'c807266e6ed8d9cd3c3a57e3aa72bfe6e82a5f42db06f10762a9a713bd72f366'
    acceptanceTool = '18e876973c8e68a9c836a207adc5fda3ffdbe7158fd5c5102fbcf59dcf80ac82'
    rawOutputContract = 'a4585821cca40cf1ebb28626de60c95f213faacabfe7dfbcd002b9cf9586d2f5'
    typedParquetRuntimeManifest = '254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e'
    python = $expectedPythonSha256
}

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Get-Sha256Lower {
    param([string]$Path)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required file is missing: $Path"
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite evidence: $Path"
    $parent = Split-Path -Parent $Path
    Require-Condition (Test-Path -LiteralPath $parent -PathType Container) "Evidence parent is missing: $parent"
    $json = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
        try {
            $writer.Write($json)
            $writer.Flush()
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Resolve-ProjectPath {
    param([string]$ProjectRoot, [string]$RelativePath)
    Require-Condition (-not [System.IO.Path]::IsPathRooted($RelativePath)) "Expected a project-relative path: $RelativePath"
    $full = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $RelativePath))
    $prefix = $ProjectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    Require-Condition ($full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) "Path escapes package root: $RelativePath"
    $canonical = [System.IO.Path]::GetRelativePath($ProjectRoot, $full).Replace('\', '/')
    Require-Condition ($canonical -ceq $RelativePath.Replace('\', '/')) "Path is not canonical: $RelativePath"
    return $full
}

function Assert-Hash {
    param([string]$Path, [string]$Expected, [string]$Label)
    $actual = Get-Sha256Lower -Path $Path
    Require-Condition ($actual -ceq $Expected) "$Label SHA-256 mismatch: expected=$Expected actual=$actual"
}

function Assert-ManifestEntry {
    param(
        [hashtable]$Index,
        [string]$RelativePath,
        [string]$ExpectedSha256,
        [string]$ProjectRoot
    )
    Require-Condition $Index.ContainsKey($RelativePath) "Package manifest does not contain: $RelativePath"
    $entry = $Index[$RelativePath]
    Require-Condition ([string]$entry.sha256 -ceq $ExpectedSha256) "Package manifest hash mismatch: $RelativePath"
    $full = Resolve-ProjectPath -ProjectRoot $ProjectRoot -RelativePath $RelativePath
    Require-Condition ((Get-Item -LiteralPath $full).Length -eq [int64]$entry.bytes) "Package manifest byte mismatch: $RelativePath"
    Assert-Hash -Path $full -Expected $ExpectedSha256 -Label "package file $RelativePath"
}

function New-FormalExecutionAuthorization {
    param(
        [object]$Umbrella,
        [string]$UmbrellaSha256,
        [string]$MeasuredRootRelativePath,
        [string]$ImplementationManifestSha256,
        [string]$AcquisitionContractSha256,
        [string]$InputFreezeManifestSha256,
        [string]$ScheduleSha256,
        [int]$OracleBatchCount
    )
    return [ordered]@{
        schema = 'gate14re-me-formal-st-execution-authorization-v5'
        studyId = $studyId
        designId = $designId
        protocolId = 'gate14re-me-formal-st-v5'
        authorizationId = ([string]$Umbrella.authorizationId + '/formal-collection')
        status = 'AUTHORIZED_FORMAL_ST_COLLECTION'
        authorizationSource = [ordered]@{
            type = 'DETERMINISTIC_CHILD_OF_USER_AUTHORIZED_END_TO_END_PACKAGE_SCOPE'
            umbrellaAuthorizationId = [string]$Umbrella.authorizationId
            umbrellaAuthorizationSha256 = $UmbrellaSha256
            userScopeSha256 = [string]$Umbrella.userAuthorization.userScopeSha256
        }
        formalRootCreationAuthorized = $true
        compileOrUnityExecutionAuthorized = $true
        formalCollectionAuthorized = $true
        formalInputGenerationAuthorized = $false
        formalAcceptanceExecutionAuthorized = $false
        formalAnalysisAuthorized = $false
        mqAuthorized = $false
        mtAuthorized = $false
        measuredRootRelativePath = $MeasuredRootRelativePath
        implementationManifestSha256 = $ImplementationManifestSha256
        executionContractSha256 = $AcquisitionContractSha256
        inputFreezeManifestSha256 = $InputFreezeManifestSha256
        scheduleSha256 = $ScheduleSha256
        oracleBatchCount = $OracleBatchCount
        executionRules = [ordered]@{
            strictSerialFreshUnityProcesses = $true
            maximumConcurrentUnityProcesses = 1
            wholeSuperblockTechnicalReplacements = 0
            retry = $false
            resume = $false
            topUp = $false
            merge = $false
            skip = $false
            reorder = $false
            parallelCompletion = $false
        }
    }
}

function Assert-FormalExecutionAuthorization {
    param(
        [object]$Authorization,
        [string]$MeasuredRootRelativePath,
        [string]$ImplementationManifestSha256,
        [string]$AcquisitionContractSha256,
        [string]$InputFreezeManifestSha256,
        [string]$ScheduleSha256
    )
    Require-Condition ($Authorization.schema -ceq 'gate14re-me-formal-st-execution-authorization-v5') 'Derived execution authorization schema mismatch.'
    Require-Condition ($Authorization.status -ceq 'AUTHORIZED_FORMAL_ST_COLLECTION') 'Derived execution authorization status mismatch.'
    Require-Condition ($Authorization.formalRootCreationAuthorized -and $Authorization.compileOrUnityExecutionAuthorized -and $Authorization.formalCollectionAuthorized) 'Derived execution authorization omits a required collection permission.'
    Require-Condition (-not $Authorization.formalInputGenerationAuthorized -and -not $Authorization.formalAcceptanceExecutionAuthorized -and -not $Authorization.formalAnalysisAuthorized -and -not $Authorization.mqAuthorized -and -not $Authorization.mtAuthorized) 'Derived execution authorization exceeds collection-only scope.'
    Require-Condition ([string]$Authorization.measuredRootRelativePath -ceq $MeasuredRootRelativePath) 'Derived execution authorization measured-root mismatch.'
    Require-Condition ([string]$Authorization.implementationManifestSha256 -ceq $ImplementationManifestSha256) 'Derived execution authorization implementation hash mismatch.'
    Require-Condition ([string]$Authorization.executionContractSha256 -ceq $AcquisitionContractSha256) 'Derived execution authorization contract hash mismatch.'
    Require-Condition ([string]$Authorization.inputFreezeManifestSha256 -ceq $InputFreezeManifestSha256) 'Derived execution authorization input-freeze hash mismatch.'
    Require-Condition ([string]$Authorization.scheduleSha256 -ceq $ScheduleSha256) 'Derived execution authorization schedule hash mismatch.'
    Require-Condition ([int]$Authorization.oracleBatchCount -eq $oracleBatchCount) 'Derived execution authorization oracle batch count mismatch.'
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..')).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$manifestPath = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.packageManifest
$umbrellaPath = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.umbrellaAuthorization
$inputAuthorizationPath = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.inputAuthorization
$identityBindingPath = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.identityBinding
$inputRootRelative = 'Research/FormalInputs/Gate14Re-ME/formal-st/v5/attempt-001'
$measuredRootRelative = 'Research/FormalRuns/Gate14Re-ME/formal-st/v5/attempt-001'
$acceptedPackageRootRelative = 'Research/FormalDataPackages/Gate14Re-ME/formal-st/v5/attempt-001'
$evidenceRootRelative = 'Research/Verification/Gate14Re-ME/formal-st-end-to-end-execution-attempt-001'
$readinessRootRelative = 'PackageReadiness/end-to-end-attempt-001'
$inputRoot = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $inputRootRelative
$measuredRoot = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $measuredRootRelative
$acceptedPackageRoot = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $acceptedPackageRootRelative
$evidenceRoot = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $evidenceRootRelative
$readinessRoot = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $readinessRootRelative

try {
    $manifest = Read-Json -Path $manifestPath
    Require-Condition ($manifest.schema -ceq 'gate14re-me-formal-st-v5-migration-package-manifest-v1') 'Package manifest schema mismatch.'
    Require-Condition ($manifest.status -ceq 'FROZEN_PACKAGE_PAYLOAD_READY_FOR_VALIDATION_FORMAL_ST_NOT_STARTED') 'Package manifest status mismatch.'
    Require-Condition ($manifest.packageId -ceq $packageId) 'This launcher requires the end-to-end attempt-004 package.'
    Require-Condition (-not $manifest.formalCollectionStarted -and -not $manifest.formalAnalysisStarted -and -not $manifest.mqStarted -and -not $manifest.mtStarted) 'Package was built outside its permitted pre-execution boundary.'

    $manifestIndex = @{}
    foreach ($entry in @($manifest.files)) {
        $path = [string]$entry.relativePath
        Require-Condition (-not [string]::IsNullOrWhiteSpace($path) -and -not $manifestIndex.ContainsKey($path)) "Invalid or duplicate package manifest path: $path"
        $manifestIndex[$path] = $entry
    }
    Require-Condition ($manifestIndex.Count -eq [int]$manifest.fileCount) 'Package manifest file cardinality mismatch.'

    $umbrellaSha256 = Get-Sha256Lower -Path $umbrellaPath
    Require-Condition ([string]$manifest.endToEndAuthorization.umbrellaRelativePath -ceq $relative.umbrellaAuthorization) 'Manifest umbrella-authorization path mismatch.'
    Require-Condition ([string]$manifest.endToEndAuthorization.umbrellaSha256 -ceq $umbrellaSha256) 'Manifest umbrella-authorization hash mismatch.'
    Assert-ManifestEntry -Index $manifestIndex -RelativePath $relative.umbrellaAuthorization -ExpectedSha256 $umbrellaSha256 -ProjectRoot $projectRoot

    $umbrella = Read-Json -Path $umbrellaPath
    Require-Condition ($umbrella.schema -ceq 'gate14re-me-formal-st-end-to-end-package-authorization-v1') 'Umbrella authorization schema mismatch.'
    Require-Condition ($umbrella.status -ceq 'AUTHORIZED_ONE_CLICK_THROUGH_ACCEPTED_DATA_PACKAGE_NOT_ANALYSIS') 'Umbrella authorization status mismatch.'
    Require-Condition ($umbrella.studyId -ceq $studyId -and $umbrella.designId -ceq $designId) 'Umbrella authorization study/design mismatch.'
    Require-Condition ([string]$umbrella.userAuthorization.userScopeSha256 -ceq $expectedUserScopeSha256) 'Umbrella authorization user-scope hash mismatch.'
    Require-Condition ($umbrella.permissions.readiness -and $umbrella.permissions.formalInputGeneration -and $umbrella.permissions.formalCollection -and $umbrella.permissions.readOnlyAcceptance -and $umbrella.permissions.acceptedDataPackageCreation) 'Umbrella authorization omits a required end-to-end stage.'
    Require-Condition (-not $umbrella.permissions.formalAnalysis -and -not $umbrella.permissions.mq -and -not $umbrella.permissions.mt -and -not $umbrella.permissions.credentialPackaging) 'Umbrella authorization exceeds the requested boundary.'
    Require-Condition ([int]$umbrella.execution.oracleBatchCount -eq $oracleBatchCount -and $umbrella.execution.strictSerialFreshUnityProcesses -and [int]$umbrella.execution.maximumConcurrentUnityProcesses -eq 1 -and [int]$umbrella.execution.wholeSuperblockTechnicalReplacements -eq 0) 'Umbrella execution policy mismatch.'
    Require-Condition ([string]$umbrella.roots.formalInputRootRelativePath -ceq $inputRootRelative) 'Umbrella formal-input root mismatch.'
    Require-Condition ([string]$umbrella.roots.measuredRootRelativePath -ceq $measuredRootRelative) 'Umbrella measured root mismatch.'
    Require-Condition ([string]$umbrella.roots.acceptedDataPackageRootRelativePath -ceq $acceptedPackageRootRelative) 'Umbrella accepted-data-package root mismatch.'
    Require-Condition ([string]$umbrella.roots.executionEvidenceRootRelativePath -ceq $evidenceRootRelative) 'Umbrella execution-evidence root mismatch.'

    $orchestratorSha256 = Get-Sha256Lower -Path $PSCommandPath
    Require-Condition ([string]$umbrella.bindings.orchestratorRelativePath -ceq [System.IO.Path]::GetRelativePath($projectRoot, $PSCommandPath).Replace('\', '/')) 'Umbrella orchestrator path mismatch.'
    Require-Condition ([string]$umbrella.bindings.orchestratorSha256 -ceq $orchestratorSha256) 'Umbrella orchestrator self-hash mismatch.'
    Require-Condition ([string]$manifest.endToEndAuthorization.orchestratorSha256 -ceq $orchestratorSha256) 'Manifest orchestrator hash mismatch.'
    Assert-ManifestEntry -Index $manifestIndex -RelativePath ([string]$umbrella.bindings.orchestratorRelativePath) -ExpectedSha256 $orchestratorSha256 -ProjectRoot $projectRoot

    Require-Condition ([string]$umbrella.bindings.inputGenerationAuthorizationRelativePath -ceq $relative.inputAuthorization) 'Umbrella input-authorization path mismatch.'
    Require-Condition ([string]$umbrella.bindings.inputGenerationAuthorizationSha256 -ceq $expectedHashes.inputAuthorization) 'Umbrella input-authorization hash mismatch.'
    Require-Condition ([string]$umbrella.bindings.identityBindingRelativePath -ceq $relative.identityBinding) 'Umbrella identity-binding path mismatch.'
    Require-Condition ([string]$umbrella.bindings.identityBindingSha256 -ceq $expectedHashes.identityBinding) 'Umbrella identity-binding hash mismatch.'

    foreach ($key in $expectedHashes.Keys) {
        $path = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath ([string]$relative[$key])
        Assert-Hash -Path $path -Expected ([string]$expectedHashes[$key]) -Label ([string]$key)
        Assert-ManifestEntry -Index $manifestIndex -RelativePath ([string]$relative[$key]) -ExpectedSha256 ([string]$expectedHashes[$key]) -ProjectRoot $projectRoot
    }

    $inputAuthorization = Read-Json -Path $inputAuthorizationPath
    Require-Condition ($inputAuthorization.schema -ceq 'gate14re-me-formal-st-input-generation-authorization-v5' -and $inputAuthorization.status -ceq 'AUTHORIZED_FORMAL_INPUT_GENERATION_ONLY') 'Input-generation child authorization header mismatch.'
    Require-Condition ([string]$inputAuthorization.authorizationSource.userScopeSha256 -ceq $expectedUserScopeSha256) 'Input-generation child authorization user scope mismatch.'
    Require-Condition ([string]$inputAuthorization.authorizationSource.umbrellaAuthorizationRelativePath -ceq $relative.umbrellaAuthorization) 'Input-generation child authorization umbrella path mismatch.'
    Require-Condition ([string]$inputAuthorization.outputRootRelativePath -ceq $inputRootRelative) 'Input-generation child authorization output root mismatch.'
    Require-Condition ([string]$inputAuthorization.identityBindingRelativePath -ceq $relative.identityBinding -and [string]$inputAuthorization.identityBindingSha256 -ceq $expectedHashes.identityBinding) 'Input-generation child authorization identity binding mismatch.'
    Require-Condition ($inputAuthorization.formalInputGenerationAuthorized -and -not $inputAuthorization.formalRootCreationAuthorized -and -not $inputAuthorization.formalCollectionAuthorized -and -not $inputAuthorization.formalAcceptanceExecutionAuthorized -and -not $inputAuthorization.formalAnalysisAuthorized -and -not $inputAuthorization.mqAuthorized -and -not $inputAuthorization.mtAuthorized) 'Input-generation child authorization exceeds its stage boundary.'

    $identity = Read-Json -Path $identityBindingPath
    Require-Condition ($identity.status -ceq 'AUTHORIZED_REUSE_OF_QUALIFIED_SIX_ALGORITHM_BIJECTION_FOR_FORMAL_ST' -and @($identity.bijection).Count -eq 6) 'Reused identity binding header/cardinality mismatch.'
    Require-Condition (-not $identity.authorizationBoundary.formalCollectionAuthorizedByThisFile -and -not $identity.authorizationBoundary.formalAnalysisAuthorizedByThisFile -and -not $identity.authorizationBoundary.algorithmRankingAuthorized) 'Identity binding exceeds its schedule-binding boundary.'

    foreach ($root in @($inputRoot, $measuredRoot, $acceptedPackageRoot, $evidenceRoot, $readinessRoot)) {
        Require-Condition (-not (Test-Path -LiteralPath $root)) "Single-use root is not fresh: $root"
    }
    Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process is active; strict-serial end-to-end launch requires an idle Unity state.'

    $syntheticAuthorizationParameters = @{
        Umbrella = $umbrella
        UmbrellaSha256 = $umbrellaSha256
        MeasuredRootRelativePath = $measuredRootRelative
        ImplementationManifestSha256 = $expectedHashes.implementationManifest
        AcquisitionContractSha256 = $expectedHashes.acquisitionContract
        InputFreezeManifestSha256 = ('a' * 64)
        ScheduleSha256 = ('b' * 64)
        OracleBatchCount = $oracleBatchCount
    }
    $syntheticAuthorization = New-FormalExecutionAuthorization @syntheticAuthorizationParameters
    $syntheticValidationParameters = @{
        Authorization = $syntheticAuthorization
        MeasuredRootRelativePath = $measuredRootRelative
        ImplementationManifestSha256 = $expectedHashes.implementationManifest
        AcquisitionContractSha256 = $expectedHashes.acquisitionContract
        InputFreezeManifestSha256 = ('a' * 64)
        ScheduleSha256 = ('b' * 64)
    }
    Assert-FormalExecutionAuthorization @syntheticValidationParameters

    if ($ValidateAuthorizationChainOnly.IsPresent) {
        Write-Output ([ordered]@{
            schema = 'gate14re-me-formal-st-end-to-end-authorization-chain-dry-run-v1'
            status = 'PASS_END_TO_END_AUTHORIZATION_CHAIN_DRY_RUN_NO_FORMAL_EXECUTION'
            packageId = $packageId
            packageManifestSha256 = Get-Sha256Lower -Path $manifestPath
            umbrellaAuthorizationSha256 = $umbrellaSha256
            orchestratorSha256 = $orchestratorSha256
            inputGenerationAuthorizationSha256 = $expectedHashes.inputAuthorization
            identityBindingSha256 = $expectedHashes.identityBinding
            formalInputsCreated = 0
            formalCollectionStarted = $false
            acceptanceStarted = $false
            formalAnalysisStarted = $false
            mqStarted = $false
            mtStarted = $false
        } | ConvertTo-Json -Depth 100 -Compress)
        return
    }

    Require-Condition $ConfirmFormalCollection.IsPresent 'Full execution requires the deliberate RUN-TO-DATA-PACKAGE entry point or -ConfirmFormalCollection. This is a launch guard, not a new scientific authorization.'

    $budgetPath = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.resourceBudget
    $budget = Read-Json -Path $budgetPath
    $driveId = [System.IO.Path]::GetPathRoot($measuredRoot).TrimEnd('\')
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveId'"
    $storageSafetyBytes = [int64](10GB)
    $requiredStorageBytes = [int64]$budget.formalRawAndDeliveryReservedStorageBytes + $storageSafetyBytes
    Require-Condition ($null -ne $drive -and [int64]$drive.FreeSpace -ge $requiredStorageBytes) "Free storage is below the end-to-end reservation plus safety margin: required=$requiredStorageBytes"
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $memorySafetyBytes = [int64](4GB)
    $requiredFreeVirtualBytes = [int64]$budget.laneAssignedCommittedMemoryBytes + $memorySafetyBytes
    $freeVirtualBytes = [int64]$operatingSystem.FreeVirtualMemory * 1024
    Require-Condition ($freeVirtualBytes -ge $requiredFreeVirtualBytes) "Free virtual memory is below the lane commitment plus safety margin: required=$requiredFreeVirtualBytes available=$freeVirtualBytes"

    $phase = 'ALGORITHM_FREE_READINESS'
    $readinessScript = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.readiness
    $readinessParameters = @{
        ReceiptRoot = $readinessRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($UnityExecutable)) {
        $readinessParameters.UnityExecutable = $UnityExecutable
    }
    if ($InstallUnityIfMissing.IsPresent) {
        $readinessParameters.InstallUnityIfMissing = $true
    }
    & $readinessScript @readinessParameters
    $readinessTerminalPath = Join-Path $readinessRoot 'deployment-readiness-terminal.v1.json'
    $readinessTerminal = Read-Json -Path $readinessTerminalPath
    Require-Condition ($readinessTerminal.status -ceq 'PASS_MIGRATION_PACKAGE_INSTALL_AND_ALGORITHM_FREE_READINESS') 'Algorithm-free package readiness did not PASS.'
    Require-Condition (-not $readinessTerminal.formalCollectionStarted -and -not $readinessTerminal.formalAnalysisStarted) 'Readiness exceeded its algorithm-free boundary.'
    $resolvedUnity = [System.IO.Path]::GetFullPath([string]$readinessTerminal.unityExecutable)
    Assert-Hash -Path $resolvedUnity -Expected $expectedUnitySha256 -Label 'readiness-resolved Unity executable'

    $phase = 'END_TO_END_EVIDENCE_INITIALIZATION'
    $null = New-Item -ItemType Directory -Path $evidenceRoot
    $launchReceipt = [ordered]@{
        schema = 'gate14re-me-formal-st-end-to-end-launch-receipt-v1'
        studyId = $studyId
        designId = $designId
        status = 'AUTHORIZED_END_TO_END_EXECUTION_STARTED'
        packageId = $packageId
        umbrellaAuthorizationId = [string]$umbrella.authorizationId
        umbrellaAuthorizationSha256 = $umbrellaSha256
        packageManifestSha256 = Get-Sha256Lower -Path $manifestPath
        orchestratorSha256 = $orchestratorSha256
        readinessTerminalSha256 = Get-Sha256Lower -Path $readinessTerminalPath
        formalInputRootRelativePath = $inputRootRelative
        measuredRootRelativePath = $measuredRootRelative
        acceptedDataPackageRootRelativePath = $acceptedPackageRootRelative
        oracleBatchCount = $oracleBatchCount
        strictSerialFreshUnityProcesses = $true
        wholeSuperblockTechnicalReplacements = 0
        retryResumeTopUpMergeSkipReorderParallel = $false
        formalAnalysisAuthorized = $false
        mqAuthorized = $false
        mtAuthorized = $false
        startedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $launchReceiptPath = Join-Path $evidenceRoot 'end-to-end-launch-receipt.v1.json'
    Write-JsonExclusive -Path $launchReceiptPath -Value $launchReceipt

    $phase = 'FORMAL_INPUT_GENERATION'
    $python = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.python
    $generator = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.generator
    & $python $generator generate --project-root $projectRoot --output $inputRoot --authorization $inputAuthorizationPath --authorization-sha256 $expectedHashes.inputAuthorization
    Require-Condition ($LASTEXITCODE -eq 0) "Formal input generation failed closed with exit code $LASTEXITCODE."
    $inputTerminalPath = Join-Path $inputRoot 'terminal-receipt.v5.json'
    $inputTerminal = Read-Json -Path $inputTerminalPath
    Require-Condition ($inputTerminal.status -ceq 'PASS_FORMAL_INPUTS_FROZEN_EXECUTION_NOT_AUTHORIZED') 'Formal input generation terminal is not PASS.'
    $inputFreezeManifestPath = Join-Path $inputRoot 'formal-input-freeze-manifest.v5.json'
    $inputFreezeManifest = Read-Json -Path $inputFreezeManifestPath
    Require-Condition ($inputFreezeManifest.status -ceq 'FROZEN_FORMAL_INPUTS_AND_SCHEDULE_EXECUTION_NOT_AUTHORIZED' -and [int]$inputFreezeManifest.inputCount -eq 1296 -and [int]$inputFreezeManifest.scheduleRowCount -eq 1296) 'Formal input freeze manifest status/cardinality mismatch.'
    $inputFreezeManifestSha256 = Get-Sha256Lower -Path $inputFreezeManifestPath
    $scheduleRelativePath = [string]$inputFreezeManifest.scheduleRelativePath
    $schedulePath = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $scheduleRelativePath
    $scheduleSha256 = Get-Sha256Lower -Path $schedulePath
    Require-Condition ($scheduleSha256 -ceq [string]$inputFreezeManifest.scheduleSha256) 'Formal schedule hash differs from its input-freeze binding.'

    $phase = 'FORMAL_COLLECTION_AUTHORIZATION_DERIVATION'
    $executionAuthorizationParameters = @{
        Umbrella = $umbrella
        UmbrellaSha256 = $umbrellaSha256
        MeasuredRootRelativePath = $measuredRootRelative
        ImplementationManifestSha256 = $expectedHashes.implementationManifest
        AcquisitionContractSha256 = $expectedHashes.acquisitionContract
        InputFreezeManifestSha256 = $inputFreezeManifestSha256
        ScheduleSha256 = $scheduleSha256
        OracleBatchCount = $oracleBatchCount
    }
    $executionAuthorization = New-FormalExecutionAuthorization @executionAuthorizationParameters
    $executionValidationParameters = @{
        Authorization = $executionAuthorization
        MeasuredRootRelativePath = $measuredRootRelative
        ImplementationManifestSha256 = $expectedHashes.implementationManifest
        AcquisitionContractSha256 = $expectedHashes.acquisitionContract
        InputFreezeManifestSha256 = $inputFreezeManifestSha256
        ScheduleSha256 = $scheduleSha256
    }
    Assert-FormalExecutionAuthorization @executionValidationParameters
    $executionAuthorizationPath = Join-Path $evidenceRoot 'formal-st-execution-authorization.v5.json'
    Write-JsonExclusive -Path $executionAuthorizationPath -Value $executionAuthorization
    $executionAuthorizationSha256 = Get-Sha256Lower -Path $executionAuthorizationPath

    $phase = 'STRICT_SERIAL_FORMAL_COLLECTION'
    $supervisor = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.supervisor
    $supervisorParameters = @{
        ProjectRoot = $projectRoot
        MeasuredRoot = $measuredRoot
        ExecutionAuthorization = $executionAuthorizationPath
        ExecutionAuthorizationSha256 = $executionAuthorizationSha256
        ImplementationManifest = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.implementationManifest)
        ImplementationManifestSha256 = $expectedHashes.implementationManifest
        ExecutionContract = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.acquisitionContract)
        ExecutionContractSha256 = $expectedHashes.acquisitionContract
        InputFreezeManifest = $inputFreezeManifestPath
        InputFreezeManifestSha256 = $inputFreezeManifestSha256
        ResourceBudget = $budgetPath
        ResourceBudgetSha256 = $expectedHashes.resourceBudget
        FairnessBinding = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.fairnessBinding)
        FairnessBindingSha256 = $expectedHashes.fairnessBinding
        Schedule = $schedulePath
        ScheduleSha256 = $scheduleSha256
        TrustedIdentityRule = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.trustedIdentityRule)
        TrustedIdentityRuleSha256 = $expectedHashes.trustedIdentityRule
        TimestampComparator = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.timestampComparator)
        TimestampComparatorSha256 = $expectedHashes.timestampComparator
        UnityExecutable = $resolvedUnity
        UnityExecutableSha256 = $expectedUnitySha256
    }
    & $supervisor @supervisorParameters
    $acquisitionTerminalPath = Join-Path $measuredRoot '_control/acquisition-terminal-receipt.v5.json'
    $acquisitionFreezeManifestPath = Join-Path $measuredRoot '_control/acquisition-freeze-manifest.v5.json'
    $acquisitionTerminal = Read-Json -Path $acquisitionTerminalPath
    Require-Condition ($acquisitionTerminal.status -ceq 'PASS_ACQUISITION_ONLY_RAW_FROZEN_ACCEPTANCE_PENDING') 'Formal acquisition did not reach the raw-frozen acceptance-pending terminal.'
    Require-Condition (Test-Path -LiteralPath $acquisitionFreezeManifestPath -PathType Leaf) 'Formal acquisition freeze manifest is missing.'

    $phase = 'READ_ONLY_ACCEPTANCE_AUTHORIZATION'
    $acceptanceAuthorization = [ordered]@{
        schema = 'gate14re-me-formal-st-read-only-acceptance-authorization-v1'
        studyId = $studyId
        designId = $designId
        authorizationId = ([string]$umbrella.authorizationId + '/read-only-acceptance')
        status = 'AUTHORIZED_READ_ONLY_ACCEPTANCE_TO_ACCEPTED_DATA_PACKAGE'
        authorizationSource = [ordered]@{
            umbrellaAuthorizationSha256 = $umbrellaSha256
            userScopeSha256 = $expectedUserScopeSha256
        }
        sourceMeasuredRootRelativePath = $measuredRootRelative
        sourceAcquisitionFreezeManifestSha256 = Get-Sha256Lower -Path $acquisitionFreezeManifestPath
        sourceAcquisitionTerminalSha256 = Get-Sha256Lower -Path $acquisitionTerminalPath
        outputRootRelativePath = $acceptedPackageRootRelative
        readOnlyAcceptanceAuthorized = $true
        acceptedDataPackageCreationAuthorized = $true
        sourceWriteBackAuthorized = $false
        formalAnalysisAuthorized = $false
        rankingOrWinnerAuthorized = $false
        mqAuthorized = $false
        mtAuthorized = $false
    }
    $acceptanceAuthorizationPath = Join-Path $evidenceRoot 'read-only-acceptance-authorization.v1.json'
    Write-JsonExclusive -Path $acceptanceAuthorizationPath -Value $acceptanceAuthorization

    $phase = 'INDEPENDENT_READ_ONLY_ACCEPTANCE'
    $acceptanceLauncher = Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.acceptanceLauncher
    $acceptanceParameters = @{
        ProjectRoot = $projectRoot
        RawRoot = $measuredRoot
        AcceptanceOutputRoot = $acceptedPackageRoot
        AcceptanceContract = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.acceptanceContract)
        AcceptanceContractSha256 = $expectedHashes.acceptanceContract
        AcquisitionContract = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.acquisitionContract)
        AcquisitionContractSha256 = $expectedHashes.acquisitionContract
        AcceptanceTool = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.acceptanceTool)
        AcceptanceToolSha256 = $expectedHashes.acceptanceTool
        RawOutputContract = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.rawOutputContract)
        RawOutputContractSha256 = $expectedHashes.rawOutputContract
        Schedule = $schedulePath
        ScheduleSha256 = $scheduleSha256
        PythonExecutable = $python
        PythonExecutableSha256 = $expectedPythonSha256
        TypedParquetRuntimeManifest = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.typedParquetRuntimeManifest)
        TypedParquetRuntimeManifestSha256 = $expectedHashes.typedParquetRuntimeManifest
        PyArrowRoot = (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.pyArrowRoot)
        BatchSize = 4096
    }
    & $acceptanceLauncher @acceptanceParameters
    $acceptanceTerminalPath = Join-Path $acceptedPackageRoot 'terminal-final.v5.json'
    $acceptanceManifestPath = Join-Path $acceptedPackageRoot 'acceptance-manifest.v5.json'
    $acceptedFileManifestPath = Join-Path $acceptedPackageRoot 'file-manifest.v5.jsonl'
    $acceptanceTerminal = Read-Json -Path $acceptanceTerminalPath
    Require-Condition ($acceptanceTerminal.status -ceq 'PASS_READ_ONLY_FORMAL_ST_ACCEPTANCE' -and $acceptanceTerminal.sourceMeasuredRootWriteBack -eq $false -and $acceptanceTerminal.formalAnalysisPerformed -eq $false) 'Independent read-only acceptance terminal is not PASS.'
    Require-Condition ([int]$acceptanceTerminal.acceptedSuperblocks -eq 1296 -and [int]$acceptanceTerminal.namedAlgorithmLanes -eq 7776 -and $acceptanceTerminal.typedParquetFullRoundTrip) 'Accepted data package cardinality or Parquet round-trip mismatch.'
    Require-Condition (Test-Path -LiteralPath $acceptanceManifestPath -PathType Leaf) 'Accepted data package manifest is missing.'
    Require-Condition (Test-Path -LiteralPath $acceptedFileManifestPath -PathType Leaf) 'Accepted data package per-file manifest is missing.'

    $phase = 'FINAL_EVIDENCE_FREEZE'
    $finalEvidenceArtifacts = @(
        [ordered]@{ role = 'package manifest'; relativePath = $relative.packageManifest; sha256 = Get-Sha256Lower -Path $manifestPath },
        [ordered]@{ role = 'umbrella authorization'; relativePath = $relative.umbrellaAuthorization; sha256 = $umbrellaSha256 },
        [ordered]@{ role = 'end-to-end launch'; relativePath = $evidenceRootRelative + '/end-to-end-launch-receipt.v1.json'; sha256 = Get-Sha256Lower -Path $launchReceiptPath },
        [ordered]@{ role = 'input-generation authorization'; relativePath = $relative.inputAuthorization; sha256 = $expectedHashes.inputAuthorization },
        [ordered]@{ role = 'identity binding'; relativePath = $relative.identityBinding; sha256 = $expectedHashes.identityBinding },
        [ordered]@{ role = 'input freeze manifest'; relativePath = $inputRootRelative + '/formal-input-freeze-manifest.v5.json'; sha256 = $inputFreezeManifestSha256 },
        [ordered]@{ role = 'formal schedule'; relativePath = $scheduleRelativePath; sha256 = $scheduleSha256 },
        [ordered]@{ role = 'formal collection authorization'; relativePath = $evidenceRootRelative + '/formal-st-execution-authorization.v5.json'; sha256 = $executionAuthorizationSha256 },
        [ordered]@{ role = 'raw acquisition freeze manifest'; relativePath = $measuredRootRelative + '/_control/acquisition-freeze-manifest.v5.json'; sha256 = Get-Sha256Lower -Path $acquisitionFreezeManifestPath },
        [ordered]@{ role = 'raw acquisition terminal'; relativePath = $measuredRootRelative + '/_control/acquisition-terminal-receipt.v5.json'; sha256 = Get-Sha256Lower -Path $acquisitionTerminalPath },
        [ordered]@{ role = 'read-only acceptance authorization'; relativePath = $evidenceRootRelative + '/read-only-acceptance-authorization.v1.json'; sha256 = Get-Sha256Lower -Path $acceptanceAuthorizationPath },
        [ordered]@{ role = 'accepted data package manifest'; relativePath = $acceptedPackageRootRelative + '/acceptance-manifest.v5.json'; sha256 = Get-Sha256Lower -Path $acceptanceManifestPath },
        [ordered]@{ role = 'accepted data package per-file manifest'; relativePath = $acceptedPackageRootRelative + '/file-manifest.v5.jsonl'; sha256 = Get-Sha256Lower -Path $acceptedFileManifestPath },
        [ordered]@{ role = 'accepted data package terminal'; relativePath = $acceptedPackageRootRelative + '/terminal-final.v5.json'; sha256 = Get-Sha256Lower -Path $acceptanceTerminalPath }
    )
    $finalFreezeManifest = [ordered]@{
        schema = 'gate14re-me-formal-st-end-to-end-final-evidence-freeze-manifest-v1'
        studyId = $studyId
        designId = $designId
        status = 'FROZEN_END_TO_END_ACCEPTED_DATA_PACKAGE_EVIDENCE'
        packageId = $packageId
        artifactCount = $finalEvidenceArtifacts.Count
        artifacts = $finalEvidenceArtifacts
        acceptedDataPackageRootRelativePath = $acceptedPackageRootRelative
        formalAnalysisPerformed = $false
        rankingOrWinnerComputed = $false
        mqPerformed = $false
        mtPerformed = $false
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $finalFreezeManifestPath = Join-Path $evidenceRoot 'final-evidence-freeze-manifest.v1.json'
    Write-JsonExclusive -Path $finalFreezeManifestPath -Value $finalFreezeManifest

    $terminal = [ordered]@{
        schema = 'gate14re-me-formal-st-end-to-end-terminal-receipt-v1'
        studyId = $studyId
        designId = $designId
        status = 'PASS_ACCEPTED_FORMAL_ST_DATA_PACKAGE_READY_FORMAL_ANALYSIS_NOT_RUN'
        packageId = $packageId
        formalInputRootRelativePath = $inputRootRelative
        measuredRootRelativePath = $measuredRootRelative
        acceptedDataPackageRootRelativePath = $acceptedPackageRootRelative
        finalEvidenceFreezeManifestRelativePath = $evidenceRootRelative + '/final-evidence-freeze-manifest.v1.json'
        finalEvidenceFreezeManifestSha256 = Get-Sha256Lower -Path $finalFreezeManifestPath
        acceptedSuperblocks = 1296
        namedAlgorithmLanes = 7776
        typedParquetFullRoundTrip = $true
        sourceMeasuredRootWriteBack = $false
        formalAnalysisPerformed = $false
        rankingOrWinnerComputed = $false
        mqPerformed = $false
        mtPerformed = $false
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $terminalPath = Join-Path $evidenceRoot 'terminal-receipt.v1.json'
    Write-JsonExclusive -Path $terminalPath -Value $terminal
    Write-Output ($terminal | ConvertTo-Json -Depth 100 -Compress)
}
catch {
    if (Test-Path -LiteralPath $evidenceRoot -PathType Container) {
        $failurePath = Join-Path $evidenceRoot 'orchestration-failure-receipt.v1.json'
        if (-not (Test-Path -LiteralPath $failurePath)) {
            $failure = [ordered]@{
                schema = 'gate14re-me-formal-st-end-to-end-orchestration-failure-receipt-v1'
                studyId = $studyId
                designId = $designId
                status = 'FAILED_CLOSED_PRESERVE_ALL_ROOTS_NO_RETRY_OR_RESUME'
                failedPhase = $phase
                errorType = $_.Exception.GetType().FullName
                error = $_.Exception.Message
                formalInputRootRelativePath = $inputRootRelative
                measuredRootRelativePath = $measuredRootRelative
                acceptedDataPackageRootRelativePath = $acceptedPackageRootRelative
                sameAttemptRetryPermitted = $false
                sameAttemptResumePermitted = $false
                topUpMergeSkipReorderReplacementParallelPermitted = $false
                formalAnalysisAuthorized = $false
                mqAuthorized = $false
                mtAuthorized = $false
                failedAtUtc = [DateTime]::UtcNow.ToString('o')
            }
            Write-JsonExclusive -Path $failurePath -Value $failure
        }
    }
    throw
}
