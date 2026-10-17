-- main.lua
-- FPS Booster
-- Swaps Rocket League's TASystemSettings.ini with a preset from the plugin's
-- assets folder, using Hebnix's native rl_config API.
--
--- Version 3.1.1 ---
--  v3.1.1:
--  - ScreenPercentage written as integer (S24 save file expects int, not float)
--  - Removed diagnostic dump
--
--  v3.1.0:
--  - Added Bright preset (FPS gain without the dark visual change)
--  - Recovery is now a preset entry ("Original") using the standard Apply flow
--  - Fixed Cinematic crash (FloatingPointRenderTargets mismatch)
--  - Rebuilt preset badge with precise text measurement
--  - Removed experimental Ultra preset (driver incompatibility)
--  - Renamed "Render Resolution %" to "Render Quality"

local plugin = {}
local PLUGIN_NAME = "FPS Booster"
local CONFIG_NAME = "TASystemSettings"
local SUPPORT_HANDLE = "@eightiesl"

local DEFAULT_RES_X      = 1920
local DEFAULT_RES_Y      = 1080
local DEFAULT_SCREEN_PCT = 100
local DEFAULT_FULLSCREEN = true
local DEFAULT_BORDERLESS = false

local RESERVED = {}

local PRESET_INFO = {
    ["original.ini"] = {
        label      = "Original",
        category   = "Recovery",
        desc       = "Fresh vanilla config. Use this if Rocket League won't start after applying a preset.",
        screen_pct = nil,
        color      = "#e74c3c",
    },
    ["BrightFPS.ini"] = {
        label      = "Bright",
        category   = "FPS",
        desc       = "15-25% FPS gain with no visual change. Only disables shadows and post-processing.",
        screen_pct = 100,
        color      = "#55ff88",
        note       = "Keeps vanilla lighting and colors. The ball, cars, and arena look the same as default.",
    },
    ["DarkFPS.ini"] = {
        label      = "Balanced",
        category   = "FPS",
        desc       = "20-30% FPS gain. Mild visual change. Safe on all hardware.",
        screen_pct = 85,
        color      = "#5dade2",
        note       = "Renders the ball, cars, and shadows with a distinctly dark / black tone. If you want FPS without the dark look, choose Bright.",
    },
    ["ExtremeFPS.ini"] = {
        label      = "Extreme",
        category   = "FPS",
        desc       = "50-70% FPS gain. Aggressive visuals. Best for low-end PCs.",
        screen_pct = 60,
        color      = "#ff8c42",
        note       = "Renders the ball, cars, and shadows with a very dark / black tone. Aggressive visual cuts across the board. If you want FPS without the dark look, choose Bright.",
    },
    ["Vibrant.ini"] = {
        label      = "Vibrant",
        category   = "Competitive",
        desc       = "Max clarity. Sharp textures, no haze. Great for ranked and streaming.",
        screen_pct = 100,
        color      = "#ff3b9c",
        warning    = "Needs a dedicated GPU. Not recommended on integrated graphics.",
    },
    ["Cinematic.ini"] = {
        label      = "Cinematic",
        category   = "Broadcast",
        desc       = "Max fidelity. All effects on. Ideal for tournament broadcasts.",
        screen_pct = 100,
        color      = "#c084fc",
        warning    = "Requires a strong GPU (4+ GB VRAM). If RL won't start, pick Original instead.",
    },
}

local CATEGORY_ORDER = { "Recovery", "FPS", "Competitive", "Broadcast" }
local CATEGORY_STYLE = {
    ["Recovery"]    = { color = "#e74c3c", title = "RECOVERY",
                        subtitle = "Use if Rocket League won't start" },
    ["FPS"]         = { color = "#5dade2", title = "FPS BOOSTING",
                        subtitle = "For low-end or mid-range PCs" },
    ["Competitive"] = { color = "#ff3b9c", title = "COMPETITIVE & STREAMING",
                        subtitle = "For dedicated GPUs" },
    ["Broadcast"]   = { color = "#c084fc", title = "BROADCASTING",
                        subtitle = "For high-res tournament setups" },
}

