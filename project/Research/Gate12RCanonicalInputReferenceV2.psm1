Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Gate12RCanonicalStorageKind = 'frozen-gate11r-upstream-reference-v1'
$script:Gate12RBundleManifestSha256 = '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc'
$script:Gate12RUtf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Get-Gate12RCanonicalLowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Gate12RCanonicalJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-Gate12RCanonicalJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 40
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = ($Value | ConvertTo-Json -Depth $Depth).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $json, $script:Gate12RUtf8)
}

function Set-Gate12RCanonicalProperty {
    param([Parameter(Mandatory = $true)]$Object, [Parameter(Mandatory = $true)][string]$Name, $Value)
    if ($null -ne $Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-Gate12RCanonicalProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)][string]$FullPath)
    $project = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
    $full = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $full.StartsWith($project + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the project: $full"
    }
    return $full.Substring($project.Length + 1).Replace('\', '/')
}

function Invoke-Gate12RCanonicalAtomicReplace {
    param([Parameter(Mandatory = $true)][string]$Source, [Parameter(Mandatory = $true)][string]$Destination)
    $backup = $Destination + '.replace-backup-' + [Guid]::NewGuid().ToString('N')
    try {
        [System.IO.File]::Replace($Source, $Destination, $backup)
        if (Test-Path -LiteralPath $backup) { [System.IO.File]::Delete($backup) }
    }
    catch {
        if ((-not (Test-Path -LiteralPath $Destination)) -and (Test-Path -LiteralPath $backup)) {
            [System.IO.File]::Move($backup, $Destination)
        }
        throw
    }
}

