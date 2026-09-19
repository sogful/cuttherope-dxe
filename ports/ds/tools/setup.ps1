$ErrorActionPreference = "Stop"
$dsroot = Split-Path $PSScriptRoot -Parent
$toolroot = Join-Path $dsroot ".tools"
$msysroot = Join-Path $toolroot "msys64"
New-Item -ItemType Directory -Force $toolroot | Out-Null
if (-not (Test-Path "$msysroot/usr/bin/bash.exe")) {
    $archive = Join-Path $toolroot "msys2.tar.xz"
    if (-not (Test-Path $archive)) {
        Invoke-WebRequest "https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.tar.xz" -OutFile $archive
    }
    & "C:/Program Files/7-Zip/7z.exe" x $archive "-o$toolroot" -y
    & tar -xf "$toolroot/msys2.tar" -C $toolroot
    if ($LASTEXITCODE) { throw "MSYS2 extraction failed" }
}
$bash = "$msysroot/usr/bin/bash.exe"
$env:MSYSTEM = "UCRT64"
$env:CHERE_INVOKING = "1"
& $bash -lc "true"
if ($LASTEXITCODE) { throw "MSYS2 initialization failed" }
$wonderful = "$msysroot/opt/wonderful"
if (-not (Test-Path "$wonderful/bin/wf-pacman.exe")) {
    New-Item -ItemType Directory -Force $wonderful | Out-Null
    $archive = Join-Path $toolroot "wonderful.tar.gz"
    Invoke-WebRequest "https://wonderful.asie.pl/bootstrap/wf-bootstrap-windows-x86_64.tar.gz" -OutFile $archive
    & tar -xf $archive -C $wonderful
    if ($LASTEXITCODE) { throw "Wonderful extraction failed" }
}
& $bash -lc "/opt/wonderful/bin/wf-pacman -Syu --noconfirm wf-tools"
if ($LASTEXITCODE) { throw "Wonderful package setup failed" }
if (-not (Test-Path "$wonderful/bin/wf-env")) {
    & $bash -lc "/opt/wonderful/bin/wf-pacman -Syu --noconfirm wf-tools"
    if ($LASTEXITCODE) { throw "Wonderful post-upgrade setup failed" }
}
& $bash -lc "source /opt/wonderful/bin/wf-env; wf-config repo enable blocksds; wf-pacman -Syu --noconfirm; wf-pacman -S --needed --noconfirm blocksds-toolchain"
if ($LASTEXITCODE) { throw "BlocksDS setup failed" }
Write-Output "BlocksDS installed locally in $wonderful"