local BADGE_POSITION_OPTIONS = {
    "Off", "Top Left", "Top Center", "Top Right",
    "Bottom Left", "Bottom Center", "Bottom Right",
}

local available_presets = {}
local assets_dir        = nil
local status_message    = "Ready."
local status_color      = "#aaaaaa"

local function safe(fn, default)
    local ok, result = pcall(fn)
    if ok then return result end
    kingmod.log("caught: " .. tostring(result))
    return default
end

local function set_status(msg, color)
    status_message = msg
    status_color = color or "#aaaaaa"
    kingmod.log(msg)
end

local function open_assets_folder()
    if kingmod.open_assets then
        local ok = safe(function() kingmod.open_assets() return true end, false)
        if ok then return true end
    end
    if assets_dir and kingmod.open_url then
        kingmod.open_url("file:///" .. assets_dir:gsub("\\", "/"))
        return true
    end
    return false
end

local function resolve_assets_dir()
    local dir = safe(function() return kingmod.plugin_dir() end, nil)
    if dir and dir ~= "" then
        return dir .. "\\assets"
    end
    return nil
end

local function make_display(name)
    local info = PRESET_INFO[name]
    if info then return info.label .. "  (" .. name .. ")" end
    return name
end

local function display_to_file(display)
    if not display or display == "" then return "" end
    local name = display:match("%((.-)%)%s*$")
    if name then return name end
    if display:match("%.ini$") then return display end
    return display
end

local function display_to_label(display)
    if not display or display == "" then return "None" end
    local label = display:match("^(.-)%s+%(")
    if label then return label end
    return display:gsub("%.ini$", "")
end

local function get_badge_position()
    local v = kingmod.get_string("badge_position", "Top Left")
    return v:lower():gsub(" ", "_")
end

local function current_preset_color(display)
    local name = display_to_file(display)
    local info = PRESET_INFO[name]
    if info and info.color then return info.color end
    return "#5dade2"
end

local function measure(text, size, bold)
    local width = safe(function()
        return kingmod.measure_text(text, size, bold)
    end, nil)
    if width and width > 0 then return width end
    return #text * size * 0.58
end

local function draw_badge(draw, w, h)
    local position = get_badge_position()
    if position == "off" then return end

    local display = kingmod.get_string("preset_display", "")
    local label   = display_to_label(display)
    local color   = current_preset_color(display)
    if label == "" or label == "None" then return end

    local scale     = math.min(1.0, h / 1080)
    local font_size = math.max(12, math.floor(15 * scale))
    local text_w    = measure(label, font_size, true)

    local pad_x   = math.floor(14 * scale)
    local pad_r   = math.floor(14 * scale)
    local dot_r   = math.floor(5 * scale)
    local gap     = math.floor(9 * scale)
    local text_h  = font_size + math.floor(6 * scale)

    local box_h = text_h + math.floor(12 * scale)
    local box_w = pad_x + (dot_r * 2) + gap + text_w + pad_r

    local margin = math.floor(20 * scale)

    local x, y
    if position == "top_left" then x, y = margin, margin
    elseif position == "top_center" then x, y = (w - box_w) / 2, margin
    elseif position == "top_right" then x, y = w - box_w - margin, margin
    elseif position == "bottom_left" then x, y = margin, h - box_h - margin
    elseif position == "bottom_center" then x, y = (w - box_w) / 2, h - box_h - margin
    elseif position == "bottom_right" then x, y = w - box_w - margin, h - box_h - margin
    else return end

    local radius = box_h / 2

    draw.rect(x, y, box_w, box_h, {
        color = "#0b0b10dd",
        filled = true,
        radius = radius,
    })

    local inset = math.max(1, math.floor(1 * scale))
    draw.rect(x + inset, y + inset, box_w - inset * 2, box_h - inset * 2, {
        color = color .. "1f",
        filled = true,
        radius = radius - inset,
    })

    draw.rect(x, y, box_w, box_h, {
        color = "#00000000",
        border = math.max(1, 1.4 * scale),
        border_color = color,
        radius = radius,
    })

    local dot_cx = x + pad_x + dot_r
    local dot_cy = y + box_h / 2
    draw.circle(dot_cx, dot_cy, dot_r, {
        color = color,
        filled = true,
    })

    local text_x = dot_cx + dot_r + gap
    local text_y = y + (box_h - font_size) / 2 - math.floor(font_size * 0.2)
    draw.text(text_x, text_y, label, {
        color = "#ffffff",
        size = font_size,
        halign = "left",
        bold = true,
    })
