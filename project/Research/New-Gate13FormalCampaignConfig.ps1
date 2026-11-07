[CmdletBinding()]
param(
    [string]$ProjectPath,
    [string]$OutputPath,
    [switch]$CheckOnly,
    [switch]$ReplacePreparedConfig
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $ProjectPath 'Research\Gate13_Formal_Campaign_Config.v1.json' }
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $ProjectPath $OutputPath }
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$expectedOutputPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Gate13_Formal_Campaign_Config.v1.json'))
if (-not [string]::Equals($OutputPath, $expectedOutputPath, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Gate 13 v1 config path must be exactly: $expectedOutputPath" }

$modulePath = Join-Path $scriptDirectory 'Gate13FormalPreparation.psm1'
Import-Module $modulePath -Force
$config = New-Gate13FormalConfig -ProjectPath $ProjectPath
$canonicalText = ConvertTo-Gate13JsonText -Value $config -Depth 30
$canonicalSha256 = Get-Gate13StringSha256 -Value $canonicalText

if ($CheckOnly) {
    $exists = Test-Path -LiteralPath $OutputPath -PathType Leaf
    $matches = $false
    if ($exists) {
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
        $matches = [string]::Equals([System.IO.File]::ReadAllText($OutputPath, $encoding), $canonicalText, [System.StringComparison]::Ordinal)
    }
    [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'validation-only'
        outputPath = $OutputPath
        exists = $exists
        canonicalBytesMatch = $matches
        canonicalSha256 = $canonicalSha256
        campaignCount = @($config.campaigns).Count
        expectedUnityProcessCount = [int]$config.totals.expectedUnityProcessCount
        formalCampaignStartAllowed = $false
        passed = $exists -and $matches
    } | ConvertTo-Json -Depth 8
    if (-not ($exists -and $matches)) { exit 1 }
    exit 0
}

if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    $existingText = [System.IO.File]::ReadAllText($OutputPath, $encoding)
    if (-not [string]::Equals($existingText, $canonicalText, [System.StringComparison]::Ordinal)) {
        if (-not $ReplacePreparedConfig) { throw 'Existing Gate 13 config differs from deterministic reconstruction; pass -ReplacePreparedConfig only during the authorized nonexecuting preparation stage.' }
        $existing = $existingText | ConvertFrom-Json
        if ($existing.authorizationBoundary.gate13ExecutionAuthorized -ne $false -or $existing.authorizationBoundary.formalCampaignStartAllowed -ne $false) { throw 'Refusing to replace a config that claims formal execution authorization.' }
        $formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13\v1'
        if (Test-Path -LiteralPath $formalRoot) { throw 'Refusing to replace the prepared config after the Gate 13 formal root exists.' }
        Write-Gate13Utf8NoBomJson -Path $OutputPath -Value $config -Depth 30
        Write-Host 'Gate 13 nonexecuting prepared config replaced after runtime hash changes; no execution was authorized.' -ForegroundColor Green
    } else {
        Write-Host 'Gate 13 formal config already matches the deterministic reconstruction; no file was changed.' -ForegroundColor Green
    }
} else {
    Write-Gate13Utf8NoBomJson -Path $OutputPath -Value $config -Depth 30
    Write-Host 'Gate 13 formal config created. This config does not authorize execution.' -ForegroundColor Green
}

[pscustomobject][ordered]@{
    schemaVersion = 1
    outputPath = $OutputPath
    sha256 = Get-Gate13LowerSha256 -Path $OutputPath
    campaignCount = @($config.campaigns).Count
    expectedUnityProcessCount = [int]$config.totals.expectedUnityProcessCount
    gate13ExecutionAuthorized = $false
    formalCampaignStartAllowed = $false
    passed = $true
} | ConvertTo-Json -Depth 8
exit 0
