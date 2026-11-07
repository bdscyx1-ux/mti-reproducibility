[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$source=Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlockV3.ps1';$output=Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlockV4.ps1';$receiptPath=Join-Path $ProjectPath 'Research\Gate12R_ProcessReuse_BlockRunnerV4_Derivation.v1.json'
$expected='028ac186d087929adddad27d621ce499da08a40b2038bf97e0144a1fa930288e';$actual=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actual-ne$expected){throw "Frozen failed block runner V3 changed: $actual"};foreach($p in @($output,$receiptPath)){if(Test-Path $p){throw "Create-new V4 artifact exists: $p"}}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$routes=@(
 [pscustomobject]@{old='Gate12RCanonicalInputReference.psm1';new='Gate12RCanonicalInputReferenceV2.psm1';count=1},
 [pscustomobject]@{old='Run-Gate12RProcessReuseBlockV3';new='Run-Gate12RProcessReuseBlockV4';count=1},
 [pscustomobject]@{old='[IO.File]::Replace($tmp,$summaryPath,$null)';new='$backup=$summaryPath+''.replace-backup-''+[Guid]::NewGuid().ToString(''N'');[IO.File]::Replace($tmp,$summaryPath,$backup);if(Test-Path -LiteralPath $backup){[IO.File]::Delete($backup)}';count=1},
 [pscustomobject]@{old="receiptKind='gate12r-canonical-input-reference-failure-v1'";new="receiptKind='gate12r-canonical-input-reference-failure-v2'";count=1}
)
$evidence=New-Object Collections.Generic.List[object];foreach($route in $routes){$count=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($count-ne[int]$route.count){throw "V4 block route count $count for $($route.old)"};$text=$text.Replace([string]$route.old,[string]$route.new);$evidence.Add([pscustomobject]@{from=$route.old;to=$route.new;count=$count})}
[IO.File]::WriteAllText($output,$text,(New-Object Text.UTF8Encoding($false,$true)));$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($output,[ref]$tokens,[ref]$errors)|Out-Null;if(@($errors).Count){throw "Generated V4 parser errors: $($errors.Message-join'; ')"}
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-process-reuse-block-runner-v4-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceRelativePath='Research/Run-Gate12RProcessReuseBlockV3.ps1';sourceSha256=$actual;outputRelativePath='Research/Run-Gate12RProcessReuseBlockV4.ps1';outputSha256=(Get-FileHash $output -Algorithm SHA256).Hash.ToLowerInvariant();moduleV2Sha256=(Get-FileHash (Join-Path $ProjectPath 'Research\Gate12RCanonicalInputReferenceV2.psm1') -Algorithm SHA256).Hash.ToLowerInvariant();routes=$evidence.ToArray();thresholdsChanged=$false;experimentalSemanticsChanged=$false};$json=($receipt|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($receiptPath,$json,(New-Object Text.UTF8Encoding($false,$true)));$receipt|ConvertTo-Json -Depth 20
