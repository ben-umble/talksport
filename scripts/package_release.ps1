param(
    [string]$Flutter = "flutter",
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$Label
    )

    Write-Host $Label
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
$Pubspec = Join-Path $RepoRoot "pubspec.yaml"

if ([string]::IsNullOrWhiteSpace($Version)) {
    $VersionLine = Select-String -Path $Pubspec -Pattern "^version:\s*(.+)$" |
        Select-Object -First 1
    if ($null -eq $VersionLine) {
        throw "Could not find version in pubspec.yaml."
    }
    $Version = $VersionLine.Matches[0].Groups[1].Value.Trim()
}

$SemVer = ($Version -split "\+")[0]
$Tag = "v$SemVer"
$DistRoot = Join-Path $RepoRoot "dist"
$ReleaseDir = Join-Path $DistRoot "release\$Tag"
$StageDir = Join-Path $DistRoot "stage"
$WindowsStage = Join-Path $StageDir "talksport-companion-windows-x64"
$WindowsBuild = Join-Path $RepoRoot "build\windows\x64\runner\Release"
$AndroidReleaseApk = Join-Path $RepoRoot "build\app\outputs\flutter-apk\app-release.apk"
$WindowsZip = Join-Path $ReleaseDir "talksport-companion-windows-x64-$Tag.zip"
$AndroidApk = Join-Path $ReleaseDir "talksport-companion-android-$Tag.apk"
$Checksums = Join-Path $ReleaseDir "SHA256SUMS.txt"

Remove-Item -LiteralPath $ReleaseDir, $StageDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $ReleaseDir, $WindowsStage | Out-Null

$RunningApp = Get-Process -Name "talksport_companion" -ErrorAction SilentlyContinue
if ($RunningApp) {
    Write-Host "Stopping running talkSPORT Companion process before packaging..."
    $RunningApp | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

Push-Location $RepoRoot
try {
    Invoke-External -FilePath $Flutter -Arguments @("pub", "get") -Label "Resolving Flutter dependencies"
    Invoke-External -FilePath $Flutter -Arguments @("build", "windows", "--release") -Label "Building Windows release"
    Invoke-External -FilePath $Flutter -Arguments @("build", "apk", "--release") -Label "Building Android release APK"
} finally {
    Pop-Location
}

Copy-Item -Path (Join-Path $WindowsBuild "*") -Destination $WindowsStage -Recurse -Force
Compress-Archive -Path $WindowsStage -DestinationPath $WindowsZip -Force
Copy-Item -Path $AndroidReleaseApk -Destination $AndroidApk -Force

$Artifacts = @($WindowsZip, $AndroidApk)
$HashLines = foreach ($Artifact in $Artifacts) {
    $Hash = Get-FileHash -Path $Artifact -Algorithm SHA256
    "$($Hash.Hash.ToLowerInvariant())  $(Split-Path -Leaf $Artifact)"
}
$HashLines | Set-Content -Path $Checksums -Encoding UTF8

Write-Host "Release artifacts written to $ReleaseDir"
Get-ChildItem -Path $ReleaseDir | Select-Object Name, Length
