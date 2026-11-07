[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$source=Join-Path $ProjectPath 'Research\Gate12RCanonicalInputReference.psm1';$output=Join-Path $ProjectPath 'Research\Gate12RCanonicalInputReferenceV2.psm1';$receiptPath=Join-Path $ProjectPath 'Research\Gate12R_CanonicalInputReferenceV2_Derivation.v1.json'
$expected='00fecf57702d761ed23fc3db25d64497689bbd86a472271b995eb56014bcbe50';$actual=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actual-ne$expected){throw "Frozen failed V1 module changed: $actual"};foreach($p in @($output,$receiptPath)){if(Test-Path $p){throw "Create-new V2 artifact exists: $p"}}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$anchor="function Invoke-Gate12RCanonicalInputExternalization {"
$helper=@'
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
'@
$anchorCount=$text.Split([string[]]@($anchor),[StringSplitOptions]::None).Count-1;if($anchorCount-ne1){throw "Helper anchor count $anchorCount"};$text=$text.Replace($anchor,$helper)
$routes=@(
 [pscustomobject]@{old='[System.IO.File]::Replace([string]$record.stagedManifest, [string]$record.targetManifest, $null)';new='Invoke-Gate12RCanonicalAtomicReplace -Source ([string]$record.stagedManifest) -Destination ([string]$record.targetManifest)'},
 [pscustomobject]@{old='[System.IO.File]::Replace([string]$record.stagedSummary, [string]$record.targetSummary, $null)';new='Invoke-Gate12RCanonicalAtomicReplace -Source ([string]$record.stagedSummary) -Destination ([string]$record.targetSummary)'},
 [pscustomobject]@{old='[System.IO.File]::Replace($stagedBlockManifest, $blockManifestPath, $null)';new='Invoke-Gate12RCanonicalAtomicReplace -Source $stagedBlockManifest -Destination $blockManifestPath'}
)
$evidence=New-Object Collections.Generic.List[object];foreach($route in $routes){$count=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($count-ne1){throw "Replacement count $count for $($route.old)"};$text=$text.Replace([string]$route.old,[string]$route.new);$evidence.Add([pscustomobject]@{from=$route.old;to=$route.new;count=$count})}
[IO.File]::WriteAllText($output,$text,(New-Object Text.UTF8Encoding($false,$true)))
$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($output,[ref]$tokens,[ref]$errors)|Out-Null;if(@($errors).Count){throw "Generated V2 module parser errors: $($errors.Message-join'; ')"}
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-canonical-reference-module-v2-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Gate12RCanonicalInputReference.psm1';sourceSha256=$actual;outputRelativePath='Research/Gate12RCanonicalInputReferenceV2.psm1';outputSha256=(Get-FileHash $output -Algorithm SHA256).Hash.ToLowerInvariant();confirmedDefect='Windows PowerShell 5.1 File.Replace null backup-path overload binding';repair='explicit unique backup path with recovery and cleanup';routes=$evidence.ToArray();thresholdsChanged=$false;experimentalSemanticsChanged=$false};$json=($receipt|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,(New-Object Text.UTF8Encoding($false,$true)));$receipt|ConvertTo-Json -Depth 20
