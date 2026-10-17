local plugin = {}

local MODES = {
    "Ranked 1v1", "Ranked 2v2", "Ranked 3v3", "2v2 Heatseeker",
    "Hoops", "Rumble", "Dropshot", "Snow Day", "Extra Modes"
}

-- Profile API playlist IDs.
local MODE_PLAYLISTS = {
    ["Ranked 1v1"] = { id = 10, names = { "Duel", "Ranked Duel 1v1" } },
    ["Ranked 2v2"] = { id = 11, names = { "Doubles", "Ranked Doubles 2v2" } },
    ["Ranked 3v3"] = { id = 13, names = { "Standard", "Ranked Standard 3v3" } },
    ["2v2 Heatseeker"] = { id = 63, names = { "Heatseeker", "Heatseeker Doubles" } },
    ["Hoops"] = { id = 27, names = { "Hoops" } },
    ["Rumble"] = { id = 28, names = { "Rumble" } },
    ["Dropshot"] = { id = 29, names = { "Dropshot" } },
    ["Snow Day"] = { id = 30, names = { "Snow Day", "Snowday" } },
    ["Extra Modes"] = { id = 63, names = { "Extra Modes" } },
}

local in_match, match_recorded = false, false
local local_primary_id, local_name = nil, "Player"
local local_identity_ids, local_team_num = {}, nil
local match_goals, match_saves, last_log_check = 0, 0, 0
local session_goals, session_saves, session_wins, session_losses = 0, 0, 0, 0
local tracker_key, tracker_requested_at, tracker_mode = nil, 0, nil
local current_mode = nil
local tracker_mmr, tracker_rank_name, tracker_tier, tracker_has_rank = "—", "Loading…", 0, false
local current_platform = ""

local function selected_mode()
    return kingmod.get_string("hebs_hud_mode", "Ranked 2v2")
end

local function mode_name()
    return selected_mode()
end

local function profile_identity(primary_id)
    local platform, account_id = tostring(primary_id or ""):match("^([^|]+)|([^|]+)")
    if not platform or not account_id or account_id == "" then return nil, nil end
    platform = string.lower(platform)
    if platform == "xbl" or platform == "xbox" then platform = "xboxone" end
    if platform == "ps4" or platform == "ps5" or platform == "playstation" then platform = "psn" end
    if platform == "nintendo" then platform = "switch" end
    return platform, account_id
end

-- launch.log provides the real local account
local function refresh_identity_from_log()
    if os.time() - last_log_check < 5 then return end
    last_log_check = os.time()
    local log = kingmod.parse_launch_log(false)
    local session = log and log.session
    if type(session) ~= "table" then return end

    local playlist_id = log.game and tonumber(log.game.playlist_id)
    local playlist_modes = {
        [10] = "Ranked 1v1", [11] = "Ranked 2v2", [13] = "Ranked 3v3",
        [63] = "2v2 Heatseeker", [27] = "Hoops", [28] = "Rumble",
        [29] = "Dropshot", [30] = "Snow Day",
    }
    current_mode = playlist_modes[playlist_id] or current_mode

    if session.username and tostring(session.username) ~= "" then
        local_name = tostring(session.username)
    end
    -- primary id only identifies the local stats-api player
    if session.primary_id and tostring(session.primary_id) ~= "" then
        local_primary_id = tostring(session.primary_id)
        local account_id = local_primary_id:match("^[^|]+|([^|]+)")
        if account_id then local_identity_ids[account_id] = true end
    end
    -- Preserve the Epic session identity reported by the launch log.
    local log_primary = tostring(session.primary_id or "")
    if string.lower(log_primary):match("^epic|") or (session.epic_id and tostring(session.epic_id) ~= "") then
        current_platform = "epic"
        if session.username and tostring(session.username) ~= "" then
            local_name = tostring(session.username)
        end
        local_primary_id = log_primary ~= "" and log_primary or nil
        local account_id = local_primary_id and local_primary_id:match("^[^|]+|([^|]+)")
        if account_id then local_identity_ids[account_id] = true end
        return
    end
    local detected = string.lower(tostring(kingmod.detected_platform() or ""))
    if detected ~= "steam" and detected ~= "epic" then
        detected = string.lower(tostring(session.platform or ""))
    end
    current_platform = detected
    if detected == "steam" and session.steam_id and tostring(session.steam_id) ~= "" then
        local steam_id = string.lower(tostring(session.steam_id))
        local_identity_ids[steam_id] = true
        local_primary_id = "steam|" .. steam_id .. "|0"
    elseif detected == "epic" and local_primary_id and not string.lower(local_primary_id):match("^epic|") then
        local_primary_id = nil
    end
