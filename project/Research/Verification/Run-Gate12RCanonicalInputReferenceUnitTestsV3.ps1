[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath,[switch]$BindingSmokeOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'V3 canonical-reference tests require an absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RCanonicalInputReferenceUnitTestsV3|$ProjectPath");exit 0}
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RCanonicalInputReferenceUnitTestsV1.ps1';$expected=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$routes=@(
 [pscustomobject]@{old="'Research/Verification/Gate12R_CanonicalInputReference/v1'";new="'Research/Verification/Gate12R_CanonicalInputReference/v3'";count=1},
 [pscustomobject]@{old="'Research\Gate12RCanonicalInputReference.psm1'";new="'Research\Gate12RCanonicalInputReferenceV2.psm1'";count=1},
 [pscustomobject]@{old="summaryKind='gate12r-canonical-input-upstream-reference-unit-tests-v1'";new="summaryKind='gate12r-canonical-input-upstream-reference-unit-tests-v3-explicit-backup-atomic-replace'";count=1},
 [pscustomobject]@{old="receiptKind='gate12r-canonical-reference-unit-failure-v1'";new="receiptKind='gate12r-canonical-reference-unit-failure-v3'";count=1}
)
$evidence=New-Object Collections.Generic.List[object];foreach($route in $routes){$count=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($count-ne[int]$route.count){throw "V3 unit route count $count for $($route.old)"};$text=$text.Replace([string]$route.old,[string]$route.new);$evidence.Add([pscustomobject]@{from=$route.old;to=$route.new;count=$count})}
$derivedRoot=Join-Path $ProjectPath 'Research\Verification\Gate12R_CanonicalReference_UnitDerived\v3';if(Test-Path $derivedRoot){throw "Create-new V3 unit derived root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derived=Join-Path $derivedRoot 'Run-Gate12RCanonicalInputReferenceUnitTestsV3.derived.ps1';[IO.File]::WriteAllText($derived,$text,(New-Object Text.UTF8Encoding($false,$true)));$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-canonical-reference-unit-v3-route-receipt';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$expected;derivedSha256=(Get-FileHash $derived -Algorithm SHA256).Hash.ToLowerInvariant();routes=$evidence.ToArray();failedV1RootPreserved=$true;failedV2WrapperProducedNoTestRoot=$true};$json=($receipt|ConvertTo-Json -Depth 15).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json,(New-Object Text.UTF8Encoding($false,$true)))
$ps='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';&$ps -NoProfile -ExecutionPolicy Bypass -File $derived -ProjectPath $ProjectPath;exit $LASTEXITCODE
