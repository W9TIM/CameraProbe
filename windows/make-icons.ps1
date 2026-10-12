# Regenerates the Windows .ico files with ImageMagick. The outputs are
# committed, so this only needs re-running when the artwork changes.
#
#   AppIcon.ico     exe / installer / window icon, from the PNGs already
#                   rendered for macOS in Resources/AppIcon.iconset
#   TrayIdle.ico    tray icon, camera idle    (from Assets/TrayIdle.svg)
#   TrayActive.ico  tray icon, camera in use  (from Assets/TrayActive.svg)
#
# Tray icons include every size Windows picks between 100% and 300% scaling.

$ErrorActionPreference = 'Stop'

$magick = (Get-Command magick -ErrorAction SilentlyContinue).Source
if (-not $magick) { $magick = Get-ChildItem "$env:ProgramFiles\ImageMagick*\magick.exe" | Select-Object -First 1 -ExpandProperty FullName }
if (-not $magick) { throw 'ImageMagick not found. Install it with: winget install ImageMagick.ImageMagick' }

$iconset = Join-Path $PSScriptRoot '..\Resources\AppIcon.iconset'
$assets  = Join-Path $PSScriptRoot 'CameraProbe.Windows\Assets'

& $magick `
    (Join-Path $iconset 'icon_16x16.png') `
    (Join-Path $iconset 'icon_32x32.png') `
    '(' (Join-Path $iconset 'icon_256x256.png') -resize 48x48 ')' `
    '(' (Join-Path $iconset 'icon_256x256.png') -resize 64x64 ')' `
    (Join-Path $iconset 'icon_128x128.png') `
    (Join-Path $iconset 'icon_256x256.png') `
    (Join-Path $assets 'AppIcon.ico')
if ($LASTEXITCODE) { throw "magick failed building AppIcon.ico" }

foreach ($name in 'TrayIdle', 'TrayActive') {
    $svg = Join-Path $assets "$name.svg"
    $sizes = 16, 20, 24, 32, 40, 48
    $layers = foreach ($s in $sizes) { '(' ; '-background'; 'none'; '-density'; '384'; $svg; '-resize'; "${s}x${s}"; ')' }
    & $magick @layers (Join-Path $assets "$name.ico")
    if ($LASTEXITCODE) { throw "magick failed building $name.ico" }
}

Write-Host "Icons written to $assets"