end

local function is_local_player(player)
    if not player then return false end
    local primary_id = player.PrimaryId or player.primary_id
    if primary_id then
        local normalized = string.lower(tostring(primary_id))
        if local_primary_id and normalized == local_primary_id then return true end
        local account_id = normalized:match("^[^|]+|([^|]+)")
        if account_id and local_identity_ids[account_id] then return true end
    end
    local name = player.Name or player.name
    return name and local_name ~= "" and tostring(name) == local_name
end

-- stats api identifies the local player
local function capture_local_identity_from_stats(event)
    local data = event and event.data
    local target = data and data.game and data.game.target
    local target_name = target and target.name
    local players = data and data.Players
    if not target_name or target_name == "" or type(players) ~= "table" then return end

    for _, player in ipairs(players) do
        local player_name = player.Name or player.name
        local primary_id = player.PrimaryId or player.primary_id
        if player_name == target_name and primary_id and tostring(primary_id) ~= "" then
            if current_platform ~= "epic" then local_name = tostring(player_name) end
            local_primary_id = tostring(primary_id)
            local account_id = local_primary_id:match("^[^|]+|([^|]+)")
            if account_id then local_identity_ids[account_id] = true end
            return
        end
    end
end

local function playlist_matches(rank, selected)
    return tonumber(rank.playlist_id) == selected.id
end

local function update_tracker_rank()
    refresh_identity_from_log()
    local platform, account_id = profile_identity(local_primary_id)
    if not platform or not account_id then
        if tracker_mmr == "—" then tracker_rank_name = "Waiting for platform ID" end
        return
    end

    local query_key = platform .. ":" .. account_id
    if tracker_key ~= query_key or os.time() - tracker_requested_at >= 300 then
        tracker_key = kingmod.fetch_profile_async(platform, account_id) or query_key
        tracker_requested_at = os.time()
    end

    local result = kingmod.stats_result(tracker_key or query_key)
    if result == nil or result == "pending" then
        if tracker_mmr == "—" then tracker_rank_name = "Loading…" end
        return
    end
    if type(result) ~= "table" or result.error then
        if tracker_mmr == "—" then tracker_rank_name = "Unavailable" end
        return
    end

    local selected = MODE_PLAYLISTS[mode_name()]
    local found = nil
    for _, rank in pairs(result.ranks or {}) do
        if playlist_matches(rank, selected) then
            found = rank
            break
        end
    end

    local found_mmr = found and tonumber(found.mmr)
    if found and found_mmr then
        tracker_mmr = tostring(found_mmr)
        tracker_rank_name = tostring(found.tier_name or "Unranked")
        tracker_tier = math.max(0, math.min(22, math.floor(tonumber(found.tier_id) or 0)))
        tracker_has_rank = true
    elseif not tracker_has_rank then
        tracker_mmr, tracker_rank_name, tracker_tier = "—", "Unranked", 0
    end
    tracker_mode = mode_name()
end
local function reset_match()
    in_match, match_recorded, local_team_num = false, false, nil
    match_goals, match_saves = 0, 0
end

local function update_local_stats(event)
    local players = event and event.data and event.data.Players
    if not players then return end
    refresh_identity_from_log()
    capture_local_identity_from_stats(event)
    for _, player in ipairs(players) do
        if is_local_player(player) then
            local_team_num = player.TeamNum
            match_goals = math.max(0, math.floor(player.Goals or 0))
            match_saves = math.max(0, math.floor(player.Saves or 0))
            return
        end
    end
end

function plugin.on_load()
    refresh_identity_from_log()
    update_tracker_rank()
    reset_match()
end

