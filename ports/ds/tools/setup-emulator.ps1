$ErrorActionPreference = "Stop"
$dsroot = Split-Path $PSScriptRoot -Parent
$directory = Join-Path $dsroot ".tools/libretro"
New-Item -ItemType Directory -Force $directory | Out-Null
$archive = Join-Path $directory "core.zip"
Invoke-WebRequest "https://buildbot.libretro.com/nightly/windows/x86_64/latest/melondsds_libretro.dll.zip" -OutFile $archive -TimeoutSec 120
Expand-Archive -LiteralPath $archive -DestinationPath $directory -Force
$core = Join-Path $directory "melondsds_libretro.dll"
if (-not (Test-Path -LiteralPath $core)) { throw "The downloaded archive did not contain the melonDS DS core" }
Get-FileHash -LiteralPath $core -Algorithm SHA256
Write-Output "Windowless test core installed in $directory. Test reports record its hash."
