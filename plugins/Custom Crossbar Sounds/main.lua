local plugin = {}

local local_player_name = ""
local in_replay = false
local has_winner = false
local last_touch_name = "Unknown"
local assets = {}
local sound_playing = false
local sound_finished_at = 0.0

local MAX_SOUND_SECONDS = 5.0
local SOUND_DURATIONS = {
    ["jixaw-metal-pipe-falling-sound.mp3"] = 3.31,
}

local function update_playback_state()
    if sound_playing and kingmod.monotonic_seconds() >= sound_finished_at then
        sound_playing = false
    end
end

local function play_sound(file, volume)
    update_playback_state()
    if sound_playing or file == "" then return false end

    if kingmod.audio.play(file, volume) then
        local duration = SOUND_DURATIONS[file] or MAX_SOUND_SECONDS
        sound_finished_at = kingmod.monotonic_seconds() + math.min(duration, MAX_SOUND_SECONDS)
        sound_playing = true
        return true
    end

    return false
end

local function try_get_local_player()
    if local_player_name ~= "" then return true end
    
    local log_info = kingmod.parse_launch_log(false)
    if log_info and log_info.session and log_info.session.username then
        local_player_name = log_info.session.username
        return true
    end
    return false
end

local function refresh_files()
    assets = kingmod.list_assets() or {}
end

function plugin.on_load()
    try_get_local_player()
    refresh_files()
end

function plugin.on_settings(ui)
    ui.horizontal(function()
        ui.combo_box("selected_sound", "Sound File", assets)
        
        if ui.button("Refresh List") then
            refresh_files()
        end
    end)
    
    ui.space(8)
    
    ui.slider("sound_volume", "Volume", 0.0, 2.0, 1.0)
    
    ui.space(12)
    if ui.button("Test Audio Playback") then
        local file = kingmod.get_string("selected_sound", "")
        local vol = kingmod.get_number("sound_volume", 1.0)
        
        play_sound(file, vol)
    end
end

function plugin.on_tick()
    update_playback_state()
end

function plugin.on_game_event(event_type, event)
    update_playback_state()
    if sound_playing then return end
    if event_type == "UpdateState" then
        if local_player_name == "" and event.data and event.data.game then
            if event.data.game.has_target and event.data.game.target and event.data.game.target.name ~= "" then
                local_player_name = event.data.game.target.name
            end
        end
        
        if event.data and event.data.game then
            in_replay = event.data.game.replay
            has_winner = event.data.game.has_winner
        end
        
    elseif event_type == "BallHit" then
        if event.data.players and event.data.players[1] then
            last_touch_name = event.data.players[1].name
        end
        
    elseif event_type == "CrossbarHit" then
        if in_replay or has_winner then return end
        
        local data = event.data
        local hitter = "Unknown"
        if data.ball_last_touch and data.ball_last_touch.player and data.ball_last_touch.player.name ~= "" then
            hitter = data.ball_last_touch.player.name
        else
            hitter = last_touch_name
        end
        
        local file = kingmod.get_string("selected_sound", "")
        local vol = kingmod.get_number("sound_volume", 1.0)
        
        play_sound(file, vol)
    end
end

return plugin