function plugin.on_tick()
    update_tracker_rank()
end

function plugin.on_game_event(event_type, event)
    if event_type == "MatchCreated" or event_type == "CountdownBegin" then
        in_match, match_recorded, match_goals, match_saves = true, false, 0, 0
    elseif event_type == "GameLeft" or event_type == "MatchDestroyed" then
        reset_match()
        return
    elseif event_type == "UpdateState" then
        in_match = true
        update_local_stats(event)
    elseif event_type == "GoalScored" and is_local_player(event and event.data and event.data.Scorer) then
        match_goals = match_goals + 1
    elseif event_type == "MatchEnded" then
        if not match_recorded and local_team_num ~= nil then
            local winner = event and event.data and event.data.WinnerTeamNum
            if winner == local_team_num then session_wins = session_wins + 1
            elseif winner ~= nil and winner >= 0 then session_losses = session_losses + 1 end
            session_goals = session_goals + match_goals
            session_saves = session_saves + match_saves
            match_recorded = true
        end
        in_match = false
    end
end

local function selected_rows()
    local rows = {
        { "MMR", "M", tracker_mmr, kingmod.get_string("hebs_hud_mmr_colour", "#f3db21ff"), "hebs_hud_show_mmr" },
        { "GOALS", "G", tostring(session_goals + (match_recorded and 0 or match_goals)), kingmod.get_string("hebs_hud_goals_colour", "#32c5ffff"), "hebs_hud_show_goals" },
        { "SAVES", "S", tostring(session_saves + (match_recorded and 0 or match_saves)), kingmod.get_string("hebs_hud_saves_colour", "#4edc77ff"), "hebs_hud_show_saves" },
        { "WINS", "W", tostring(session_wins), kingmod.get_string("hebs_hud_win_colour", "#228cecff"), "hebs_hud_show_wins" },
        { "LOSSES", "L", tostring(session_losses), kingmod.get_string("hebs_hud_loss_colour", "#ff6f00ff"), "hebs_hud_show_losses" },
    }
    local selected = {}
    for _, row in ipairs(rows) do
        if kingmod.get_bool(row[5], true) then table.insert(selected, row) end
    end
    if #selected == 0 then
        kingmod.set("hebs_hud_show_mmr", true)
        table.insert(selected, rows[1])
    end
    return selected
end

local function render_default(draw, w, h, rows, scale, margin_x, margin_y)
    local width, row_h = 214 * scale, 37 * scale
    local height, x, y = 8 * scale + row_h * #rows, w - margin_x - width, margin_y
    local bg = kingmod.get_string("hebs_hud_background_colour", "#070914e8")
    local line = kingmod.get_string("hebs_hud_line_colour", "#20253eff")
    local label = kingmod.get_string("hebs_hud_label_colour", "#6e7898ff")
    local has_mmr = rows[1][1] == "MMR"
    local label_x = has_mmr and x + 42 * scale or x + 14 * scale
    local right, text_size, value_size = x + width - 14 * scale, 12 * scale, 18 * scale

    draw.rect(x, y, width, height, { color = bg, filled = true, border = 1, border_color = line })
    if has_mmr then
        local icon_size = 22 * scale
        draw.image("assets/ranks/" .. tracker_tier .. ".png", x + 10 * scale, y + 7 * scale, icon_size, icon_size)
    end
    for index, row in ipairs(rows) do
        local row_y = y + 11 * scale + (index - 1) * row_h
        if index > 1 then
            draw.rect(x + 13 * scale, row_y - 7 * scale, width - 26 * scale, 1, { color = line, filled = true })
        end
        draw.text(label_x, row_y, row[1], { color = label, size = text_size })
        draw.text(right, row_y - 3 * scale, row[3], { color = row[4], size = value_size, halign = "right" })
    end
end

