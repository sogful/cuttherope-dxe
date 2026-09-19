param(
    [string]$SourceCommit = "90fe6a53c154448e63f0a9efdd045e31e83badfc"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$assetRoot = Join-Path $repositoryRoot "ports\android\assets"
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ctrdx-android-assets-" + [guid]::NewGuid().ToString("N"))
$archive = Join-Path $temporaryRoot "assets.tar"

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $assetRoot -Force | Out-Null

    Push-Location $repositoryRoot
    try {
        git cat-file -e "$SourceCommit`^{commit}"
        if ($LASTEXITCODE -ne 0) {
            throw "Android asset commit $SourceCommit is not available. Fetch the full repository history first."
        }

        git archive --format=tar --output=$archive $SourceCommit assets
        if ($LASTEXITCODE -ne 0) {
            throw "Could not export Android assets from $SourceCommit."
        }
    }
    finally {
        Pop-Location
    }

    tar -xf $archive -C $temporaryRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Could not extract the Android asset archive."
    }

    $sourceRoot = Join-Path $temporaryRoot "assets"
    $copied = 0
    $existing = 0
    foreach ($source in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse) {
        $relative = [System.IO.Path]::GetRelativePath($sourceRoot, $source.FullName)
        $destination = Join-Path $assetRoot $relative
        if (Test-Path -LiteralPath $destination) {
            $existing++
            continue
        }

        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination $destination
        $copied++
    }

    Write-Output "Android assets ready: $copied restored, $existing already present."
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
