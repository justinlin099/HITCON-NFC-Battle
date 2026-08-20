[CmdletBinding()]
param(
    [string]$AndroidSerial = '',
    [ValidateRange(1024, 65535)]
    [int]$DevicePort = 18765
)

$ErrorActionPreference = 'Stop'
$mainPublishedPort = $null
$publishedPort = $null
$helperRestartRequired = $false

function Get-ComposePublishedPort {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ContainerPort,
        [int]$Attempts = 12
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
        [string[]]$AdbArguments,
        [ValidateRange(250, 30000)][int]$TimeoutMilliseconds = 8000
    )

    foreach ($argument in $AdbArguments) {
        if ($null -eq $argument -or [string]$argument -match '[\s"]') {
            throw 'ADB 參數格式不安全。'
        }
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:AdbPath
    $startInfo.Arguments = $AdbArguments -join ' '
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

function Invoke-Adb {
    param([string[]]$AdbArguments)

    $capture = Invoke-AdbCapture -AdbArguments $AdbArguments
    if ($capture.ExitCode -ne 0) {
        throw "ADB 指令失敗：adb $($AdbArguments -join ' ')"
    }
    return $capture.Output
}

Push-Location -LiteralPath $PSScriptRoot
try {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -eq $adbCommand) {
        throw '找不到 adb.exe。請先安裝 Android SDK Platform-Tools，並把它加入 PATH。'
    }
    $script:AdbPath = $adbCommand.Source

    $deviceOutput = Invoke-Adb -AdbArguments @('devices', '-l')
    $usbSerialResult = Invoke-AdbCapture -AdbArguments @('-d', 'get-serialno')
    $usbSerialOutput = $usbSerialResult.Output
    if ($usbSerialResult.ExitCode -ne 0) {
        if (($deviceOutput -join "`n") -match '\sunauthorized(?:\s|$)') {
            throw '手機尚未授權。請解鎖手機，並在「允許 USB 偵錯」視窗按允許。'
        }
        throw '找不到唯一的 USB ADB 手機。請接上一台已授權的實體手機，並拔除其他 USB Android 裝置。'
    }
    $selectedSerial = ($usbSerialOutput | Select-Object -First 1).Trim()
    if (-not $selectedSerial -or $selectedSerial -eq 'unknown') {
        throw 'ADB 無法確認 USB 手機序號。'
    }
    if ($AndroidSerial -and $AndroidSerial -ne $selectedSerial) {
        throw "USB 手機序號是 $selectedSerial，與 -AndroidSerial $AndroidSerial 不符。"
    }

    $publishedPort = Get-ComposePublishedPort -ContainerPort 8001

    try {
        $healthParameters = @{
            Uri = "http://127.0.0.1:$publishedPort/healthz"
            TimeoutSec = 3
        }
        Invoke-RestMethod @healthParameters | Out-Null
    } catch {
        throw '手機掃描器服務尚未就緒。請確認卡片列印站容器為 healthy。'
    }

    $mainPublishedPort = Get-ComposePublishedPort -ContainerPort 8000

    # Keep the existing helper alive until all read-only preflight checks pass.
    # From this point onward, always restart it in finally—even if a later ADB
    # or phone-launch step fails.
    $helperRestartRequired = $true
    & (Join-Path $PSScriptRoot 'phone-scanner-helper.ps1') -Action Stop

    $reverseList = Invoke-Adb -AdbArguments @('-d', 'reverse', '--list')
    $existingTarget = $null
    foreach ($line in $reverseList) {
        if ($line -match "^\s*\S+\s+tcp:$DevicePort\s+tcp:(\d+)\s*$") {
            $existingTarget = $Matches[1]
            break
        }
    }
    if ($existingTarget -and $existingTarget -ne $publishedPort) {
        throw "手機的 tcp:$DevicePort 已被其他 ADB reverse 使用；請改用 -DevicePort 指定其他連接埠。"
    }
    if (-not $existingTarget) {
        Invoke-Adb -AdbArguments @(
            '-d', 'reverse', '--no-rebind',
            "tcp:$DevicePort", "tcp:$publishedPort"
        ) | Out-Null
    }

    $verified = Invoke-Adb -AdbArguments @('-d', 'reverse', '--list')
    if (($verified -join "`n") -notmatch "tcp:$DevicePort\s+tcp:$publishedPort") {
        throw 'ADB reverse 建立後無法驗證。'
    }

    try {
        $deviceGrant = Invoke-RestMethod -Method Post `
            -Uri "http://127.0.0.1:$mainPublishedPort/api/scanner/devices" `
            -TimeoutSec 5
        $deviceCapability = [string]$deviceGrant.device.capability
    } catch {
        throw '無法建立 USB 手機連線憑證。請確認卡片列印站容器為 healthy。'
    }
    if ($deviceCapability -notmatch '^[A-Za-z0-9_-]{40,80}$') {
        throw '卡片列印站回傳了無效的 USB 手機連線憑證。'
    }

    # 非敏感 connection id 強制 Chrome 重新載入；秘密 fragment 不會被送進
    # HTTP request 或伺服器 log，手機頁面讀取後也會立刻清除。
    $connectionId = ([Guid]::NewGuid().ToString('N')).Substring(0, 12)
    $phoneUrl = "http://localhost:$DevicePort/?connection=$connectionId#device=$deviceCapability"
    $openResult = Invoke-AdbCapture -TimeoutMilliseconds 10000 -AdbArguments @(
        '-d', 'shell', 'am', 'start', '-W', '-a',
        'android.intent.action.VIEW', '-d', $phoneUrl
    )
    $phoneUrl = $null
    if ($openResult.ExitCode -ne 0) {
        throw '無法在 USB 手機開啟掃描頁。'
    }

    Write-Host "手機掃描器已在 $selectedSerial 自動連線。" -ForegroundColor Green
    Write-Host '之後在 Windows 按「用手機掃描」即可，不必再輸入配對碼。'
} finally {
    if ($helperRestartRequired -and $mainPublishedPort -and $publishedPort) {
        try {
            & (Join-Path $PSScriptRoot 'phone-scanner-helper.ps1') `
                -Action Start `
                -MainPort $mainPublishedPort `
                -CompanionPort $publishedPort `
                -DevicePort $DevicePort
        } catch {
            Write-Warning "自動喚醒 helper 未能重新啟動：$($_.Exception.Message)"
        }
    }
    Pop-Location
}