end

local function extract_section(content, section_name)
    if not content then return nil end
    local header = "[" .. section_name .. "]"
    local start_pos = content:find(header, 1, true)
    if not start_pos then return nil end
    local after_header = start_pos + #header
    local next_section = content:find("\n[", after_header, true)
    if next_section then return content:sub(start_pos, next_section - 1) end
    return content:sub(start_pos)
end

local function upsert_section(content, section_name, section_body)
    local header = "[" .. section_name .. "]"
    local start_pos = content:find(header, 1, true)
    if start_pos then
        local after_header = start_pos + #header
        local next_section = content:find("\n[", after_header, true)
        if next_section then
            return content:sub(1, start_pos - 1) .. section_body .. content:sub(next_section)
        end
        return content:sub(1, start_pos - 1) .. section_body
    end
    return content .. "\n" .. section_body
end

local function replace_in_system_settings(content, key, value)
    local section = extract_section(content, "SystemSettings")
    if not section then return content end
    local pattern = "(%f[%w]" .. key .. "=)[^\r\n]*"
    local new_section = section:gsub(pattern, "%1" .. value, 1)
    return upsert_section(content, "SystemSettings", new_section)
end

local function extract_from_system_settings(content, key)
    local section = extract_section(content, "SystemSettings")
    if not section then return nil end
    return section:match("\n%s*" .. key .. "%s*=%s*([^\r\n]+)")
end

