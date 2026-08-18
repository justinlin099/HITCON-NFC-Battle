[CmdletBinding()]
param(
    [string]$AndroidSerial = '',
    [ValidateRange(1024, 65535)]
    [int]$DevicePort = 18765
)

$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    param([string[]]$AdbArguments)

    $result = & $script:AdbPath @AdbArguments
    if ($LASTEXITCODE -ne 0) {
        throw "ADB 指令失敗：adb $($AdbArguments -join ' ')"
    }
    return $result
}

Push-Location -LiteralPath $PSScriptRoot
try {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -eq $adbCommand) {
        throw '找不到 adb.exe。請先安裝 Android SDK Platform-Tools，並把它加入 PATH。'
    }
    $script:AdbPath = $adbCommand.Source

    $deviceOutput = Invoke-Adb -AdbArguments @('devices', '-l')
    $usbSerialOutput = & $script:AdbPath -d get-serialno 2>&1
    if ($LASTEXITCODE -ne 0) {
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

    $publishedEndpoint = docker compose port cardprinter 8001 |
        Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $publishedEndpoint) {
        throw '無法取得手機掃描器連接埠。請先執行 .\start.ps1。'
    }
    $publishedPort = ($publishedEndpoint.Trim() -split ':')[-1]
    if ($publishedPort -notmatch '^\d+$') {
        throw 'Docker 回傳了無法辨識的手機掃描器連接埠。'
    }

    try {
        $healthParameters = @{
            Uri = "http://127.0.0.1:$publishedPort/healthz"
            TimeoutSec = 3
        }
        Invoke-RestMethod @healthParameters | Out-Null
    } catch {
        throw '手機掃描器服務尚未就緒。請確認卡片列印站容器為 healthy。'
    }

    $mainPublishedEndpoint = docker compose port cardprinter 8000 |
        Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $mainPublishedEndpoint) {
        throw '無法取得卡片列印站連接埠。請先執行 .\start.ps1。'
    }
    $mainPublishedPort = ($mainPublishedEndpoint.Trim() -split ':')[-1]
    if ($mainPublishedPort -notmatch '^\d+$') {
        throw 'Docker 回傳了無法辨識的卡片列印站連接埠。'
    }

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
    & $script:AdbPath @(
        '-d', 'shell', 'am', 'start', '-W', '-a',
        'android.intent.action.VIEW', '-d', $phoneUrl
    ) | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw '無法在 USB 手機開啟掃描頁。'
    }

    Write-Host "手機掃描器已在 $selectedSerial 自動連線。" -ForegroundColor Green
    Write-Host '之後在 Windows 按「用手機掃描」即可，不必再輸入配對碼。'
} finally {
    Pop-Location
}
