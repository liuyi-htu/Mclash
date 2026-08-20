$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$flutterProject = Join-Path $root "mclash"
$serviceProject = Join-Path $root "windows-service"
$packageDir = Join-Path $root "windows-package"
$mihomo = Join-Path $packageDir "mihomo.exe"
$singBox = Join-Path $packageDir "sing-box.exe"
$defaultConfigUrl = "https://txt.2468999.xyz/sub/mini-ali/clash/mini-ali.yaml"
$downloadedDefaultConfig = Join-Path $packageDir "downloaded-config.yaml"
$ruleSetDir = Join-Path $packageDir "rulesets"
$releaseVersion = if ($env:MCLASH_VERSION) {
    $env:MCLASH_VERSION.Trim()
} else {
    "1.0.2"
}
if ($releaseVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "MCLASH_VERSION must use the x.y.z format without a v prefix."
}
$buildNumber = if ($env:MCLASH_BUILD_NUMBER) {
    $env:MCLASH_BUILD_NUMBER.Trim()
} else {
    "1"
}
if ($buildNumber -notmatch '^[1-9]\d*$') {
    throw "MCLASH_BUILD_NUMBER must be a positive integer."
}
$packageVersion = "$releaseVersion+$buildNumber"

# The package staging directory is intentionally not committed. Create it for
# clean checkouts before downloading cores and runtime data into it.
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

$isccCandidates = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
    "D:\Program Files\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object {
    $_ -and (Test-Path -LiteralPath $_ -PathType Leaf)
} | Select-Object -First 1
if (-not $iscc) {
    throw "Inno Setup 6 (ISCC.exe) was not found."
}

$releaseHeaders = @{
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "Mclash-Windows-Build"
}

