$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$WinRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$RepoRoot = Resolve-Path (Join-Path $WinRoot "..")
$OutDist = Join-Path $RepoRoot "dist\PhotoPic-Windows"
$BuildMetaPath = Join-Path $WinRoot "build_version.json"

Push-Location $WinRoot
try {
    $BaseVer = (Get-Content "$RepoRoot\VERSION" -Raw).Trim()
    $BuildNum = [int](git rev-list --count HEAD)
    $ShortSha = (git rev-parse --short HEAD).Trim()
    $FullVer = "$BaseVer.$BuildNum"

    @{
        version = $FullVer
        build_number = $BuildNum
        commit_sha = $ShortSha
        repository = "stevensb2003-afk/PhotoPic"
    } | ConvertTo-Json | Set-Content -Path $BuildMetaPath -Encoding UTF8

    python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    pyinstaller `
      --noconfirm `
      --clean `
      --windowed `
      --name "PhotoPic" `
      --icon "$WinRoot\assets\AppIcon.ico" `
      --add-data "$RepoRoot\assets\icons;assets\icons" `
      --add-data "$WinRoot\assets\AppIcon.ico;assets" `
      --add-data "$WinRoot\scripts\wpd_bridge.ps1;scripts" `
      --add-data "$BuildMetaPath;." `
      --collect-data "mediapipe" `
      --hidden-import "rawpy" `
      --hidden-import "pillow_heif" `
      --distpath "$RepoRoot\dist" `
      run_photopic.py
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if (Test-Path "$RepoRoot\dist\PhotoPic") {
        if (Test-Path $OutDist) { Remove-Item -Recurse -Force $OutDist }
        Rename-Item "$RepoRoot\dist\PhotoPic" "PhotoPic-Windows"
    }
    Write-Host "Build completed ($FullVer build $BuildNum): $OutDist\PhotoPic.exe"
}
finally {
    if (Test-Path $BuildMetaPath) { Remove-Item -Force $BuildMetaPath }
    Pop-Location
}
