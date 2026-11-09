KingMod 2026.11.09.0015 - Item spawning, Free events and workshop maps

- Added Spawn All for the current item or title search and filters, with one of each result and default attributes. Notify controls whether new items show an in-game popup or arrive quietly.
- Improved queued item delivery, inventory refresh handling and redelivery after starting a new game session. Genuine inventory and progression stay intact; KingMod-created local drops have been removed.
- Free mode opens without a key or server connection. Added support for signed, timed owner Free events that enable Premium while active and return event users to Free when they end. Paid keys keep their own access and expiry.
- Free clients can receive signed announcements. Temporary service outages preserve remembered keys and saved Premium preferences while access is rechecked.
- Browse and download BakkesPlugins workshop maps with creator links, progress, retry, favorites and a downloaded library. Load maps while Rocket League is closed and restore the original arena when finished.
- Added prepared workshop map entries to Join LAN Match and map checks/sharing for friends on the same LAN or an existing private VPN. Internet play requires a shared Tailscale or ZeroTier connection. Live local hosting and a real two-PC match still need in-game verification.
- Faster setup verification, progress with elapsed/remaining time, automatic reviewed compatibility checks and recovery for previous-build profile records. The original-game reset barrier remains in place.

Close Rocket League before updating. Existing settings and recovery data are preserved. Free-event and continuous announcement support also require the matching license-server update; publishing this client does not deploy that server update.

---

KingMod 2026.11.06.0011 - Faster setup, progress and BakkesPlugins maps

- Preparation and verification now show a 0-100% progress bar, the current step, elapsed time and estimated time remaining.
- Current profile checks decode the game package once. Verified unchanged packages reuse checks after restart, and unchanged options avoid rebuilding the profile.
- Fixed previous-build profile records blocking setup. KingMod preserves old recovery records and reapplies saved options against verified current item support.
- Compatibility checks refresh the reviewed catalog automatically, with cached support offline. Supported Steam/Epic package compression changes can be recognized without launcher verification. Compatible changes prepare after Rocket League closes; temporary failures retry.
- Browse maps from BakkesPlugins with creator credit, map links and background thumbnail loading. Removed Import Map and the Multiplayer page from Maps.
- Added letters jumping into KingMod in order and a final whole-word shake. Telegram notification and Rizz intro sounds are embedded, with mute, volume and reduced-motion controls.
- Saved Premium preferences survive temporary service outages and can reapply when verified access returns.
- The database updater lists numbered dump folders for selection and fixes staging failures while retaining the checkout. The call inspector exports function and PsyNet method diagnostics.

47 targeted checks passed and three previews were checked. Repeat read-only verification measured about 0.33 seconds versus about 2 seconds uncached on an isolated release fixture; this does not measure first installation or game launch. In-game behavior, production atomic recovery and a real Epic installation still need testing. Unknown future script changes may require a reviewed compatibility catalog or a new client.

Close Rocket League before updating. Existing settings and original-game reset state are preserved. To play a loaded map, select the same replacement arena in Training > Free Play.

---

KingMod 2026.10.28.0005 - Fixed menu flickering and typing

- Fixed the menu shaking or refreshing while Rocket League is running.
- Fixed custom-title and search fields losing focus while typing. You can keep typing without clicking the field again.
- Fixed in-game menu input being interrupted by background inventory updates.

Close Rocket League before updating, then reopen KingMod to load the fix. Your existing settings are preserved.

---

KingMod 2026.10.28.0004 - Premium player names and clearer title guidance

KingMod now opens without a key. Free mode includes local item spawning, your own local item customizations, and the Garage title collection. Activate Premium in Settings > Free & Premium.

- Original player names is now Premium-only, including saved settings, pending changes and automatic expiry reset. Camera slider and colour options remain available in Free mode.
- Added a clear Free-mode notice to the desktop and in-game item/title menus: spawned items show locally in matches; custom titles and normal titles from KingMod need Premium for match display.
- Refreshed interface with animated KingMod branding, a skippable startup animation, and an optional announcement chime.
- Paid controls are visibly locked in Free mode. Premium covers match titles and shared Premium cosmetics, ping customization, opponent boost, Original player names, Rocket Pass display overrides, KingMod drop spawning/opening, rank and season-reward display changes, and hiding goal explosions or demolition smoke.
- Expired or revoked Premium access now resets paid settings automatically. Queued paid drops are cancelled, old requests cannot reapply them, and paid options stay off after renewal until you enable them again.
- The reset survives restarting KingMod and retries settings that could not be saved. Free item/title collections, genuine Rocket League inventory and drops, Sync Inventory, and restoration remain available.
- Fixed the drop selector closing when clicking or typing in its search field.
- Removed the old Profile title spoofer. The Garage title collection remains available.
- Fixed Open KingMod in original-game mode so an incomplete reset no longer blocks access to the normal app. Reset reports and backups are retained.

Close Rocket League before updating or changing tiers so previously loaded native changes can be restored or rebuilt.
