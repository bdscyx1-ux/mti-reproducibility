[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop'
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$relativePaths=@(
    'Research\Gate13RPR2MemoryPolicyPilotV1.psm1',
    'Research\Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1',
    'Research\Run-Gate13RPR2MemoryPolicyPilotV1.ps1',
    'Research\Start-Gate13RPR2MemoryPolicyPilotV1.ps1',
    'Research\Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV1.ps1',
    'Research\Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV1.ps1',
    'Research\Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV1.ps1'
)
$results=New-Object Collections.Generic.List[object]
foreach($relative in $relativePaths){
    $path=Join-Path $ProjectPath $relative;$tokens=$null;$errors=$null
    [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)|Out-Null
    $results.Add([pscustomobject][ordered]@{relativePath=$relative;errorCount=@($errors).Count;errors=@($errors|ForEach-Object{$_.Message});passed=@($errors).Count -eq 0})
}
$failed=@($results|Where-Object{-not $_.passed})
[pscustomobject][ordered]@{runtime=$PSVersionTable.PSVersion.ToString();fileCount=$results.Count;passedFileCount=$results.Count-$failed.Count;results=$results.ToArray();passed=$failed.Count -eq 0}|ConvertTo-Json -Depth 10
if($failed.Count){exit 1}
