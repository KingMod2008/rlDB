local plugin = {}

local BASE_URL = "https://seekrstats.com"
local CACHE_TTL = 3600
local UPLOAD_INTERVAL = 10

local discord_id = ""
local loader_key = ""
local discord_username = ""
local discord_role = "User"
local status = "Waiting..."

local current_gamemode = "Waiting for match..."
local current_server_name = "LocalMatch"
local current_region = "Unknown"
local current_match_guid = "0"
local current_playlist = 0
local current_is_tournament = "0"
local current_is_heatseeker = false

local in_match_tracking = false
local current_uploader_id = "0"
local active_match_guid = "0"
local last_valid_snapshot = nil
local last_finished_guid = nil
local last_upload_time = 0
local seen_players = {}
local player_cache = {}
local tracker_pending = {}

local next_log_refresh = 0
local next_heartbeat = 0
local heartbeat_pending = false
local oauth_session = nil
local oauth_deadline = 0
local oauth_next_poll = 0
local oauth_pending = false
local upload_sequence = 0

local function get_value(object, ...)
    if type(object) ~= "table" then return nil end
    for index = 1, select("#", ...) do
        local key = select(index, ...)
        if object[key] ~= nil then return object[key] end
    end
    return nil
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function number(value, fallback)
    local parsed = tonumber(value)
    if parsed == nil then return fallback or 0 end
    return parsed
end

local function setting(key, fallback)
    return hebnix.get_string(key, fallback or "")
end

local function save_auth()
    hebnix.set("discord_id", discord_id)
    hebnix.set("loader_key", loader_key)
    hebnix.set("username", discord_username)
    hebnix.set("role", discord_role)
end

local function detailed_log(message)
    if hebnix.get_bool("seekr_detailed_logging", false) then
        hebnix.log("[Seekr] " .. message)
    end
end

