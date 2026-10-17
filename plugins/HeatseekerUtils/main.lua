local plugin = {}

local START_SPEED = 107
local MAX_SPEED = 165
local SPEED_STEP = 3

local in_game = false
local is_replay = false
local match_ended = false
local current_speed = START_SPEED
local changes_until_max = 20
local last_update_time = 0

local blue_score = 0
local orange_score = 0
local ball_team = 255
local demo_chaser_name = nil
local demo_chaser_count = 0

local player_touches = {}
local player_ground_ticks = {}
local active_rally_player = nil
local rally_count = 0
local display_rally_name = nil
local display_rally_count = 0
local rally_fade_time = 0

-- Scoreboard side follows the local player's actual team.
local my_team_num = nil
local local_primary_id = nil
local local_identity_ids = {}
local eos_identity_key = nil
local last_identity_lookup = 0

local function refresh_local_primary_id()
    if local_primary_id then return end

    -- Retry a failed EOS lookup instead of leaving identity unavailable for the
    -- entire match. StatsAPI and EOS can label the same account differently.
    if not eos_identity_key then
        if os.time() - last_identity_lookup < 2 then return end
        last_identity_lookup = os.time()
        eos_identity_key = kingmod.eos_token_async(kingmod.detected_platform())
        return
    end

    local token = kingmod.eos_result(eos_identity_key)
    if token == false then
        eos_identity_key = nil
        return
    end
    if type(token) ~= "table" then return end

    local platform = tostring(token.platform or ""):lower()
    local ids = { token.steam_id, token.account_id }
    for _, id in ipairs(ids) do
        if id and tostring(id) ~= "" then
            local_identity_ids[string.lower(tostring(id))] = true
        end
    end
    for _, id in ipairs(ids) do
        if platform ~= "" and id and tostring(id) ~= "" then
            local_primary_id = platform .. "|" .. tostring(id) .. "|0"
            return
        end
    end
end

local function is_local_player(player)
    if not player then return false end
    local primary_id = player.PrimaryId or player.primary_id
    if not primary_id then return false end
    local normalized = string.lower(tostring(primary_id))
    if local_primary_id and normalized == local_primary_id then return true end

    -- Match the stable account-id segment when the platform prefix differs.
    local account_id = normalized:match("^[^|]+|([^|]+)")
    return account_id and local_identity_ids[account_id] == true
end
local function round_down(num)
    return math.floor(num or 0)
end

local function trigger_end_rally()
    if rally_count > 0 then
        if rally_count >= 4 then
            rally_fade_time = os.time() + 2
        else
            display_rally_count = 0
            rally_fade_time = 0
        end
        active_rally_player = nil
        rally_count = 0
    end
end

local function reset_stats()
    current_speed = START_SPEED
    changes_until_max = math.ceil((MAX_SPEED - START_SPEED) / SPEED_STEP)
    blue_score = 0
    orange_score = 0
    ball_team = 255
    demo_chaser_name = nil
    demo_chaser_count = 0
    
    player_touches = {}
    player_ground_ticks = {}
    active_rally_player = nil
    rally_count = 0
    display_rally_name = nil
    display_rally_count = 0
    rally_fade_time = 0

    is_replay = false
    match_ended = false
    
    my_team_num = nil
    local_primary_id = nil
    local_identity_ids = {}
    eos_identity_key = nil
    last_identity_lookup = 0
end

local function calculate_changes(speed)
    if speed >= MAX_SPEED then
        return 0
    end
    local effective_speed = math.max(speed, START_SPEED)
    return math.ceil((MAX_SPEED - effective_speed) / SPEED_STEP)
end

function plugin.on_load()
    reset_stats()
end

function plugin.on_unload()
end