local function refresh_presets()
    available_presets = {}
    local files = safe(function() return kingmod.list_assets() end, nil)
    if files then
        for _, name in ipairs(files) do
            local lower = name:lower()
            if lower:match("%.ini$") and not RESERVED[lower] then
                table.insert(available_presets, name)
            end
        end
    end
    table.sort(available_presets)

    for i, name in ipairs(available_presets) do
        if name:lower() == "original.ini" then
            table.remove(available_presets, i)
            table.insert(available_presets, 1, name)
            break
        end
    end

    kingmod.log("Found " .. #available_presets .. " preset(s)")
end

local function init_display_defaults()
    if kingmod.get_number("disp_initialized", 0) == 1 then return end

    local current = safe(function() return kingmod.rl_read_config(CONFIG_NAME) end, nil)

    if current then
        local rx = extract_from_system_settings(current, "ResX")
        local ry = extract_from_system_settings(current, "ResY")
        local sp = extract_from_system_settings(current, "ScreenPercentage")
        if rx then kingmod.set("disp_res_x", tonumber(rx) or DEFAULT_RES_X) end
        if ry then kingmod.set("disp_res_y", tonumber(ry) or DEFAULT_RES_Y) end
        if sp then kingmod.set("disp_screen_pct", tonumber(sp) or DEFAULT_SCREEN_PCT) end
    end

    local mode = safe(function() return kingmod.window_mode() end, nil)
    if mode == "Fullscreen" then
        kingmod.set("disp_fullscreen", true); kingmod.set("disp_borderless", false)
    elseif mode == "Borderless" then
        kingmod.set("disp_fullscreen", false); kingmod.set("disp_borderless", true)
    elseif mode == "Windowed" then
        kingmod.set("disp_fullscreen", false); kingmod.set("disp_borderless", false)
    elseif current then
        local fs = extract_from_system_settings(current, "Fullscreen")
        local bl = extract_from_system_settings(current, "Borderless")
        if fs then kingmod.set("disp_fullscreen", fs:lower() == "true") end
        if bl then kingmod.set("disp_borderless", bl:lower() == "true") end
    end

    kingmod.set("disp_initialized", 1)
end

local function apply_preset(display)
    local preset_name = display_to_file(display)
    if not preset_name or preset_name == "" then
        set_status("ERROR: No preset selected.", "#ff5555"); return
    end

    local preset = safe(function() return kingmod.read_asset_text(preset_name) end, nil)
    if not preset then
        set_status("ERROR: Could not read " .. preset_name .. ". Ping " .. SUPPORT_HANDLE .. ".", "#ff5555")
        return
    end

    local is_recovery = (preset_name:lower() == "original.ini")

    if not is_recovery then
        local current = safe(function() return kingmod.rl_read_config(CONFIG_NAME) end, nil)
        if current then
            local stats_section = extract_section(current, "StatsAPI")
            if stats_section then preset = upsert_section(preset, "StatsAPI", stats_section) end
        end

        local rx = math.floor(kingmod.get_number("disp_res_x", DEFAULT_RES_X))
        local ry = math.floor(kingmod.get_number("disp_res_y", DEFAULT_RES_Y))
        local sp = math.floor(kingmod.get_number("disp_screen_pct", DEFAULT_SCREEN_PCT))
        local fs = kingmod.get_bool("disp_fullscreen", DEFAULT_FULLSCREEN)
        local bl = kingmod.get_bool("disp_borderless", DEFAULT_BORDERLESS)

        -- ScreenPercentage written as an integer. Season 24's save file
        -- stores render quality as an int, and RL appears to reject float
        -- values by resetting back to its last-valid integer.
        preset = replace_in_system_settings(preset, "ResX",             tostring(rx))
        preset = replace_in_system_settings(preset, "ResY",             tostring(ry))
        preset = replace_in_system_settings(preset, "ScreenPercentage", tostring(sp))
        preset = replace_in_system_settings(preset, "Fullscreen",       fs and "True" or "False")
        preset = replace_in_system_settings(preset, "Borderless",       bl and "True" or "False")
    end

    local ok = safe(function() return kingmod.rl_write_config(CONFIG_NAME, preset) end, false)

    if ok then
        if is_recovery then
            set_status("SUCCESS: Vanilla config restored. Launch Rocket League to test.", "#55ff88")
        else
            local rx = math.floor(kingmod.get_number("disp_res_x", DEFAULT_RES_X))
            local ry = math.floor(kingmod.get_number("disp_res_y", DEFAULT_RES_Y))
            local sp = math.floor(kingmod.get_number("disp_screen_pct", DEFAULT_SCREEN_PCT))
            local note = ""
            local info = PRESET_INFO[preset_name]
            if sp >= 100 and info and info.screen_pct and info.screen_pct < 100 then
                note = " Tip: set Render Quality lower for a bigger boost."
            end
            set_status("SUCCESS: " .. preset_name .. " applied (" ..
                rx .. "x" .. ry .. " @ " .. sp .. "%). Restart RL." .. note, "#55ff88")
        end
    else
        set_status("ERROR: Write failed. Is Rocket League running? Ping " .. SUPPORT_HANDLE .. ".", "#ff5555")
    end
end

function plugin.on_load()
    kingmod.log("Loading v3.1.1")

    if not kingmod.rl_write_config then
        set_status("ERROR: Requires Hebnix 2.1.8 or newer.", "#ff5555")
        return
    end

    assets_dir = resolve_assets_dir()
    if assets_dir then kingmod.log("Assets: " .. assets_dir) end

    refresh_presets()
    init_display_defaults()

    if kingmod.get_string("preset_display", "") == "" and #available_presets > 0 then
        kingmod.set("preset_display", make_display(available_presets[1]))
        kingmod.set("last_selected_display", make_display(available_presets[1]))
    end

    set_status("Ready. " .. #available_presets .. " preset(s) available.", "#aaaaaa")
end

function plugin.on_overlay(draw, w, h)
    if get_badge_position() == "off" then return end
    if not w or not h or w < 640 or h < 480 then return end
    local connected = safe(function() return kingmod.rl_connected() end, false)
    if not connected then return end
    safe(function() draw_badge(draw, w, h) end)
end

function plugin.on_settings(ui)
    if not kingmod.rl_write_config then
        ui.colored_label("#ff5555", "Requires Hebnix 2.1.8 or newer.")
        return
    end

    ui.heading(PLUGIN_NAME)
    ui.colored_label("#666666", "v3.1.1   |   by Qiddiyah   |   support: " .. SUPPORT_HANDLE)
    ui.space(6)

    ui.colored_label("#ffaa55", "Rocket League won't start after applying a preset?")
    ui.colored_label("#888888", "Pick 'Original' from the preset list below and click Apply.")
    ui.colored_label("#888888", "This writes the vanilla config and clears any problematic values.")
    ui.space(6)
    ui.separator()

    ui.colored_label("#ffffff", "CHOOSE YOUR PRESET")
    ui.space(2)

    for _, category in ipairs(CATEGORY_ORDER) do
        local style = CATEGORY_STYLE[category]
        if style then
            ui.space(4)
            ui.horizontal(function(ui)
                ui.colored_label(style.color, style.title)
                ui.colored_label("#888888", "   " .. style.subtitle)
            end)
            ui.space(2)

            for _, name in ipairs(available_presets) do
                local info = PRESET_INFO[name]
                if info and info.category == category then
                    ui.horizontal(function(ui)
                        ui.colored_label(info.color, "  " .. info.label)
                        ui.colored_label("#888888", "   -   " .. info.desc)
                    end)
                end
            end
        end
    end

    ui.space(6)
    ui.separator()

    ui.colored_label("#ffffff", "ACTIVE PRESET")
    ui.space(4)

    local options = {}
    for _, name in ipairs(available_presets) do
        table.insert(options, make_display(name))
    end

    local selected_display = ""
    if #options == 0 then
        ui.colored_label("#ff5555",
            "No presets found. Click 'Open Folder', add .ini files to assets/, then Refresh.")
    else
        local previous_display = kingmod.get_string("last_selected_display", "")
        selected_display = ui.combo_box("preset_display", "Selected", options)

        if selected_display ~= previous_display then
            local real_name = display_to_file(selected_display)
            local info = PRESET_INFO[real_name]
            if info and info.screen_pct then
                kingmod.set("disp_screen_pct", info.screen_pct)
            end
            kingmod.set("last_selected_display", selected_display)
        end

        local real_name = display_to_file(selected_display)
        local info = PRESET_INFO[real_name]
        if info then
            ui.space(4)
            ui.horizontal(function(ui)
                ui.colored_label(info.color, info.label)
                ui.colored_label("#666666", "   " .. info.category)
            end)
            ui.colored_label("#aaaaaa", info.desc)

            if info.warning then
                ui.space(2)
                ui.colored_label("#ffaa55", "WARNING:  " .. info.warning)
            end

            if info.note then
                ui.space(2)
                ui.colored_label("#5dade2", "Note:  " .. info.note)
            end
        end
    end

    ui.space(6)
    ui.horizontal(function(ui)
        if ui.button("Open Folder") then
            if open_assets_folder() then
                set_status("Opened assets folder.", "#5dade2")
            else
                set_status("ERROR: Could not open assets folder.", "#ff5555")
            end
        end

        if ui.button("Refresh") then
            refresh_presets()
            set_status("Refreshed. Found " .. #available_presets .. " preset(s).", "#5dade2")
        end
    end)

    ui.space(6)
    ui.separator()

    ui.collapsing("Display Settings", function(ui)
        ui.colored_label("#888888", "Applied with the preset. Not used for the Original preset.")
        ui.space(4)
        ui.slider("disp_res_x", "Resolution Width", 800, 3840, DEFAULT_RES_X)
        ui.slider("disp_res_y", "Resolution Height", 600, 2160, DEFAULT_RES_Y)
        ui.slider("disp_screen_pct", "Render Quality", 40, 100, DEFAULT_SCREEN_PCT)
        ui.checkbox("disp_fullscreen", "Fullscreen", DEFAULT_FULLSCREEN)
        ui.checkbox("disp_borderless", "Borderless", DEFAULT_BORDERLESS)

        ui.space(4)
        ui.horizontal(function(ui)
            if ui.button("Re-detect") then
                local current = safe(function() return kingmod.rl_read_config(CONFIG_NAME) end, nil)
                if current then
                    local rx = extract_from_system_settings(current, "ResX")
                    local ry = extract_from_system_settings(current, "ResY")
                    local sp = extract_from_system_settings(current, "ScreenPercentage")
                    if rx then kingmod.set("disp_res_x", tonumber(rx) or DEFAULT_RES_X) end
                    if ry then kingmod.set("disp_res_y", tonumber(ry) or DEFAULT_RES_Y) end
                    if sp then kingmod.set("disp_screen_pct", tonumber(sp) or DEFAULT_SCREEN_PCT) end
                    local mode = safe(function() return kingmod.window_mode() end, nil)
                    if mode == "Fullscreen" then
                        kingmod.set("disp_fullscreen", true); kingmod.set("disp_borderless", false)
                    elseif mode == "Borderless" then
                        kingmod.set("disp_fullscreen", false); kingmod.set("disp_borderless", true)
                    elseif mode == "Windowed" then
                        kingmod.set("disp_fullscreen", false); kingmod.set("disp_borderless", false)
                    end
                    set_status("Re-detected from live config.", "#5dade2")
                else
                    set_status("ERROR: Could not read current config.", "#ff5555")
                end
            end

            if ui.button("Match Window") then
                local rect = safe(function() return kingmod.rocket_league_window_rect() end, nil)
                if rect then
                    local w = rect.right - rect.left
                    local h = rect.bottom - rect.top
                    if w > 0 and h > 0 then
                        kingmod.set("disp_res_x", w); kingmod.set("disp_res_y", h)
                        set_status("Matched RL window: " .. w .. "x" .. h, "#55ff88")
                    else
                        set_status("ERROR: Invalid window rect.", "#ff5555")
                    end
                else
                    set_status("ERROR: RL window not detected. Is RL running?", "#ff5555")
                end
            end
        end)
    end)

    ui.collapsing("Preset Badge", function(ui)
        ui.colored_label("#888888", "Shows the active preset over the game.")
        ui.space(4)
        ui.combo_box("badge_position", "Position", BADGE_POSITION_OPTIONS)
        ui.space(2)
        ui.colored_label("#666666", "For accurate FPS numbers, use RL's built-in performance stats")
        ui.colored_label("#666666", "(Settings > Interface > Performance Stats).")
    end)

    ui.space(6)
    ui.separator()
    ui.colored_label("#55ff88", "APPLY")
    ui.colored_label("#888888", "Close Rocket League before applying.")
    ui.space(4)
    ui.horizontal(function(ui)
        if ui.button("Apply Preset + Display Settings") then
            apply_preset(selected_display)
        end
    end)

    ui.space(6)
    ui.separator()
    ui.colored_label("#ffffff", "STATUS")
    ui.colored_label(status_color, status_message)
end

function plugin.on_unload()
    kingmod.log("Unloaded.")
end

return plugin