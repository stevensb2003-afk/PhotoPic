$ErrorActionPreference = "Stop"
$WinRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$RepoRoot = Resolve-Path (Join-Path $WinRoot "..")
$OutDist = Join-Path $RepoRoot "dist\PhotoPic-Windows"

Set-Location $WinRoot
python -m pip install --upgrade pip
pip install -r requirements.txt

pyinstaller `
  --noconfirm `
  --clean `
  --windowed `
  --name "PhotoPic" `
  --icon "$WinRoot\assets\AppIcon.ico" `
  --add-data "$RepoRoot\assets\icons;assets\icons" `
  --add-data "$WinRoot\scripts\wpd_bridge.ps1;scripts" `
  --distpath "$RepoRoot\dist" `
  photopic_win\main.py

if (Test-Path "$RepoRoot\dist\PhotoPic") {
    if (Test-Path $OutDist) { Remove-Item -Recurse -Force $OutDist }
    Rename-Item "$RepoRoot\dist\PhotoPic" "PhotoPic-Windows"
}
Write-Host "Build completed: $OutDist\PhotoPic.exe"
