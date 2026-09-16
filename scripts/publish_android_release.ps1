param(
    [Parameter(Mandatory = $true)]
    [string]$VersionName,

    [Parameter(Mandatory = $true)]
    [int]$VersionCode,

    [Parameter(Mandatory = $true)]
    [int]$MinSupportedVersionCode,

    [Parameter(Mandatory = $true)]
    [string]$Changelog,

    [string]$Repository = "aerfa-beita/self_to-do-list",
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    throw "GITHUB_TOKEN is required. Keep it in the local environment only."
}

if ($MinSupportedVersionCode -gt $VersionCode) {
    throw "MinSupportedVersionCode cannot exceed VersionCode."
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
$expectedVersion = "version: $VersionName+$VersionCode"
if (-not (Select-String -Path $pubspecPath -SimpleMatch $expectedVersion -Quiet)) {
    throw "pubspec.yaml must contain '$expectedVersion' before publishing."
}

if ([string]::IsNullOrWhiteSpace($Tag)) {
    $Tag = "v$VersionName"
}

$distDir = Join-Path $projectRoot "dist"
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

Push-Location $projectRoot
try {
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter release build failed."
    }

    $sourceApk = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path -LiteralPath $sourceApk)) {
        throw "Release APK was not generated."
    }

    $apkName = "xiaohua-todo-$VersionName.apk"
    $apkPath = Join-Path $distDir $apkName
    Copy-Item -LiteralPath $sourceApk -Destination $apkPath -Force

    $headers = @{
        Accept = "application/vnd.github+json"
        Authorization = "Bearer $($env:GITHUB_TOKEN)"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $releaseBody = @{
        tag_name = $Tag
        name = "Xiaohua Todo $VersionName"
        body = $Changelog
        draft = $true
        prerelease = $false
    } | ConvertTo-Json
    $release = Invoke-RestMethod `
        -Method Post `
        -Uri "https://api.github.com/repos/$Repository/releases" `
        -Headers $headers `
        -ContentType "application/json" `
        -Body ([Text.Encoding]::UTF8.GetBytes($releaseBody))

    $uploadBase = ($release.upload_url -replace "\{\?name,label\}$", "")
    $encodedApkName = [Uri]::EscapeDataString($apkName)
    Invoke-RestMethod `
        -Method Post `
        -Uri "$uploadBase`?name=$encodedApkName" `
        -Headers $headers `
        -ContentType "application/vnd.android.package-archive" `
        -InFile $apkPath | Out-Null

    $hash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item -LiteralPath $apkPath).Length
    $manifest = [ordered]@{
        versionName = $VersionName
        versionCode = $VersionCode
        minSupportedVersionCode = $MinSupportedVersionCode
        apkUrl = "https://github.com/$Repository/releases/download/$Tag/$apkName"
        sha256 = $hash
        sizeBytes = $size
        changelog = $Changelog
        publishedAt = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json
    $manifestPath = Join-Path $distDir "update-manifest.json"
    [IO.File]::WriteAllText(
        $manifestPath,
        $manifest,
        (New-Object Text.UTF8Encoding($false))
    )

    Invoke-RestMethod `
        -Method Post `
        -Uri "$uploadBase`?name=update-manifest.json" `
        -Headers $headers `
        -ContentType "application/json" `
        -InFile $manifestPath | Out-Null

    $publishBody = @{ draft = $false } | ConvertTo-Json
    $published = Invoke-RestMethod `
        -Method Patch `
        -Uri "https://api.github.com/repos/$Repository/releases/$($release.id)" `
        -Headers $headers `
        -ContentType "application/json" `
        -Body ([Text.Encoding]::UTF8.GetBytes($publishBody))

    Write-Host "Published $($published.html_url)"
    Write-Host "APK SHA-256: $hash"
} finally {
    Pop-Location
}
