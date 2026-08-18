[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Push-Location -LiteralPath $PSScriptRoot
try {
    docker compose down
    if ($LASTEXITCODE -ne 0) {
        throw '卡片列印站停止失敗。請確認 Docker Desktop 正在執行。'
    }
} finally {
    Pop-Location
}
