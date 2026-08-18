[CmdletBinding()]
param(
    [string]$AndroidSerial = '',
    [ValidateRange(1024, 65535)]
    [int]$DevicePort = 18765
)

$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($null -eq $adbCommand) {
    throw '找不到 adb.exe。'
}

$deviceOutput = & $adbCommand.Source devices -l
if ($LASTEXITCODE -ne 0) {
    throw '無法讀取 ADB 裝置。'
}
$usbSerialOutput = & $adbCommand.Source -d get-serialno 2>&1
if ($LASTEXITCODE -ne 0) {
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

$publishedEndpoint = docker compose port cardprinter 8001 |
    Select-Object -First 1
if ($LASTEXITCODE -ne 0 -or -not $publishedEndpoint) {
    throw '無法確認本工具的 companion port；為避免移除其他工具的 ADB reverse，已停止操作。'
}
$publishedPort = ($publishedEndpoint.Trim() -split ':')[-1]
if ($publishedPort -notmatch '^\d+$') {
    throw 'Docker 回傳了無法辨識的 companion port。'
}

$reverseList = & $adbCommand.Source -d reverse --list
if ($LASTEXITCODE -ne 0) {
    throw '無法讀取 ADB reverse 清單。'
}
if (($reverseList -join "`n") -notmatch "tcp:$DevicePort\s+tcp:\d+") {
    Write-Host '這個手機掃描器連線目前不存在。'
    return
}
if (($reverseList -join "`n") -notmatch "tcp:$DevicePort\s+tcp:$publishedPort(?:\s|$)") {
    throw "手機 tcp:$DevicePort 目前屬於其他 ADB reverse；未進行移除。"
}

& $adbCommand.Source -d reverse --remove "tcp:$DevicePort"
if ($LASTEXITCODE -ne 0) {
    throw "無法移除手機 tcp:$DevicePort 的 ADB reverse。"
}
Write-Host '手機掃描器連線已移除。' -ForegroundColor Green
} finally {
    Pop-Location
}
