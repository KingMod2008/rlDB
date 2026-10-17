local plugin = {}

plugin.overlay_page = "post-match-analysis.html?v=local-platform-id-1"
plugin.clickable = true

local archive = {}
local current_match = nil
local menu_visible = true
local sequence = 0
local last_rank_poll = 0
local rank_pending = {}
local rank_cache = {}
local local_platform_id = nil
local local_identity_ids = {}
local identity_log_key = nil
local next_identity_retry = 0

local RANKED_PLAYLISTS = {
    [10] = { "Ranked Duel 1v1", "Ranked 1v1" },
    [11] = { "Ranked Doubles 2v2", "Ranked 2v2" },
    [13] = { "Ranked Standard 3v3", "Ranked 3v3" },
    [27] = { "Hoops" },
    [28] = { "Rumble" },
    [29] = { "Dropshot" },
    [30] = { "Snowday", "Snow Day" },
    [34] = { "Tournaments", "Tournament" },
    [63] = { "Heatseeker", "Heatseeker Doubles", "2v2 Heatseeker" },
}


local function value(source, ...)
    if type(source) ~= "table" then return nil end
    for index = 1, select("#", ...) do
        local result = source[select(index, ...)]
        if result ~= nil then return result end
    end
    return nil
end

local function number(raw, fallback)
    local parsed = tonumber(raw)
    if parsed == nil then return fallback end
    return parsed
end

local function request_local_identity(reset)
    if reset then
        hebnix.clear_launch_log()
        identity_log_key = nil
        local_platform_id = nil
        local_identity_ids = {}
    end
    if not identity_log_key then identity_log_key = hebnix.parse_launch_log_async(false) end
end

local function poll_local_identity()
    if #local_identity_ids > 0 then return end
    if not identity_log_key then request_local_identity(false) end
    local info = hebnix.launch_log_result(identity_log_key)
    if type(info) ~= "table" then return end
    local session = value(info, "session", "Session")
    local candidates = {}
    local function add(id)
        if not id or id == "" then return end
        for _, existing in ipairs(candidates) do
            if existing:lower() == id:lower() then return end
        end
        table.insert(candidates, id)
    end
    local epic = value(session, "epic_id", "EpicId")
    if epic and tostring(epic) ~= "" then add("Epic|" .. tostring(epic) .. "|0") end
    local steam = value(session, "steam_id", "SteamId")
    if steam and tostring(steam) ~= "" then add("Steam|" .. tostring(steam) .. "|0") end
    local primary = tostring(value(session, "primary_id", "PrimaryId") or "")
    if primary:match("^[^|]+|[^|]+|%d+$") and not primary:lower():match("^unknown|") then add(primary) end
    if #candidates > 0 then
        local_identity_ids = candidates
        return
    end
    local now = hebnix.monotonic_seconds()
    if now >= next_identity_retry then
        next_identity_retry = now + 5
        request_local_identity(true)
    end
end
local function player_id(player, index)
    return tostring(value(player, "PrimaryId", "primary_id") or value(player, "Shortcut", "shortcut") or index)
end

local function archive_path()
    if type(hebnix.plugin_dir) ~= "function" then return nil end
    return hebnix.plugin_dir() .. "\\assets\\matches.json"
end

local function load_archive()
    local path = archive_path()
    if not path then return end
    local file = io.open(path, "rb")
    if not file then return end
    local encoded = file:read("*a")
    file:close()
    local ok, decoded = pcall(hebnix.json_decode, encoded)
    if ok and type(decoded) == "table" then archive = decoded end
    while #archive > 10 do table.remove(archive) end
end

local function save_archive()
    local path = archive_path()
    if not path then return end
    local ok, encoded = pcall(hebnix.json_encode, archive)
    if not ok then return end
    local file = io.open(path, "wb")
    if not file then return end
    file:write(encoded)
    file:close()
end

