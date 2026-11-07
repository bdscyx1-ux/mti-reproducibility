[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'An explicit absolute ProjectPath is required.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|New-Gate13RPR2FormalUnityAdapterV2|$ProjectPath"
    exit 0
}

$sourceRelative = 'Assets/_Scripts/Research/Editor/Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.cs'
$targetRelative = 'Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV1.cs'
$receiptRelative = 'Research/Gate13R_PR2_Formal_Unity_Adapter_Derivation_Receipt.v1.json'
$source = [IO.Path]::GetFullPath((Join-Path $ProjectPath $sourceRelative.Replace('/', '\')))
$target = [IO.Path]::GetFullPath((Join-Path $ProjectPath $targetRelative.Replace('/', '\')))
$receiptPath = [IO.Path]::GetFullPath((Join-Path $ProjectPath $receiptRelative.Replace('/', '\')))
$expectedSourceSha256 = 'a47a731c979d58304230a150947ca1bb50207d13d1214b7d4de6e683bba6b5d6'
$actualSourceSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSourceSha256 -ne $expectedSourceSha256) { throw "Frozen PR1B v3 command changed: $actualSourceSha256" }
if (Test-Path -LiteralPath $target) { throw "Create-new formal adapter already exists: $target" }
if (Test-Path -LiteralPath $receiptPath) { throw "Create-new derivation receipt already exists: $receiptPath" }

$text = [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8)
$routes = @(
    [pscustomobject]@{ old = '/// Gate 13R-PR1B v3 path-safe research-only entry point. This additive command leaves the'; new = '/// Gate 13R-PR2 formal path-safe entry point, mechanically derived from the frozen'; count = 1 },
    [pscustomobject]@{ old = '/// frozen V3 process-reuse implementation untouched, uses native Windows process'; new = '/// PR1B V3 command. It retains the same workload, reset, telemetry, memory, and'; count = 1 },
    [pscustomobject]@{ old = '/// counters, and takes the managed-memory endpoint only after the non-inlined'; new = '/// atomic-persistence logic while binding a formally authorized config and receipt.'; count = 1 },
    [pscustomobject]@{ old = '/// sample method has returned and a full collection boundary has completed.'; new = '/// Both two-sample heterogeneous and four-sample shared Williams blocks are accepted.'; count = 1 },
    [pscustomobject]@{ old = 'Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3'; new = 'Gate13RPR2FormalBatchCommandV1'; count = 1 },
    [pscustomobject]@{ old = 'public string pilotPlanRelativePath;'; new = 'public string formalConfigRelativePath;'; count = 1 },
    [pscustomobject]@{ old = 'public string pilotPlanSha256;'; new = 'public string formalConfigSha256;'; count = 1 },
    [pscustomobject]@{ old = 'telemetryProbeResultRelativePath'; new = 'executionReceiptRelativePath'; count = 2 },
    [pscustomobject]@{ old = 'telemetryProbeResultSha256'; new = 'executionReceiptSha256'; count = 5 },
    [pscustomobject]@{ old = 'gate13r-pr1b-v2-memory-aware-process-reuse-sample-summary-v1'; new = 'gate13r-pr2-rq-aligned-s48-h48-formal-sample-summary-v1'; count = 1 },
    [pscustomobject]@{ old = 'gate13r-pr1b-v2-memory-aware-process-reuse-block-manifest-v1'; new = 'gate13r-pr2-rq-aligned-s48-h48-formal-block-manifest-v1'; count = 1 },
    [pscustomobject]@{ old = 'gate13r-pr1b-v2-memory-aware-process-reuse-block-checkpoint-v1'; new = 'gate13r-pr2-rq-aligned-s48-h48-formal-block-checkpoint-v1'; count = 1 },
    [pscustomobject]@{ old = 'gate13r-pr1b-v2-memory-aware-process-reuse-block-failure-v1'; new = 'gate13r-pr2-rq-aligned-s48-h48-formal-block-failure-v1'; count = 1 },
    [pscustomobject]@{ old = 'gate13r-pr1b-v2-memory-gate-evaluation-v1'; new = 'gate13r-pr2-rq-aligned-s48-h48-formal-memory-gate-evaluation-v1'; count = 1 },
    [pscustomobject]@{ old = '-ddmGate10RBlockPlanPath'; new = '-ddmGate13RPR2BlockPlanPath'; count = 1 },
    [pscustomobject]@{ old = '-ddmGate10RBlockPlanSha256'; new = '-ddmGate13RPR2BlockPlanSha256'; count = 1 },
    [pscustomobject]@{ old = '-ddmGate10ROutputDirectory'; new = '-ddmGate13RPR2OutputDirectory'; count = 1 },
    [pscustomobject]@{ old = 'Gate 10R process-reuse block plan is missing.'; new = 'Gate 13R-PR2 formal block plan is missing.'; count = 1 },
    [pscustomobject]@{ old = 'DDM Gate 10R process-reuse block completed: '; new = 'DDM Gate 13R-PR2 formal block completed: '; count = 1 },
    [pscustomobject]@{ old = 'Unsupported Gate 10R process-reuse block-plan schema.'; new = 'Unsupported Gate 13R-PR2 formal block-plan schema.'; count = 1 },
    [pscustomobject]@{ old = 'Gate 10R process-reuse design identity mismatch.'; new = 'Gate 13R-PR2 process-reuse design identity mismatch.'; count = 1 },
    [pscustomobject]@{ old = 'if (plan.formalCampaign) throw new InvalidOperationException("This command invocation is not authorized to produce formal samples.");'; new = 'if (!plan.formalCampaign) throw new InvalidOperationException("The Gate 13R-PR2 formal adapter requires a formally authorized block plan.");'; count = 1 },
    [pscustomobject]@{ old = 'if (expectedAlgorithms.Length != 2) throw new InvalidOperationException("Gate 13R-PR1B v2 accepts only a two-sample heterogeneous Williams block.");'; new = 'if (expectedAlgorithms.Length != 2 && expectedAlgorithms.Length != 4) throw new InvalidOperationException("Gate 13R-PR2 accepts only a complete two- or four-sample frozen Williams cohort.");'; count = 1 },
    [pscustomobject]@{ old = 'if (plan.verificationInjectedFailurePosition < 0 || plan.verificationInjectedFailurePosition > plan.entries.Length) throw new InvalidOperationException("Injected verification failure position is outside the block.");'; new = 'if (plan.verificationInjectedFailurePosition != 0) throw new InvalidOperationException("Injected failures are forbidden in a formal block plan.");'; count = 1 },
    [pscustomobject]@{ old = 'if (plan.verificationInjectedFailurePosition > 0 && !string.Equals(plan.analysisRole, "excluded-negative-fail-closed-verification", StringComparison.Ordinal)) throw new InvalidOperationException("Injected failure is permitted only for the excluded negative verification fixture.");'; new = 'if (!string.Equals(plan.analysisRole, "formal-timing", StringComparison.Ordinal)) throw new InvalidOperationException("The formal block analysis role must be formal-timing.");'; count = 1 },
    [pscustomobject]@{ old = 'ValidateBoundFile(projectRoot, plan.pilotPlanRelativePath, plan.pilotPlanSha256, "Gate 10R config");'; new = 'ValidateBoundFile(projectRoot, plan.formalConfigRelativePath, plan.formalConfigSha256, "Gate 13R-PR2 formal config");'; count = 1 },
    [pscustomobject]@{ old = 'ValidateBoundFile(projectRoot, plan.specificationRelativePath, plan.specificationSha256, "Gate 10R specification");'; new = 'ValidateBoundFile(projectRoot, plan.specificationRelativePath, plan.specificationSha256, "Gate 13R-PR2 formal execution specification");'; count = 1 },
    [pscustomobject]@{ old = 'ValidateBoundFile(projectRoot, plan.testDesignRelativePath, plan.testDesignSha256, "Gate 10R test design");'; new = 'ValidateBoundFile(projectRoot, plan.testDesignRelativePath, plan.testDesignSha256, "Gate 13R-PR2 prelaunch test design");'; count = 1 },
    [pscustomobject]@{ old = 'ValidateBoundFile(projectRoot, plan.amendmentRelativePath, plan.amendmentSha256, "Gate 10R authorization");'; new = 'ValidateBoundFile(projectRoot, plan.amendmentRelativePath, plan.amendmentSha256, "Gate 13R-PR2 two-phase amendment");'; count = 1 },
    [pscustomobject]@{ old = 'ValidateBoundFile(projectRoot, plan.commandRelativePath, plan.commandSha256, "Gate 10R command");'; new = 'ValidateBoundFile(projectRoot, plan.commandRelativePath, plan.commandSha256, "Gate 13R-PR2 formal command");'; count = 1 },
    [pscustomobject]@{ old = 'ValidateBoundFile(projectRoot, plan.provenanceRelativePath, plan.provenanceSha256, "Gate 10R provenance");'; new = 'ValidateBoundFile(projectRoot, plan.provenanceRelativePath, plan.provenanceSha256, "Gate 13R-PR2 formal execution provenance");'; count = 1 },
    [pscustomobject]@{ old = 'ValidateBoundFile(projectRoot, plan.executionReceiptRelativePath, plan.executionReceiptSha256, "successful telemetry probe result");'; new = 'ValidateBoundFile(projectRoot, plan.executionReceiptRelativePath, plan.executionReceiptSha256, "Gate 13R-PR2 formal execution receipt");'; count = 1 }
)

$evidence = New-Object Collections.Generic.List[object]
foreach ($route in $routes) {
    $actual = $text.Split([string[]]@([string]$route.old), [StringSplitOptions]::None).Count - 1
    if ($actual -ne [int]$route.count) {
        throw "Formal adapter replacement count mismatch: expected=$($route.count) actual=$actual token=$($route.old)"
    }
    $text = $text.Replace([string]$route.old, [string]$route.new)
    $evidence.Add([ordered]@{ from = [string]$route.old; to = [string]$route.new; replacementCount = $actual })
}

$utf8 = New-Object Text.UTF8Encoding($false, $true)
[IO.File]::WriteAllText($target, $text, $utf8)
$targetSha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-formal-unity-adapter-mechanical-derivation-receipt-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    sourceRelativePath = $sourceRelative
    sourceSha256 = $actualSourceSha256
    targetRelativePath = $targetRelative
    targetSha256 = $targetSha256
    routes = $evidence.ToArray()
    sourceFileModified = $false
    researchAlgorithmSemanticsChanged = $false
    scenarioSemanticsChanged = $false
    resetTelemetryMemoryOrAtomicPersistenceChanged = $false
    formalAuthorizationAndBindingChanged = $true
    completeTwoOrFourSampleWilliamsCohortsAccepted = $true
    formalCampaign = $true
}
$receiptText = (($receipt | ConvertTo-Json -Depth 40).Replace("`r`n", "`n").Replace("`r", "`n") + "`n")
[IO.File]::WriteAllText($receiptPath, $receiptText, $utf8)
Write-Output "FORMAL-UNITY-ADAPTER-DERIVED|$targetSha256"