function Invoke-Gate12RCanonicalInputExternalization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$BlockPlanPath
    )

    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    $BlockPlanPath = [System.IO.Path]::GetFullPath($BlockPlanPath)
    $scenarioRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalScenarios\Gate11R_5pct\v1\Scenarios'))
    $bundleManifest = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalScenarios\Gate11R_5pct\v1\bundle-manifest.json'))
    if (-not (Test-Path -LiteralPath $bundleManifest -PathType Leaf) -or
        (Get-Gate12RCanonicalLowerSha256 $bundleManifest) -ne $script:Gate12RBundleManifestSha256) {
        throw 'Frozen Gate 11R bundle-manifest SHA-256 mismatch.'
    }
    if (-not (Test-Path -LiteralPath $BlockPlanPath -PathType Leaf)) { throw 'Block plan is missing.' }
    $plan = Read-Gate12RCanonicalJson $BlockPlanPath
    if ([int]$plan.schemaVersion -ne 2 -or $plan.formalCampaign -ne $false) { throw 'Unauthorized block plan for canonical externalization.' }
    if ([string]$plan.analysisRole -eq 'excluded-negative-fail-closed-verification') { throw 'Negative fixtures must not be externalized.' }

    $blockManifestPath = Join-Path $OutputDirectory 'block-manifest.json'
    $checkpointPath = Join-Path $OutputDirectory 'block-checkpoint.json'
    if (-not (Test-Path -LiteralPath $blockManifestPath -PathType Leaf)) { throw 'Completed block manifest is missing.' }
    if (-not (Test-Path -LiteralPath $checkpointPath -PathType Leaf)) { throw 'Completed block checkpoint is missing.' }
    $blockManifest = Read-Gate12RCanonicalJson $blockManifestPath
    $checkpoint = Read-Gate12RCanonicalJson $checkpointPath
    if ($blockManifest.completed -ne $true -or $blockManifest.formalCampaign -ne $false -or
        $blockManifest.hardMemoryRulesPassed -ne $true -or [string]$checkpoint.status -ne 'block-completed') {
        throw 'Only a complete, non-formal, memory-valid block may be externalized.'
    }
    if ([string]$blockManifest.blockId -ne [string]$plan.blockId) { throw 'Block identity mismatch.' }

    $stageRoot = Join-Path $OutputDirectory ('.canonical-reference-stage-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stageRoot | Out-Null
    $records = New-Object System.Collections.Generic.List[object]
    $canonicalFiles = New-Object System.Collections.Generic.List[string]
    $logicalBytesRemoved = 0L
    $originalBlockManifestSha256 = Get-Gate12RCanonicalLowerSha256 $blockManifestPath

    try {
        for ($index = 0; $index -lt @($blockManifest.samples).Count; $index++) {
            $sampleRecord = $blockManifest.samples[$index]
            $manifestPath = Join-Path $OutputDirectory ([string]$sampleRecord.manifestRelativePath).Replace('/', '\')
            $summaryPath = Join-Path $OutputDirectory ([string]$sampleRecord.summaryRelativePath).Replace('/', '\')
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
                -not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
                throw "Sample evidence is missing at index $index."
            }
            $manifest = Read-Gate12RCanonicalJson $manifestPath
            $summary = Read-Gate12RCanonicalJson $summaryPath
            if ($manifest.completed -ne $true -or $manifest.formalCampaign -ne $false -or
                [string]$manifest.canonicalScenarioFile -ne 'scenario.canonical.json') {
                throw "Sample $index is incomplete, formal, or already externalized."
            }
            $sampleDirectory = Split-Path -Parent $manifestPath
            $localCanonical = [System.IO.Path]::GetFullPath((Join-Path $sampleDirectory 'scenario.canonical.json'))
            $source = [string]$manifest.scenarioSourcePath
            if (-not [System.IO.Path]::IsPathRooted($source)) { $source = Join-Path $ProjectPath $source }
            $source = [System.IO.Path]::GetFullPath($source)
            if (-not $source.StartsWith($scenarioRoot.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Canonical source is outside the frozen Gate 11R scenario root: $source"
            }
            if (-not (Test-Path -LiteralPath $localCanonical -PathType Leaf) -or
                -not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Canonical local/source file is missing at index $index."
            }
            $localInfo = Get-Item -LiteralPath $localCanonical
            $sourceInfo = Get-Item -LiteralPath $source
            $localSha = Get-Gate12RCanonicalLowerSha256 $localCanonical
            $sourceSha = Get-Gate12RCanonicalLowerSha256 $source
            if ($localSha -ne [string]$manifest.canonicalScenarioSha256 -or
                $sourceSha -ne [string]$manifest.scenarioSourceSha256 -or
                $localSha -ne $sourceSha -or
                [long]$localInfo.Length -ne [long]$sourceInfo.Length) {
                throw "Canonical byte-identity proof failed at index $index."
            }

            $originalManifestSha = Get-Gate12RCanonicalLowerSha256 $manifestPath
            $originalSummarySha = Get-Gate12RCanonicalLowerSha256 $summaryPath
            if ($originalManifestSha -ne [string]$sampleRecord.manifestSha256 -or
                $originalSummarySha -ne [string]$sampleRecord.summarySha256) {
                throw "Original sample hash chain failed at index $index."
            }

            $sourceRelative = Get-Gate12RCanonicalProjectRelativePath -ProjectPath $ProjectPath -FullPath $source
            $manifest.schemaVersion = 5
            $manifest.canonicalScenarioFile = $sourceRelative
            Set-Gate12RCanonicalProperty $manifest 'canonicalScenarioStorageKind' $script:Gate12RCanonicalStorageKind
            Set-Gate12RCanonicalProperty $manifest 'canonicalScenarioProjectRelativePath' $sourceRelative
            Set-Gate12RCanonicalProperty $manifest 'canonicalScenarioOriginalLocalFile' 'scenario.canonical.json'
            Set-Gate12RCanonicalProperty $manifest 'canonicalScenarioLocalCopyPresent' $false
            Set-Gate12RCanonicalProperty $manifest 'canonicalScenarioResolvedRawBytes' ([long]$sourceInfo.Length)
            Set-Gate12RCanonicalProperty $manifest 'canonicalScenarioReferenceVerified' $true

            $stagedManifest = Join-Path $stageRoot ('manifest-{0:D2}.json' -f ($index + 1))
            Write-Gate12RCanonicalJson -Path $stagedManifest -Value $manifest -Depth 40
            $updatedManifestSha = Get-Gate12RCanonicalLowerSha256 $stagedManifest
            $summary.manifestSha256 = $updatedManifestSha
            Set-Gate12RCanonicalProperty $summary 'canonicalScenarioStorageKind' $script:Gate12RCanonicalStorageKind
            $stagedSummary = Join-Path $stageRoot ('summary-{0:D2}.json' -f ($index + 1))
            Write-Gate12RCanonicalJson -Path $stagedSummary -Value $summary -Depth 20
            $updatedSummarySha = Get-Gate12RCanonicalLowerSha256 $stagedSummary

            $sampleRecord.manifestSha256 = $updatedManifestSha
            $sampleRecord.summarySha256 = $updatedSummarySha
            $logicalBytesRemoved += [long]$localInfo.Length
            $canonicalFiles.Add($localCanonical)
            $records.Add([pscustomobject][ordered]@{
                position = [int]$sampleRecord.position
                algorithmId = [string]$sampleRecord.algorithmId
                runId = [string]$sampleRecord.runId
                localCanonicalRelativePath = Get-Gate12RCanonicalProjectRelativePath $ProjectPath $localCanonical
                frozenSourceRelativePath = $sourceRelative
                canonicalSha256 = $sourceSha
                canonicalRawBytes = [long]$sourceInfo.Length
                originalManifestSha256 = $originalManifestSha
                updatedManifestSha256 = $updatedManifestSha
                originalSummarySha256 = $originalSummarySha
                updatedSummarySha256 = $updatedSummarySha
                stagedManifest = $stagedManifest
                stagedSummary = $stagedSummary
                targetManifest = $manifestPath
                targetSummary = $summaryPath
            })
        }

        Set-Gate12RCanonicalProperty $blockManifest 'canonicalScenarioStorageKind' $script:Gate12RCanonicalStorageKind
        Set-Gate12RCanonicalProperty $blockManifest 'canonicalScenarioLocalCopiesRemoved' $true
        Set-Gate12RCanonicalProperty $blockManifest 'canonicalScenarioLogicalRawBytesRemoved' ([long]$logicalBytesRemoved)
        Set-Gate12RCanonicalProperty $blockManifest 'canonicalScenarioReferenceCount' ([int]$records.Count)
        Set-Gate12RCanonicalProperty $blockManifest 'canonicalScenarioReferenceValidationPassed' $true
        $stagedBlockManifest = Join-Path $stageRoot 'block-manifest.json'
        Write-Gate12RCanonicalJson -Path $stagedBlockManifest -Value $blockManifest -Depth 50

        foreach ($record in $records) {
            Invoke-Gate12RCanonicalAtomicReplace -Source ([string]$record.stagedManifest) -Destination ([string]$record.targetManifest)
            Invoke-Gate12RCanonicalAtomicReplace -Source ([string]$record.stagedSummary) -Destination ([string]$record.targetSummary)
        }
        Invoke-Gate12RCanonicalAtomicReplace -Source $stagedBlockManifest -Destination $blockManifestPath
        foreach ($canonicalFile in $canonicalFiles) { [System.IO.File]::Delete($canonicalFile) }

        $receiptRecords = @($records | ForEach-Object {
            [pscustomobject][ordered]@{
                position = $_.position; algorithmId = $_.algorithmId; runId = $_.runId
                removedLocalCanonicalRelativePath = $_.localCanonicalRelativePath
                frozenSourceRelativePath = $_.frozenSourceRelativePath
                canonicalSha256 = $_.canonicalSha256; canonicalRawBytes = $_.canonicalRawBytes
                originalManifestSha256 = $_.originalManifestSha256; updatedManifestSha256 = $_.updatedManifestSha256
                originalSummarySha256 = $_.originalSummarySha256; updatedSummarySha256 = $_.updatedSummarySha256
            }
        })
        $receipt = [pscustomobject][ordered]@{
            schemaVersion = 1
            receiptKind = 'gate12r-canonical-input-upstream-reference-receipt-v1'
            completedAtUtc = [DateTime]::UtcNow.ToString('o')
            amendmentId = 'gate12r-canonical-input-upstream-reference-v1'
            storageKind = $script:Gate12RCanonicalStorageKind
            blockId = [string]$blockManifest.blockId
            blockPlanSha256 = Get-Gate12RCanonicalLowerSha256 $BlockPlanPath
            gate11BundleManifestSha256 = $script:Gate12RBundleManifestSha256
            originalBlockManifestSha256 = $originalBlockManifestSha256
            updatedBlockManifestSha256 = Get-Gate12RCanonicalLowerSha256 $blockManifestPath
            referenceCount = [int]$records.Count
            removedLocalCanonicalRawBytes = [long]$logicalBytesRemoved
            records = $receiptRecords
            operationsChanged = $false
            workloadResultChanged = $false
            telemetryChanged = $false
            timingChanged = $false
            resetChanged = $false
            formalCampaign = $false
            passed = $true
        }
        $receiptPath = Join-Path $OutputDirectory 'canonical-input-reference-receipt.json'
        if (Test-Path -LiteralPath $receiptPath) { throw 'Create-new canonical reference receipt already exists.' }
        Write-Gate12RCanonicalJson -Path $receiptPath -Value $receipt -Depth 30
        return [pscustomobject][ordered]@{
            passed = $true
            receiptPath = $receiptPath
            receiptSha256 = Get-Gate12RCanonicalLowerSha256 $receiptPath
            blockManifestSha256 = Get-Gate12RCanonicalLowerSha256 $blockManifestPath
            referenceCount = [int]$records.Count
            removedLocalCanonicalRawBytes = [long]$logicalBytesRemoved
            storageKind = $script:Gate12RCanonicalStorageKind
        }
    }
    finally {
        if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
    }
}

Export-ModuleMember -Function 'Invoke-Gate12RCanonicalInputExternalization'
