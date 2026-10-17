param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot '..\Hebnix src\Hebnix-Public-main\hebnix_rs'),
    [string]$Version = (Get-Date -Format 'yyyy.M.d.HHmm'),
    [switch]$NoPush,
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$setupRoot = [IO.Path]::GetFullPath((Join-Path $SourceRoot '..\KingMod-Setup-main'))
[void][Version]::Parse($Version)
if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Use a four-part numeric version.' }
$appSource = Join-Path $SourceRoot 'crates\hebnix-app\src\app.rs'
if (-not $SkipBuild) {
    $text = [IO.File]::ReadAllText($appSource)
    $text = [regex]::Replace($text, 'pub const APP_VERSION: &str = "[^"]+";', ('pub const APP_VERSION: &str = "' + $Version + '";'))
    [IO.File]::WriteAllText($appSource, $text, [Text.UTF8Encoding]::new($false))
    Push-Location $SourceRoot
    try { & cargo build -p hebnix-app --release --bin KingMod; if ($LASTEXITCODE) { throw 'Client build failed.' } }
    finally { Pop-Location }
    $msbuild = (Get-Command msbuild.exe -ErrorAction SilentlyContinue).Source
    if (-not $msbuild) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path -LiteralPath $vswhere) {
            $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -property installationPath
            if ($visualStudio) { $msbuild = Join-Path $visualStudio 'MSBuild\Current\Bin\MSBuild.exe' }
        }
    }
    if (-not $msbuild) { $msbuild = 'F:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' }
    if (-not (Test-Path -LiteralPath $msbuild)) { throw 'Install Visual Studio MSBuild and the .NET Framework 4.8 targeting pack.' }
    & $msbuild (Join-Path $setupRoot 'KingMod-Setup.csproj') /p:Configuration=Release /nologo /verbosity:minimal
    if ($LASTEXITCODE) { throw 'Setup build failed.' }
}
elseif ([IO.File]::ReadAllText($appSource) -notmatch ('pub const APP_VERSION: &str = "' + [regex]::Escape($Version) + '";')) { throw 'SkipBuild requires the version already compiled into the client.' }

$client = Join-Path $SourceRoot 'target\release\KingMod.exe'
$setup = Join-Path $setupRoot 'bin\Release\KingMod-Setup.exe'
foreach ($file in $client,$setup) { if (-not (Test-Path -LiteralPath $file)) { throw "Missing build: $file" } }
$releaseRoot = Join-Path $PSScriptRoot 'releases'
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
$zipName = "KingMod-$Version.zip"; $setupName = "KingMod-Setup-$Version.exe"
$zip = Join-Path $releaseRoot $zipName
if ((Test-Path -LiteralPath $zip) -or (Test-Path -LiteralPath (Join-Path $releaseRoot $setupName))) { throw 'This release version already exists. Publish a new version; existing release files are immutable.' }
$stage = Join-Path $PSScriptRoot ('.build\release-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -LiteralPath $client -Destination (Join-Path $stage 'KingMod.exe')
$license = Join-Path $SourceRoot '..\LICENSE.md'
if (-not (Test-Path -LiteralPath $license)) { $license = Join-Path $SourceRoot 'dist\KingMod-Collections-Client\LICENSE.md' }
Copy-Item -LiteralPath $license -Destination (Join-Path $stage 'LICENSE.md')
[IO.File]::WriteAllText((Join-Path $stage 'portable.txt'), 'KingMod portable data folder')
[IO.File]::WriteAllText((Join-Path $stage 'README.txt'), "KingMod $Version`r`nOpen KingMod Setup to install, update or remove the client. Close Rocket League before game-file changes. Custom title changes load when the game starts. Your settings are preserved during updates.`r`n")
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
Copy-Item -LiteralPath $setup -Destination (Join-Path $releaseRoot $setupName)
$prefix = 'https://raw.githubusercontent.com/KingMod2008/rlDB/main/releases/'
$manifest = [ordered]@{
    version=$Version;url=$prefix+$zipName;sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $zip).Length
    exe_sha256=(Get-FileHash -LiteralPath $client -Algorithm SHA256).Hash.ToLowerInvariant()
    setup_url=$prefix+$setupName;setup_sha256=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant();setup_bytes=(Get-Item -LiteralPath $setup).Length
}
if ($manifest.bytes -gt 96MB -or $manifest.setup_bytes -gt 8MB) { throw 'Release exceeds the download limit.' }
$manifestText = ConvertTo-Json -InputObject $manifest
[IO.File]::WriteAllText((Join-Path $releaseRoot "KingMod-$Version.json"),$manifestText,[Text.UTF8Encoding]::new($false))
# Update the channel only after both immutable downloads and checksums exist.
$latest = Join-Path $releaseRoot 'latest.json'
[IO.File]::WriteAllText(($latest+'.new'),$manifestText,[Text.UTF8Encoding]::new($false))
if (Test-Path -LiteralPath $latest) { [IO.File]::Replace(($latest+'.new'),$latest,$null) } else { [IO.File]::Move(($latest+'.new'),$latest) }
Copy-Item -LiteralPath $setup -Destination (Join-Path $PSScriptRoot 'KingMod-Setup.exe') -Force
Write-Host "Prepared KingMod $Version and its checked installer. No personal settings are in the package."
if (-not $NoPush) { & (Join-Path $PSScriptRoot 'Update_rlDB.bat'); if ($LASTEXITCODE) { throw 'GitHub upload failed. Prepared releases were preserved.' } }
