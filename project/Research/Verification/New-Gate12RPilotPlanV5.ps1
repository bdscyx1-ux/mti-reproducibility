[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($ProjectPath)
$sourcePath = Join-Path $root 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v4.json'
$targetPath = Join-Path $root 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v5.json'
$receiptPath = Join-Path $root 'Research\Gate12R_PilotPlanV5_Derivation.v1.json'
$specPath = Join-Path $root 'Research\Gate12R_5pct_ProcessReuse_Pilot_Specification.v2.md'
$testPath = Join-Path $root 'Research\Gate12R_5pct_ProcessReuse_Pilot_Test_Design.v2.md'
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($path in @($sourcePath, $specPath, $testPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required derivation input is missing: $path" }
}
if ((Test-Path -LiteralPath $targetPath) -or (Test-Path -LiteralPath $receiptPath)) {
    throw 'Gate12R pilot plan v5 or its derivation receipt already exists.'
}
$sourceSha = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceSha -ne 'e2f595aac916dd856e5d6062d1562d3fc7745deaa352b4b0ee3ffc8b78dc3086') {
    throw 'Superseded pilot plan v4 SHA-256 mismatch.'
}
$plan = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
$plan.schemaVersion = 3
$plan.planId = 'gate12r-fresh-process-reuse-5pct-pilot-plan-v3-consolidated-memory-aggregation'
$plan.specificationId = 'gate12r-fresh-process-reuse-5pct-pilot-spec-v2-memory-aggregation'
$plan.testDesignId = 'gate12r-fresh-process-reuse-5pct-pilot-tests-v2-memory-aggregation'
$plan | Add-Member -NotePropertyName specificationBinding -NotePropertyValue ([pscustomobject][ordered]@{
    relativePath = 'Research/Gate12R_5pct_ProcessReuse_Pilot_Specification.v2.md'
    sha256 = (Get-FileHash -LiteralPath $specPath -Algorithm SHA256).Hash.ToLowerInvariant()
})
$plan | Add-Member -NotePropertyName testDesignBinding -NotePropertyValue ([pscustomobject][ordered]@{
    relativePath = 'Research/Gate12R_5pct_ProcessReuse_Pilot_Test_Design.v2.md'
    sha256 = (Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash.ToLowerInvariant()
})
$json = ($plan | ConvertTo-Json -Depth 30) + "`n"
[System.IO.File]::WriteAllText($targetPath, $json, $utf8)
$targetSha = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate12r-pilot-plan-v5-derivation-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('O')
    sourceRelativePath = 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v4.json'
    sourceSha256 = $sourceSha
    sourceStatus = 'SUPERSEDED-BEFORE-EXECUTION'
    targetRelativePath = 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v5.json'
    targetSha256 = $targetSha
    specificationSha256 = (Get-FileHash -LiteralPath $specPath -Algorithm SHA256).Hash.ToLowerInvariant()
    testDesignSha256 = (Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash.ToLowerInvariant()
    pilotRootChanged = $false
    thresholdsChangedFromV4 = $false
    researchSemanticsChangedFromV4 = $false
    completed = $true
}
[System.IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 10) + "`n"), $utf8)
$receipt | ConvertTo-Json -Depth 10