function plugin.on_game_event(event_type, event)
    if event_type == "BallHit" then
        return
    end

    if event_type == "GoalScored" then
        refresh_local_primary_id()
        local team_colour = my_team_num == 1 and "Orange" or (my_team_num == 0 and "Blue" or "Unknown")
        if not local_primary_id and event.data and event.data.Players then
            local players = {}
            for _, p in ipairs(event.data.Players) do
                table.insert(players, string.format("%s=%s(team %s)", tostring(p.Name), tostring(p.PrimaryId), tostring(p.TeamNum)))
            end
        end
    end

    if event_type == "GoalScored" 
       or event_type == "MatchEnded" 
       or event_type == "MatchDestroyed"
       or event_type == "CountdownBegin" 
       or event_type == "MatchCreated" 
       or event_type == "GoalReplayStart" 
       or event_type == "GoalReplayEnd" then
        
        current_speed = START_SPEED
        changes_until_max = calculate_changes(START_SPEED)
        ball_team = 255
        
        player_touches = {}
        player_ground_ticks = {}
        active_rally_player = nil
        rally_count = 0
        display_rally_name = nil
        display_rally_count = 0
        rally_fade_time = 0
        
        if event_type == "MatchEnded" or event_type == "MatchDestroyed" then
            in_game = false
            match_ended = true
        elseif event_type == "GoalReplayStart" then
            is_replay = true
        elseif event_type == "GoalReplayEnd" then
            is_replay = false
        elseif event_type == "CountdownBegin" or event_type == "MatchCreated" then
            match_ended = false
            is_replay = false
        end

    elseif event_type == "GameLeft" then
        reset_stats()
        in_game = false
        match_ended = true

    elseif event_type == "UpdateState" then
        -- 1. Heatseeker Check (Using Launch.log)
        local game_data = event.data and event.data.Game or {}
        
        -- StatsAPI doesn't send the gamemode string, so we must pull it from the Launch.log
        -- to properly detect Private Matches where the Playlist ID is just '6'.
        local log_info = kingmod.parse_launch_log(false)
        local raw_gamemode = ""
        local log_playlist = 0
        
        if log_info and log_info.game then
            local g = log_info.game
            raw_gamemode = tostring(g.game_class) .. " " .. tostring(g.game_tags) .. " " .. tostring(g.game_mode) .. " " .. tostring(g.gamemode)
            log_playlist = g.playlist_id or 0
        end
        
        local playlist = game_data.Playlist or log_playlist
        local gm_lower = string.lower(raw_gamemode)
        
        local is_hs = string.find(gm_lower, "godball") or string.find(gm_lower, "heatseeker") 
                   or string.find(gm_lower, "territory") or string.find(gm_lower, "ricochet") 
                   or string.find(gm_lower, "splitshot") 
                   or playlist == 43 or playlist == 63 or playlist == 66 or playlist == 34
                   
        if not is_hs then
            in_game = false
            return
        end

        in_game = true
        last_update_time = os.time()

        if not event.data then return end

        if event.data.Game then
            if event.data.Game.Teams then
                for _, team in ipairs(event.data.Game.Teams) do
                    if team.TeamNum == 0 then
                        blue_score = team.Score or 0
                    elseif team.TeamNum == 1 then
                        orange_score = team.Score or 0
                    end
                end
            end

            if event.data.Game.Ball then
                local raw_speed = event.data.Game.Ball.Speed or 0.0
                local new_speed = round_down(raw_speed)

                if new_speed >= current_speed then
                    current_speed = new_speed
                    changes_until_max = calculate_changes(current_speed)
                end
                
                ball_team = event.data.Game.Ball.TeamNum or 255
            end
        end
        
        if event.data.Players then
            refresh_local_primary_id()
            local max_demos = 1 
            local chaser = nil
            
            for _, p in ipairs(event.data.Players) do
                -- Match the Stats API primary ID to the local platform ID.
                if is_local_player(p) then
                    my_team_num = p.TeamNum or 0
                end
                
                local d = p.Demos or 0
                if d > max_demos then
                    max_demos = d
                    chaser = p.Name
                end
                
                local name = p.Name
                if name then
                    local is_grounded = p.bOnGround
                    local touches = p.Touches or 0
                    
                    if is_grounded then
                        player_ground_ticks[name] = (player_ground_ticks[name] or 0) + 1
                    else
                        player_ground_ticks[name] = 0
                    end
                    
                    local really_grounded = (player_ground_ticks[name] > 2)
                    
                    if name == active_rally_player and really_grounded then
                        trigger_end_rally()
                    end
                    
                    local prev = player_touches[name]
                    if prev == nil then
                        player_touches[name] = touches
                    elseif touches > prev then
                        player_touches[name] = touches
                        
                        if is_grounded then
                            if really_grounded then
                                trigger_end_rally()
                            end
                        else
                            if name == active_rally_player then
                                rally_count = rally_count + 1
                                display_rally_name = name
                                display_rally_count = rally_count
                                rally_fade_time = 0
                            else
                                trigger_end_rally()
                                active_rally_player = name
                                rally_count = 1
                            end
                        end
                    end
                end
            end
            
            demo_chaser_count = max_demos
            demo_chaser_name = chaser
        end
    end
