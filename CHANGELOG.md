KingMod — appearance, inventory and interface update

GAME OPTIONS AND COLOURS
- Extended FOV, distance and height sliders in Rocket League's own camera settings.
- Extra primary paint colours in the game's garage palette, including greyscale choices.
- An option to show original player names where the game supplies them locally.
- Restored fixed-value reported ping from the working backup. The applied value is saved and prepared before game launch; changing it requires restarting Rocket League and does not reduce real network delay.
- Custom wheel colours with a searchable image gallery and multiple wheel selection. Only selected supported wheel assets are changed; deselected wheels are restored.
- Custom Alpha Boost colour, plus grouped car, arena/HUD and ball appearance controls.
- Removed the ineffective underglow patch and its separate colour picker. Underglow is unavailable in this release.

SPAWNING AND PRESETS
- Item browsing with catalogue images, rarity colours, category/search filters, paint, quality, certification and quantity controls.
- Coloured title cards with corrected text alignment, title search and custom title text/glow controls.
- Automatic item-delivery setup, clearer pending/connected states and local spawned-item restoration.
- Catalogue-driven local drops, container contents and simulated reward delivery.
- Inventory sync/reset controls and saved item sets; camera presets are managed separately.
- Credit spawning and the experimental ball-prediction feature are removed.

PROFILE AND SHARED COSMETICS
- Expanded local rank response handling for ranked 1v1/2v2/3v3, Hoops, Rumble, Dropshot, Snow Day and tournaments.
- Division, MMR, placement and supported match/win/reward controls; missing and sparse local rating records can supply rank badge data.
- Ranked event playlists are discovered from game configuration. Casual Heatseeker has no ranked badge to change.
- Shared cosmetic exchange starts automatically when a compatible KingMod sync server is available. No settings switch or diagnostic panel is shown.

SWAPS AND CUSTOM IMAGES
- A separate Swap page for car, body, decal, boost and ball replacements.
- Body selection with catalogue previews for custom car replacements.
- Experimental local image replacements for supported banner packages, stadium advertisements and avatar widgets, including a local Epic-user avatar option.
- Select-all controls for supported banner and stadium-ad targets; original files are retained for restoration.

INTERFACE
- Reorganised pages into Spawn, Colours and Swap, with matching KingMod styling and icons.
- Grouped item/title/drop actions, colour controls and texture replacements on their own pages.
- Restored the Garage main-menu button and corrected native KingMod page alignment, scaling and full-size Discord/Back buttons.
- The native KingMod page contains KingMod text and the Discord link; colour/spawn controls are managed in the desktop app.
- Corrected item-image flickering and title-card text placement.
- Saved configuration and applied settings persist between sessions.

UPDATES AND RELIABILITY
- What's new is downloaded from rlDB's published release manifest and cached for offline viewing.
- In-app update notices offer download, installation and app restart; Setup provides install/reinstall/update handling and preserves settings.
- Plugin updates now require a newer version, compare KingMod revisions numerically and validate package/catalog agreement. Failed updates restore the previous enabled plugin.
- Plugins are distributed as authenticated encrypted Lua bytecode and assets; editable sources remain in the project.
- Removed Match Tools and Opponent/Player Boost from the public plugin catalogue and package folders.
- Improved game-folder setup diagnostics, certificate handling and connection recovery while preserving the working item/title and secure connection paths.
- Fixed native-menu/startup regressions and retired the earlier crashing underglow format.

Game-file appearance and camera changes require Rocket League to be closed while applying, then relaunched. Shared cosmetics require a compatible sync server. Some visual targets and live rank badge refreshes still need game-side testing.
