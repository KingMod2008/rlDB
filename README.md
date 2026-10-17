# KingMod database

Public item and title metadata, item previews, Lua plugins and texture collections for KingMod.

- `items.json`, `titles.json`, `paints.json`, `rarities.json`: game database exports.
- `images/`: item previews produced by KingMod-Catalog-Images.exe.
- `catalogs/`: item-swapper metadata.
- `plugins/`: complete plugin folders; the uploader generates `plugins/index.json` with recursive file lists and SHA-256 checksums.
- `patches/balls/`, `patches/boosts/`, `patches/decals/`, `patches/cars/`: original patch ZIP archives and previews.
- `patches/*-github.json`: collection metadata using repository-relative paths and archive checksums.

Run `Update_rlDB.bat` to prepare a temporary checkout, commit the public files and push to KingMod2008/rlDB main. Git must be installed and authenticated. A failed upload leaves the temporary checkout for recovery and preserves this folder. Runtime plugin config, cache and runtime directories are excluded. The uploader does not execute any plugins or install game modifications.

The October 17, 2026 mirror contains 52 balls, 41 boost packs, 99 decal packs and 2 cars. Archives and preview images were downloaded from the public Hebnix patch catalog at the owner's request. Original authors, descriptions and any licenses inside archives are preserved; these assets retain their respective ownership and license terms.

KingMod can read this local mirror at E:\KingModITEMSdb, a KingModITEMSdb folder beside the EXE, or the folder selected by KINGMOD_DATABASE_PATH. Other installations fetch the same paths from GitHub.
