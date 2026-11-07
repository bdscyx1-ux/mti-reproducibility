[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ProjectPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$passport = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Run_Passport.md'
$ledger = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Run_Passport_run_ledger.yaml'
$promptPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Campaign_Next_Authorization_Prompt.md'
$evidenceRoot = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Prelaunch\v1\Ledger'
$entryPath = Join-Path $evidenceRoot 'initial-authorization-entry.json'
if (Test-Path -LiteralPath $ledger) { throw "Formal execution ledger already exists: $ledger" }
if (Test-Path -LiteralPath $entryPath) { throw "Create-new ledger entry already exists: $entryPath" }
$prompt = [IO.File]::ReadAllText($promptPath, [Text.Encoding]::UTF8)
$match = [regex]::Match($prompt, '(?s)```text\s*(.*?)\s*```')
if (-not $match.Success) { throw 'Could not recover the exact frozen authorization text.' }
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$entry = [ordered]@{ kind = 'initial_instructions'; user_words = $match.Groups[1].Value }
[IO.File]::WriteAllText($entryPath, (($entry | ConvertTo-Json -Depth 5).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"), (New-Object Text.UTF8Encoding($false, $true)))
$python = 'C:\Users\bdscy\AppData\Local\Python\pythoncore-3.14-64\python.exe'
$runLedger = 'C:\Users\bdscy\.codex\plugins\cache\ars-codex\ars-codex\3.23.0\skills\academic-research-suite\ars\scripts\run_ledger.py'
& $python $runLedger append --passport-path $passport --entry-file $entryPath
if ($LASTEXITCODE -ne 0) { throw "run_ledger append failed with exit $LASTEXITCODE" }
Write-Output 'FORMAL-EXECUTION-LEDGER-INITIALIZED'
