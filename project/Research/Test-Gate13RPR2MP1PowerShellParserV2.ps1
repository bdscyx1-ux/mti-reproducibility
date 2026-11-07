[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or -not[IO.Path]::IsPathRooted($ProjectPath)){throw 'An explicit absolute ProjectPath is required.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output "BINDING-SMOKE-PASSED|Test-Gate13RPR2MP1PowerShellParserV2|$ProjectPath";exit 0}
$relativePaths=@(
 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1',
 'Research\Test-Gate13RPR2MP1V2CheckpointStateMachine.ps1',
 'Research\Test-Gate13RPR2MP1V2ZeroBlockFailure.ps1',
 'Research\Run-Gate13RPR2MemoryPolicyPilotBlockV2.ps1',
 'Research\Run-Gate13RPR2MemoryPolicyPilotV2.ps1',
 'Research\Start-Gate13RPR2MemoryPolicyPilotV2.ps1',
 'Research\Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV2.ps1',
 'Research\Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV2.ps1',
 'Research\Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV2.ps1',
 'Research\Finalize-Gate13RPR2MP1PrePilotV2.ps1',
 'Research\Invoke-Gate13RPR2MP1V2PrePilotValidation.ps1'
)
$results=New-Object Collections.Generic.List[object]
foreach($relative in $relativePaths){
 $path=Join-Path $ProjectPath $relative;$tokens=$null;$errors=$null
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){$results.Add([pscustomobject][ordered]@{relativePath=$relative;errorCount=1;errors=@('missing-file');passed=$false});continue}
 [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)|Out-Null
 $results.Add([pscustomobject][ordered]@{relativePath=$relative;errorCount=@($errors).Count;errors=@($errors|ForEach-Object{$_.Message});passed=@($errors).Count-eq0})
}
$failed=@($results|Where-Object{-not$_.passed})
[pscustomobject][ordered]@{runtime=$PSVersionTable.PSVersion.ToString();fileCount=$results.Count;passedFileCount=$results.Count-$failed.Count;results=$results.ToArray();passed=$failed.Count-eq0}|ConvertTo-Json -Depth 10
if($failed.Count){exit 1}
