param (
    [string]$TexconvUrl = "https://github.com/microsoft/DirectXTex/releases/latest/download/texconv.exe",
    [string]$TexconvPath = ".\texconv.exe",
    [string]$SourceDir = ".\raw_assets",
    [string]$OutputDir = ".\textures"
)

Write-Host "FS25 DDS Asset Converter"
Write-Host "========================"

if (-not (Test-Path $TexconvPath)) {
    Write-Host "Downloading texconv.exe from $TexconvUrl ..."
    Invoke-WebRequest -Uri $TexconvUrl -OutFile $TexconvPath
    if (-not (Test-Path $TexconvPath)) {
        Write-Error "Failed to download texconv.exe."
        exit 1
    }
}

if (-not (Test-Path $SourceDir)) {
    Write-Host "Source directory '$SourceDir' not found. Creating it..."
    New-Item -ItemType Directory -Force -Path $SourceDir | Out-Null
    Write-Host "Please place your raw .png files in '$SourceDir' and run this script again."
    exit 0
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

$pngFiles = Get-ChildItem -Path $SourceDir -Recurse -Filter *.png

if ($pngFiles.Count -eq 0) {
    Write-Host "No .png files found in '$SourceDir'."
    exit 0
}

Write-Host "Found $($pngFiles.Count) PNG files. Starting conversion to BC7 DDS..."

foreach ($file in $pngFiles) {
    $relativePath = $file.DirectoryName.Substring((Get-Item $SourceDir).FullName.Length)
    $destPath = Join-Path $OutputDir $relativePath
    
    if (-not (Test-Path $destPath)) {
        New-Item -ItemType Directory -Force -Path $destPath | Out-Null
    }

    Write-Host "Converting $($file.Name)..."
    # FS25 Standard: BC7 compression, Generate Mipmaps, overwrite existing
    # -f BC7_UNORM: Format BC7
    # -pmalpha: Premultiply alpha (sometimes needed, but let's use standard first)
    # -m 0: Full mipmap chain
    # -y: Overwrite
    & $TexconvPath -f BC7_UNORM -m 0 -y -o $destPath $file.FullName
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to convert $($file.Name)"
    }
}

Write-Host "Done! All files converted."
