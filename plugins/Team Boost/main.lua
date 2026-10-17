local plugin = {}

plugin.overlay_page = "team-boost.html"

local last_players = {}
local last_team = 0

local function field(value, ...)
    if type(value) ~= "table" then return nil end
    for index = 1, select("#", ...) do
        local result = value[select(index, ...)]
        if result ~= nil then return result end
    end
    return nil
end

local function number(value, fallback)
    local parsed = tonumber(value)
    if parsed == nil then return fallback end
    return parsed
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function settings_payload()
    return {
        scale = hebnix.get_number("team_boost_scale", 1.0),
        right_margin = hebnix.get_number("team_boost_right_margin", 36),
        vertical_offset = hebnix.get_number("team_boost_vertical_offset", 0),
        show_numbers = hebnix.get_bool("team_boost_show_numbers", true),
    }
end

local function send_overlay(players, team)
    local settings = settings_payload()
    settings.visible = hebnix.get_bool("team_boost_enabled", true) and #players > 0
    settings.players = players
    settings.team = team or 0
    hebnix.overlay.send(settings)
end

local function hide_overlay()
    last_players = {}
    send_overlay(last_players, last_team)
end

local function player_sort_key(player)
    local shortcut = number(field(player, "Shortcut", "shortcut"), 9999)
    local primary_id = tostring(field(player, "PrimaryId", "primary_id") or "")
    local name = tostring(field(player, "Name", "name") or "")
    return string.format("%06d|%s|%s", shortcut, primary_id, name)
end

local function update_roster(event)
    local data = event and (event.data or event.Data) or nil
    local players = data and field(data, "Players", "players") or nil
    local game = data and field(data, "Game", "game") or nil
    local target = game and field(game, "Target", "target") or nil
    if type(players) ~= "table" or type(target) ~= "table" then
        hide_overlay()
        return
    end

    local target_team = number(field(target, "TeamNum", "team_num"), nil)
    local target_shortcut = number(field(target, "Shortcut", "shortcut"), nil)
    local target_name = tostring(field(target, "Name", "name") or "")
    local local_index = nil

    for index, player in ipairs(players) do
        local shortcut = number(field(player, "Shortcut", "shortcut"), nil)
        if target_shortcut ~= nil and shortcut == target_shortcut then
            local_index = index
            target_team = number(field(player, "TeamNum", "team_num"), target_team)
            break
        end
    end

    if local_index == nil and target_name ~= "" then
        for index, player in ipairs(players) do
            local name = tostring(field(player, "Name", "name") or "")
            local team = number(field(player, "TeamNum", "team_num"), nil)
            if name == target_name and (target_team == nil or team == target_team) then
                local_index = index
                target_team = team or target_team
                break
            end
        end
    end

    if local_index == nil or target_team == nil then
        hide_overlay()
        return
    end

    local teammates = {}
    for index, player in ipairs(players) do
        local team = number(field(player, "TeamNum", "team_num"), -1)
        if index ~= local_index and team == target_team then
            local name = tostring(field(player, "Name", "name") or "Teammate")
            local boost = math.floor(clamp(number(field(player, "Boost", "boost"), 0), 0, 100) + 0.5)
            local primary_id = tostring(field(player, "PrimaryId", "primary_id") or "")
            local shortcut = tostring(field(player, "Shortcut", "shortcut") or index)
            table.insert(teammates, {
                id = primary_id ~= "" and primary_id or (shortcut .. ":" .. name),
                name = name,
                boost = boost,
                sort_key = player_sort_key(player),
            })
        end
    end

    table.sort(teammates, function(left, right)
        return left.sort_key < right.sort_key
    end)
    for _, teammate in ipairs(teammates) do teammate.sort_key = nil end

    last_players = teammates
    last_team = target_team
    send_overlay(last_players, last_team)
end

function plugin.on_load()
    hide_overlay()
end

function plugin.on_unload()
    hide_overlay()
end

function plugin.on_game_event(event_type, event)
    if event_type == "UpdateState" then
        update_roster(event)
    elseif event_type == "MatchCreated" or event_type == "CountdownBegin" then
        hide_overlay()
    elseif event_type == "MatchEnded" or event_type == "MatchDestroyed" or event_type == "GameLeft" then
        hide_overlay()
    end
end

function plugin.on_settings(ui)
    ui.heading("Team Boost")
    ui.checkbox("team_boost_enabled", "Show teammate boost", true)
    ui.checkbox("team_boost_show_numbers", "Show boost numbers", true)
    ui.separator()
    ui.heading("Layout")
    ui.slider("team_boost_scale", "Scale", 0.5, 1.5, 1.0)
    ui.slider("team_boost_right_margin", "Right margin", 0, 400, 36)
    ui.slider("team_boost_vertical_offset", "Vertical offset", -500, 500, 0)
    ui.label("Bars appear on the right for every teammate in the current match.")
end

return plugin
