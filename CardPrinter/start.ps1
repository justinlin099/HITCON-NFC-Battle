[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectDirectory = $PSScriptRoot

Push-Location -LiteralPath $projectDirectory
try {
    $dockerOsType = docker info --format '{{.OSType}}'
    if ($LASTEXITCODE -ne 0) {
        throw '無法連線到 Docker Desktop；請先啟動 Docker Desktop。'
    }
    if ($dockerOsType.Trim() -ne 'linux') {
        throw '卡片列印站需要 Docker Desktop 的 Linux containers／WSL2 模式。'
    }

    if (-not (Test-Path -LiteralPath '.env')) {
        Copy-Item -LiteralPath '.env.example' -Destination '.env'
        Write-Host '已建立 .env。STAFF_JWT 留白時，可在網頁中臨時貼入憑證。' -ForegroundColor Yellow
    }

    docker compose up --build -d --wait --wait-timeout 60
    if ($LASTEXITCODE -ne 0) {
        throw '卡片列印站建置、啟動或健康檢查失敗。請查看上方 Docker 訊息。'
    }

    docker compose ps
    if ($LASTEXITCODE -ne 0) {
        throw '無法讀取卡片列印站容器狀態。'
    }

    $publishedEndpoint = docker compose port cardprinter 8000 |
        Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $publishedEndpoint) {
        throw '卡片列印站已啟動，但無法取得對外連接埠。'
    }
    $publishedPort = ($publishedEndpoint.Trim() -split ':')[-1]
    Write-Host "卡片列印站已啟動：http://localhost:$publishedPort" -ForegroundColor Green
    Write-Host '若要用 USB 舊手機掃描，請執行 .\connect-phone-scanner.ps1。'
} finally {
    Pop-Location
}
