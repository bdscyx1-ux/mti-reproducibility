[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$probeId = [guid]::NewGuid().ToString('N')
$outputPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "gate12-exit-probe-$probeId.out")
$errorPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "gate12-exit-probe-$probeId.err")

try {
    $powershellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
    $process = Start-Process -FilePath $powershellPath -ArgumentList '-NoProfile -Command "exit 0"' -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru
    while (-not $process.WaitForExit(1000)) { }

    $exitCodeProperty = $process.PSObject.Properties['ExitCode']
    $reflectionValue = $null
    $reflectionError = $null
    try {
        $reflectionValue = $process.GetType().GetProperty('ExitCode').GetValue($process, $null)
    }
    catch {
        $reflectionError = $_.Exception.Message
    }

    $before = [ordered]@{
        hasExited = $process.HasExited
        exitCode = $process.ExitCode
        exitCodeIsNull = ($null -eq $process.ExitCode)
        processType = $process.GetType().FullName
        psPropertyMemberType = [string]$exitCodeProperty.MemberType
        psPropertyTypeNameOfValue = [string]$exitCodeProperty.TypeNameOfValue
        reflectionExitCode = $reflectionValue
        reflectionError = $reflectionError
    }

    $process.WaitForExit()
    $after = [ordered]@{
        hasExited = $process.HasExited
        exitCode = $process.ExitCode
        exitCodeIsNull = ($null -eq $process.ExitCode)
    }

    $waitOutputPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "gate12-exit-probe-wait-$probeId.out")
    $waitErrorPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "gate12-exit-probe-wait-$probeId.err")
    try {
        $waitProcess = Start-Process -FilePath $powershellPath -ArgumentList '-NoProfile -Command "exit 0"' -WindowStyle Hidden -RedirectStandardOutput $waitOutputPath -RedirectStandardError $waitErrorPath -Wait -PassThru
        $waitCase = [ordered]@{
            hasExited = $waitProcess.HasExited
            exitCode = $waitProcess.ExitCode
            exitCodeIsNull = ($null -eq $waitProcess.ExitCode)
        }
    }
    finally {
        if (Test-Path -LiteralPath $waitOutputPath) { Remove-Item -LiteralPath $waitOutputPath -Force }
        if (Test-Path -LiteralPath $waitErrorPath) { Remove-Item -LiteralPath $waitErrorPath -Force }
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershellPath
    $startInfo.Arguments = '-NoProfile -Command "exit 0"'
    $startInfo.WorkingDirectory = (Get-Location).Path
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $ownedProcess = New-Object System.Diagnostics.Process
    $ownedProcess.StartInfo = $startInfo
    if (-not $ownedProcess.Start()) { throw 'Owned System.Diagnostics.Process failed to start.' }
    $ownedStdoutTask = $ownedProcess.StandardOutput.ReadToEndAsync()
    $ownedStderrTask = $ownedProcess.StandardError.ReadToEndAsync()
    while (-not $ownedProcess.WaitForExit(1000)) { }
    $ownedProcess.WaitForExit()
    $ownedStdoutTask.Wait()
    $ownedStderrTask.Wait()
    $ownedCase = [ordered]@{
        hasExited = $ownedProcess.HasExited
        exitCode = $ownedProcess.ExitCode
        exitCodeIsNull = ($null -eq $ownedProcess.ExitCode)
        stdoutCharacters = $ownedStdoutTask.Result.Length
        stderrCharacters = $ownedStderrTask.Result.Length
    }
    $ownedProcess.Dispose()

    [ordered]@{
        schemaVersion = 1
        windowsPowerShellVersion = $PSVersionTable.PSVersion.ToString()
        beforeParameterlessWait = $before
        afterParameterlessWait = $after
        startProcessWaitCase = $waitCase
        ownedDiagnosticsProcessCase = $ownedCase
    } | ConvertTo-Json -Depth 5
}
finally {
    if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force }
    if (Test-Path -LiteralPath $errorPath) { Remove-Item -LiteralPath $errorPath -Force }
}