if (-not (Test-Path -LiteralPath $mihomo -PathType Leaf) -or
    (Get-Item -LiteralPath $mihomo).Length -eq 0) {
    Write-Host "Downloading the latest official mihomo Windows amd64 core..."
    $mihomoRelease = Invoke-RestMethod `
        -Headers $releaseHeaders `
        -Uri "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
    $mihomoAsset = $mihomoRelease.assets | Where-Object {
        $_.name -match '^mihomo-windows-amd64-compatible-.*\.zip$'
    } | Select-Object -First 1
    if (-not $mihomoAsset -or -not $mihomoAsset.digest -or
        -not $mihomoAsset.digest.StartsWith("sha256:")) {
        throw "The latest mihomo release has no verifiable Windows amd64-compatible archive."
    }

    $archive = Join-Path $env:TEMP $mihomoAsset.name
    $extractDir = Join-Path $env:TEMP "mclash-mihomo-$([guid]::NewGuid())"
    try {
        Invoke-WebRequest `
            -Headers @{ "User-Agent" = "Mclash-Windows-Build" } `
            -Uri $mihomoAsset.browser_download_url `
            -OutFile $archive
        $expectedHash = $mihomoAsset.digest.Substring(7).ToUpperInvariant()
        $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            throw "mihomo SHA-256 mismatch: expected=$expectedHash actual=$actualHash"
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
        $downloadedCore = Get-ChildItem -LiteralPath $extractDir -Filter "mihomo*.exe" -Recurse |
            Select-Object -First 1
        if (-not $downloadedCore) {
            throw "The mihomo archive does not contain an executable."
        }
        Copy-Item -LiteralPath $downloadedCore.FullName -Destination $mihomo -Force
    }
    finally {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $singBox -PathType Leaf) -or
    (Get-Item -LiteralPath $singBox).Length -eq 0) {
    Write-Host "Downloading the latest official sing-box Windows amd64 core..."
    $release = Invoke-RestMethod -Headers $releaseHeaders -Uri "https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -match '^sing-box-[0-9.]+-windows-amd64\.zip$' } | Select-Object -First 1
    if (-not $asset -or -not $asset.digest -or -not $asset.digest.StartsWith("sha256:")) { throw "No verifiable sing-box Windows amd64 archive was found." }
    $archive = Join-Path $env:TEMP $asset.name
    $extractDir = Join-Path $env:TEMP "mclash-singbox-$([guid]::NewGuid())"
    try {
        Invoke-WebRequest -Headers @{ "User-Agent" = "Mclash-Windows-Build" } -Uri $asset.browser_download_url -OutFile $archive
        if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $asset.digest.Substring(7).ToUpperInvariant()) { throw "sing-box SHA-256 mismatch." }
        Expand-Archive $archive $extractDir -Force
        $exe = Get-ChildItem $extractDir -Filter "sing-box.exe" -Recurse | Select-Object -First 1
        if (-not $exe) { throw "sing-box archive contains no executable." }
        Copy-Item $exe.FullName $singBox -Force
    } finally {
        Remove-Item $archive -Force -ErrorAction SilentlyContinue
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Resolving the latest MetaCubeX geodata release..."
$geodataRelease = Invoke-RestMethod `
    -Headers $releaseHeaders `
    -Uri "https://api.github.com/repos/MetaCubeX/meta-rules-dat/releases/latest"
$geodataFiles = @(
    @{ Asset = "geosite.dat"; Installed = "GeoSite.dat" },
    @{ Asset = "geoip.dat"; Installed = "GeoIP.dat" },
    @{ Asset = "country.mmdb"; Installed = "Country.mmdb" }
)

foreach ($entry in $geodataFiles) {
    $asset = $geodataRelease.assets | Where-Object {
        $_.name -ieq $entry.Asset
    } | Select-Object -First 1
    if (-not $asset) {
        throw "The latest MetaCubeX geodata release does not contain $($entry.Asset)."
    }
    if (-not $asset.digest -or -not $asset.digest.StartsWith("sha256:")) {
        throw "The geodata asset $($entry.Asset) has no SHA-256 digest."
    }

    $expectedHash = $asset.digest.Substring(7).ToUpperInvariant()
    $destination = Join-Path $packageDir $entry.Asset
    $validCachedFile = (Test-Path -LiteralPath $destination -PathType Leaf) -and `
        ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $expectedHash)
    if (-not $validCachedFile) {
        $temporary = "$destination.download"
        try {
            Invoke-WebRequest `
                -Headers @{ "User-Agent" = "Mclash-Windows-Build" } `
                -Uri $asset.browser_download_url `
                -OutFile $temporary
            $actualHash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
            if ($actualHash -ne $expectedHash) {
                throw "$($entry.Asset) SHA-256 mismatch: expected=$expectedHash actual=$actualHash"
            }
            Move-Item -LiteralPath $temporary -Destination $destination -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporary) {
                Remove-Item -LiteralPath $temporary -Force
            }
        }
    }
    Write-Host "Geodata ready: $($entry.Installed)"
}

Write-Host "Resolving official sing-box rule sets..."
New-Item -ItemType Directory -Path $ruleSetDir -Force | Out-Null
$singBoxRuleSets = @(
    @{ Repo = "SagerNet/sing-geoip"; File = "geoip-cn.srs" },
    @{ Repo = "SagerNet/sing-geosite"; File = "geosite-cn.srs" },
    @{ Repo = "SagerNet/sing-geosite"; File = "geosite-private.srs" },
    @{ Repo = "SagerNet/sing-geosite"; File = "geosite-category-ads-all.srs" },
    @{ Repo = "SagerNet/sing-geosite"; File = "geosite-geolocation-!cn.srs" }
)

foreach ($entry in $singBoxRuleSets) {
    $metadata = Invoke-RestMethod `
        -Headers $releaseHeaders `
        -Uri "https://api.github.com/repos/$($entry.Repo)/contents/$($entry.File)?ref=rule-set"
    if (-not $metadata.content -or -not $metadata.sha) {
        throw "The official sing-box rule set $($entry.File) has no content or Git hash."
    }
    $bytes = [Convert]::FromBase64String(($metadata.content -replace '\s', ''))
    $header = [Text.Encoding]::UTF8.GetBytes("blob $($bytes.Length)`0")
    $blob = New-Object byte[] ($header.Length + $bytes.Length)
    [Buffer]::BlockCopy($header, 0, $blob, 0, $header.Length)
    [Buffer]::BlockCopy($bytes, 0, $blob, $header.Length, $bytes.Length)
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try {
        $actualGitHash = [BitConverter]::ToString($sha1.ComputeHash($blob)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha1.Dispose()
    }
    if ($actualGitHash -ne $metadata.sha.ToLowerInvariant()) {
        throw "$($entry.File) Git blob hash mismatch: expected=$($metadata.sha) actual=$actualGitHash"
    }
    [IO.File]::WriteAllBytes((Join-Path $ruleSetDir $entry.File), $bytes)
    Write-Host "sing-box rule set ready: $($entry.File)"
}

Push-Location $flutterProject
try {
    flutter pub get
    dart format --output=none --set-exit-if-changed lib test
    flutter analyze
    flutter test
    flutter build windows --release
}
finally {
    Pop-Location
}

Push-Location $serviceProject
try {
    $env:GOOS = "windows"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"
    $unformatted = @(gofmt -l .)
    if ($unformatted.Count -gt 0) {
        throw "Go files are not formatted: $($unformatted -join ', ')"
    }
    go mod tidy -diff
    if ($LASTEXITCODE -ne 0) {
        throw "go.mod or go.sum is not tidy."
    }
    go test ./...
    if ($LASTEXITCODE -ne 0) {
        throw "Go tests failed."
    }
    Remove-Item -LiteralPath (Join-Path $packageDir "mihomoService.exe") -Force -ErrorAction SilentlyContinue
    go build -trimpath -ldflags="-s -w" -o "$packageDir\MclashService.exe" .
}
finally {
    Pop-Location
}

$releaseDir = Join-Path $flutterProject "build\windows\x64\runner\Release"
Remove-Item -LiteralPath (Join-Path $releaseDir "MclashService.exe") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $releaseDir "mihomoService.exe") -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $packageDir "MclashService.exe") -Destination $releaseDir -Force
Copy-Item -LiteralPath $mihomo -Destination $releaseDir -Force
Copy-Item -LiteralPath $singBox -Destination $releaseDir -Force

Write-Host "Downloading the default mihomo configuration..."
$temporaryDefaultConfig = "$downloadedDefaultConfig.download"
try {
    Invoke-WebRequest `
        -Headers @{ "User-Agent" = "clash.meta" } `
        -Uri $defaultConfigUrl `
        -OutFile $temporaryDefaultConfig
    if (-not (Test-Path -LiteralPath $temporaryDefaultConfig -PathType Leaf) -or
        (Get-Item -LiteralPath $temporaryDefaultConfig).Length -eq 0) {
        throw "The downloaded default mihomo configuration is empty."
    }
    $defaultConfigContent = Get-Content -LiteralPath $temporaryDefaultConfig -Raw
    if ($defaultConfigContent -notmatch '(?m)^\s*(proxies|proxy-providers|proxy-groups|rules|mixed-port|port|socks-port|redir-port|tproxy-port)\s*:') {
        throw "The downloaded default configuration is not a mihomo/Clash YAML configuration."
    }
    Move-Item -LiteralPath $temporaryDefaultConfig -Destination $downloadedDefaultConfig -Force

    & $iscc "/DMyAppVersion=$releaseVersion" "/DMyBuildNumber=$buildNumber" `
        (Join-Path $root "installer\Mclash.iss")
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup failed with exit code $LASTEXITCODE."
    }
}
finally {
    Remove-Item -LiteralPath $temporaryDefaultConfig -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $downloadedDefaultConfig -Force -ErrorAction SilentlyContinue
}
$installer = Join-Path $root "installer\Output\Mclash-Windows-Setup-$packageVersion-x64.exe"
Write-Host "Windows installer: $installer"
