[CmdletBinding()]
param(
    [string]$AndroidSerial = '',
    [ValidateRange(1024, 65535)]
    [int]$DevicePort = 18765
)

$ErrorActionPreference = 'Stop'

function Get-ComposePublishedPort {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ContainerPort,
        [int]$Attempts = 4
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt += 1) {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $portOutput = @(docker compose port cardprinter $ContainerPort 2>&1)
            $portExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($portExitCode -eq 0) {
            foreach ($line in $portOutput) {
                if ([string]$line -match ':(\d+)\s*$') {
                    return [int]$Matches[1]
                }
            }
        }
        if ($attempt -lt $Attempts) {
            Start-Sleep -Milliseconds 250
        }
    }
    throw "無法取得容器連接埠 $ContainerPort 的 Windows 對外連接埠。"
}

function Invoke-AdbCapture {
    param(
        [Parameter(Mandatory = $true)][string]$AdbPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [ValidateRange(250, 30000)][int]$TimeoutMilliseconds = 5000
    )

    foreach ($argument in $Arguments) {
        if ($null -eq $argument -or [string]$argument -match '[\s"]') {
            throw 'ADB 參數格式不安全。'
        }
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $AdbPath
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
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try { $process.Kill() } catch {}
            [void]$process.WaitForExit(1000)
            return [pscustomobject]@{ ExitCode = -1; Output = @() }
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $output = @()
        if ($stdout) { $output += @($stdout -split '\r?\n' | Where-Object { $_ }) }
        if ($stderr) { $output += @($stderr -split '\r?\n' | Where-Object { $_ }) }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
    } finally {
        $process.Dispose()
    }
}

Push-Location -LiteralPath $PSScriptRoot
try {
try {
    & (Join-Path $PSScriptRoot 'phone-scanner-helper.ps1') -Action Stop
} catch {
    Write-Warning "USB 手機掃描自動喚醒未能正常停止：$($_.Exception.Message)"
}
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($null -eq $adbCommand) {
    throw '找不到 adb.exe。'
}

$deviceResult = Invoke-AdbCapture -AdbPath $adbCommand.Source -Arguments @('devices', '-l')
$deviceOutput = $deviceResult.Output
if ($deviceResult.ExitCode -ne 0) {
    throw '無法讀取 ADB 裝置。'
}
$serialResult = Invoke-AdbCapture -AdbPath $adbCommand.Source -Arguments @('-d', 'get-serialno')
$usbSerialOutput = $serialResult.Output
if ($serialResult.ExitCode -ne 0) {
    if (($deviceOutput -join "`n") -notmatch '\sdevice(?:\s|$)') {
        Write-Host '沒有連線中的 USB 手機；不需要移除 ADB reverse。'
        return
    }
    throw '找不到唯一的 USB ADB 手機；請拔除其他 USB Android 裝置後重試。'
}
$selectedSerial = ($usbSerialOutput | Select-Object -First 1).Trim()
if (-not $selectedSerial -or $selectedSerial -eq 'unknown') {
    Write-Host '沒有連線中的手機；不需要移除 ADB reverse。'
    return
}
if ($AndroidSerial -and $AndroidSerial -ne $selectedSerial) {
    throw "USB 手機序號是 $selectedSerial，與 -AndroidSerial $AndroidSerial 不符。"
}

$publishedPort = Get-ComposePublishedPort -ContainerPort 8001

$reverseResult = Invoke-AdbCapture -AdbPath $adbCommand.Source -Arguments @('-d', 'reverse', '--list')
$reverseList = $reverseResult.Output
if ($reverseResult.ExitCode -ne 0) {
    throw '無法讀取 ADB reverse 清單。'
}
if (($reverseList -join "`n") -notmatch "tcp:$DevicePort\s+tcp:\d+") {
    Write-Host '這個手機掃描器連線目前不存在。'
    return
}
if (($reverseList -join "`n") -notmatch "tcp:$DevicePort\s+tcp:$publishedPort(?:\s|$)") {
    throw "手機 tcp:$DevicePort 目前屬於其他 ADB reverse；未進行移除。"
}

$removeResult = Invoke-AdbCapture -AdbPath $adbCommand.Source -Arguments @(
    '-d', 'reverse', '--remove', "tcp:$DevicePort"
)
if ($removeResult.ExitCode -ne 0) {
    throw "無法移除手機 tcp:$DevicePort 的 ADB reverse。"
}
Write-Host '手機掃描器連線已移除。' -ForegroundColor Green
} finally {
    Pop-Location
}
