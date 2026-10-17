# Window Widget 1.0.0

A Hebnix plugin for turning a normal Windows application window into a live
Rocket League overlay widget.

## Intended user flow

1. Install the plugin normally.
2. Open Window Widget.
3. Press Refresh Windows.
4. Pick Discord, Chrome, Spotify, Calculator, etc. from the dropdown.
5. Press Start Capture.
6. Enable Show Widget.
7. Adjust X, Y, width, height, opacity and FPS.

No companion EXE is required.

## Hebnix version

This build targets the new native `hebnix.capture` API introduced in the
Hebnix 2.2.x development build.

The public documentation page currently does not list the new capture endpoint
signatures, so `main.lua` contains a small compatibility adapter that accepts
the likely 2.2.x naming variants (`list_windows/windows/enumerate_windows`,
`start/create/open`, `frame/get_frame/current_frame`, `stop/destroy/close`).

If the final 2.2.1 API uses different names or argument order, only those
adapter calls need to be changed. The UI and plugin behaviour do not need to
change.

## Important

This package is not a claim that every 2.2.1 build has identical capture
signatures. The Hebnix developer should test it against the exact 2.2.1
capture implementation before publishing.
