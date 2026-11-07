[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$PythonPath = 'C:\Users\bdscy\AppData\Local\Python\pythoncore-3.14-64\python.exe',
    [switch]$WriteSnapshot,
    [switch]$RenderReport
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$PythonPath = [IO.Path]::GetFullPath($PythonPath)
$monitor = Join-Path $ProjectPath 'Research\Gate13RPR2Attempt4MonitoringV1.py'
foreach ($required in @($ProjectPath,$PythonPath,$monitor)) { if (-not (Test-Path -LiteralPath $required)) { throw "Required path does not exist: $required" } }
$arguments = @($monitor,'--project-root',$ProjectPath)
if ($WriteSnapshot) { $arguments += '--write-snapshot' }
if ($RenderReport) { $arguments += '--render-report' }
& $PythonPath @arguments
if ($LASTEXITCODE -ne 0) { throw "Gate13R-PR2 attempt-4 monitor exited with code $LASTEXITCODE." }