local function render_pill(draw, w, rows, scale, margin_x, margin_y)
    local bg = kingmod.get_string("hebs_hud_background_colour", "#070914e8")
    local line = kingmod.get_string("hebs_hud_line_colour", "#20253eff")
    local label = kingmod.get_string("hebs_hud_label_colour", "#6e7898ff")
    local parts = {}
    for _, row in ipairs(rows) do table.insert(parts, row[2] .. ": " .. row[3]) end
    local text = table.concat(parts, "  |  ")
    local width, height = math.max(94 * scale, (#text * 5.8 + 32) * scale), 34 * scale
    local x, y = w - margin_x - width, margin_y
    draw.rect(x, y, width, height, { color = bg, filled = true, border = 1, border_color = line, radius = 17 * scale })
    local cursor = x + 14 * scale
    for index, row in ipairs(rows) do
        local prefix = row[2] .. ": "
        draw.text(cursor, y + 7 * scale, prefix, { color = label, size = 14 * scale })
        cursor = cursor + #prefix * 7.5 * scale
        draw.text(cursor, y + 7 * scale, row[3], { color = row[4], size = 14 * scale })
        cursor = cursor + #row[3] * 8 * scale
        if index < #rows then
            draw.text(cursor + 7 * scale, y + 7 * scale, "|", { color = line, size = 14 * scale })
            cursor = cursor + 20 * scale
        end
    end
end

function plugin.on_overlay(draw, w, h)
    if not kingmod.get_bool("hebs_hud_enabled", true) then return end
    local scale = kingmod.get_number("hebs_hud_scale", 1.0)
    local margin_x = kingmod.get_number("hebs_hud_margin_x", 28)
    local margin_y = kingmod.get_number("hebs_hud_margin_y", 14)
    local rows = selected_rows()
    if kingmod.get_string("hebs_hud_style", "Default") == "Pill" then
        render_pill(draw, w, rows, scale, margin_x, margin_y)
    else
        render_default(draw, w, h, rows, scale, margin_x, margin_y)
    end
end

local function clear_session_stats()
    match_goals, match_saves = 0, 0
    session_goals, session_saves, session_wins, session_losses = 0, 0, 0, 0
end

function plugin.on_settings(ui)
    ui.checkbox("hebs_hud_enabled", "Show top-right HUD", true)

    ui.space(8)
    ui.heading("Display")
    local display_keys = {
        { "hebs_hud_show_mmr", "Show MMR" },
        { "hebs_hud_show_goals", "Show Goals" },
        { "hebs_hud_show_saves", "Show Saves" },
        { "hebs_hud_show_wins", "Show Wins" },
        { "hebs_hud_show_losses", "Show Losses" },
    }
    local visible = 0
    for _, item in ipairs(display_keys) do
        if kingmod.get_bool(item[1], true) then visible = visible + 1 end
    end
    for _, item in ipairs(display_keys) do
        local was_visible = kingmod.get_bool(item[1], true)
        local is_visible = ui.checkbox(item[1], item[2], true)
        if was_visible and not is_visible and visible == 1 then kingmod.set(item[1], true) end
    end
    ui.combo_box("hebs_hud_mode", "MMR gamemode", MODES)
    if ui.button("Clear session stats") then clear_session_stats() end

    ui.space(8)
    ui.heading("Layout")
    ui.combo_box("hebs_hud_style", "Style", { "Default", "Pill" })
    ui.slider("hebs_hud_scale", "Scale", 0.65, 1.75, 1.0)
    ui.slider("hebs_hud_margin_x", "Right margin", 0, 300, 28)
    ui.slider("hebs_hud_margin_y", "Top margin", 0, 300, 14)

    ui.space(8)
    ui.heading("Colours")
    ui.color_picker("hebs_hud_background_colour", "Panel background", "#070914e8")
    ui.color_picker("hebs_hud_line_colour", "Panel border and dividers", "#20253eff")
    ui.color_picker("hebs_hud_label_colour", "Row labels", "#6e7898ff")
    ui.color_picker("hebs_hud_mmr_colour", "MMR value", "#f3db21ff")
    ui.color_picker("hebs_hud_goals_colour", "Goals value", "#32c5ffff")
    ui.color_picker("hebs_hud_saves_colour", "Saves value", "#4edc77ff")
    ui.color_picker("hebs_hud_win_colour", "Wins value", "#228cecff")
    ui.color_picker("hebs_hud_loss_colour", "Losses value", "#ff6f00ff")
end

return plugin