end

function plugin.on_tick()
    if in_game and (os.time() - last_update_time > 3) then
        in_game = false
        reset_stats()
    end
end

function plugin.on_overlay(draw, w, h)
    if not in_game or is_replay or match_ended or not kingmod.get_bool("heatseeker_enable_overlay", true) then 
        return 
    end

    local center_x = w / 2

    local box_width = 12
    local box_height = 5
    local gap = 4
    local total_width = (7 * box_width) + (6 * gap)
    
    local left_start_x = (center_x - 140) - (total_width / 2)
    local right_start_x = (center_x + 140) - (total_width / 2)

    -- Keep the local player's team on the left.
    local should_swap = my_team_num == 1
    
    local blue_start_x = should_swap and right_start_x or left_start_x
    local orange_start_x = should_swap and left_start_x or right_start_x
    local boxes_y = 115 

    for i = 1, 7 do
        local bx = orange_start_x + ((i - 1) * (box_width + gap))
        local color = (i <= orange_score) and "#e67e22" or "#555555aa"
        
        draw.rect(bx, boxes_y, box_width, box_height, { color = color, filled = true })
        draw.rect(bx, boxes_y, box_width, box_height, { color = "#ffffff40", width = 1 })
    end

    for i = 1, 7 do
        local bx = blue_start_x + ((i - 1) * (box_width + gap))
        local color = (i <= blue_score) and "#3498db" or "#555555aa"
        
        draw.rect(bx, boxes_y, box_width, box_height, { color = color, filled = true })
        draw.rect(bx, boxes_y, box_width, box_height, { color = "#ffffff40", width = 1 })
    end

    local show_rally = false
    if rally_fade_time > 0 then
        if os.time() > rally_fade_time then
            rally_fade_time = 0
            display_rally_count = 0
        else
            show_rally = true
        end
    elseif display_rally_count >= 2 then
        show_rally = true
    end

    local box_w = 200
    local box_h = 45
    
    if show_rally then
        box_h = box_h + 15
    end
    if demo_chaser_name then
        box_h = box_h + 15
    end
    
    local pos_x = center_x - (box_w / 2)
    local pos_y = 130

    draw.rect(pos_x, pos_y, box_w, box_h, { color = "#0f0f15ee", filled = true })
    draw.rect(pos_x, pos_y, box_w, box_h, { color = "#e74c3caa", width = 1.0 })

    local changes_text = ""
    local changes_color = "#f39c12"
    
    if changes_until_max <= 0 then
        changes_text = "Ball is at max speed"
        changes_color = "#e74c3c"
    else
        changes_text = string.format("Changes until max: %d", changes_until_max)
    end
    
    draw.text(pos_x + (box_w / 2), pos_y + 8, changes_text, { 
        color = changes_color, 
        size = 16, 
        halign = "center" 
    })
    
    local pos_text = "Possession: None"
    local pos_color = "#bdc3c7"
    if ball_team == 0 then
        pos_text = "Possession: Blue"
        pos_color = "#3498db"
    elseif ball_team == 1 then
        pos_text = "Possession: Orange"
        pos_color = "#e67e22"
    end
    
    draw.text(pos_x + (box_w / 2), pos_y + 26, pos_text, { 
        color = pos_color, 
        size = 12, 
        halign = "center" 
    })

    local cursor_y = pos_y + 42
    
    if show_rally then
        local rally_text = string.format("Rally: %s (%d)", display_rally_name, display_rally_count)
        draw.text(pos_x + (box_w / 2), cursor_y, rally_text, { 
            color = "#9b59b6", 
            size = 12, 
            halign = "center" 
        })
        cursor_y = cursor_y + 15
    end
    
    if demo_chaser_name then
        local demo_text = string.format("Demo Chaser: %s (%d)", demo_chaser_name, demo_chaser_count)
        draw.text(pos_x + (box_w / 2), cursor_y, demo_text, { 
            color = "#c0392b", 
            size = 12, 
            halign = "center" 
        })
    end
end

function plugin.on_settings(ui)
    ui.checkbox("heatseeker_enable_overlay", "Show In-Game Overlays", true)
    
    ui.space(8)
    if ui.button("Reset Tracker Manually") then
        reset_stats()
    end
end

return plugin