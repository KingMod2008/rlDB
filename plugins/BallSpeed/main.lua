local plugin = {}

local current_speed = 0.0
local max_speed = 0.0
local window_configured = false
local location_picker_active = false
local in_game = false
local match_ended = false

local function open_location_window()
    if not window_configured then
        kingmod.window.open({
            title = "Ball Speed Location",
            width = 240,
            height = 80,
            opacity = 0.90,
        })
        window_configured = true
    else
        kingmod.window.open()
    end
    location_picker_active = true
end

local function reset_stats()
    current_speed = 0.0
    max_speed = 0.0
    in_game = false
    match_ended = true
end

local function round(num)
    return math.floor((num or 0) + 0.5)
end

local function extract_ball_speed(event)
    if not event or not event.data then return 0 end

    if event.data.Game and event.data.Game.Ball then
        return round(event.data.Game.Ball.Speed or 0.0)
    end
    if event.data.Ball then
        return round(event.data.Ball.Speed or event.data.Ball.speed or 0.0)
    end
    return 0
end

local function has_live_ball_data(event)
    if not event or not event.data then return false end
    return (event.data.Game and event.data.Game.Ball) ~= nil
        or event.data.Ball ~= nil
end

function plugin.on_load()
    kingmod.log("Ball Speed plugin loaded")
end

function plugin.on_unload()
    kingmod.window.close()
end

function plugin.on_game_event(event_type, event)
    if event_type == "GameLeft" or event_type == "MatchEnded" or event_type == "MatchDestroyed" then
        reset_stats()
        return
    end

    if event_type == "UpdateState" and has_live_ball_data(event) then
        in_game = true
        match_ended = false
        current_speed = extract_ball_speed(event)
        if current_speed > max_speed then
            max_speed = current_speed
        end
    end
end

function plugin.on_tick()
    if location_picker_active and not kingmod.window.is_open() then
        location_picker_active = false
    end
end

function plugin.on_overlay(draw, w, h)
    if not in_game or match_ended or location_picker_active or not kingmod.get_bool("ballspeed_enable_overlay", true) then return end

    local use_mph = kingmod.get_bool("ballspeed_convert_mph", false)
    local unit = use_mph and "MPH" or "KPH"
    local speed = round(use_mph and (current_speed * 0.621371) or current_speed)
    local peak = round(use_mph and (max_speed * 0.621371) or max_speed)
    local show_max = kingmod.get_bool("ballspeed_show_max", false)
    local show_label = kingmod.get_bool("ballspeed_show_label", true)
    local show_background = kingmod.get_bool("ballspeed_show_background", false)
    local background_colour = kingmod.get_string("ballspeed_background_colour", "#000000aa")
    local speed_colour = kingmod.get_string("ballspeed_speed_colour", "#ffffff")
    local max_colour = kingmod.get_string("ballspeed_max_colour", "#ffffff")
    local speed_text = show_label
        and string.format("Ball Speed: %d %s", speed, unit)
        or string.format("%d %s", speed, unit)
    local max_text = string.format("Max: %d %s", peak, unit)
    local box_h = show_max and 52 or 35
    local pos_x = kingmod.get_number("ballspeed_pos_x", 100)
    local pos_y = kingmod.get_number("ballspeed_pos_y", 100)
    local desktop_x = kingmod.get_number("ballspeed_desktop_x", -1)
    local desktop_y = kingmod.get_number("ballspeed_desktop_y", -1)

    if desktop_x >= 0 and desktop_y >= 0 and kingmod.rocket_league_window_rect then
        local rect = kingmod.rocket_league_window_rect()
        if rect and rect.right > rect.left and rect.bottom > rect.top then
            pos_x = (desktop_x - rect.left) * w / (rect.right - rect.left)
            pos_y = (desktop_y - rect.top) * h / (rect.bottom - rect.top)
        end
    end

    pos_x = math.max(0, math.min(pos_x, math.max(0, w - 200)))
    pos_y = math.max(0, math.min(pos_y, math.max(0, h - box_h)))
    local font_size = 20

    if show_background then
        draw.rect(pos_x - 10, pos_y - 3, 200, box_h, { color = background_colour, filled = true })
        draw.rect(pos_x - 10, pos_y - 3, 200, box_h, { color = "#ffffff20", width = 1 })
    end

    draw.text(pos_x, pos_y, speed_text, { color = speed_colour, size = font_size })
    if show_max then
        draw.text(pos_x, pos_y + 24, max_text, { color = max_colour, size = 14 })
    end
end

function plugin.on_window(ui)
    if ui.button("Set Location") then
        local position = nil
        if kingmod.window.get_position then
            position = kingmod.window.get_position()
        end
        local x = position and position.x or kingmod.get_number("__win_x", 100)
        local y = position and position.y or kingmod.get_number("__win_y", 100)
        kingmod.set("ballspeed_pos_x", x)
        kingmod.set("ballspeed_pos_y", y)
        kingmod.set("ballspeed_desktop_x", x)
        kingmod.set("ballspeed_desktop_y", y)
        location_picker_active = false
        kingmod.window.close()
    end
end

function plugin.on_settings(ui)
    if ui.button("Change Location") then
        open_location_window()
    end

    ui.space(8)
    ui.heading("Display")
    ui.checkbox("ballspeed_show_label", "Ball Speed: Text", true)
    ui.checkbox("ballspeed_show_max", "Show Peak Match Speed", false)

    ui.space(8)
    ui.heading("Overlay Appearance")
    ui.checkbox("ballspeed_show_background", "Show Background", false)
    ui.color_picker("ballspeed_background_colour", "Background colour", "#000000aa")
    ui.color_picker("ballspeed_speed_colour", "Ball speed text colour", "#ffffff")
    ui.color_picker("ballspeed_max_colour", "Max speed text colour", "#ffffff")

    ui.space(8)
    ui.heading("Unit Conversion")
    ui.checkbox("ballspeed_convert_mph", "Convert to MPH", false)

    ui.space(8)
    if ui.button("Reset Max Speed") then
        max_speed = 0.0
    end
end

return plugin
