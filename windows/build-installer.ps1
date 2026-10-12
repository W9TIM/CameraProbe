# Publishes CameraProbe for Windows and builds the Inno Setup installer.
#
#   powershell -ExecutionPolicy Bypass -File windows\build-installer.ps1
#
# Output: windows\dist\CameraProbe-Setup-<version>.exe
# Needs the .NET 8 SDK and Inno Setup 6 (winget install JRSoftware.InnoSetup).

$ErrorActionPreference = 'Stop'

$dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
if (-not $dotnet) { $dotnet = "$env:ProgramFiles\dotnet\dotnet.exe" }

$iscc = (Get-Command ISCC -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
    $iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
              "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
              "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iscc) { throw 'Inno Setup not found. Install it with: winget install JRSoftware.InnoSetup' }

[xml]$props = Get-Content (Join-Path $PSScriptRoot 'Directory.Build.props')
$version = $props.Project.PropertyGroup.Version
$publish = Join-Path $PSScriptRoot 'publish'

if (Test-Path $publish) { Remove-Item $publish -Recurse -Force }

# Run from windows\ so global.json pins the .NET 8 SDK.
Push-Location $PSScriptRoot
try {
    & $dotnet publish CameraProbe.Cli\CameraProbe.Cli.csproj -c Release -r win-x64 --self-contained false -o $publish -nologo
    if ($LASTEXITCODE) { throw 'dotnet publish failed' }
} finally {
    Pop-Location
}

# Debug symbols aren't needed in the installer.
Get-ChildItem $publish -Filter *.pdb | Remove-Item

& $iscc "/DAppVersion=$version" "/DPublishDir=$publish" (Join-Path $PSScriptRoot 'installer\CameraProbe.iss')
if ($LASTEXITCODE) { throw 'ISCC failed' }

Write-Host "`nInstaller: $(Join-Path $PSScriptRoot "dist\CameraProbe-Setup-$version.exe")"