local function url_encode(value)
    return tostring(value or ""):gsub("\n", "\r\n"):gsub("([^%w%-_%.~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
end

local function decode_json(body)
    local ok, result = pcall(hebnix.json_decode, body or "")
    if ok and type(result) == "table" then return result end
    return nil
end

local function auth_headers(timestamp, signature)
    return {
        ["Authorization"] = "Bearer " .. loader_key .. "-" .. discord_id,
        ["X-Seekr-Client-ID"] = discord_id,
        ["X-Seekr-Timestamp"] = timestamp,
        ["X-Seekr-Signature"] = signature,
    }
end

local function authenticated()
    return discord_id ~= "" and loader_key ~= ""
end

local function perform_logout()
    discord_id = ""
    loader_key = ""
    discord_username = ""
    discord_role = "User"
    oauth_session = nil
    oauth_pending = false
    heartbeat_pending = false
    in_match_tracking = false
    current_uploader_id = "0"
    save_auth()
    status = "Pending login"
    hebnix.log("[Seekr] Logged out successfully.")
end

local function start_oauth()
    if oauth_pending then return end
    status = "Contacting Auth Servers..."
    oauth_pending = true
    hebnix.http_get_async("seekr_oauth_init", BASE_URL .. "/api/listener/init", {})
end

local function refresh_log(force)
    local now = os.time()
    if not force and now < next_log_refresh then return end
    next_log_refresh = now + 5

    local parsed = hebnix.parse_launch_log(false)
    local game = parsed and parsed.game
    if type(game) ~= "table" then return end

    current_playlist = number(game.playlist_id, current_playlist)
    current_is_tournament = current_playlist == 34 and "1" or "0"
    current_gamemode = table.concat({
        tostring(game.game_class or ""),
        tostring(game.game_tags or ""),
        tostring(game.game_mode or ""),
        tostring(game.gamemode or ""),
        tostring(game.playlist_name or ""),
    }, " ")
    current_server_name = tostring(game.server_name or current_server_name)
    current_region = tostring(game.region or current_region)
end

local function refresh_match_context(data, game)
    local playlist = get_value(game, "PlaylistId", "playlist_id")
        or get_value(data, "PlaylistId", "playlist_id")
    if playlist ~= nil then
        current_playlist = number(playlist, current_playlist)
        current_is_tournament = current_playlist == 34 and "1" or "0"
    end

    local mode = lower(current_gamemode)
    local explicit_heatseeker = mode:find("godball", 1, true) ~= nil
        or mode:find("heatseeker", 1, true) ~= nil
        or mode:find("territory", 1, true) ~= nil
        or mode:find("ricochet", 1, true) ~= nil
        or mode:find("splitshot", 1, true) ~= nil

    if current_playlist == 6 or current_playlist == 34 then
        current_is_heatseeker = explicit_heatseeker
    else
        current_is_heatseeker = current_playlist == 43
            or current_playlist == 63
            or current_playlist == 66
            or current_playlist == 75
    end
end

local function event_blocks(event)
    local data = get_value(event, "data", "Data") or event or {}
    if type(data) ~= "table" then data = {} end
    local game = get_value(data, "Game", "game") or get_value(event, "Game", "game") or {}
    if type(game) ~= "table" then game = {} end
    return data, game
end

local function event_guid(event, data)
    local guid = get_value(data, "MatchGuid", "match_guid")
        or get_value(event, "MatchGuid", "match_guid")
        or current_match_guid
    guid = tostring(guid or "0")
    if guid == "" then guid = "0" end
    return guid
end

local function target_name(game, data)
    local target = get_value(game, "Target", "target") or get_value(data, "Target", "target")
    if type(target) == "table" then
        return trim(get_value(target, "Name", "name"))
    end
    return trim(target)
end

local function lock_uploader(data, game)
    if current_uploader_id ~= "0" then return end
    local wanted = lower(target_name(game, data))
    local players = get_value(data, "Players", "players")
    if wanted == "" or type(players) ~= "table" then return end

    for _, player in ipairs(players) do
        local name = lower(get_value(player, "Name", "name"))
        local platform_id = tostring(get_value(player, "PrimaryId", "primary_id") or "0")
        if name ~= "" and (name == wanted or name:find(wanted, 1, true) or wanted:find(name, 1, true)) then
            current_uploader_id = platform_id
            detailed_log("Uploader ID locked: " .. current_uploader_id)
            return
        end
    end
end

local function profile_identity(primary_id)
    local platform, account_id = tostring(primary_id or ""):match("^([^|]+)|([^|]+)")
    if not platform or not account_id or account_id == "" then return nil, nil end
    platform = lower(platform)
    if platform == "xbl" or platform == "xbox" then platform = "xboxone" end
    if platform == "ps4" or platform == "ps5" or platform == "playstation" then platform = "psn" end
    if platform == "nintendo" then platform = "switch" end
    return platform, account_id
end

local function request_player_stats(platform_id)
    if tracker_pending[platform_id] then return tracker_pending[platform_id] end
    local platform, account_id = profile_identity(platform_id)
    if not platform or not account_id then return nil end
    local request_key = hebnix.fetch_profile_async(platform, account_id)
    if request_key then tracker_pending[platform_id] = request_key end
    return request_key
end

local function read_player_stats(platform_id)
    local request_key = tracker_pending[platform_id]
    if not request_key then return nil end
    local result = hebnix.stats_result(request_key)
    if result == nil or result == "pending" then return nil end

    local ranks = type(result) == "table" and result.ranks or nil
    local cached = {
        timestamp = os.time(),
        casual_mmr = 0,
        comp_hs_mmr = 0,
        comp_hs_rank = 0,
        tourn_mmr = 0,
        tourn_rank = 0,
    }
    if type(ranks) == "table" then
        for _, rank in pairs(ranks) do
            local playlist_id = number(rank.playlist_id, -1)
            if playlist_id == 0 then
                cached.casual_mmr = number(rank.mmr)
            elseif playlist_id == 34 then
                cached.tourn_mmr = number(rank.mmr)
                cached.tourn_rank = number(rank.tier_id)
            elseif playlist_id == 63 then
                cached.comp_hs_mmr = number(rank.mmr)
                cached.comp_hs_rank = number(rank.tier_id)
            end
        end
    end
    player_cache[platform_id] = cached
    tracker_pending[platform_id] = nil
    return cached
end

local function player_rank_data(platform_id, player_name, match_type)
    local result = { mmr = 0, comp_rank = 0, tourn_rank = 0 }
    local id = tostring(platform_id or "0")
    if match_type:match("^Private") or id == "0" or lower(id):find("bot", 1, true) then
        return result
    end

    local cached = player_cache[id]
    if cached and os.time() - number(cached.timestamp) > CACHE_TTL then
        cached = nil
        player_cache[id] = nil
        tracker_pending[id] = nil
    end
    if not cached then
        if not seen_players[id] then
            seen_players[id] = true
            detailed_log("Fetching competitor: " .. tostring(player_name))
        end
        request_player_stats(id)
        cached = read_player_stats(id)
    end
    if not cached then return result end

    if match_type == "Competitive" then
        result.mmr = number(cached.comp_hs_mmr)
        result.comp_rank = number(cached.comp_hs_rank)
    elseif match_type == "Tournament" then
        result.mmr = number(cached.tourn_mmr)
        result.tourn_rank = number(cached.tourn_rank)
    else
        result.mmr = number(cached.casual_mmr)
    end
    return result
end

local function winner_team(game)
    local raw = tostring(get_value(game, "Winner", "winner") or "-1")
    local normalized = lower(raw)
    if normalized:find("blue", 1, true) then return "0" end
    if normalized:find("orange", 1, true) then return "1" end
    return tostring(number(raw, -1))
end

local function extract_payload(event, match_status)
    local data, game = event_blocks(event)
    local players = get_value(data, "Players", "players") or {}
    local teams = get_value(game, "Teams", "teams") or get_value(data, "Teams", "teams") or {}
    local guid = event_guid(event, data)
    if guid == "0" then guid = active_match_guid end
    if guid == "0" then guid = current_match_guid end

    local blue_goals, orange_goals = 0, 0
    local blue_name, orange_name = "Blue", "Orange"
    local blue_colour, orange_colour = "38bdf8", "fb923c"
    if type(teams) == "table" then
        for _, team in ipairs(teams) do
            local team_num = number(get_value(team, "TeamNum", "team_num"), -1)
            local name = tostring(get_value(team, "Name", "name") or "")
            local colour = tostring(get_value(team, "ColorPrimary", "color_primary") or "")
            local score = number(get_value(team, "Score", "score"))
            if team_num == 0 or lower(name) == "blue" then
                blue_goals = score
                if name ~= "" then blue_name = name end
                if colour ~= "" then blue_colour = colour end
            elseif team_num == 1 or lower(name) == "orange" then
                orange_goals = score
                if name ~= "" then orange_name = name end
                if colour ~= "" then orange_colour = colour end
            end
        end
    end

    local map_name = tostring(get_value(game, "Arena", "arena")
        or get_value(data, "MapName", "map_name") or "Unknown")
    local mode = lower(current_gamemode)
    local variant
    if mode:find("heatseekerterritory", 1, true) or mode:find("splitshot", 1, true)
        or current_playlist == 75 then
        variant = "Splitshot"
    elseif mode:find("ricochet", 1, true) then
        variant = "Ricochet"
    else
        variant = "Heatseeker"
    end

    local match_type
    if current_playlist == 6 then
        match_type = "Private_" .. variant
    elseif current_playlist == 22 or current_playlist == 34 or current_is_tournament == "1" then
        match_type = "Tournament"
    elseif current_playlist == 43 or current_playlist == 63 then
        match_type = "Competitive"
    elseif variant == "Ricochet" or current_playlist == 66 then
        match_type = "Ricochet"
    elseif variant == "Splitshot" then
        match_type = "Splitshot"
    else
        match_type = "Casual"
    end

    local winner = winner_team(game)
    local processed_players = {}
    if type(players) == "table" then
        for _, player in ipairs(players) do
            local team_num = number(get_value(player, "TeamNum", "team_num"))
            local id = tostring(get_value(player, "PrimaryId", "primary_id") or "0")
            local name = tostring(get_value(player, "Name", "name") or "Unknown")
            local rank = player_rank_data(id, name, match_type)
            table.insert(processed_players, {
                platform_id = id,
                name = name,
                team = team_num == 0 and "0" or "1",
                team_name = team_num == 0 and blue_name or orange_name,
                is_winner = winner == tostring(team_num),
                is_uploader = current_uploader_id ~= "0" and id == current_uploader_id,
                score = number(get_value(player, "Score", "score")),
                goals = number(get_value(player, "Goals", "goals")),
                assists = number(get_value(player, "Assists", "assists")),
                saves = number(get_value(player, "Saves", "saves")),
                demos = number(get_value(player, "Demos", "demos")),
                shots = number(get_value(player, "Shots", "shots")),
                touches = number(get_value(player, "Touches", "touches")),
                mmr = rank.mmr,
                comp_rank = rank.comp_rank,
                tourn_rank = rank.tourn_rank,
            })
        end
    end

    local team_size = number(get_value(data, "TeamSize", "team_size")
        or get_value(game, "TeamSize", "team_size"), #processed_players)
    local time_played = number(get_value(data, "TimeSeconds", "time_seconds")
        or get_value(game, "TimeSeconds", "time_seconds"))
    return {
        api_key = loader_key,
        match_guid = tostring(guid),
        match_status = tostring(match_status),
        uploader_platform_id = tostring(current_uploader_id),
        match_type = match_type,
        team_size = math.floor(team_size),
        blue_goals = math.floor(blue_goals),
        orange_goals = math.floor(orange_goals),
        team0_colour = blue_colour,
        team1_colour = orange_colour,
        winning_team = winner,
        server_name = current_server_name,
        server_region = current_region,
        playlist_id = math.floor(current_playlist),
        map_name = map_name,
        time_played = math.floor(time_played),
        is_tournament = current_is_tournament,
        players = processed_players,
    }
end

local function dispatch_telemetry(event, force_finish)
    local now = os.time()
    if not force_finish and now - last_upload_time < UPLOAD_INTERVAL then return end

    local state = force_finish and "FINISHED" or "LIVE"
    local payload = extract_payload(event, state)
    local json = hebnix.json_encode(payload)
    local compressed = hebnix.zlib_compress(json)
    local encoded = hebnix.base64_encode(compressed)
    local timestamp = tostring(now)
    local signature = hebnix.crypto_hmac_sha256(loader_key, timestamp .. "." .. encoded)
    local headers = auth_headers(timestamp, signature)
    headers["Content-Type"] = "text/plain"
    upload_sequence = upload_sequence + 1
    local request_id = "seekr_upload:" .. tostring(upload_sequence) .. ":" .. state
    hebnix.http_post_async(request_id, BASE_URL .. "/api/listener/upload", encoded, headers)
    last_upload_time = now
end

local function reset_match()
    in_match_tracking = false
    current_uploader_id = "0"
    active_match_guid = "0"
    current_is_heatseeker = false
    last_valid_snapshot = nil
    last_finished_guid = nil
    seen_players = {}
end

local function send_heartbeat()
    if not authenticated() or heartbeat_pending then return end
    local timestamp = tostring(os.time())
    local signature = hebnix.crypto_hmac_sha256(loader_key, timestamp .. ".heartbeat")
    heartbeat_pending = true
    hebnix.http_get_async(
        "seekr_heartbeat",
        BASE_URL .. "/api/listener/heartbeat",
        auth_headers(timestamp, signature)
    )
end

function plugin.on_load()
    discord_id = setting("discord_id")
    loader_key = setting("loader_key")
    discord_username = setting("username")
    discord_role = setting("role", "User")
    refresh_log(true)
    status = authenticated() and "Authenticated" or "Pending login"
    if authenticated() then
        hebnix.log("[Seekr] Profile synchronized: " .. discord_username .. " (" .. discord_role .. ")")
    end
end

function plugin.on_unload()
    oauth_session = nil
    oauth_pending = false
    heartbeat_pending = false
end

function plugin.on_tick()
    local now = os.time()

    if oauth_session and now >= oauth_deadline then
        oauth_session = nil
        oauth_pending = false
        status = "Login timed out"
    elseif oauth_session and not oauth_pending and now >= oauth_next_poll then
        oauth_pending = true
        oauth_next_poll = now + 3
        local url = BASE_URL .. "/api/listener/poll?session_id=" .. url_encode(oauth_session)
        hebnix.http_get_async("seekr_oauth_poll", url, {})
    end

    if authenticated() and now >= next_heartbeat then
        next_heartbeat = now + 60
        send_heartbeat()
    end

    for platform_id in pairs(tracker_pending) do
        read_player_stats(platform_id)
    end
end

function plugin.on_game_event(event_type, event)
    if not authenticated() then
        status = "Waiting for Auth"
        return
    end

    refresh_log(false)
    local data, game = event_blocks(event)
    local guid = event_guid(event, data)
    refresh_match_context(data, game)

    if in_match_tracking and guid ~= "0" then
        if active_match_guid ~= "0" and guid ~= active_match_guid then
            current_uploader_id = "0"
            last_finished_guid = nil
            seen_players = {}
            detailed_log("Match context shifted; reset tracking state.")
        end
        active_match_guid = guid
        current_match_guid = guid
    end

    if event_type == "UpdateState" then
        last_valid_snapshot = event
        local replay = get_value(game, "bReplay", "isReplay", "IsReplay", "is_replay") == true
        if not replay then lock_uploader(data, game) end
        if in_match_tracking and not replay and current_is_heatseeker and guid ~= last_finished_guid then
            dispatch_telemetry(event, false)
            status = "Live (Heatseeker)"
        elseif not current_is_heatseeker then
            status = "Not Heatseeker"
        end
    elseif event_type == "MatchCreated" or event_type == "MatchInitialized" then
        in_match_tracking = true
        last_finished_guid = nil
        current_uploader_id = "0"
        seen_players = {}
        detailed_log("Match created.")
    elseif event_type == "MatchEnded" then
        if in_match_tracking and current_is_heatseeker then
            local snapshot = last_valid_snapshot or event
            local snapshot_data = event_blocks(snapshot)
            last_finished_guid = event_guid(snapshot, snapshot_data)
            dispatch_telemetry(snapshot, true)
            detailed_log("Final match dataset queued.")
        end
        in_match_tracking = false
        last_valid_snapshot = nil
        current_uploader_id = "0"
        active_match_guid = "0"
        current_is_heatseeker = false
        status = "Finished"
    elseif event_type == "GameLeft" or event_type == "MatchDestroyed" then
        reset_match()
        status = "Waiting..."
    end
end

function plugin.on_http_response(request_id, http_status, body)
    if request_id == "seekr_oauth_init" then
        oauth_pending = false
        if http_status ~= 200 then
            status = "Handshake Refused by Server"
            return
        end
        local response = decode_json(body)
        if not response or not response.session_id or not response.auth_url then
            status = "Invalid Auth Server Package"
            return
        end
        oauth_session = tostring(response.session_id)
        oauth_deadline = os.time() + 300
        oauth_next_poll = os.time()
        status = "Action Required (Check Browser)"
        hebnix.open_url(tostring(response.auth_url))
        return
    end

    if request_id == "seekr_oauth_poll" then
        oauth_pending = false
        if http_status == 202 then return end
        if http_status ~= 200 then
            oauth_session = nil
            status = "Session Invalidated"
            return
        end
        local response = decode_json(body)
        if response and response.status == "success" then
            discord_id = tostring(response.discord_id or "")
            loader_key = tostring(response.loader_key or "")
            discord_username = tostring(response.username or "Linked User")
            discord_role = tostring(response.role or "User")
            save_auth()
            oauth_session = nil
            status = "Authenticated"
            hebnix.log("[Seekr] Login verified via stream handshake.")
        end
        return
    end

    if request_id == "seekr_heartbeat" then
        heartbeat_pending = false
        if http_status ~= 200 then
            detailed_log("Heartbeat rejected: " .. tostring(http_status))
            return
        end
        local response = decode_json(body)
        if response and response.user_status == "banned" then
            status = "Account Banned"
            hebnix.log("[Seekr] Account banned; tracking halted.")
            perform_logout()
            status = "Account Banned"
        elseif response and response.username and tostring(response.username) ~= discord_username then
            discord_username = tostring(response.username)
            save_auth()
        end
        return
    end

    if request_id:match("^seekr_upload:") then
        local state = request_id:match(":([^:]+)$") or "LIVE"
        if http_status == 200 then
            detailed_log(state .. " match telemetry synchronized.")
        else
            detailed_log("Upload rejected: " .. tostring(http_status) .. " - " .. tostring(body))
        end
    end
end

function plugin.on_settings(ui)
    ui.heading("Seekr")
    local user = authenticated() and (discord_username ~= "" and discord_username or discord_id)
        or "Not Logged In"
    ui.label("User: " .. user)
    if authenticated() then ui.label("Role: " .. discord_role) end
    ui.label("Status: " .. status)
    ui.space(6)

    if authenticated() then
        if ui.button("Logout") then perform_logout() end
    elseif oauth_session or oauth_pending then
        ui.label("Complete the Discord login in your browser.")
    elseif ui.button("Login via Discord") then
        start_oauth()
    end

    ui.space(8)
    ui.checkbox("seekr_detailed_logging", "Enable Detailed Logging", false)
end

return plugin
