[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectDirectory = $PSScriptRoot

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

    $publishedPort = Get-ComposePublishedPort -ContainerPort 8000
    $companionPublishedPort = Get-ComposePublishedPort -ContainerPort 8001
    Write-Host "卡片列印站已啟動：http://localhost:$publishedPort" -ForegroundColor Green
    try {
        & (Join-Path $PSScriptRoot 'phone-scanner-helper.ps1') `
            -Action Start `
            -MainPort $publishedPort `
            -CompanionPort $companionPublishedPort
    } catch {
        Write-Warning "USB 手機掃描自動喚醒未啟動：$($_.Exception.Message)"
        Write-Host '仍可執行 .\connect-phone-scanner.ps1 使用手動備援。'
    }
} finally {
    Pop-Location
}
