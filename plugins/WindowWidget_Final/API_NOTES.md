# Native capture API expected by Window Widget

The Hebnix developer said the new endpoints live under `hebnix.capture`.

The plugin expects the native layer to provide equivalent operations:

- enumerate visible Windows
- start/open a capture for a selected window
- obtain the latest frame
- stop/close/destroy the capture
- expose the frame to the overlay draw API

Preferred shape:

```lua
hebnix.capture.list_windows()
hebnix.capture.start(window_id, {
    fps = 30,
    cursor = false
})
hebnix.capture.frame(handle)
hebnix.capture.stop(handle)
```

The overlay should accept the native frame as a texture:

```lua
draw.capture_image(
    frame,
    x, y, width, height,
    { opacity = 1.0 }
)
```

If the native API uses different names, edit the adapter functions in
`main.lua`. The rest of the plugin is independent of the exact native names.
