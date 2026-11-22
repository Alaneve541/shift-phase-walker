$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    node --test test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed; no package was created.' }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $output = Join-Path $PSScriptRoot "SHIFT-Phase-Walker-HTML5-$stamp.zip"
    $archive = [IO.Compression.ZipFile]::Open($output, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in @('index.html', 'LICENSE')) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, (Join-Path $PSScriptRoot $file), $file,
                [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    } finally { $archive.Dispose() }
    Write-Host "HTML5 package ready: $output"
    Write-Host 'Upload as an HTML game on itch.io, then submit the published game to the jam.'
} finally { Pop-Location }