local function format_clock(seconds)
    seconds = math.max(0, math.floor(number(seconds, 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function new_match(payload)
    local data = payload and value(payload, "data", "Data") or nil
    local game = data and value(data, "Game", "game") or nil
    sequence = 0
    current_match = {
        played_at = os.date("%Y-%m-%d %H:%M"),
        arena = tostring(value(game, "Arena", "arena") or "Unknown arena"),
        playlist_id = number(value(game, "PlaylistId", "playlist_id"), 0),
        events = {},
        players = {},
        local_platform_id = nil,
        teams = {},
        last_stats = {},
        player_metrics = {},
        roster_seen = {},
        lead_history = {},
        overtime = false,
        overtime_started_at = nil,
        last_sample_at = 0,
        rank_generation = tostring(os.time()) .. "-" .. tostring(hebnix.monotonic_seconds()),
        clock_seconds = 300,
        started = false,
        started_at = nil,
        result = "Completed",
    }
end

local function ensure_match(payload)
    if not current_match then new_match(payload) end
    return current_match
end

local function mark_match_started(payload)
    local match = ensure_match(payload)
    if match.started then return match end
    match.started = true
    match.started_at = hebnix.monotonic_seconds()
    match.clock_seconds = 300
    match.events = {}
    match.last_stats = {}
    match.player_metrics = {}
    match.roster_seen = {}
    match.lead_history = {}
    match.overtime = false
    match.overtime_started_at = nil
    match.last_sample_at = 0
    sequence = 0
    return match
end

local function add_timeline_event(kind, player, team, related, related_team, relation, details)
    if not current_match or not current_match.started or not current_match.started_at then return nil end
    sequence = sequence + 1
    local elapsed = math.max(0, math.floor(hebnix.monotonic_seconds() - current_match.started_at))
    local item = {
        sequence = sequence,
        kind = kind,
        player = player,
        team = team,
        clock = format_clock(elapsed),
        elapsed = elapsed,
    }
    if related and related ~= "" then item.related = related end
    if related_team ~= nil then item.related_team = related_team end
    if relation and relation ~= "" then item.relation = relation end
    if type(details) == "table" then
        for key, detail in pairs(details) do item[key] = detail end
    end
    table.insert(current_match.events, item)
    return item
end

local function add_unique_timeline_event(kind, player, team, related, related_team, relation, details)
    if not current_match or not current_match.started or not current_match.started_at then return nil end
    local elapsed = math.max(0, math.floor(hebnix.monotonic_seconds() - current_match.started_at))
    for index = #current_match.events, 1, -1 do
        local item = current_match.events[index]
        if elapsed - number(item.elapsed, 0) > 2 then break end
        if item.kind == kind and item.player == player then
            if related and related ~= "" then item.related = related end
            if related_team ~= nil then item.related_team = related_team end
            if relation and relation ~= "" then item.relation = relation end
            if type(details) == "table" then
                for key, detail in pairs(details) do item[key] = detail end
            end
            return item
        end
    end
    return add_timeline_event(kind, player, team, related, related_team, relation, details)
end

local function copy_team_scores(game)
    local teams = value(game, "Teams", "teams")
    if type(teams) ~= "table" then return end
    local copied = {}
    local blue, orange = 0, 0
    for _, team in ipairs(teams) do
        local team_number = number(value(team, "TeamNum", "team_num"), 0)
        local score = number(value(team, "Score", "score"), 0)
        if team_number == 0 then blue = score elseif team_number == 1 then orange = score end
        table.insert(copied, {
            team = team_number,
            name = tostring(value(team, "Name", "name") or "Team"),
            score = score,
        })
    end
    current_match.teams = copied
    if current_match.started and current_match.started_at then
        local history = current_match.lead_history or {}
        local last = history[#history]
        if not last or number(last.blue, -1) ~= blue or number(last.orange, -1) ~= orange then
            local elapsed = math.max(0, math.floor(hebnix.monotonic_seconds() - current_match.started_at))
            table.insert(history, {
                elapsed = elapsed,
                clock = format_clock(elapsed),
                blue = blue,
                orange = orange,
                leader = blue == orange and -1 or (blue > orange and 0 or 1),
            })
            current_match.lead_history = history
        end
    end
end

local tracked_stats = {
    { field = "Shots", kind = "Shot" },
    { field = "Saves", kind = "Save" },
    { field = "Goals", kind = "Goal" },
    { field = "Assists", kind = "Assist" },
    { field = "Demos", kind = "Demo" },
}

local function rank_key(id, playlist_id, generation)
    return tostring(id) .. ":" .. tostring(playlist_id) .. ":" .. tostring(generation or "current")
end

local function rank_matches_playlist(rank, playlist_id)
    return number(value(rank, "playlist_id", "playlistId"), -1) == playlist_id
end

local function division_roman(rank)
    local division = math.max(0, math.min(3, math.floor(number(value(rank, "division_id", "divisionId"), 0))))
    return ({ "I", "II", "III", "IV" })[division + 1]
end

local function profile_identity(primary_id)
    local platform, account_id = tostring(primary_id or ""):match("^([^|]+)|([^|]+)")
    if not platform or not account_id or account_id == "" then return nil, nil end
    platform = string.lower(platform)
    if platform == "epicgames" then platform = "epic" end
    if platform == "xbl" or platform == "xbox" then platform = "xboxone" end
    if platform == "ps4" or platform == "ps5" or platform == "playstation" then platform = "psn" end
    if platform == "nintendo" then platform = "switch" end
    if platform ~= "epic" and platform ~= "steam" and platform ~= "xboxone"
        and platform ~= "psn" and platform ~= "switch" then return nil, nil end
    return platform, account_id
end

local function request_player_rank(match, id, name)
    local playlist_id = number(match.playlist_id, 0)
    if not RANKED_PLAYLISTS[playlist_id] or id == "" then return nil end
    if type(hebnix.is_bot) == "function" and hebnix.is_bot(id) then return nil end
    local key = rank_key(id, playlist_id, match.rank_generation)
    if rank_cache[key] then return rank_cache[key] end
    if rank_pending[key] then rank_pending[key].matches[match] = true; return nil end
    local platform, account_id = profile_identity(id)
    if not platform then return nil end
    local poll_key = hebnix.fetch_profile_async(platform, account_id)
    if not poll_key then return nil end
    rank_pending[key] = { id = id, poll_key = poll_key, playlist_id = playlist_id, matches = { [match] = true } }
    return nil
end
local function apply_rank(match, id, rank)
    local changed = false
    for _, player in ipairs(match.players or {}) do
        if tostring(player.id or "") == id then
            player.rank_name = rank.name
            player.rank_division = rank.division
            player.rank_mmr = rank.mmr
            player.rank_tier_id = rank.tier_id
            player.rank_division_id = rank.division_id
            changed = true
        end
    end
    return changed
end

local function poll_player_ranks()
    local now = hebnix.monotonic_seconds()
    if now - last_rank_poll < 0.5 then return false end
    last_rank_poll = now
    local changed = false
    for key, pending in pairs(rank_pending) do
        local stats = hebnix.stats_result(pending.poll_key)
        if stats ~= nil and stats ~= "pending" then
            local resolved = { name = "Unranked", division = nil, mmr = nil, tier_id = 0, division_id = -1 }
            if type(stats) == "table" and stats.error == nil then
                for rank_key_value, rank in pairs(stats.ranks or {}) do
                    if rank_matches_playlist(rank, pending.playlist_id)
                        or number(rank_key_value, -1) == pending.playlist_id then
                        resolved.name = tostring(value(rank, "tier_name", "tierName") or "Unranked")
                        resolved.mmr = number(value(rank, "mmr", "rating"), nil)
                        resolved.tier_id = math.max(0, math.min(23, math.floor(number(value(rank, "tier_id", "tierId"), 0))))
                        resolved.division_id = math.max(0, math.min(3, math.floor(number(value(rank, "division_id", "divisionId"), 0))))
                        if number(value(rank, "tier_id", "tierId"), 0) > 0 then resolved.division = division_roman(rank) end
                        break
                    end
                end
            end
            rank_cache[key] = resolved
            for match in pairs(pending.matches) do
                if apply_rank(match, pending.id, resolved) then changed = true end
            end
            rank_pending[key] = nil
        end
    end
    return changed
end

local function copy_loadout(player)
    local raw = value(player, "Loadout", "loadout")
    if type(raw) ~= "table" then return nil end
    return {
        body = tostring(raw[1] or "None"),
        decal = tostring(raw[2] or "None"),
        wheels = tostring(raw[3] or "None"),
        boost = tostring(raw[4] or "None"),
        goal_explosion = tostring(raw[16] or "None"),
    }
end

local function update_player_metrics(match, id, player, summary, should_sample)
    local metrics = match.player_metrics[id] or {
        samples = 0, boost_sum = 0, low_boost = 0, empty_boost = 0, full_boost = 0,
        boost_used = 0, boost_collected = 0, speed_sum = 0, grounded = 0, active = 0,
    }
    if should_sample then
        local boost = number(value(player, "Boost", "boost"), -1)
        local speed = math.max(0, number(value(player, "Speed", "speed"), 0))
        if boost >= 0 then
            metrics.samples = metrics.samples + 1
            metrics.boost_sum = metrics.boost_sum + boost
            if boost <= 10 then metrics.low_boost = metrics.low_boost + 1 end
            if boost <= 1 then metrics.empty_boost = metrics.empty_boost + 1 end
            if boost >= 99 then metrics.full_boost = metrics.full_boost + 1 end
            if metrics.last_boost ~= nil then
                local delta = boost - metrics.last_boost
                if delta < 0 then metrics.boost_used = metrics.boost_used - delta else metrics.boost_collected = metrics.boost_collected + delta end
            end
            metrics.last_boost = boost
            metrics.speed_sum = metrics.speed_sum + speed
            if value(player, "bOnGround", "on_ground") == true then metrics.grounded = metrics.grounded + 1 end
            if speed > 50 then metrics.active = metrics.active + 1 end
        end
    end
    match.player_metrics[id] = metrics
    local samples = math.max(1, number(metrics.samples, 0))
    summary.average_boost = metrics.boost_sum / samples
    summary.low_boost_percent = metrics.low_boost / samples * 100
    summary.empty_boost_percent = metrics.empty_boost / samples * 100
    summary.full_boost_percent = metrics.full_boost / samples * 100
    summary.boost_used = metrics.boost_used
    summary.boost_collected = metrics.boost_collected
    summary.average_speed = metrics.speed_sum / samples
    summary.grounded_percent = metrics.grounded / samples * 100
    summary.activity_percent = metrics.active / samples * 100
    summary.touches = math.max(0, math.floor(number(value(player, "Touches", "touches", "CarTouches", "car_touches"), 0)))
    summary.loadout = copy_loadout(player)
end

local function update_match(payload)
    local data = payload and value(payload, "data", "Data") or nil
    local players = data and value(data, "Players", "players") or nil
    local game = data and value(data, "Game", "game") or nil
    if type(players) ~= "table" or #players == 0 or type(game) ~= "table" then return end

    local match = current_match
    if not match or not match.started then return end
    match.arena = tostring(value(game, "Arena", "arena") or match.arena)
    match.playlist_id = number(value(game, "PlaylistId", "playlist_id"), match.playlist_id)
    local now = hebnix.monotonic_seconds()
    local should_sample = now - number(match.last_sample_at, 0) >= 0.25
    if should_sample then match.last_sample_at = now end
    local overtime_started = value(game, "bOvertime", "overtime") == true and not match.overtime
    if overtime_started then
        match.overtime = true
        match.overtime_started_at = math.max(0, math.floor(now - match.started_at))
        add_timeline_event("Overtime", "Overtime began", 255)
    end
    local roster_local_id
    for _, candidate in ipairs(local_identity_ids) do
        for _, player in ipairs(players) do
            local primary = value(player, "PrimaryId", "primary_id")
            if primary and tostring(primary):lower() == candidate:lower() then
                roster_local_id = tostring(primary)
                break
            end
        end
        if roster_local_id then break end
    end
    if roster_local_id then
        local_platform_id = roster_local_id
        match.local_platform_id = roster_local_id
    end
    copy_team_scores(game)

    local previous_players = {}
    for _, player in ipairs(match.players or {}) do previous_players[tostring(player.id or "")] = player end
    local latest_players = {}
    local seen_players = {}
    for index, player in ipairs(players) do
        local id = player_id(player, index)
        local name = tostring(value(player, "Name", "name") or "Player")
        local team = number(value(player, "TeamNum", "team_num"), 255)
        local player_shortcut = value(player, "Shortcut", "shortcut")
        if roster_local_id and id:lower() == roster_local_id:lower() then
            match.local_platform_id = id
            match.local_player = name
        end
        local previous = match.last_stats[id]
        local snapshot = { name = name, team = team }
        local summary = {
            id = id,
            name = name,
            team = team,
            shortcut = player_shortcut,
            score = math.max(0, math.floor(number(value(player, "Score", "score"), 0))),
            left = false,
        }
        seen_players[id] = true
        if match.initial_roster_captured and not match.roster_seen[id] then
            add_timeline_event("Player Joined", name, team)
        elseif previous_players[id] and previous_players[id].left then
            summary.rejoined = true
            summary.rejoin_count = number(previous_players[id].rejoin_count, 0) + 1
            add_timeline_event("Player Rejoined", name, team)
        elseif previous_players[id] then
            summary.rejoin_count = number(previous_players[id].rejoin_count, 0)
        end
        match.roster_seen[id] = true
        local known_rank = request_player_rank(match, id, name)
        if known_rank then
            summary.rank_name = known_rank.name
            summary.rank_division = known_rank.division
            summary.rank_mmr = known_rank.mmr
            summary.rank_tier_id = known_rank.tier_id
            summary.rank_division_id = known_rank.division_id
        elseif previous_players[id] then
            summary.rank_name = previous_players[id].rank_name
            summary.rank_division = previous_players[id].rank_division
            summary.rank_mmr = previous_players[id].rank_mmr
            summary.rank_tier_id = previous_players[id].rank_tier_id
            summary.rank_division_id = previous_players[id].rank_division_id
        end

        for _, tracked in ipairs(tracked_stats) do
            local count = math.max(0, math.floor(number(value(player, tracked.field, tracked.field:lower()), 0)))
            snapshot[tracked.field] = count
            summary[tracked.field:lower()] = count
            -- Goals and assists come from authoritative game events. UpdateState
            -- can briefly contain unnamed mirror rows whose counters rise later,
            -- which previously invented blue "Player" goals after real orange goals.
            if previous and name ~= "Player" and tracked.kind ~= "Goal" and tracked.kind ~= "Assist" then
                local increase = math.max(0, count - number(previous[tracked.field], 0))
                for _ = 1, increase do add_unique_timeline_event(tracked.kind, name, team) end
            end
        end

        local demolished = value(player, "bDemolished", "demolished") == true
        local attacker = value(player, "Attacker", "attacker")
        snapshot.demolished = demolished
        if previous and demolished and not previous.demolished and type(attacker) == "table" then
            local attacker_name = tostring(value(attacker, "Name", "name") or "Player")
            local attacker_team = number(value(attacker, "TeamNum", "team_num"), 255)
            add_unique_timeline_event("Demo", attacker_name, attacker_team, name, team, "demolished")
        end

        update_player_metrics(match, id, player, summary, should_sample)
        match.last_stats[id] = snapshot
        table.insert(latest_players, summary)
    end
    for id, player in pairs(previous_players) do
        if not seen_players[id] then
            if not player.left then add_timeline_event("Player Left", player.name or "Player", player.team) end
            player.left = true
            table.insert(latest_players, player)
        end
    end
    match.players = latest_players
    match.initial_roster_captured = true
    if overtime_started then
        match.overtime_baseline = {}
        for _, player in ipairs(latest_players) do
            match.overtime_baseline[tostring(player.id or "")] = {
                goals = player.goals, assists = player.assists, saves = player.saves,
                shots = player.shots, demos = player.demos, score = player.score,
            }
        end
    end
end

local function timeline_player(subject)
    if type(subject) ~= "table" then return "Player", 255 end
    local name = value(subject, "Name", "name", "PlayerName", "player_name", "DisplayName", "display_name")
    local team = number(value(subject, "TeamNum", "team_num", "Team", "team"), 255)
    local id = tostring(value(subject, "PrimaryId", "primary_id", "PlayerID", "player_id", "UniqueId", "unique_id") or "")
    local shortcut = value(subject, "Shortcut", "shortcut")
    if name ~= nil and tostring(name) ~= "" and tostring(name) ~= "Player" then return tostring(name), team end
    local nested = value(subject, "Player", "player", "Target", "target", "PRI", "pri")
    if type(nested) == "table" and nested ~= subject then
        local nested_name, nested_team = timeline_player(nested)
        if nested_name ~= "Player" then return nested_name, nested_team end
    end
    for _, known in ipairs((current_match and current_match.players) or {}) do
        if id ~= "" and tostring(known.id or "") == id then return tostring(known.name or "Player"), number(known.team, team) end
        if shortcut ~= nil and known.shortcut ~= nil and tostring(known.shortcut) == tostring(shortcut) then
            return tostring(known.name or "Player"), number(known.team, team)
        end
    end
    return "Player", team
end
local function record_goal(payload)
    local data = payload and value(payload, "data", "Data") or nil
    if type(data) ~= "table" then return end
    if not current_match or not current_match.started then return end
    local scorer = value(data, "Scorer", "scorer")
    if type(scorer) ~= "table" then return end
    local assister = value(data, "Assister", "assister")
    local scorer_name, scorer_team = timeline_player(scorer)
    -- StatsAPI emits a delayed, anonymous GoalScored echo after the real event.
    -- It has no resolvable scorer, defaults to blue, and must not enter the timeline.
    if scorer_name == "Player" then return end
    local related, related_team
    if type(assister) == "table" then
        related, related_team = timeline_player(assister)
        if related == "Player" then related = nil end
    end
    add_unique_timeline_event(
        "Goal",
        scorer_name,
        scorer_team,
        related,
        related_team,
        related and "assisted by" or nil,
        { goal_speed = number(value(data, "GoalSpeed", "goal_speed"), 0) }
    )
    if related and related ~= "" then
        add_unique_timeline_event("Assist", related, related_team or scorer_team, scorer_name, scorer_team, "assisted")
    end
end

local function record_statfeed(payload)
    local data = payload and value(payload, "data", "Data") or nil
    if type(data) ~= "table" then return end
    if not current_match or not current_match.started then return end
    local event_name = string.lower(tostring(value(data, "EventName", "event_name") or ""))
    local event_type = string.lower(tostring(value(data, "Type", "type") or ""))
    local main = value(data, "MainTarget", "main_target")
    local secondary = value(data, "SecondaryTarget", "secondary_target")
    if type(main) ~= "table" then return end

    local kind
    local relation
    if event_name:find("bump", 1, true) or event_type:find("bump", 1, true) then
        kind, relation = "Bump", "bumped"
    elseif event_name:find("demol", 1, true) or event_type:find("demol", 1, true) then
        kind, relation = "Demo", "demolished"
    elseif event_name:find("save", 1, true) or event_type:find("save", 1, true) then
        kind, relation = "Save", "saved a shot by"
    elseif event_name:find("shot", 1, true) or event_type:find("shot", 1, true) then
        kind, relation = "Shot", "shot against"
    else
        return
    end

    local main_name, main_team = timeline_player(main)
    local related, related_team
    if type(secondary) == "table" then
        related, related_team = timeline_player(secondary)
        if related == "Player" then related = nil end
    end
    add_unique_timeline_event(kind, main_name, main_team, related, related_team, related and relation or nil)
end

local function reconcile_goal_events(match)
    local recorded = {}
    local highest_sequence = 0
    for _, event in ipairs(match.events or {}) do
        highest_sequence = math.max(highest_sequence, number(event.sequence, 0))
        if event.kind == "Goal" and event.player ~= "Player" then
            local key = tostring(event.team) .. "|" .. tostring(event.player)
            recorded[key] = number(recorded[key], 0) + 1
        end
    end
    local elapsed = math.max(0, math.floor(number(match.duration_seconds, 0)))
    for _, player in ipairs(match.players or {}) do
        local key = tostring(player.team) .. "|" .. tostring(player.name)
        local missing = math.max(0, math.floor(number(player.goals, 0) - number(recorded[key], 0)))
        for _ = 1, missing do
            highest_sequence = highest_sequence + 1
            table.insert(match.events, {
                sequence = highest_sequence, kind = "Goal", player = player.name,
                team = player.team, elapsed = elapsed, clock = format_clock(elapsed),
                reconciled = true,
            })
        end
    end
end
local function finalize_match(result)
    if not current_match then return end
    local completed = current_match
    current_match = nil
    if not completed.started or not completed.started_at then return end
    completed.result = result or completed.result
    completed.duration_seconds = math.max(0, math.floor(hebnix.monotonic_seconds() - completed.started_at))
    reconcile_goal_events(completed)
    completed.last_stats = nil
    completed.player_metrics = nil
    completed.roster_seen = nil
    completed.initial_roster_captured = nil
    completed.last_sample_at = nil
    completed.rank_generation = nil
    completed.started_at = nil
    completed.started = nil
    table.insert(archive, 1, completed)
    while #archive > 10 do table.remove(archive) end
    save_archive()
end

local function send_overlay()
    -- Keep the iframe stable. Its JS reports an empty pointer region in-game.
    -- Toggling this rebuilt the iframe after the visible message and lost the launcher state.
    plugin.clickable = true
    hebnix.overlay.send({
        visible = menu_visible,
        matches = archive,
    })
end

local function queue_archive_ranks()
    for index, match in ipairs(archive) do
        local playlist_id = number(match.playlist_id, 0)
        if RANKED_PLAYLISTS[playlist_id] then
            local previous_generation = match.rank_generation
            match.rank_generation = "archive-" .. tostring(match.played_at or index) .. "-" .. tostring(index)
            for _, player in ipairs(match.players or {}) do
                local id = tostring(player.id or "")
                local known = request_player_rank(match, id, tostring(player.name or ""))
                if known then apply_rank(match, id, known) end
            end
            match.rank_generation = previous_generation
        end
    end
end
function plugin.on_load()
    request_local_identity(false)
    load_archive()
    queue_archive_ranks()
    send_overlay()
end

function plugin.on_unload()
    menu_visible = false
    send_overlay()
end

function plugin.on_game_event(event_type, event)
    if event_type == "GameConnected" then
        menu_visible = true
        request_local_identity(true)
    elseif event_type == "MatchCreated" or event_type == "MatchInitialized" then
        menu_visible = false
        if current_match then finalize_match("Interrupted") end
        new_match(event)
    elseif event_type == "CountdownBegin" or event_type == "RoundStarted" then
        menu_visible = false
        mark_match_started(event)
    elseif event_type == "ClockUpdatedSeconds" then
        local data = event and value(event, "data", "Data") or nil
        if current_match and current_match.started and type(data) == "table" then
            current_match.clock_seconds = number(value(data, "TimeSeconds", "Seconds", "seconds"), current_match.clock_seconds)
        end
    elseif event_type == "GoalScored" then
        record_goal(event)
    elseif event_type == "StatfeedEvent" then
        record_statfeed(event)
    elseif event_type == "UpdateState" then
        if current_match then update_match(event) end
    elseif event_type == "MatchEnded" then
        local data = event and value(event, "data", "Data") or nil
        local winner = data and value(data, "WinnerTeamNum", "winner_team_num") or nil
        finalize_match(winner ~= nil and ("Winner: team " .. tostring(winner)) or "Completed")
    elseif event_type == "GameLeft" or event_type == "MatchDestroyed" then
        if current_match and current_match.started then
            add_timeline_event("Left Game", "You left the match", 255)
            for _, player in ipairs(current_match.players or {}) do
                if tostring(player.id or "") == tostring(current_match.local_platform_id or "__no_local__") then player.left = true end
            end
        end
        finalize_match("Left match")
        menu_visible = true
    end
    send_overlay()
end

function plugin.on_tick()
    poll_local_identity()
    if poll_player_ranks() then
        save_archive()
        send_overlay()
    end
end


return plugin

