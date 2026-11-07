[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop'
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$root=Join-Path $ProjectPath 'Research\Verification\Gate10R_Attempt4_Preflight\v1'
$officialRoot=Join-Path $ProjectPath 'Research\Verification\Gate10R_ProcessReuse_5pct\v4'
if(Test-Path -LiteralPath $officialRoot){throw 'Official v4 root exists; failure closure refuses to continue.'}
if (@(Get-Process Unity -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Unity is running; failure closure refuses to continue.' }
function Get-LowerSha([string]$Path){(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}
function Write-AtomicJson([string]$Path,$Value){if(Test-Path -LiteralPath $Path){throw "Refusing overwrite: $Path"};$json=($Value|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n");if(-not$json.EndsWith("`n",[StringComparison]::Ordinal)){$json+="`n"};$tmp=$Path+'.tmp-'+[guid]::NewGuid().ToString('N');$encoding=New-Object Text.UTF8Encoding($false,$true);[IO.File]::WriteAllText($tmp,$json,$encoding);[IO.File]::Move($tmp,$Path)}
$stdout=Join-Path $root 'MechanicalTransform.validation-only.stdout.log';$stderr=Join-Path $root 'MechanicalTransform.validation-only.stderr.log'
if ((Get-LowerSha $stdout) -ne '80360e7d76267df251f8675d24a3f1c54592e067b27a6753c3c3fcbdec86bd62' -or (Get-LowerSha $stderr) -ne 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') { throw 'Partial preflight evidence changed before closure.' }
$manifestPath=Join-Path $root 'Gate10R_Attempt4_OutsideRoot_Preflight_Partial_Manifest.v1.json'
$receiptPath=Join-Path $root 'Gate10R_Attempt4_OutsideRoot_Preflight_Failure_Receipt.v1.json'
$checkpointPath=Join-Path $root 'gate10r-attempt4-outside-root-preflight-checkpoint.v1.json'
$manifest=[ordered]@{schemaVersion=1;manifestId='gate10r-attempt4-outside-root-preflight-v1-partial';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-EXPECTED-NEGATIVE-STDERR-CAPTURE';artifactCount=2;rawBytes=4186;artifacts=@([ordered]@{relativePath='MechanicalTransform.validation-only.stderr.log';bytes=0;sha256='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'},[ordered]@{relativePath='MechanicalTransform.validation-only.stdout.log';bytes=4186;sha256='80360e7d76267df251f8675d24a3f1c54592e067b27a6753c3c3fcbdec86bd62'});officialV4RootCreated=$false;unityStarted=$false}
Write-AtomicJson $manifestPath $manifest
$receipt=[ordered]@{schemaVersion=1;receiptId='gate10r-attempt4-outside-root-preflight-v1-failure';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-ATOMICALLY-CLOSED-RETRY-AUTHORIZED';attempt=4;stage='outside-v4-root-no-unity-preflight';failureClass='EXPECTED-NEGATIVE-CHILD-STDERR-PROMOTED-BY-PARENT-ERRORACTIONPREFERENCE';failedAtCase='output-isolation-reject-original-summary';diagnosis='The harness correctly rejected the frozen original summary. The parent Windows PowerShell 5.1 preflight promoted the expected child stderr NativeCommandError to a terminating error before recording the nonzero exit code.';repairBoundary='Only capture expected-negative child stdout/stderr through Start-Process redirection and evaluate ExitCode; harness and all research semantics remain frozen.';partialManifestSha256=Get-LowerSha $manifestPath;officialV4RootCreated=$false;unityStarted=$false;projectLockPresent=$false;automaticRetryAuthorized=$true;resumeThisRootAllowed=$false;overwriteAllowed=$false;nextPreflightRoot='Research/Verification/Gate10R_Attempt4_Preflight/v2';gate11RAuthorized=$false;gate12RAuthorized=$false;gate13RAuthorized=$false}
Write-AtomicJson $receiptPath $receipt
$checkpoint=[ordered]@{schemaVersion=1;checkpointKind='gate10r-attempt4-outside-root-preflight-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');status='GATE10R-ATTEMPT4-OUTSIDE-PREFLIGHT-V1-FAILED-CLOSED-RETRY-V2-AUTHORIZED';failureReceiptSha256=Get-LowerSha $receiptPath;partialManifestSha256=Get-LowerSha $manifestPath;officialExecutionCount=0;officialV4RootCreated=$false;unityStarted=$false;resumeAllowed=$false;gate11RAuthorized=$false;gate12RAuthorized=$false;gate13RAuthorized=$false}
Write-AtomicJson $checkpointPath $checkpoint
$checkpoint|ConvertTo-Json -Depth 10
