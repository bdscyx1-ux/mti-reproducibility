[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$VerificationRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Get-Sha256Lower {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-BoundFile {
    param(
        [string]$Role,
        [string]$RelativePath,
        [string]$ExpectedSha256
    )
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $script:ResolvedProjectRoot $RelativePath))
    Require-Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) "Missing bound file: $RelativePath"
    $actual = Get-Sha256Lower $fullPath
    $item = Get-Item -LiteralPath $fullPath
    $binding = [ordered]@{
        role = $Role
        relativePath = ($RelativePath -replace '\\', '/')
        lengthBytes = $item.Length
        expectedSha256 = $ExpectedSha256
        actualSha256 = $actual
        matched = ($actual -eq $ExpectedSha256)
    }
    $script:Bindings.Add([pscustomobject]$binding)
    Require-Condition $binding.matched "Hash mismatch: $RelativePath"
    return $fullPath
}

function ConvertTo-CompactJson {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Copy-JsonValue {
    param([object]$Value)
    return (ConvertTo-CompactJson $Value | ConvertFrom-Json -Depth 100)
}

function Test-JsonAgainstSchema {
    param([string]$Json, [string]$SchemaPath)
    $result = Test-Json -Json $Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue 2>$null
    return ($result -eq $true)
}

function Test-ExactJsonValue {
    param([object]$Left, [object]$Right)
    return ((ConvertTo-CompactJson $Left) -ceq (ConvertTo-CompactJson $Right))
}

function New-PositiveBundle {
    $starts = @()
    for ($index = 0; $index -lt 8; $index++) {
        $starts += [ordered]@{ x = $index; y = 0 }
    }

    $phases = @('block', 'unblock_or_restore', 'increase_cost', 'decrease_or_restore_cost')
    $groups = @()
    for ($index = 0; $index -lt 24; $index++) {
        $groups += [ordered]@{
            eventGroupId = ('kat-event-{0:D2}' -f $index)
            eventGroupIndex = $index
            cycleIndex = [math]::Floor($index / 4)
            phase = $phases[$index % 4]
            topology = 'compact'
            atomicPartitions = @(
                [ordered]@{
                    partitionIndex = 0
                    changes = @(
                        [ordered]@{
                            x = 20 + $index
                            y = 20
                            isWalkable = $false
                            traversalCost = 1.0
                        }
                    )
                }
            )
        }
    }

    return [ordered]@{
        schema = 'gate14re-me-qualification-input-bundle-v1'
        studyId = 'Gate14Re-ME'
        protocolId = 'gate14re-me-load-qualification-v1'
        inputId = 'kat-input-001'
        superblockId = 'kat-superblock-001'
        designRegion = 'core'
        seed = 1
        gridEdge = 64
        agentCount = 8
        changedCellCount = 1
        changeTopology = 'compact'
        graphProfile = 'four_way_weighted_dense'
        sameTickAtomicPartitions = 1
        contextStratumId = 'kat-context'
        connectivity = 4
        allowDiagonalCornerCutting = $false
        defaultTraversalCost = 1.0
        initialCellOverrides = @()
        goal = [ordered]@{ x = 63; y = 63 }
        starts = $starts
        eventGroups = $groups
    }
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite existing receipt: $Path"
    $json = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $encoding)
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

$createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
$script:Bindings = [System.Collections.Generic.List[object]]::new()
$tests = [ordered]@{}
$passed = $false
$exactFailure = $null
$exceptionType = $null
$stackTrace = $null

$script:ResolvedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$expectedVerificationRoot = [System.IO.Path]::GetFullPath((Join-Path $script:ResolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001'))
$resolvedVerificationRoot = [System.IO.Path]::GetFullPath($VerificationRoot)
Require-Condition ($resolvedVerificationRoot -ieq $expectedVerificationRoot) 'Verification root is outside the exact authorized evidence directory.'
Require-Condition (Test-Path -LiteralPath $resolvedVerificationRoot -PathType Container) 'Authorized verification root does not exist.'
$receiptPath = Join-Path $resolvedVerificationRoot 'schema-known-answer-receipt.v1.json'
Require-Condition (-not (Test-Path -LiteralPath $receiptPath)) 'Schema known-answer receipt already exists; overwrite is prohibited.'

try {
    $authorizationPath = Resolve-BoundFile 'authorization' 'Research/Gate14Re-ME/Gate14Re_ME_Qualification_Input_Schema_Compatibility_Corrigendum_Authorization.v1.json' 'dc8a9e5563e0b428f895f7de56265e78d51b3c57b59295fc9ad4f0bf86c7d6b6'
    $planPath = Resolve-BoundFile 'plan' 'Research/Gate14Re-ME/Gate14Re_ME_Qualification_Input_Schema_Compatibility_Corrigendum_Plan.v1.md' '6d93d2542baaccd82375ad364ad1ebfa2dc45c7e55bb4b52c917afc7b27fccbb'
    $statusPath = Resolve-BoundFile 'parent-status-v11' 'Research/Gate14Re-ME/Gate14Re_ME_Status.v11.json' '4bd0f8b512fec16daf3e5dd793caf8420fafd3f80b4f95cd3aca4981f469e47e'
    $failurePath = Resolve-BoundFile 'retained-planning-failure' 'Research/Verification/Gate14Re-ME/qualification-planning-freeze-attempt-001/failure-receipt.v1.json' 'f3ebfb70faba9d48d39d12eeff5fe64cfc2776ac73c0b672e1ecf04273b4b2c6'
    $auditPath = Resolve-BoundFile 'retained-preflight-audit' 'Research/Verification/Gate14Re-ME/qualification-planning-freeze-attempt-001/preflight-compatibility-audit.v1.json' '68fa5cb6c4a3a9c87d29f06acb69dd93f2081f060f69e192478fdedf2231afcf'
    $schemaV1Path = Resolve-BoundFile 'legacy-input-schema-v1' 'Research/Gate14Re-ME/Execution/v1/load-qualification-input-schema.v1.json' '12105816916eaadc6575ed28dc96a6bb4a9863d2dbbe70cc034ebcfbf1de2c6b'
    $schemaV2Path = Resolve-BoundFile 'corrected-input-schema-v2' 'Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json' '1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117'
    $bindingPath = Resolve-BoundFile 'planning-schema-binding-v2' 'Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json' 'abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7'
    $dtoPath = Resolve-BoundFile 'qualification-contracts-source' 'Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEQualificationContractsV1.cs' '0e6a516c24eff27195b634227a96fde742eea6ef5899eaa7aeda7c514c2b7ee4'
    $oraclePath = Resolve-BoundFile 'reference-oracle-source' 'Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs' '3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25'
    $runnerPath = Resolve-BoundFile 'qualification-runner-v2-source' 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs' '39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73'

    $schemaV1 = Get-Content -LiteralPath $schemaV1Path -Raw | ConvertFrom-Json -Depth 100
    $schemaV2 = Get-Content -LiteralPath $schemaV2Path -Raw | ConvertFrom-Json -Depth 100

    $tests.runtimeBundleIdentityPreserved = ($schemaV2.properties.schema.const -ceq 'gate14re-me-qualification-input-bundle-v1')
    $tests.topLevelRequiredUnchanged = Test-ExactJsonValue $schemaV1.required $schemaV2.required
    $tests.topLevelPropertiesUnchanged = Test-ExactJsonValue $schemaV1.properties $schemaV2.properties
    $tests.coordinateDefinitionUnchanged = Test-ExactJsonValue $schemaV1.'$defs'.coordinate $schemaV2.'$defs'.coordinate
    $tests.cellStateDefinitionUnchanged = Test-ExactJsonValue $schemaV1.'$defs'.cellState $schemaV2.'$defs'.cellState
    $tests.atomicPartitionDefinitionUnchanged = Test-ExactJsonValue $schemaV1.'$defs'.atomicPartition $schemaV2.'$defs'.atomicPartition

    $eventV1 = $schemaV1.'$defs'.eventGroup
    $eventV2 = $schemaV2.'$defs'.eventGroup
    $legacyPropertyNames = @($eventV1.properties.PSObject.Properties.Name)
    $correctedPropertyNames = @($eventV2.properties.PSObject.Properties.Name)
    $addedProperties = @($correctedPropertyNames | Where-Object { $_ -notin $legacyPropertyNames })
    $removedProperties = @($legacyPropertyNames | Where-Object { $_ -notin $correctedPropertyNames })
    $addedRequired = @($eventV2.required | Where-Object { $_ -notin @($eventV1.required) })
    $removedRequired = @($eventV1.required | Where-Object { $_ -notin @($eventV2.required) })
    $tests.onlyTopologyPropertyAdded = ($addedProperties.Count -eq 1 -and $addedProperties[0] -ceq 'topology' -and $removedProperties.Count -eq 0)
    $tests.onlyTopologyRequirementAdded = ($addedRequired.Count -eq 1 -and $addedRequired[0] -ceq 'topology' -and $removedRequired.Count -eq 0)
    $tests.topologyLevelsEqualInputLevels = Test-ExactJsonValue $eventV2.properties.topology.enum $schemaV2.properties.changeTopology.enum

    $eventV2WithoutTopology = Copy-JsonValue $eventV2
    $eventV2WithoutTopology.required = @($eventV2WithoutTopology.required | Where-Object { $_ -cne 'topology' })
    $eventV2WithoutTopology.properties.PSObject.Properties.Remove('topology')
    $tests.eventGroupLegacyConstraintsUnchanged = Test-ExactJsonValue $eventV1 $eventV2WithoutTopology
    $oldSemanticChecksRetained = $true
    foreach ($check in @($schemaV1.semanticChecksOutsideJsonSchema)) {
        if ($check -notin @($schemaV2.semanticChecksOutsideJsonSchema)) {
            $oldSemanticChecksRetained = $false
        }
    }
    $tests.oldSemanticChecksRetained = $oldSemanticChecksRetained
    $tests.crossFieldTopologyEqualityDeclaredForOracle = ('every event-group topology exactly equals the input-level changeTopology' -in @($schemaV2.semanticChecksOutsideJsonSchema))

    $positive = New-PositiveBundle
    $positiveJson = ConvertTo-CompactJson $positive
    $tests.positiveTopologyBundlePassesV2 = Test-JsonAgainstSchema $positiveJson $schemaV2Path
    $tests.positiveTopologyBundleFailsV1 = -not (Test-JsonAgainstSchema $positiveJson $schemaV1Path)

    $missingTopology = Copy-JsonValue $positive
    foreach ($group in @($missingTopology.eventGroups)) {
        $group.PSObject.Properties.Remove('topology')
    }
    $missingTopologyJson = ConvertTo-CompactJson $missingTopology
    $tests.missingTopologyBundlePassesV1 = Test-JsonAgainstSchema $missingTopologyJson $schemaV1Path
    $tests.missingTopologyBundleFailsV2 = -not (Test-JsonAgainstSchema $missingTopologyJson $schemaV2Path)

    $invalidTopology = Copy-JsonValue $positive
    $invalidTopology.eventGroups[0].topology = 'clustered'
    $tests.invalidTopologyLevelFailsV2 = -not (Test-JsonAgainstSchema (ConvertTo-CompactJson $invalidTopology) $schemaV2Path)

    $unknownField = Copy-JsonValue $positive
    $unknownField.eventGroups[0] | Add-Member -NotePropertyName 'unexpectedField' -NotePropertyValue 1
    $tests.unknownEventGroupPropertyFailsV2 = -not (Test-JsonAgainstSchema (ConvertTo-CompactJson $unknownField) $schemaV2Path)

    $missingTopLevel = Copy-JsonValue $positive
    $missingTopLevel.PSObject.Properties.Remove('inputId')
    $tests.missingRequiredTopLevelFieldFailsV2 = -not (Test-JsonAgainstSchema (ConvertTo-CompactJson $missingTopLevel) $schemaV2Path)

    foreach ($test in $tests.GetEnumerator()) {
        Require-Condition ([bool]$test.Value) "Known-answer check failed: $($test.Key)"
    }
    $passed = $true
}
catch {
    $passed = $false
    $exactFailure = $_.Exception.Message
    $exceptionType = $_.Exception.GetType().FullName
    $stackTrace = $_.ScriptStackTrace
}

$completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
$receipt = [ordered]@{
    schema = 'gate14re-me-input-schema-compatibility-known-answer-receipt-v1'
    studyId = 'Gate14Re-ME'
    authorizationId = 'gate14re-me-qualification-input-schema-compatibility-corrigendum-attempt-001'
    status = $(if ($passed) { 'PASS_INPUT_SCHEMA_COMPATIBILITY_KNOWN_ANSWER' } else { 'FAILED_CLOSED_INPUT_SCHEMA_COMPATIBILITY_KNOWN_ANSWER' })
    createdAtUtc = $createdAtUtc
    completedAtUtc = $completedAtUtc
    passed = $passed
    terminal = $true
    validationEngine = [ordered]@{
        host = 'PowerShell Test-Json'
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        dependencyInstalledForStage = $false
    }
    tool = [ordered]@{
        relativePath = 'Research/Gate14Re-ME/Tools/Test-Gate14ReMEInputSchemaCompatibilityV1.ps1'
        sha256 = Get-Sha256Lower $MyInvocation.MyCommand.Path
    }
    bindings = @($script:Bindings)
    tests = $tests
    boundary = [ordered]@{
        syntheticBundleMaterializedToDisk = $false
        scheduleRowsGenerated = 0
        qualificationInputsGenerated = 0
        anonymousIdentityMappingsGenerated = 0
        qualificationMeasuredRootCreated = $false
        plannerConstructedOrInvoked = $false
        algorithmLaneExecuted = $false
        formalCollectionPerformed = $false
        formalAnalysisPerformed = $false
        algorithmRankingPerformed = $false
        winnerAdjudicationPerformed = $false
    }
    exceptionType = $exceptionType
    exactFailure = $exactFailure
    stackTrace = $stackTrace
}

Write-JsonExclusive $receiptPath $receipt
Write-Output ($receipt | ConvertTo-Json -Depth 100 -Compress)
if (-not $passed) {
    exit 1
}
