[CmdletBinding()]
param(
    [ValidateSet('Start', 'Run', 'Stop', 'Status')]
    [string]$Action = 'Start',
    [ValidateRange(1, 65535)]
    [int]$MainPort = 18080,
    [ValidateRange(1, 65535)]
    [int]$CompanionPort = 18081,
    [ValidateRange(1024, 65535)]
    [int]$DevicePort = 18765,
    [ValidateRange(250, 5000)]
    [int]$PollMilliseconds = 500
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$mutexName = 'Local\HITCONCardPrinterPhoneScannerHelper'
$stopEventName = 'Local\HITCONCardPrinterPhoneScannerHelperStop'
$readyEventName = 'Local\HITCONCardPrinterPhoneScannerHelperReady'
$script:AdbPath = $null
$script:OwnedReverseSerial = $null
$script:OwnedReverseTargetPort = $null
$script:StopEvent = $null

function New-NamedManualResetEvent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$InitialState
    )

    $createdNew = $false
    return [System.Threading.EventWaitHandle]::new(
        $InitialState,
        [System.Threading.EventResetMode]::ManualReset,
        $Name,
        [ref]$createdNew
    )
}

function Open-NamedEvent {
    param([Parameter(Mandatory = $true)][string]$Name)

    try {
        return [System.Threading.EventWaitHandle]::OpenExisting($Name)
    } catch [System.Threading.WaitHandleCannotBeOpenedException] {
        return $null
    }
}

function Test-HelperReady {
    $readyEvent = Open-NamedEvent -Name $readyEventName
    if ($null -eq $readyEvent) {
        return $false
    }
    try {
        return $readyEvent.WaitOne(0)
    } finally {
        $readyEvent.Dispose()
    }
}

function Invoke-AdbCapture {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [ValidateRange(250, 30000)][int]$TimeoutMilliseconds = 5000
    )

    foreach ($argument in $Arguments) {
        if ($null -eq $argument -or [string]$argument -match '[\s"]') {
            throw 'Unsafe ADB argument.'
        }
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:AdbPath
    $startInfo.Arguments = $Arguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ ExitCode = -1; Output = @() }
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
        while (-not $process.WaitForExit(100)) {
            if (
                ($null -ne $script:StopEvent -and $script:StopEvent.WaitOne(0)) -or
                [DateTime]::UtcNow -ge $deadline
            ) {
                try { $process.Kill() } catch {}
                [void]$process.WaitForExit(1000)
                return [pscustomobject]@{ ExitCode = -1; Output = @() }
            }
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $output = @()
        if ($stdout) { $output += @($stdout -split '\r?\n' | Where-Object { $_ }) }
        if ($stderr) { $output += @($stderr -split '\r?\n' | Where-Object { $_ }) }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $output
        }
    } finally {
        $process.Dispose()
    }
}

function Get-UsbSerial {
    $result = Invoke-AdbCapture -Arguments @('-d', 'get-serialno')
    if ($result.ExitCode -ne 0 -or $result.Output.Count -lt 1) {
        return $null
    }
    $serial = ([string]$result.Output[0]).Trim()
    if ($serial -notmatch '^[A-Za-z0-9._:-]{1,128}$' -or $serial -eq 'unknown') {
        return $null
    }
    return $serial
}

function Ensure-ScannerReverse {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][int]$TargetPort
    )

    $list = Invoke-AdbCapture -Arguments @('-s', $Serial, 'reverse', '--list')
    if ($list.ExitCode -ne 0) {
        return $false
    }

    $existingTarget = $null
    foreach ($line in $list.Output) {
        if ([string]$line -match "^\s*\S+\s+tcp:$DevicePort\s+tcp:(\d+)\s*$") {
            $existingTarget = $Matches[1]
            break
        }
    }
    if ($existingTarget) {
        return $existingTarget -eq [string]$TargetPort
    }

    $created = Invoke-AdbCapture -Arguments @(
        '-s', $Serial, 'reverse', '--no-rebind',
        "tcp:$DevicePort", "tcp:$TargetPort"
    )
    if ($created.ExitCode -ne 0) {
        return $false
    }

    $verified = Invoke-AdbCapture -Arguments @('-s', $Serial, 'reverse', '--list')
    if (
        $verified.ExitCode -ne 0 -or
        ($verified.Output -join "`n") -notmatch "tcp:$DevicePort\s+tcp:$TargetPort(?:\s|$)"
    ) {
        return $false
    }

    $script:OwnedReverseSerial = $Serial
    $script:OwnedReverseTargetPort = $TargetPort
    return $true
}

