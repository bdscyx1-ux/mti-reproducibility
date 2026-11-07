[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Get-Sha256Lower {
    param([string]$Path)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required source is missing: $Path"
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Utf8NoBomExclusive {
    param([string]$Path, [string]$Text)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite target: $Path"
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { $null = New-Item -ItemType Directory -Path $parent }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$sourceRunner = Join-Path $root 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_1.cs'
$sourceOracle = Join-Path $root 'Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs'
$sourceSupervisor = Join-Path $root 'Research/Gate14Re-ME/Execution/v4/Run-Gate14ReMELoadQualification.v4_1.ps1'
$targetRunner = Join-Path $root 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_2.cs'
$targetRunnerMeta = $targetRunner + '.meta'
$targetValidator = Join-Path $root 'Assets/_Scripts/Research/Gate14ReME/v4/Gate14ReMEInputGeometryValidatorV4_2.cs'
$targetValidatorMeta = $targetValidator + '.meta'
$targetSupervisor = Join-Path $root 'Research/Gate14Re-ME/Execution/v4/Run-Gate14ReMELoadQualification.v4_2.ps1'

Require-Condition ((Get-Sha256Lower -Path $sourceRunner) -ceq 'a3013097068325f314e6842dd9f9bdc2cedbc5d6773a51032200925228690a9f') 'Frozen v4.1 runner source hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $sourceOracle) -ceq '3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25') 'Frozen v1 oracle/validator source hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $sourceSupervisor) -ceq '1787264268e78c75e4ad7adc0e1490f7e812ea62f0ac5ba4b742a0cc9cba0fb3') 'Frozen v4.1 supervisor source hash mismatch.'

$oracleText = [IO.File]::ReadAllText($sourceOracle, [Text.Encoding]::UTF8)
$marker = '    public static class Gate14ReMEInputGeometryValidatorV1'
$classStart = $oracleText.IndexOf($marker, [StringComparison]::Ordinal)
$namespaceEnd = $oracleText.LastIndexOf('}', [StringComparison]::Ordinal)
Require-Condition ($classStart -ge 0 -and $namespaceEnd -gt $classStart) 'Unable to isolate the v1 geometry validator class.'
$classText = $oracleText.Substring($classStart, $namespaceEnd - $classStart).TrimEnd()
$classText = $classText.Replace('Gate14ReMEInputGeometryValidatorV1', 'Gate14ReMEInputGeometryValidatorV4_2')
$classText = $classText.Replace('private static readonly int[] GridLevels = { 64, 128, 256 };', 'private static readonly int[] GridLevels = { 64, 96, 128 };')
$classText = $classText.Replace('private static readonly int[] AgentLevels = { 8, 32, 128, 512 };', 'private static readonly int[] AgentLevels = { 32, 64, 128 };')
$classText = $classText.Replace('private static readonly int[] ChangeLevels = { 1, 9, 81, 225 };', 'private static readonly int[] ChangeLevels = { 1, 9, 25, 81 };')
$classText = $classText.Replace('Require(input.gridEdge == 256 && input.agentCount == 512 && input.changedCellCount == 225, "Stress inputs must use the frozen high corner.");', 'Require(input.gridEdge == 128 && input.agentCount == 128 && input.changedCellCount == 81, "Stress inputs must use the frozen bounded high corner.");')
Require-Condition ($classText.Contains('GridLevels = { 64, 96, 128 }') -and $classText.Contains('AgentLevels = { 32, 64, 128 }') -and $classText.Contains('ChangeLevels = { 1, 9, 25, 81 }') -and $classText.Contains('input.gridEdge == 128 && input.agentCount == 128 && input.changedCellCount == 81')) 'The versioned G/N/F policy rewrite was incomplete.'
$validatorText = @"
using System;
using System.Collections.Generic;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;

namespace DDM.Research.Gate14ReME.V4
{
$classText
}
"@
Write-Utf8NoBomExclusive -Path $targetValidator -Text ($validatorText.TrimStart() + [Environment]::NewLine)

$validatorMeta = @"
fileFormatVersion: 2
guid: a8f58d19f81349039b7b6a02c60ec12b
MonoImporter:
  externalObjects: {}
  serializedVersion: 2
  defaultReferences: []
  executionOrder: 0
  icon: {instanceID: 0}
  userData:
  assetBundleName:
  assetBundleVariant:
"@
Write-Utf8NoBomExclusive -Path $targetValidatorMeta -Text ($validatorMeta.TrimStart() + [Environment]::NewLine)

$runnerText = [IO.File]::ReadAllText($sourceRunner, [Text.Encoding]::UTF8)
$runnerText = $runnerText.Replace('using DDM.Research.Gate14ReME.V3;', "using DDM.Research.Gate14ReME.V3;`r`nusing DDM.Research.Gate14ReME.V4;")
$runnerText = $runnerText.Replace('Gate14ReMELoadQualificationRunnerV4_1', 'Gate14ReMELoadQualificationRunnerV4_2')
$runnerText = $runnerText.Replace('Gate14ReMEInputGeometryValidatorV1', 'Gate14ReMEInputGeometryValidatorV4_2')
Require-Condition ($runnerText.Contains('public static class Gate14ReMELoadQualificationRunnerV4_2') -and $runnerText.Contains('Gate14ReMEInputGeometryValidatorV4_2.Validate') -and $runnerText.Contains('Gate14ReMEInputGeometryValidatorV4_2.BuildGrid')) 'Runner v4.2 rewrite was incomplete.'
Write-Utf8NoBomExclusive -Path $targetRunner -Text $runnerText

$runnerMeta = @"
fileFormatVersion: 2
guid: ea7532949b5d4d158873ecaf21a19adf
MonoImporter:
  externalObjects: {}
  serializedVersion: 2
  defaultReferences: []
  executionOrder: 0
  icon: {instanceID: 0}
  userData:
  assetBundleName:
  assetBundleVariant:
"@
Write-Utf8NoBomExclusive -Path $targetRunnerMeta -Text ($runnerMeta.TrimStart() + [Environment]::NewLine)

$supervisorText = [IO.File]::ReadAllText($sourceSupervisor, [Text.Encoding]::UTF8)
$supervisorText = $supervisorText.Replace('DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV4_1.Run', 'DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV4_2.Run')
$supervisorText = $supervisorText.Replace('RunnerV4_1', 'RunnerV4_2')
$supervisorText = $supervisorText.Replace('manifestSchemaV4_1', 'manifestSchemaV4_2')
$supervisorText = $supervisorText.Replace('gate14re-me-qualification-current-implementation-manifest-v4.1', 'gate14re-me-qualification-current-implementation-manifest-v4.2')
$supervisorText = $supervisorText.Replace('FROZEN_V4_1_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED', 'FROZEN_V4_2_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED')
$supervisorText = $supervisorText.Replace('Implementation manifest v4.1 header', 'Implementation manifest v4.2 header')
$supervisorText = $supervisorText.Replace('Implementation manifest v4.1 readiness', 'Implementation manifest v4.2 readiness')
$supervisorText = $supervisorText.Replace('Implementation manifest v4.1 does not bind', 'Implementation manifest v4.2 does not bind')
$supervisorText = $supervisorText.Replace('gate14re-me-load-qualification-acquisition-contract-v4.1', 'gate14re-me-load-qualification-acquisition-contract-v4.2')
$supervisorText = $supervisorText.Replace('FROZEN_V4_1_ACQUISITION_ONLY_EXECUTION_UNAUTHORIZED', 'FROZEN_V4_2_ACQUISITION_ONLY_EXECUTION_UNAUTHORIZED')
$supervisorText = $supervisorText.Replace('Acquisition contract v4.1 header', 'Acquisition contract v4.2 header')
Require-Condition ($supervisorText.Contains("`$runnerMethod = 'DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV4_2.Run'") -and $supervisorText.Contains('manifestSchemaV4_2') -and $supervisorText.Contains('acquisition-contract-v4.2')) 'Supervisor v4.2 rewrite was incomplete.'
Write-Utf8NoBomExclusive -Path $targetSupervisor -Text $supervisorText

[pscustomobject]@{
    status = 'CREATED_VERSIONED_V4_2_ORACLE_COMPATIBILITY_FIX'
    validator = @{ path = [IO.Path]::GetRelativePath($root, $targetValidator).Replace('\', '/'); sha256 = Get-Sha256Lower -Path $targetValidator }
    validatorMeta = @{ path = [IO.Path]::GetRelativePath($root, $targetValidatorMeta).Replace('\', '/'); sha256 = Get-Sha256Lower -Path $targetValidatorMeta }
    runner = @{ path = [IO.Path]::GetRelativePath($root, $targetRunner).Replace('\', '/'); sha256 = Get-Sha256Lower -Path $targetRunner }
    runnerMeta = @{ path = [IO.Path]::GetRelativePath($root, $targetRunnerMeta).Replace('\', '/'); sha256 = Get-Sha256Lower -Path $targetRunnerMeta }
    supervisor = @{ path = [IO.Path]::GetRelativePath($root, $targetSupervisor).Replace('\', '/'); sha256 = Get-Sha256Lower -Path $targetSupervisor }
} | ConvertTo-Json -Depth 10
