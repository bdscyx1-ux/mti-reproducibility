[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate13R command derivation v2 requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|New-Gate13RFormalBatchCommandV2|$ProjectPath"; exit 0 }

$source = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate12RProcessReuseBatchCommandV3.cs'
$destination = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RProcessReuseFormalBatchCommandV1.cs'
$receiptPath = Join-Path $ProjectPath 'Research\Gate13R_Formal_Command_Derivation.v2.json'
$expectedSourceSha256 = 'eeca58f7e1121d0a297e8796430a90ae32f8492c32fc5fb676ae102b5f4a0c97'
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedSourceSha256) { throw 'Frozen Gate12R V3 command source hash changed.' }
if (Test-Path -LiteralPath $destination) { throw "Create-new Gate13R formal command already exists: $destination" }
if (Test-Path -LiteralPath $receiptPath) { throw "Create-new Gate13R derivation receipt already exists: $receiptPath" }

$text = [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8)
$routes = @(
    [pscustomobject]@{ old = 'Gate12RProcessReuseBatchCommandV3'; new = 'Gate13RProcessReuseFormalBatchCommandV1'; expected = 1 },
    [pscustomobject]@{ old = '-ddmGate10R'; new = '-ddmGate13R'; expected = 4 },
    [pscustomobject]@{ old = 'pilotPlanRelativePath'; new = 'formalConfigRelativePath'; expected = 2 },
    [pscustomobject]@{ old = 'pilotPlanSha256'; new = 'formalConfigSha256'; expected = 2 },
    [pscustomobject]@{ old = 'telemetryProbeResultRelativePath'; new = 'executionReceiptRelativePath'; expected = 2 },
    [pscustomobject]@{ old = 'telemetryProbeResultSha256'; new = 'executionReceiptSha256'; expected = 3 },
    [pscustomobject]@{ old = 'if (plan.formalCampaign) throw new InvalidOperationException("This command invocation is not authorized to produce formal samples.");'; new = 'if (!plan.formalCampaign) throw new InvalidOperationException("Gate 13R formal command requires a formally authorized block plan.");'; expected = 1 },
    [pscustomobject]@{ old = 'if (plan.verificationInjectedFailurePosition < 0 || plan.verificationInjectedFailurePosition > plan.entries.Length) throw new InvalidOperationException("Injected verification failure position is outside the block.");'; new = "if (plan.verificationInjectedFailurePosition != 0) throw new InvalidOperationException(`"Gate 13R formal plans cannot inject verification failures.`");`r`n            if (!string.Equals(plan.analysisRole, `"formal-timing`", StringComparison.Ordinal)) throw new InvalidOperationException(`"Gate 13R formal analysis role mismatch.`");"; expected = 1 },
    [pscustomobject]@{ old = 'if (plan.verificationInjectedFailurePosition > 0 && !string.Equals(plan.analysisRole, "excluded-negative-fail-closed-verification", StringComparison.Ordinal)) throw new InvalidOperationException("Injected failure is permitted only for the excluded negative verification fixture.");'; new = '// Formal timing never permits an injected verification failure.'; expected = 1 },
    [pscustomobject]@{ old = 'ValidateBoundFile(projectRoot, plan.formalConfigRelativePath, plan.formalConfigSha256, "Gate 10R config");'; new = 'ValidateBoundFile(projectRoot, plan.formalConfigRelativePath, plan.formalConfigSha256, "Gate 13R formal config");'; expected = 1 },
    [pscustomobject]@{ old = 'ValidateBoundFile(projectRoot, plan.executionReceiptRelativePath, plan.executionReceiptSha256, "successful telemetry probe result");'; new = 'ValidateBoundFile(projectRoot, plan.executionReceiptRelativePath, plan.executionReceiptSha256, "Gate 13R formal execution receipt");'; expected = 1 },
    [pscustomobject]@{ old = 'Unsupported Gate 10R process-reuse block-plan schema.'; new = 'Unsupported Gate 13R formal block-plan schema.'; expected = 1 },
    [pscustomobject]@{ old = 'Gate 10R process-reuse design identity mismatch.'; new = 'Gate 13R process-reuse design identity mismatch.'; expected = 1 },
    [pscustomobject]@{ old = 'gate12r-process-reuse-5pct-process-reuse-block-manifest-v2'; new = 'gate13r-process-reuse-5pct-formal-block-manifest-v1'; expected = 1 },
    [pscustomobject]@{ old = 'gate10r-process-reuse-5pct-process-reuse-sample-summary-v1'; new = 'gate13r-process-reuse-5pct-formal-sample-summary-v1'; expected = 1 },
    [pscustomobject]@{ old = 'gate10r-process-reuse-5pct-process-reuse-block-checkpoint-v1'; new = 'gate13r-process-reuse-5pct-formal-block-checkpoint-v1'; expected = 1 },
    [pscustomobject]@{ old = 'gate12r-process-reuse-5pct-process-reuse-block-failure-v2'; new = 'gate13r-process-reuse-5pct-formal-block-failure-v1'; expected = 1 }
)

$evidence = New-Object Collections.Generic.List[object]
foreach ($route in $routes) {
    $count = $text.Split([string[]]@([string]$route.old), [StringSplitOptions]::None).Count - 1
    if ($count -ne [int]$route.expected) { throw "Gate13R command derivation replacement count mismatch: expected=$($route.expected) actual=$count token=$($route.old)" }
    $text = $text.Replace([string]$route.old, [string]$route.new)
    $evidence.Add([ordered]@{ from = [string]$route.old; to = [string]$route.new; replacementCount = $count })
}

[IO.File]::WriteAllText($destination, $text, (New-Object Text.UTF8Encoding($false, $true)))
$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-formal-command-mechanical-derivation-v2'
    sourceRelativePath = 'Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV3.cs'
    sourceSha256 = $expectedSourceSha256
    destinationRelativePath = 'Assets/_Scripts/Research/Editor/Gate13RProcessReuseFormalBatchCommandV1.cs'
    destinationSha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    replacements = $evidence.ToArray()
    algorithmSemanticsChanged = $false
    scenarioSemanticsChanged = $false
    resetTelemetryMemorySemanticsChanged = $false
    formalIdentityAndAuthorizationSemanticsChanged = $true
    attempt1FailureRelativePath = 'Research/Gate13R_Command_Derivation_Attempt1_Failure.v1.json'
    formalCampaignExecuted = $false
}
$json = ($receipt | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
[IO.File]::WriteAllText($receiptPath, $json, (New-Object Text.UTF8Encoding($false, $true)))
Write-Host "Gate13R formal command derived without execution: $($receipt.destinationSha256)" -ForegroundColor Green
