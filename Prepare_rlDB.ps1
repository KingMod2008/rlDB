param([string]$Destination = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$databaseRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$destinationRoot = [IO.Path]::GetFullPath($Destination)
if (-not (Test-Path -LiteralPath (Join-Path $databaseRoot 'items.json'))) { throw 'items.json is missing.' }
# Publish public files only, excluding runtime settings and caches.
$pluginRows = @()
$pluginSource = Join-Path $databaseRoot 'plugins'
foreach ($manifest in (Get-ChildItem -LiteralPath $pluginSource -Filter plugin.toml -File -Recurse | Where-Object { $_.FullName.Substring($pluginSource.Length + 1) -notmatch '^(cache|config|runtime)[\\/]' })) {
    $folder = $manifest.Directory.FullName
    $relative = $folder.Substring($databaseRoot.Length + 1).Replace('\','/')
    $text = [IO.File]::ReadAllText($manifest.FullName)
    $name = $manifest.Directory.Name; $version = '1.0'
    if ($text -match '(?m)^name\s*=\s*"([^"]+)"') { $name = $Matches[1] }
    if ($text -match '(?m)^version\s*=\s*"([^"]+)"') { $version = $Matches[1] }
    $files = @(Get-ChildItem -LiteralPath $folder -File -Recurse | Where-Object { $_.Extension -notin '.log','.tmp','.part' } | ForEach-Object {
        @{path=$_.FullName.Substring($databaseRoot.Length + 1).Replace('\','/'); bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    $pluginRows += @{plugin_id=$relative.Substring(8);folder=$relative;name=$name;version_number=$version;short_description='KingMod plugin';files=$files}
}
[IO.File]::WriteAllText((Join-Path $pluginSource 'index.json'), (ConvertTo-Json -InputObject @($pluginRows) -Depth 12), [Text.UTF8Encoding]::new($false))
if ($destinationRoot -ne $databaseRoot) {
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    # Clean only the cloned Git checkout, never the original database.
    if (Test-Path -LiteralPath (Join-Path $destinationRoot '.git')) {
        foreach ($relative in 'plugins/cache','plugins/config','plugins/runtime','image_export.log','image_progress.json','image_progress.tmp') {
            $cleanupPath = [IO.Path]::GetFullPath((Join-Path $destinationRoot $relative))
            if (-not $cleanupPath.StartsWith($destinationRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid cleanup path.' }
            if (Test-Path -LiteralPath $cleanupPath) { Remove-Item -LiteralPath $cleanupPath -Force -Recurse }
        }
    }
    foreach ($file in 'items.json','titles.json','paints.json','rarities.json','manifest.json','README.md','Update_rlDB.bat','Prepare_rlDB.ps1','Publish_KingMod.bat','Publish_KingMod.ps1','KingMod-Setup.exe') {
        $sourceFile = Join-Path $databaseRoot $file
        if (Test-Path -LiteralPath $sourceFile) { Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $destinationRoot $file) -Force }
    }
    foreach ($folder in 'images','catalogs','releases') {
        $sourceFolder = Join-Path $databaseRoot $folder
        if (Test-Path -LiteralPath $sourceFolder) {
            & robocopy $sourceFolder (Join-Path $destinationRoot $folder) /E /R:2 /W:1 /NFL /NDL /NJH /NJS | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "Copy failed: $folder" }
        }
    }
    foreach ($plugin in $pluginRows) {
        & robocopy (Join-Path $databaseRoot $plugin.folder) (Join-Path $destinationRoot $plugin.folder) /E /R:2 /W:1 /XF '*.log' '*.tmp' '*.part' /NFL /NDL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Copy failed: $($plugin.name)" }
    }
    Copy-Item -LiteralPath (Join-Path $pluginSource 'index.json') -Destination (Join-Path $destinationRoot 'plugins/index.json') -Force
    $patchSource = Join-Path $databaseRoot 'patches'
    New-Item -ItemType Directory -Path (Join-Path $destinationRoot 'patches') -Force | Out-Null
    foreach ($folder in 'balls','boosts','decals','cars') {
        $sourceFolder = Join-Path $patchSource $folder
        if (Test-Path -LiteralPath $sourceFolder) {
            & robocopy $sourceFolder (Join-Path $destinationRoot "patches/$folder") /E /R:2 /W:1 /XF '*.part' /NFL /NDL /NJH /NJS | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "Copy failed: patches/$folder" }
        }
    }
    Get-ChildItem -LiteralPath $patchSource -Filter '*-github.json' -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destinationRoot 'patches') -Force
    }
}
$large = @(Get-ChildItem -LiteralPath $destinationRoot -File -Recurse | Where-Object { $_.Length -gt 95MB -and $_.FullName -notmatch '[\\/]\.git[\\/]' })
if ($large.Count) { throw "Files exceed GitHub's file limit: $($large.Name -join ', '). Nothing pushed." }
Write-Host "Prepared public catalog, $($pluginRows.Count) plugin folders, images and four patch collections."
