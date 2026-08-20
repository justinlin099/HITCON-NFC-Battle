[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Push-Location -LiteralPath $PSScriptRoot
try {
    try {
        & (Join-Path $PSScriptRoot 'disconnect-phone-scanner.ps1')
    } catch {
        Write-Warning "USB 手機掃描連線未能完整移除：$($_.Exception.Message)"
        try {
            & (Join-Path $PSScriptRoot 'phone-scanner-helper.ps1') -Action Stop
        } catch {
            Write-Warning "USB 手機掃描自動喚醒未能正常停止：$($_.Exception.Message)"
        }
    }
    docker compose down
    if ($LASTEXITCODE -ne 0) {
        throw '卡片列印站停止失敗。請確認 Docker Desktop 正在執行。'
    }
} finally {
    Pop-Location
}