function Remove-OwnedScannerReverse {
    if (-not $script:OwnedReverseSerial -or -not $script:OwnedReverseTargetPort) {
        return
    }

    $serial = $script:OwnedReverseSerial
    $targetPort = $script:OwnedReverseTargetPort
    $list = Invoke-AdbCapture -TimeoutMilliseconds 2000 -Arguments @(
        '-s', $serial, 'reverse', '--list'
    )
    if (
        $list.ExitCode -eq 0 -and
        ($list.Output -join "`n") -match "tcp:$DevicePort\s+tcp:$targetPort(?:\s|$)"
    ) {
        [void](Invoke-AdbCapture -TimeoutMilliseconds 2000 -Arguments @(
            '-s', $serial, 'reverse', '--remove', "tcp:$DevicePort"
        ))
    }
    $script:OwnedReverseSerial = $null
    $script:OwnedReverseTargetPort = $null
}

function Get-ActiveScanner {
    $response = Invoke-RestMethod `
        -Method Get `
        -Uri "http://127.0.0.1:$CompanionPort/api/scanner/sessions/active" `
        -Headers @{ Accept = 'application/json' } `
        -TimeoutSec 2
    return $response.scanner
}

function New-DeviceCapability {
    param([Parameter(Mandatory = $true)][string]$SessionId)

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "http://127.0.0.1:$MainPort/api/scanner/devices" `
        -Headers @{
            Accept = 'application/json'
            'X-Scanner-Session-Id' = $SessionId
        } `
        -TimeoutSec 3
    $capability = [string]$response.device.capability
    if ($capability -notmatch '^[A-Za-z0-9_-]{40,80}$') {
        throw 'CardPrinter returned an invalid phone capability.'
    }
    return $capability
}

function Open-PhoneScanner {
    param(
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$Capability
    )

    $wake = Invoke-AdbCapture -Arguments @(
        '-s', $Serial, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'
    )
    if ($wake.ExitCode -ne 0) {
        return $false
    }

    $connectionId = ([Guid]::NewGuid().ToString('N')).Substring(0, 12)
    $phoneUrl = "http://localhost:$DevicePort/?connection=$connectionId#device=$Capability"
    $opened = Invoke-AdbCapture -TimeoutMilliseconds 10000 -Arguments @(
        '-s', $Serial, 'shell', 'am', 'start', '-W', '-a',
        'android.intent.action.VIEW', '-d', $phoneUrl
    )
    $phoneUrl = $null
    return $opened.ExitCode -eq 0
}

