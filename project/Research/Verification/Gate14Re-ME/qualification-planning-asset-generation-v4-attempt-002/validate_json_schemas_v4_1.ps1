param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $true)]
    [string]$AttemptRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Utf8Json {
    param([string]$Path, [object]$Value)
    $json = $Value | ConvertTo-Json -Depth 100
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $utf8)
}

$expectedAttempt = Join-Path $ProjectRoot 'Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002'
$resolvedProject = [System.IO.Path]::GetFullPath($ProjectRoot)
$resolvedAttempt = [System.IO.Path]::GetFullPath($AttemptRoot)
if ($resolvedAttempt -cne [System.IO.Path]::GetFullPath($expectedAttempt)) {
    throw 'Attempt root is not the authorized canonical path.'
}

$receiptDirectory = Join-Path $resolvedAttempt 'validation'
[System.IO.Directory]::CreateDirectory($receiptDirectory) | Out-Null
$receiptPath = Join-Path $receiptDirectory 'json-schema-validation-receipt.v4.json'
$inputSchema = Join-Path $resolvedProject 'Research/Gate14Re-ME/Execution/v4/load-qualification-input-schema.v4_0.json'
$scheduleSchema = Join-Path $resolvedProject 'Research/Gate14Re-ME/Execution/v4/load-qualification-schedule-schema.v4_0.json'
$inputRoot = Join-Path $resolvedAttempt 'planning-assets/inputs'
$schedulePath = Join-Path $resolvedAttempt 'planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl'
$failures = [System.Collections.Generic.List[object]]::new()
$inputFiles = @(Get-ChildItem -LiteralPath $inputRoot -File -Recurse -Filter '*.input.v4.json' | Sort-Object FullName)
$inputPasses = 0

foreach ($file in $inputFiles) {
    try {
        $raw = [System.IO.File]::ReadAllText($file.FullName)
        if ($raw | Test-Json -SchemaFile $inputSchema -ErrorAction Stop) {
            $inputPasses++
        } else {
            $failures.Add([ordered]@{ kind = 'input'; path = $file.FullName; reason = 'Test-Json returned false' })
        }
    } catch {
        $failures.Add([ordered]@{ kind = 'input'; path = $file.FullName; reason = $_.Exception.Message })
    }
}

$schedulePasses = 0
$scheduleLines = @([System.IO.File]::ReadAllLines($schedulePath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
for ($index = 0; $index -lt $scheduleLines.Count; $index++) {
    try {
        if ($scheduleLines[$index] | Test-Json -SchemaFile $scheduleSchema -ErrorAction Stop) {
            $schedulePasses++
        } else {
            $failures.Add([ordered]@{ kind = 'schedule'; row = $index; reason = 'Test-Json returned false' })
        }
    } catch {
        $failures.Add([ordered]@{ kind = 'schedule'; row = $index; reason = $_.Exception.Message })
    }
}

$passed = $inputFiles.Count -eq 126 -and $inputPasses -eq 126 -and $scheduleLines.Count -eq 126 -and $schedulePasses -eq 126 -and $failures.Count -eq 0
$receipt = [ordered]@{
    schema = 'gate14re-me-qualification-planning-assets-json-schema-validation-v4'
    studyId = 'Gate14Re-ME'
    authorizationId = 'gate14re-me-qualification-planning-asset-generation-v4-attempt-002'
    status = if ($passed) { 'PASS_JSON_SCHEMA_VALIDATION' } else { 'FAIL_JSON_SCHEMA_VALIDATION' }
    validatedAtUtc = [DateTime]::UtcNow.ToString('o')
    engine = 'PowerShell Test-Json'
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    inputSchemaRelativePath = 'Research/Gate14Re-ME/Execution/v4/load-qualification-input-schema.v4_0.json'
    scheduleSchemaRelativePath = 'Research/Gate14Re-ME/Execution/v4/load-qualification-schedule-schema.v4_0.json'
    inputBundleCount = $inputFiles.Count
    inputBundlePassCount = $inputPasses
    scheduleRowCount = $scheduleLines.Count
    scheduleRowPassCount = $schedulePasses
    failureCount = $failures.Count
    failures = @($failures)
}
Write-Utf8Json -Path $receiptPath -Value $receipt

if (-not $passed) {
    throw "Gate14Re-ME planning asset JSON Schema validation failed; see $receiptPath"
}

$receipt | ConvertTo-Json -Depth 8 -Compress
