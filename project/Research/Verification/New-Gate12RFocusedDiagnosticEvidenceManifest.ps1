[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'ProjectPath must be an explicit absolute path.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
$root=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct\reset-diagnostic-v1'))
$output=Join-Path $root 'evidence-manifest.json';$summaryPath=Join-Path $root 'focused-diagnostic-summary.json'
if(-not(Test-Path -LiteralPath $root -PathType Container)){throw 'Focused diagnostic root is missing.'};if(Test-Path -LiteralPath $output){throw "Create-new evidence manifest exists: $output"}
$summary=Read-Gate12RJson $summaryPath
if($summary.passed-ne$true-or[int]$summary.freshProcessRepeatCount-ne3-or[int]$summary.distinctProcessIdCount-ne3-or$summary.memoryRulePassed-ne$true-or[long]$summary.maximumBlockRetainedManagedGrowthBytes-gt134217728L-or[int]$summary.structuralComparisonCount-ne10-or$summary.thresholdsChanged-ne$false){throw 'Focused diagnostic summary does not satisfy the frozen repair gate.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v2')){throw 'Pilot v2 root must remain absent.'};if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')){throw 'Gate13R formal root must remain absent.'}
$files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force|Sort-Object FullName);$rows=New-Object Collections.Generic.List[object]
foreach($file in $files){$rows.Add([pscustomobject][ordered]@{relativePath=Get-Gate12RProjectRelativePath $ProjectPath $file.FullName;rawBytes=[long]$file.Length;sha256=Get-Gate12RLowerSha256 $file.FullName})}
$manifest=[ordered]@{schemaVersion=1;manifestKind='gate12r-planner-reset-focused-diagnostic-evidence-manifest-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');rootRelativePath=Get-Gate12RProjectRelativePath $ProjectPath $root;fileCount=$rows.Count;rawBytes=[long](($files|Measure-Object Length -Sum).Sum);files=$rows.ToArray();summarySha256=Get-Gate12RLowerSha256 $summaryPath;freshProcessRepeatCount=3;maximumBlockRetainedManagedGrowthBytes=[long]$summary.maximumBlockRetainedManagedGrowthBytes;frozenManagedLimitBytes=134217728L;structuralComparisonCount=10;thresholdsChanged=$false;formalCampaign=$false;excludedFromFormalAnalysis=$true;pilotV2RootCreated=$false;gate13rRootCreated=$false;passed=$true}
Write-Gate12RAtomicUtf8NoBomJson -Path $output -Value $manifest -Depth 30
Write-Host "Gate12R focused diagnostic evidence manifest created: $output" -ForegroundColor Green