function Start-HelperProcess {
    if (Test-HelperReady) {
        Stop-HelperProcess
    }

    $hostExecutable = if ($PSVersionTable.PSEdition -eq 'Core') {
        Join-Path $PSHOME 'pwsh.exe'
    } else {
        Join-Path $PSHOME 'powershell.exe'
    }
    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Action', 'Run',
        '-MainPort', [string]$MainPort,
        '-CompanionPort', [string]$CompanionPort,
        '-DevicePort', [string]$DevicePort,
        '-PollMilliseconds', [string]$PollMilliseconds
    )
    Start-Process `
        -FilePath $hostExecutable `
        -ArgumentList $arguments `
        -WindowStyle Hidden | Out-Null

    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-HelperReady) {
            Write-Host 'USB 手機掃描自動喚醒已啟動。' -ForegroundColor Green
            return
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'USB 手機掃描自動喚醒程式未能啟動。'
}

function Stop-HelperProcess {
    $stopEvent = Open-NamedEvent -Name $stopEventName
    if ($null -eq $stopEvent) {
        Write-Host 'USB 手機掃描自動喚醒目前沒有執行。'
        return
    }
    try {
        [void]$stopEvent.Set()
    } finally {
        $stopEvent.Dispose()
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Test-HelperReady)) {
            Write-Host 'USB 手機掃描自動喚醒已停止。' -ForegroundColor Green
            return
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'USB 手機掃描自動喚醒程式未在期限內停止。'
}

function Run-HelperLoop {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -eq $adbCommand) {
        throw 'adb.exe is not available.'
    }
    $script:AdbPath = $adbCommand.Source

    $createdNew = $false
    $mutex = [System.Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)
    if (-not $createdNew) {
        $mutex.Dispose()
        return
    }
    $stopEvent = New-NamedManualResetEvent -Name $stopEventName -InitialState $false
    $readyEvent = New-NamedManualResetEvent -Name $readyEventName -InitialState $false
    [void]$stopEvent.Reset()
    $script:StopEvent = $stopEvent
    [void]$readyEvent.Set()

    $activeSessionId = $null
    $deviceCapability = $null
    $nextWakeAt = [DateTime]::MinValue
    try {
        while (-not $stopEvent.WaitOne(0)) {
            try {
                $scanner = Get-ActiveScanner
                if ($null -eq $scanner -or -not [bool]$scanner.available) {
                    $activeSessionId = $null
                    $deviceCapability = $null
                    $nextWakeAt = [DateTime]::MinValue
                    [void]$stopEvent.WaitOne($PollMilliseconds)
                    continue
                }

                $sessionId = [string]$scanner.sessionId
                if ($sessionId -notmatch '^[A-Za-z0-9_-]{20,40}$') {
                    throw 'CardPrinter returned an invalid scanner session id.'
                }
                if ([bool]$scanner.paired) {
                    if ($activeSessionId -ne $sessionId) {
                        $activeSessionId = $sessionId
                        $deviceCapability = $null
                        $nextWakeAt = [DateTime]::MinValue
                    }
                    # A helper restart may remove the reverse after the phone
                    # has already claimed the session. Restore only the data
                    # path; never rotate the paired capability or reopen the
                    # page with a new device grant.
                    if ([DateTime]::UtcNow -ge $nextWakeAt) {
                        $serial = Get-UsbSerial
                        [void](
                            $serial -and
                            (Ensure-ScannerReverse `
                                -Serial $serial `
                                -TargetPort $CompanionPort)
                        )
                        $nextWakeAt = [DateTime]::UtcNow.AddSeconds(3)
                    }
                    [void]$stopEvent.WaitOne($PollMilliseconds)
                    continue
                }
                if ($activeSessionId -ne $sessionId) {
                    $activeSessionId = $sessionId
                    $deviceCapability = $null
                    $nextWakeAt = [DateTime]::MinValue
                }

                if ([DateTime]::UtcNow -lt $nextWakeAt) {
                    [void]$stopEvent.WaitOne($PollMilliseconds)
                    continue
                }

                $serial = Get-UsbSerial
                if (-not $serial -or -not (Ensure-ScannerReverse -Serial $serial -TargetPort $CompanionPort)) {
                    $nextWakeAt = [DateTime]::UtcNow.AddSeconds(1)
                    [void]$stopEvent.WaitOne($PollMilliseconds)
                    continue
                }
                if (-not $deviceCapability) {
                    $deviceCapability = New-DeviceCapability -SessionId $sessionId
                }
                [void](Open-PhoneScanner -Serial $serial -Capability $deviceCapability)
                $nextWakeAt = [DateTime]::UtcNow.AddSeconds(3)
            } catch {
                # This helper is intentionally silent because HTTP/ADB errors
                # can contain the fragment capability. The desktop UI keeps
                # the manual pairing code available as a safe fallback.
                $nextWakeAt = [DateTime]::UtcNow.AddSeconds(1)
            }
            [void]$stopEvent.WaitOne($PollMilliseconds)
        }
    } finally {
        $script:StopEvent = $null
        try {
            Remove-OwnedScannerReverse
        } catch {
            # Never remove an unverified reverse mapping during cleanup.
        }
        [void]$readyEvent.Reset()
        $readyEvent.Dispose()
        $stopEvent.Dispose()
        if ($createdNew) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

switch ($Action) {
    'Start' {
        Start-HelperProcess
    }
    'Run' {
        Run-HelperLoop
    }
    'Stop' {
        Stop-HelperProcess
    }
    'Status' {
        if (Test-HelperReady) {
            Write-Host 'USB 手機掃描自動喚醒正在執行。' -ForegroundColor Green
        } else {
            Write-Host 'USB 手機掃描自動喚醒沒有執行。'
        }
    }
}
