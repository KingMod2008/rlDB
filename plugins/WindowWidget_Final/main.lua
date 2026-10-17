local plugin = {}

local windows = {}
local capture_handle = nil
local selected_id = ""
local status = "Not started"
local refresh_requested = false

local function safe_call(fn, ...)
    if type(fn) ~= "function" then
        return nil, "missing"
    end

    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return nil, tostring(a)
    end

    return a, b, c
end

local function capture_api()
    return hebnix.capture
end

local function refresh_windows()
    local cap = capture_api()
    if not cap then
        windows = {}
        status = "hebnix.capture is unavailable"
        return
    end

    local list, err

    -- Accept the common naming variants while the 2.2.1 capture API settles.
    if type(cap.list_windows) == "function" then
        list, err = safe_call(cap.list_windows)
    elseif type(cap.windows) == "function" then
        list, err = safe_call(cap.windows)
    elseif type(cap.enumerate_windows) == "function" then
        list, err = safe_call(cap.enumerate_windows)
    end

    if type(list) ~= "table" then
        windows = {}
        status = err or "No Windows returned"
        return
    end

    windows = list
    status = "Found " .. tostring(#windows) .. " Windows"
end

local function window_id(w)
    return w.id or w.hwnd or w.handle or w.window_id or ""
end

local function window_label(w)
    local title = w.title or w.name or "Untitled Window"
    local process = w.process or w.process_name or w.exe or ""
    if process ~= "" then
        return title .. "  [" .. process .. "]"
    end
    return title
end

local function stop_capture()
    if not capture_handle then
        return
    end

    local cap = capture_api()
    if cap then
        if type(cap.stop) == "function" then
            safe_call(cap.stop, capture_handle)
        elseif type(cap.destroy) == "function" then
            safe_call(cap.destroy, capture_handle)
        elseif type(cap.close) == "function" then
            safe_call(cap.close, capture_handle)
        end
    end

    capture_handle = nil
end

local function start_capture(id)
    stop_capture()

    local cap = capture_api()
    if not cap then
        status = "Capture API unavailable"
        return
    end

    local fps = hebnix.get_number("ww_fps", 30)

    local handle, err

    if type(cap.start) == "function" then
        handle, err = safe_call(cap.start, id, {
            fps = fps,
            cursor = hebnix.get_bool("ww_cursor", false)
        })
    elseif type(cap.create) == "function" then
        handle, err = safe_call(cap.create, id, {
            fps = fps,
            cursor = hebnix.get_bool("ww_cursor", false)
        })
    elseif type(cap.open) == "function" then
        handle, err = safe_call(cap.open, id, {
            fps = fps,
            cursor = hebnix.get_bool("ww_cursor", false)
        })
    end

    if handle == nil then
        status = "Could not start capture: " .. tostring(err or "unsupported")
        return
    end

    capture_handle = handle
    selected_id = tostring(id)
    hebnix.set("ww_selected_id", selected_id)
    status = "Capturing"
end

local function get_frame()
    if not capture_handle then
        return nil
    end

    local cap = capture_api()
    if not cap then
        return nil
    end

    local frame

    if type(cap.frame) == "function" then
        frame = select(1, safe_call(cap.frame, capture_handle))
    elseif type(cap.get_frame) == "function" then
        frame = select(1, safe_call(cap.get_frame, capture_handle))
    elseif type(cap.current_frame) == "function" then
        frame = select(1, safe_call(cap.current_frame, capture_handle))
    end

    return frame
end

local function draw_capture(draw, frame, x, y, w, h, opacity)
    if not frame then
        return false
    end

    -- Native 2.2.1 builds may expose the frame as a draw texture.
    if type(draw.capture_image) == "function" then
        local ok = pcall(
            draw.capture_image,
            draw,
            frame,
            x, y, w, h,
            { opacity = opacity }
        )
        if ok then
            return true
        end
    end

    if type(draw.image) == "function" then
        local ok = pcall(
            draw.image,
            draw,
            frame,
            x, y, w, h,
            { opacity = opacity }
        )
        if ok then
            return true
        end
    end

    return false
end

function plugin.on_load()
    hebnix.window.open({
        title = "Window Widget",
        width = 620,
        height = 560,
        opacity = 0.96
    })

    selected_id = hebnix.get_string("ww_selected_id", "")
    refresh_windows()

    hebnix.log("[Window Widget] loaded")
end

function plugin.on_settings(ui)
    ui.heading("Window Widget")

    ui.label("Turn any Windows app into a Rocket League overlay widget.")

    local enabled = ui.checkbox(
        "ww_enabled",
        "Show widget",
        true
    )

    ui.checkbox(
        "ww_cursor",
        "Capture mouse cursor",
        false
    )

    ui.separator()

    local fps = ui.slider(
        "ww_fps",
        "Capture FPS",
        10,
        60,
        30
    )

    local x = ui.slider(
        "ww_x",
        "Widget X",
        0,
        3840,
        40
    )

    local y = ui.slider(
        "ww_y",
        "Widget Y",
        0,
        2160,
        40
    )

    local width = ui.slider(
        "ww_width",
        "Widget width",
        160,
        1920,
        640
    )

    local height = ui.slider(
        "ww_height",
        "Widget height",
        100,
        1080,
        360
    )

    local opacity = ui.slider(
        "ww_opacity",
        "Widget opacity",
        10,
        100,
        100
    )

    ui.separator()
    ui.label("FPS: " .. tostring(fps))
    ui.label("Position: " .. tostring(x) .. ", " .. tostring(y))
    ui.label("Size: " .. tostring(width) .. " x " .. tostring(height))
    ui.label("Opacity: " .. tostring(opacity) .. "%")

    if not enabled then
        stop_capture()
    end
end

function plugin.on_window(ui)
    ui.heading("Window Widget")

    ui.label("Choose a Windows window")

    if ui.button("Refresh Windows") then
        refresh_requested = true
    end

    if refresh_requested then
        refresh_windows()
        refresh_requested = false
    end

    if #windows == 0 then
        ui.label("No Windows found")
        ui.label("Try Refresh Windows")
    else
        local options = {}

        for _, w in ipairs(windows) do
            table.insert(options, window_label(w))
        end

        local selected_label =
            ui.combo_box(
                "ww_selected_window",
                "Window",
                options
            )

        for _, w in ipairs(windows) do
            if window_label(w) == selected_label then
                local id = window_id(w)

                if tostring(id) ~= tostring(selected_id) then
                    start_capture(id)
                end
                break
            end
        end
    end

    ui.separator()

    ui.label("Status: " .. status)

    if capture_handle then
        if ui.button("Stop Capture") then
            stop_capture()
            status = "Stopped"
        end
    else
        if ui.button("Start Capture") then
            local stored = hebnix.get_string(
                "ww_selected_id",
                ""
            )

            if stored ~= "" then
                start_capture(stored)
            else
                status = "Select a window first"
            end
        end
    end

    if ui.button("Open / Close Widget") then
        if hebnix.window.is_open() then
            hebnix.window.close()
        else
            hebnix.window.open()
        end
    end

    ui.separator()
    ui.label("The selected app is rendered over Rocket League.")
    ui.label("Move and resize the widget with the settings above.")
end

function plugin.on_tick()
    if not hebnix.get_bool("ww_enabled", true) then
        return
    end

    if not capture_handle and selected_id ~= "" then
        start_capture(selected_id)
    end
end

function plugin.on_overlay(draw)
    if not hebnix.get_bool("ww_enabled", true) then
        return
    end

    local frame = get_frame()

    if not frame then
        return
    end

    local x = hebnix.get_number("ww_x", 40)
    local y = hebnix.get_number("ww_y", 40)
    local w = hebnix.get_number("ww_width", 640)
    local h = hebnix.get_number("ww_height", 360)
    local opacity =
        hebnix.get_number("ww_opacity", 100) / 100

    if not draw_capture(
        draw,
        frame,
        x, y, w, h,
        opacity
    ) then
        status = "Capture frame received but draw API rejected it"
    end
end

function plugin.on_unload()
    stop_capture()
    hebnix.window.close()
    hebnix.log("[Window Widget] unloaded")
end

return plugin
