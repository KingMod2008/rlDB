local plugin = {}

local PLAYLISTS = {
    ["Ranked 1v1"] = { id = 10, names = { "Duel", "Ranked Duel 1v1" } },
    ["Ranked 2v2"] = { id = 11, names = { "Doubles", "Ranked Doubles 2v2" } },
    ["Ranked 3v3"] = { id = 13, names = { "Standard", "Ranked Standard 3v3" } },
    ["Hoops"] = { id = 27, names = { "Hoops" } },
    ["Rumble"] = { id = 28, names = { "Rumble" } },
    ["Dropshot"] = { id = 29, names = { "Dropshot" } },
    ["Snow Day"] = { id = 30, names = { "Snow Day", "Snowday" } },
    ["Tournament"] = { id = 34, names = { "Tournament", "Tournament Matches" } },
    ["2v2 Heatseeker"] = { id = 63, aliases = { 34 }, names = { "Heatseeker", "Heatseeker Doubles" } },
}
local LOG_PLAYLISTS = {
    [10] = "Ranked 1v1",
    [11] = "Ranked 2v2", [13] = "Ranked 3v3", [27] = "Hoops", [28] = "Rumble",
    [29] = "Dropshot", [30] = "Snow Day", [34] = "Tournament", [63] = "2v2 Heatseeker",
}

local local_name, primary_id, platform = "", nil, ""
local last_log_check, tracker_key, requested_at = 0, nil, 0
local show_viewer, match_mode = false, nil
local result = { mmr = nil, tier = 0, division = 0, rank_name = "Loading…", entries = nil }

local function active_mode()
    return match_mode
end
local function refresh_identity(force)
    if not force and os.time() - last_log_check < 5 then return end
    last_log_check = os.time()
    local log = kingmod.parse_launch_log(false)
    local session = log and log.session
    if type(session) ~= "table" then return end
    platform = string.lower(tostring(kingmod.detected_platform() or session.platform or ""))
    if session.username and tostring(session.username) ~= "" then local_name = tostring(session.username) end
    if session.primary_id and tostring(session.primary_id) ~= "" then
        local raw_primary_id = string.lower(tostring(session.primary_id))
        primary_id = raw_primary_id:match("^[^|]*|([^|]+)|.*$") or raw_primary_id
    end
    local playlist_id = log.game and tonumber(log.game.playlist_id)
    if playlist_id then match_mode = LOG_PLAYLISTS[playlist_id] end
end

local function rank_matches(rank, selected)
    if tonumber(rank.playlist_id) == selected.id then return true end
    for _, alias in ipairs(selected.aliases or {}) do if tonumber(rank.playlist_id) == alias then return true end end
    local name = string.lower(tostring(rank.playlist_name or ""))
    for _, candidate in ipairs(selected.names) do
        if name == string.lower(candidate) then return true end
    end
    return false
end

local function load_thresholds(playlist_id)
    local text = nil
    if type(kingmod.read_asset_text) == "function" then
        text = kingmod.read_asset_text("RankNumbers/" .. playlist_id .. ".json")
    end
    -- Compatibility for currently released Hebnix builds: read this plugin's
    -- own bundled table only, never an arbitrary user-supplied path.
    if not text and io and io.open then
        local appdata = os.getenv("APPDATA")
        if appdata and appdata ~= "" then
            local path = appdata .. "/Hebnix/plugins/RankViewer/assets/RankNumbers/" .. playlist_id .. ".json"
            local file = io.open(path, "r")
            if file then text = file:read("*a"); file:close() end
        end
    end
    if not text then return nil end
    text = text:gsub("%s+", "")
    local entries = {}
    for tier, div, min, max in text:gmatch('"tier":(%d+).-"division":(%d+).-"minMMR":(-?%d+),"maxMMR":(-?%d+)') do
        if tonumber(tier) > 0 then
        table.insert(entries, { tier = tonumber(tier), div = tonumber(div), min = tonumber(min), max = tonumber(max) })
        end
    end
    table.sort(entries, function(a, b) return a.min < b.min end)
    return entries
end

local function update_rank()
    refresh_identity()
    local mode = active_mode()
    if not mode or not PLAYLISTS[mode] then return end
    local selected = PLAYLISTS[mode]
    local key
    if platform == "epic" then
        if not primary_id then return end
        key = "epic:" .. primary_id
        if tracker_key ~= key or os.time() - requested_at > 300 then
            tracker_key = kingmod.fetch_profile_async("epic", primary_id) or key
            requested_at = os.time()
        end
    else
        if not primary_id then return end
        key = primary_id
        if tracker_key ~= key or os.time() - requested_at > 300 then
            kingmod.fetch_stats_async(primary_id, local_name); tracker_key, requested_at = key, os.time()
        end
    end
    local stats = kingmod.stats_result(tracker_key or key)
    if type(stats) ~= "table" or stats.error then return end
    for _, rank in pairs(stats.ranks or {}) do
        if rank_matches(rank, selected) then
            result.mmr = tonumber(rank.mmr)
            result.tier = math.max(0, math.min(22, math.floor(tonumber(rank.tier_id) or 0)))
            result.division = math.max(0, math.floor(tonumber(rank.division_id) or 0))
            result.rank_name = tostring(rank.tier_name or "Unranked")
            result.entries = load_thresholds(selected.id)
            return
        end
    end
