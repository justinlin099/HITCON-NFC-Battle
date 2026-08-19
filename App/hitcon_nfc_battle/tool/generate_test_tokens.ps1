#requires -Version 5.1

<#
.SYNOPSIS
Generates HMAC-SHA256 JWTs for NFC Battle testing.

.DESCRIPTION
The JWT secret is read from JWT_SECRET. If the environment variable is not set,
the script prompts for it without echoing the value. The secret is never written
to the output.

By default, tokens use the staging issuer and audience. Every generated token is
decoded and signature-checked locally before it is printed.

.EXAMPLE
.\tool\generate_test_tokens.ps1 -UserId test_attendee_017

.EXAMPLE
.\tool\generate_test_tokens.ps1 -Prefix test_attendee_ -Start 17 -Count 10

.EXAMPLE
.\tool\generate_test_tokens.ps1 -UserId rock,jimmy -AsJson

.EXAMPLE
.\tool\generate_test_tokens.ps1 -Prefix test_attendee_ -Start 17 -Count 10 `
  -OutputPath .\test-tokens.json -AsJson

.EXAMPLE
.\tool\generate_test_tokens.ps1 -UserId test_attendee_017 -VerifyWithApi

.NOTES
VerifyWithApi calls GET /users/me. On staging, that endpoint initializes a
profile for a previously unseen subject.
#>

[CmdletBinding(DefaultParameterSetName = 'ExplicitIds')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ExplicitIds', Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$UserId,

    [Parameter(Mandatory, ParameterSetName = 'GeneratedIds')]
    [ValidateNotNullOrEmpty()]
    [string]$Prefix,

    [Parameter(Mandatory, ParameterSetName = 'GeneratedIds')]
    [ValidateRange(1, 1000)]
    [int]$Count,

    [Parameter(ParameterSetName = 'GeneratedIds')]
    [ValidateRange(0, 2147483647)]
    [int]$Start = 1,

    [Parameter(ParameterSetName = 'GeneratedIds')]
    [ValidateRange(0, 12)]
    [int]$Padding = 3,

    [ValidateSet('ATTENDEE', 'STAFF', 'SPONSOR', 'COMMUNITY')]
    [string]$Role = 'ATTENDEE',

    [ValidateRange(1, 3650)]
    [int]$DaysValid = 365,

    [string]$Issuer,

    [string]$Audience,

    [switch]$AsJson,

    [string]$OutputPath,

    [switch]$VerifyWithApi,

    [string]$ApiBaseUrl = 'https://nfc-battle-staging.hitcon2026.online'
)

$ErrorActionPreference = 'Stop'

function ConvertTo-Base64Url {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    return [Convert]::ToBase64String($Bytes).
        TrimEnd('=').
        Replace('+', '-').
        Replace('/', '_')
}

function ConvertFrom-Base64Url {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $base64 = $Value.Replace('-', '+').Replace('_', '/')
    $padding = (4 - ($base64.Length % 4)) % 4
    if ($padding -gt 0) {
        $base64 += '=' * $padding
    }
    return [Convert]::FromBase64String($base64)
}

function Test-FixedTimeEqual {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Left,

        [Parameter(Mandatory)]
        [byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }

    $difference = 0
    for ($index = 0; $index -lt $Left.Length; $index++) {
        $difference = $difference -bor ($Left[$index] -bxor $Right[$index])
    }
    return $difference -eq 0
}

function Get-HmacSha256 {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Key,

        [Parameter(Mandatory)]
        [byte[]]$Data
    )

    $hmac = [Security.Cryptography.HMACSHA256]::new($Key)
    try {
        return $hmac.ComputeHash($Data)
    }
    finally {
        $hmac.Dispose()
    }
}

function Assert-UserId {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value.Length -gt 128) {
        throw "User ID is longer than 128 characters: $Value"
    }
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]*$') {
        throw "User ID contains unsupported characters: $Value"
    }
}

if ([string]::IsNullOrWhiteSpace($Issuer)) {
    $Issuer = if ([string]::IsNullOrWhiteSpace($env:JWT_ISSUER)) {
        'hitcon-2026-staging'
    }
    else {
        $env:JWT_ISSUER
    }
}

if ([string]::IsNullOrWhiteSpace($Audience)) {
    $Audience = if ([string]::IsNullOrWhiteSpace($env:JWT_AUDIENCE)) {
        'nfc-battle-api-server-staging'
    }
    else {
        $env:JWT_AUDIENCE
    }
}

$secret = $env:JWT_SECRET
if ([string]::IsNullOrWhiteSpace($secret)) {
    $secureSecret = Read-Host 'JWT_SECRET' -AsSecureString
    $credential = [Management.Automation.PSCredential]::new('jwt', $secureSecret)
    $secret = $credential.GetNetworkCredential().Password
}
if ([string]::IsNullOrWhiteSpace($secret)) {
    throw 'JWT_SECRET cannot be empty.'
}

$ids = [Collections.Generic.List[string]]::new()
if ($PSCmdlet.ParameterSetName -eq 'ExplicitIds') {
    foreach ($id in $UserId) {
        $ids.Add($id.Trim())
    }
}
else {
    for ($offset = 0; $offset -lt $Count; $offset++) {
        $number = $Start + $offset
        $suffix = if ($Padding -eq 0) {
            $number.ToString()
        }
        else {
            $number.ToString("D$Padding")
        }
        $ids.Add("$Prefix$suffix")
    }
}

$uniqueIds = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal
)
foreach ($id in $ids) {
    Assert-UserId -Value $id
    if (-not $uniqueIds.Add($id)) {
        throw "Duplicate user ID: $id"
    }
}

if ($VerifyWithApi) {
    $parsedApiUrl = $null
    if (
        -not [Uri]::TryCreate(
            $ApiBaseUrl,
            [UriKind]::Absolute,
            [ref]$parsedApiUrl
        ) -or
        $parsedApiUrl.Scheme -ne 'https' -or
        -not [string]::IsNullOrEmpty($parsedApiUrl.Query) -or
        -not [string]::IsNullOrEmpty($parsedApiUrl.Fragment)
    ) {
        throw 'ApiBaseUrl must be an HTTPS origin without a query or fragment.'
    }
}

$utf8 = [Text.UTF8Encoding]::new($false)
$secretBytes = $utf8.GetBytes($secret)
$headerJson = '{"alg":"HS256","typ":"JWT"}'
$encodedHeader = ConvertTo-Base64Url -Bytes $utf8.GetBytes($headerJson)
$expiresAtUnix = [DateTimeOffset]::UtcNow.
    AddDays($DaysValid).
    ToUnixTimeSeconds()
$expiresAt = [DateTimeOffset]::FromUnixTimeSeconds($expiresAtUnix)
$results = [Collections.Generic.List[object]]::new()

foreach ($id in $ids) {
    $payload = [ordered]@{
        sub  = $id
        exp  = $expiresAtUnix
        iss  = $Issuer
        aud  = $Audience
        role = $Role
    }
    $payloadJson = $payload | ConvertTo-Json -Compress
    $encodedPayload = ConvertTo-Base64Url -Bytes $utf8.GetBytes($payloadJson)
    $unsignedToken = "$encodedHeader.$encodedPayload"
    $signatureBytes = Get-HmacSha256 `
        -Key $secretBytes `
        -Data $utf8.GetBytes($unsignedToken)
    $encodedSignature = ConvertTo-Base64Url -Bytes $signatureBytes
    $token = "$unsignedToken.$encodedSignature"

    $parts = $token.Split('.')
    if ($parts.Count -ne 3) {
        throw "Generated malformed JWT for $id."
    }

    $decodedHeader = $utf8.GetString(
        (ConvertFrom-Base64Url -Value $parts[0])
    ) | ConvertFrom-Json
    $decodedPayload = $utf8.GetString(
        (ConvertFrom-Base64Url -Value $parts[1])
    ) | ConvertFrom-Json
    $decodedSignature = ConvertFrom-Base64Url -Value $parts[2]
    $expectedSignature = Get-HmacSha256 `
        -Key $secretBytes `
        -Data $utf8.GetBytes("$($parts[0]).$($parts[1])")

    if (
        $decodedHeader.alg -ne 'HS256' -or
        $decodedPayload.sub -ne $id -or
        $decodedPayload.exp -ne $expiresAtUnix -or
        $decodedPayload.iss -ne $Issuer -or
        $decodedPayload.aud -ne $Audience -or
        $decodedPayload.role -ne $Role -or
        -not (Test-FixedTimeEqual `
            -Left $decodedSignature `
            -Right $expectedSignature)
    ) {
        throw "Generated JWT failed local verification for $id."
    }

    $httpStatus = $null
    if ($VerifyWithApi) {
        $verifyUri = "$($ApiBaseUrl.TrimEnd('/'))/users/me"
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Method Get `
            -Uri $verifyUri `
            -Headers @{ Authorization = "Bearer $token" } `
            -TimeoutSec 30
        $httpStatus = [int]$response.StatusCode
        if ($httpStatus -ne 200) {
            throw "API verification failed for $id with HTTP $httpStatus."
        }
    }

    $results.Add([pscustomobject][ordered]@{
        user_id      = $id
        role         = $Role
        issuer       = $Issuer
        audience     = $Audience
        expires_at   = $expiresAt.ToString('o')
        token_length = $token.Length
        verified_http = $httpStatus
        token        = $token
    })
}

if ($AsJson) {
    $output = ConvertTo-Json -InputObject @($results) -Depth 4
}
else {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($result in $results) {
        $lines.Add("user_id=$($result.user_id)")
        $lines.Add("role=$($result.role)")
        $lines.Add("expires_at=$($result.expires_at)")
        $lines.Add("token_length=$($result.token_length)")
        if ($null -ne $result.verified_http) {
            $lines.Add("verified_http=$($result.verified_http)")
        }
        $lines.Add("token=$($result.token)")
        $lines.Add('')
    }
    $output = $lines -join [Environment]::NewLine
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Output $output
}
else {
    $fullOutputPath = [IO.Path]::GetFullPath(
        [IO.Path]::Combine((Get-Location).Path, $OutputPath)
    )
    $outputDirectory = [IO.Path]::GetDirectoryName($fullOutputPath)
    if (-not [IO.Directory]::Exists($outputDirectory)) {
        throw "Output directory does not exist: $outputDirectory"
    }
    [IO.File]::WriteAllText($fullOutputPath, $output, $utf8)
    Write-Host "Wrote $($results.Count) token(s) to $fullOutputPath"
    Write-Warning 'The output file contains login credentials. Store it securely.'
}
