$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$WinRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$RepoRoot = Resolve-Path (Join-Path $WinRoot "..")
$OutDist = Join-Path $RepoRoot "dist\PhotoPic-Windows"

Push-Location $WinRoot
try {
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
    Write-Host "Build completed: $OutDist\PhotoPic.exe"
}
finally {
    Pop-Location
}
