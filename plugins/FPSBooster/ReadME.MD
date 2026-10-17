# FPS Booster

A Hebnix plugin that swaps Rocket League's `TASystemSettings.ini` with a
performance-oriented preset. Raises FPS by 20–70% depending on hardware by
disabling heavy visual effects (dynamic shadows, ambient occlusion, bloom,
light shafts, decals).

## Requirements

- Hebnix 2.1.8 or newer
- Rocket League closed before applying a preset

## Bundled presets

| Preset | Description |
|---|---|
| `DarkFPS.ini` | Balanced FPS boost with moderate visual changes |
| `ExtremeFPS.ini` | Aggressive low-end preset; expect a blurrier image |

## Usage

1. Open Hebnix → Plugins → FPS Booster → Settings.
2. Select a preset from the dropdown.
3. Adjust display settings if desired (Resolution, Render %, Fullscreen/Borderless).
4. Close Rocket League.
5. Click **Set**.
6. Relaunch Rocket League.

## Adding your own presets

Any `.ini` file dropped into the plugin's `assets/` folder appears in the
dropdown. Click **Open Folder**, paste the file, then click **Refresh**.

## Restoring

**Restore Original** reverts the config using the `.bak` file Hebnix creates
automatically on the first write.

## Support

If something breaks, ping `@eightiesl` on the Hebnix Discord.