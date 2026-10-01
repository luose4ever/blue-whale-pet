param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist'))
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$inline = ((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manage.ps1')) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }) -join ' '
if ($inline.Contains('"') -or $inline.Contains('%')) { throw 'Unexpected inline-command delimiter' }
$launcher = @('@echo off', 'setlocal DisableDelayedExpansion', 'set "BLUE_WHALE_ACTION=%~1"', 'set "BLUE_WHALE_HOME=%~2"', 'set "BLUE_WHALE_REPLACE=%~3"', 'set "BLUE_WHALE_PACKAGE=%~dp0.."', ('powershell.exe -NoLogo -NoProfile -Command "& { ' + $inline + ' }"'), 'exit /b %errorlevel%')
if ($launcher[6].Length -gt 7900) { throw 'Command exceeds the supported Windows command length' }
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'manage.cmd'), $launcher, [Text.Encoding]::ASCII)
$files = @('.gitignore', '.gitattributes', 'README.md', 'LICENSE', 'ASSET-NOTICE.md', 'checksums.json', 'install.cmd', 'uninstall.cmd', 'pet\pet.json', 'pet\spritesheet.png', 'preview\all-states.gif', 'scripts\manage.ps1', 'scripts\manage.cmd', 'scripts\build-package.ps1', 'tests\install.Tests.ps1')
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$zipPath = Join-Path $outputRoot 'blue-whale-pet-v1.0.0-windows.zip'
if (Test-Path -LiteralPath $zipPath) { throw 'Output already exists; choose another output directory' }
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$stage = Join-Path $outputRoot ('package-stage-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $stage 'blue-whale-pet'
try {
    foreach ($file in $files) {
        $destination = Join-Path $package $file
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $destination
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $expected = @($files | ForEach-Object { 'blue-whale-pet/' + $_.Replace('\', '/') } | Sort-Object)
        $actual = @($archive.Entries | ForEach-Object { $_.FullName } | Sort-Object)
        if (Compare-Object $expected $actual) { throw 'ZIP contents do not match the release whitelist' }
    } finally { $archive.Dispose() }
    $digest = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $outputRoot 'SHA256SUMS.txt'), $digest + '  blue-whale-pet-v1.0.0-windows.zip' + [Environment]::NewLine, [Text.Encoding]::ASCII)
    Write-Host ('Verified package: ' + $zipPath)
    Write-Host ('SHA256: ' + $digest)
} finally {
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if (-not $resolvedStage.StartsWith($outputRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe stage directory' }
    if (Test-Path -LiteralPath $resolvedStage) { Remove-Item -LiteralPath $resolvedStage -Recurse -Force }
}