end

local function threshold_entries()
    local entries = result.entries
    if not entries or not result.mmr then return nil, nil, nil end
    -- Tracker's division numbering varies by endpoint.  Use the real MMR range
    -- rather than trusting that number, so neighbouring thresholds stay correct.
    local current_index = #entries
    for index, entry in ipairs(entries) do
        if result.mmr <= entry.max then current_index = index; break end
    end
    return entries[math.max(1, current_index - 1)], entries[current_index], entries[math.min(#entries, current_index + 1)]
end

local function rank_div_label(entry)
    if not entry then return "Unranked" end
    local tier = math.max(0, math.min(22, tonumber(entry.tier) or 0))
    if tier == 0 then return "Unranked" end
    if tier == 22 then return "Supersonic Legend" end
    local groups = { "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Champion", "Grand Champion" }
    local group_index = math.floor((tier - 1) / 3) + 1
    local rank_number = ((tier - 1) % 3) + 1
    local division = (tonumber(entry.div) or tonumber(result.division) or 0) + 1
    return groups[group_index] .. " " .. rank_number .. " - Div " .. math.max(1, math.min(4, division))
end
function plugin.on_load() refresh_identity() end
function plugin.on_tick()
    if show_viewer then update_rank() end
end
function plugin.on_game_event(event_type, event)
    if event_type == "MatchCreated" or event_type == "CountdownBegin" then
        show_viewer = false
        refresh_identity(true)
    elseif event_type == "MatchEnded" then
        refresh_identity(true)
        if match_mode and PLAYLISTS[match_mode] then
            show_viewer = true
            update_rank()
        end
    elseif event_type == "GameLeft" or event_type == "MatchDestroyed" then
        show_viewer = false
    end
end
function plugin.on_overlay(draw, w, h)
    if not kingmod.get_bool("rankviewer_enabled", true) then return end
    if not show_viewer then return end
    local mode = active_mode()
    if not mode then return end
    local prev, current, next = threshold_entries()
    if result.mmr and not current then
        -- Compatibility fallback used only before the rebuilt host exposes the
        -- RankNumbers asset API. Keep the same tier for ordinary div changes.
        local tier, div = result.tier, result.division
        local prev_tier, prev_div = tier, div - 1
        if prev_div < 0 then prev_tier, prev_div = math.max(0, tier - 1), 3 end
        local next_tier, next_div = tier, div + 1
        if next_div > 3 then next_tier, next_div = math.min(22, tier + 1), 0 end
        prev = { tier = prev_tier, div = prev_div, min = result.mmr - 25, max = result.mmr - 1 }
        current = { tier = tier, div = div, min = result.mmr - 12, max = result.mmr + 12 }
        next = { tier = next_tier, div = next_div, min = result.mmr + 1, max = result.mmr + 25 }
    end

    -- Original RankViewer layout: a full-height black right rail with the next,
    -- current, and previous MMR cards positioned from top to bottom.
    local scale = 1.2
    local rail_w, card_w, card_h = 50 * scale, 220 * scale, 88 * scale
    local right_pad = 0
    local rail_x, card_x = w - rail_w, w - right_pad - card_w
    local top_y, bottom_y = 125 * scale, h - 125 * scale - card_h
    -- Keep the three cards explicitly separated while validating the port.
    local current_y = math.floor((h - card_h) * 0.5)
    local dark, blue, white, dark_blue = "#000000e8", "#dff8ffff", "#f4f8ffff", "#036190ff"

    -- Black connector lines only fill the gaps between the three rank cards.
    local first_gap = math.max(0, current_y - (top_y + card_h))
    local second_gap = math.max(0, bottom_y - (current_y + card_h))
    draw.rect(rail_x, top_y + card_h, rail_w, first_gap, { color = "#000000ff", filled = true })
    draw.rect(rail_x, current_y + card_h, rail_w, second_gap, { color = "#000000ff", filled = true })
    local function draw_card(entry, label, cy, bg, fg, value)
        draw.rect(card_x, cy, card_w, card_h, { color = bg, filled = true })
        draw.rect(card_x, cy, card_w, card_h, { color = "#173150ff", width = 1 })
        local tier = entry and entry.tier or result.tier
        draw.image("assets/ranks/" .. math.max(0, math.min(22, tier)) .. ".png", card_x + 10 * scale, cy + 11 * scale, 55 * scale, 55 * scale)
        draw.text(card_x + 76 * scale, cy + 12 * scale, label, { color = fg, size = 11 * scale })
        draw.text(card_x + 76 * scale, cy + 31 * scale, value and tostring(math.floor(value)) or "—", { color = fg, size = 25 * scale })
        draw.text(card_x + 149 * scale, cy + 38 * scale, "MMR", { color = fg, size = 12 * scale })
        draw.text(card_x + 10 * scale, cy + card_h - 25 * scale, rank_div_label(entry), { color = fg, size = 11 * scale })
    end
    draw_card(next, "NEXT", top_y, dark, white, next and next.min)
    draw_card(current, "CURRENT", current_y, blue, dark_blue, result.mmr)
    draw_card(prev, "PREVIOUS", bottom_y, dark, white, prev and prev.max)
end
return plugin



















