local plugin = {}

local POLL = 0.5
local LRC_GET = "https://lrclib.net/api/get"
local LRC_SEARCH = "https://lrclib.net/api/search"
local LRC_UA = "hebnix-media-overlay (https://github.com/Hebbins)"
-- Better Lyrics: apple music lyrics with word timing. keyless for songs already
-- in its cache, anything else answers 401 (they aren't handing out keys), so
-- it goes first and lrclib catches the rest
local BL_GET = "https://lyrics-api.boidu.dev/getLyrics"
-- youtube captions for browser videos. windows only gives the tab's title and
-- channel, so: search for the video, ask the player for its caption tracks,
-- download one. the player only hands caption urls that work without a
-- browser-made proof token to the mobile apps, so that request says it's the
-- iOS app
local YT_SEARCH = "https://www.youtube.com/youtubei/v1/search?prettyPrint=false"
local YT_PLAYER = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
local YT_WEB_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
local YT_WEB = { clientName = "WEB", clientVersion = "2.20260101.00.00", hl = "en" }
local YT_IOS_UA = "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
local YT_IOS = { clientName = "IOS", clientVersion = "20.10.4", deviceModel = "iPhone16,2", hl = "en" }
local YT_THUMB = "https://i.ytimg.com/vi/%s/%s.jpg"

local DEFAULT_PALETTE = {
    dominant = "#7a26c8", vibrant = "#ff9de6", light = "#e6c8ff",
    average = "#7a26c8", dark = "#3d1466", text = "#ffffff", accent = "#ff9de6",
    base = "#7a26c8", grad1 = "#8f3bd6", grad2 = "#3d1466",
}

-- source app ids windows hands out for browsers, where "Artist - Title" in the
-- title is the norm and the "artist" is really the channel
local BROWSERS = { "chrome", "msedge", "firefox", "opera", "brave", "vivaldi", "308046b0af4a39cb" }

-- bracketed bits of video titles that only get in the way of a lyrics lookup
local JUNK = { "official", "video", "audio", "lyric", "visuali", "music video", "mv", "hd", "4k", "hq", "explicit", "clean" }

local S = {}
local function reset_state()
    S = {
        last_poll = -999,
        key = nil,
        track_n = 0,
        thumb_rev = -1,
        cover_file = nil,
        palette = DEFAULT_PALETTE,
        lyrics = nil,
        lyric_i = -1,
        lyric_t0 = 0,
        app = nil,
        now = nil,
    }
end

local function mono() return hebnix.monotonic_seconds() end

local function hex(n)
    local t = {}
    for _ = 1, n do t[#t + 1] = string.format("%02x", math.random(0, 255)) end
    return table.concat(t)
end

local function urlencode(s)
    return (s:gsub("[^%w%-%_%.%~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function is_browser(app)
    app = (app or ""):lower()
    -- firefox-likes register under a hashed id rather than an exe name
    if app:match("^%x+$") and #app == 16 then return true end
    for _, b in ipairs(BROWSERS) do
        if app:find(b, 1, true) then return true end
    end
    return false
end

-- youtube video mode only changes anything for media playing in a browser
local function video_mode()
    return hebnix.get_bool("media_overlay_youtube_mode", false) and is_browser(S.app)
end

-- the overlay text (lyrics, or captions in video mode) is on
local function text_on()
    return hebnix.get_bool("media_overlay_lyrics", true) or video_mode()
end

local function app_name(app)
    if not app or #app == 0 then return "unknown app" end
    return (app:gsub("%.exe$", ""))
end

local function clean_artist(a)
    a = a or ""
    a = a:gsub("%s*%-%s*Topic$", ""):gsub("VEVO$", "")
    return trim(a)
end

local function clean_title(t)
    t = t or ""
    local function strip(group)
        local l = group:lower()
        for _, j in ipairs(JUNK) do
            if l:find(j, 1, true) then return "" end
        end
        return group
    end
    t = t:gsub("%b()", strip):gsub("%b[]", strip)
    t = t:gsub("%s+[fF]eat%.?%s.*$", ""):gsub("%s+[fF]t%.?%s.*$", "")
    t = t:gsub("%s+|%s+.*$", "")
    return trim(t)
end

-- best guess at (artist, title) for lrclib. youtube titles are usually
-- "Artist - Title (Official Video)" with the channel as the artist
local function lyric_query(now)
    local title, artist = now.title or "", clean_artist(now.artist)
    local a, t = title:match("^(.-)%s+%-%s+(.+)$")
    if a and t and (#artist == 0 or is_browser(S.app)
        or a:lower() == artist:lower()) then
        artist, title = a, t
    end
    return clean_artist(artist), clean_title(title)
end

-- the first of several credited artists, which is what lyric databases file a
-- song under. " and " / " with " are left alone, too many band names have them
local ARTIST_SEPS = { " & ", ", ", " x ", " feat. ", " feat ", " ft. ", " ft " }
local function primary_artist(a)
    local lower = a:lower()
    local cut = #a + 1
    for _, sep in ipairs(ARTIST_SEPS) do
        local i = lower:find(sep, 1, true)
        if i and i < cut then cut = i end
    end
    return trim(a:sub(1, cut - 1))
end

-- every artist as plain words for free-text search, SimpMusic's cleanForSearch:
-- no brackets, dots, feat markers or joining words
local SEARCH_DROP = { ["&"] = true, x = true, ["and"] = true, feat = true, ft = true, with = true }
local function search_words(s)
    s = s:gsub("[%(%)%[%]]", " "):gsub("%.", " ")
    local out = {}
    for w in s:gmatch("%S+") do
        w = w:gsub(",$", "")
        if #w > 0 and not SEARCH_DROP[w:lower()] then out[#out + 1] = w end
    end
    return table.concat(out, " ")
end

local function parse_lrc(s)
    local out = {}
    for line in (s .. "\n"):gmatch("(.-)\n") do
        local text = line:gsub("%[%d+:%d+%.?%d*%]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        for mm, ss in line:gmatch("%[(%d+):(%d+%.?%d*)%]") do
            out[#out + 1] = { t = tonumber(mm) * 60 + tonumber(ss), text = text }
        end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

-- ttml times come as 12.345, 1:02.345 or 1:01:02.345
local function ttml_time(s)
    if not s then return nil end
    local h, m, sec = s:match("^(%d+):(%d+):([%d%.]+)$")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec) end
    m, sec = s:match("^(%d+):([%d%.]+)$")
    if m then return tonumber(m) * 60 + tonumber(sec) end
    return tonumber((s:gsub("s$", "")))
end

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }
local function unescape(s)
    return (s:gsub("&(#?x?)(%w+);", function(p, v)
        if p == "" then return ENTITIES[v] end
        local n = (p == "#x") and tonumber(v, 16) or tonumber(v)
        return (n and utf8) and utf8.char(n) or nil
    end))
end

-- background vocals are their own span (with word spans inside) in the
-- middle of a line. the overlay only shows the lead line, so cut them out
local function drop_bg(s)
    while true do
        local a, b = s:find('<span[^>]-ttm:role="x%-bg"[^>]*>')
        if not a then return s end
        local depth, i = 1, b + 1
        while depth > 0 do
            local o = s:find("<span", i, true)
            local c = s:find("</span>", i, true)
            if not c then i = #s + 1 break end
            if o and o < c then
                depth, i = depth + 1, o + 5
            else
                depth, i = depth - 1, c + 7
            end
        end
        s = s:sub(1, a - 1) .. s:sub(i)
    end
end

-- Better Lyrics' apple music ttml into the same lines parse_lrc makes, plus
-- the line's end time and, when timed per word, each word's begin/end and
-- where it stops in the line text (for the karaoke fill)
local function parse_ttml(ttml)
    local word_timed = not ttml:find('itunes:timing="Line"', 1, true)
    local out = {}
    for attrs, inner in ttml:gmatch("<p%s([^>]*)>(.-)</p>") do
        local t = ttml_time(attrs:match('begin="([^"]+)"'))
        if t then
            inner = drop_bg(inner)
            local text, words, pos = "", {}, 1
            -- whitespace collapsed as it's added so the word stops stay right
            local function add(piece)
                piece = unescape(piece):gsub("%s+", " ")
                if text == "" or text:sub(-1) == " " then piece = piece:gsub("^ ", "") end
                text = text .. piece
            end
            while true do
                local a, b, sattrs, word = inner:find("<span%s([^>]*)>([^<]*)</span>", pos)
                if not a then break end
                add((inner:sub(pos, a - 1):gsub("<[^>]*>", "")))
                add(word)
                local wt = ttml_time(sattrs:match('begin="([^"]+)"'))
                local we = ttml_time(sattrs:match('end="([^"]+)"'))
                if wt and we and word:find("%S") then
                    words[#words + 1] = { t = wt, e = we, stop = #text }
                end
                pos = b + 1
            end
            add((inner:sub(pos):gsub("<[^>]*>", "")))
            text = text:gsub("%s+$", "")
            for _, w in ipairs(words) do
                if w.stop > #text then w.stop = #text end
            end
            if #text > 0 then
                out[#out + 1] = { t = t, e = ttml_time(attrs:match('end="([^"]+)"')), text = text,
                    words = (word_timed and #words > 0) and words or nil }
            end
        end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return #out > 0 and out or nil
end

local function norm(s)
    return ((s or ""):lower():gsub("[%p%s]+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function yt_text(r)
    if type(r) ~= "table" then return "" end
    if type(r.simpleText) == "string" then return r.simpleText end
    local t = {}
    for _, run in ipairs(r.runs or {}) do t[#t + 1] = run.text or "" end
    return table.concat(t)
end

-- "3:34" / "1:02:03" in seconds
local function yt_length(s)
    local total, n = 0, 0
    for part in (s or ""):gmatch("%d+") do total, n = total * 60 + tonumber(part), n + 1 end
    return n > 0 and total or nil
end

local function yt_videos(o, out, depth)
    if #out >= 8 or depth > 40 or type(o) ~= "table" then return end
    local v = o.videoRenderer
    if type(v) == "table" and type(v.videoId) == "string" then out[#out + 1] = v end
    for _, x in pairs(o) do
        if type(x) == "table" then yt_videos(x, out, depth + 1) end
        if #out >= 8 then return end
    end
end

-- the search result that is the video being watched: the title has to match,
-- backed up by the channel or the length. a reupload with the same title
-- but another channel and length doesn't get through
local function yt_pick(j)
    local vids = {}
    yt_videos(j, vids, 0)
    local want_t, want_c = norm(S.now.title), norm(S.now.artist)
    local dur = math.floor((S.now.duration_ms or 0) / 1000)
    local best, best_s
    for i, v in ipairs(vids) do
        local t, c = norm(yt_text(v.title)), norm(yt_text(v.ownerText))
        local len = yt_length(yt_text(v.lengthText))
        local s = 0
        if t == want_t then
            s = s + 4
        elseif #t > 0 and #want_t > 0 and (t:find(want_t, 1, true) or want_t:find(t, 1, true)) then
            s = s + 2
        end
        if #c > 0 and #want_c > 0 and (c:find(want_c, 1, true) or want_c:find(c, 1, true)) then s = s + 3 end
        local far = false
        if dur > 0 and len then
            local d = math.abs(len - dur)
            if d <= 3 then s = s + 3 elseif d > 15 then far = true end
        end
        s = s - i * 0.01 -- ties go to youtube's own ranking
        if not far and s >= 5 and (not best_s or s > best_s) then best, best_s = v.videoId, s end
    end
    return best
end

-- english made by a person first, then english auto-generated, then
-- whatever else the video has
local function yt_track(j)
    local list = type(j.captions) == "table" and j.captions.playerCaptionsTracklistRenderer
    local tracks = type(list) == "table" and list.captionTracks
    if type(tracks) ~= "table" then return nil end
    local best, best_s
    for _, t in ipairs(tracks) do
        if type(t.baseUrl) == "string" then
            local s = (((t.languageCode or ""):sub(1, 2) == "en") and 2 or 0) + ((t.kind == "asr") and 0 or 1)
            if not best_s or s > best_s then best, best_s = t, s end
        end
    end
    if not best then return nil end
    return best.baseUrl:gsub("&fmt=[^&]*", "") .. "&fmt=json3", best.kind == "asr"
end

-- youtube's json3 captions into lyric lines. auto-generated tracks time each
-- word, those become karaoke words. filler events (just a newline) are skipped
local function parse_json3(j, asr)
    local out = {}
    for _, ev in ipairs(type(j.events) == "table" and j.events or {}) do
        if type(ev.segs) == "table" and ev.tStartMs then
            local t0 = ev.tStartMs / 1000
            local text, words = "", {}
            for _, sg in ipairs(ev.segs) do
                local piece = tostring(sg.utf8 or ""):gsub("%s+", " ")
                if text == "" or text:sub(-1) == " " then piece = piece:gsub("^ ", "") end
                text = text .. piece
                if asr and piece:find("%S") then
                    words[#words + 1] = { t = t0 + (sg.tOffsetMs or 0) / 1000, stop = #text }
                end
            end
            text = text:gsub("%s+$", "")
            if #text > 0 then
                for _, w in ipairs(words) do
                    if w.stop > #text then w.stop = #text end
                end
                out[#out + 1] = { t = t0, e = t0 + (ev.dDurationMs or 0) / 1000, text = text,
                    words = #words > 0 and words or nil }
            end
        end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    -- auto-generated events overlap the next one, end each where the next starts
    for i, l in ipairs(out) do
        local nx = out[i + 1]
        if nx and l.e > nx.t then l.e = nx.t end
        if l.words then
            for k, w in ipairs(l.words) do
                local nw = l.words[k + 1]
                w.e = nw and nw.t or l.e
                if w.e < w.t then w.e = w.t end
            end
        end
    end
    return #out > 0 and out or nil
end

-- lyric lookup. lrclib misses now and then (answers slower than the 10s http
-- timeout, 5xx, rate limits) and the media session often fills in the artist
-- or duration a few seconds into a song, so one request per track isn't
-- enough. go through a list of queries, and when they all miss go round
-- again a few times. lyrics that land midway through a song still line up,
-- they go by the song position
local LYR_ROUND_DELAY = { 3, 8, 20, 45 } -- seconds before each extra round
local LYR_TIMEOUT = 15 -- a request with no answer by then counts as failed
local LYR_TRANSIENT_TRIES = 2 -- retries of the same query after a network error

-- the queries for this round, best first. "pick" says how to choose from a
-- search result
local function lyric_steps()
    local artist, title = lyric_query(S.now)
    if #title == 0 then return {} end
    local dur = math.floor((S.now.duration_ms or 0) / 1000)
    local steps = {}
    -- Better Lyrics' cache key includes duration and album, so without a
    -- duration it would only miss. a miss stays a miss, so round 1 only
    if #artist > 0 and dur > 0 then
        local q = "?s=" .. urlencode(title) .. "&a=" .. urlencode(primary_artist(artist))
            .. "&d=" .. tostring(dur)
        if (S.now.album or "") ~= "" then q = q .. "&al=" .. urlencode(S.now.album) end
        steps[#steps + 1] = { url = BL_GET .. q, bl = true, once = true }
    end
    -- /get wants an exact duration
    if #artist > 0 and dur > 0 then
        steps[#steps + 1] = { url = LRC_GET .. "?artist_name=" .. urlencode(artist)
            .. "&track_name=" .. urlencode(title)
            .. "&album_name=" .. urlencode(S.now.album or "")
            .. "&duration=" .. tostring(dur), get = true }
    end
    if #artist > 0 then
        steps[#steps + 1] = { url = LRC_SEARCH .. "?track_name=" .. urlencode(title)
            .. "&artist_name=" .. urlencode(artist) }
        -- free text copes with "feat." and channel names in the artist field
        steps[#steps + 1] = { url = LRC_SEARCH .. "?q=" .. urlencode(search_words(artist) .. " " .. title) }
    end
    -- title only could be any song with that name, so only take a result
    -- whose length matches. without a duration there's nothing to check
    -- against, so only fall back to it when there's no artist either
    if dur > 0 then
        steps[#steps + 1] = { url = LRC_SEARCH .. "?track_name=" .. urlencode(title), strict = dur }
    elseif #artist == 0 then
        steps[#steps + 1] = { url = LRC_SEARCH .. "?track_name=" .. urlencode(title) }
    end
    -- only the sources ticked in settings
    local use_bl = hebnix.get_bool("media_overlay_src_betterlyrics", true)
    local use_lrc = hebnix.get_bool("media_overlay_src_lrclib", true)
    local out = {}
    for _, s in ipairs(steps) do
        if (s.bl and use_bl) or (not s.bl and use_lrc) then out[#out + 1] = s end
    end
    return out
end

-- youtube video mode: a browser video shows its youtube captions instead of
-- lyrics. the search goes by the raw tab title, that's what youtube calls it
local function yt_steps()
    if #(S.now.title or "") == 0 then return {} end
    return { { yt = true, stage = "search", once = true, method = "POST", url = YT_SEARCH,
        body = hebnix.json_encode({ context = { client = YT_WEB }, query = S.now.title }),
        headers = { ["Content-Type"] = "application/json", ["User-Agent"] = YT_WEB_UA } } }
end

local function any_source()
    return video_mode()
        or hebnix.get_bool("media_overlay_src_betterlyrics", true)
        or hebnix.get_bool("media_overlay_src_lrclib", true)
end

-- changes when the metadata the queries are built from changes, or the
-- ticked sources do, so either starts the lookup over
local function lyric_sig()
    local artist, title = lyric_query(S.now)
    return artist .. "\1" .. title .. "\1" .. math.floor((S.now.duration_ms or 0) / 1000)
        .. "\1" .. tostring(hebnix.get_bool("media_overlay_src_betterlyrics", true))
        .. tostring(hebnix.get_bool("media_overlay_src_lrclib", true))
        .. tostring(hebnix.get_bool("media_overlay_src_saved", true))
        .. tostring(video_mode())
end

-- from a search result, the synced lyrics whose length is closest to ours.
-- more than 10s off is another version of the song (3s when matching on
-- the title alone)
local function pick_synced(items, strict)
    local dur = S.now and math.floor((S.now.duration_ms or 0) / 1000) or 0
    local best, best_d
    for _, item in ipairs(items) do
        if type(item) == "table" and type(item.syncedLyrics) == "string" and #item.syncedLyrics > 0 then
            local idur = tonumber(item.duration)
            local d = (dur > 0 and idur) and math.abs(idur - dur) or 0
            if d <= (strict and 3 or 10) and (not best_d or d < best_d) then
                best, best_d = item.syncedLyrics, d
            end
        end
    end
    return best
end

-- lyrics that were found once are saved per song, so a replay shows them
-- straight away without asking anyone (SimpMusic does the same). misses are
-- never saved, a song can still turn up later
local CACHE_MAX = 300
local function cache_name()
    if not S.now then return nil end
    local a, t = lyric_query(S.now)
    if #t == 0 then return nil end
    -- captions are saved apart from lyrics, so switching video mode never
    -- brings back the other kind
    local key = ((video_mode() and "yt|" or "") .. a .. "|" .. t):lower()
    local h = 5381
    for i = 1, #key do h = (h * 33 + key:byte(i)) % 4294967296 end
    return string.format("%s_%08x", key:gsub("[^%w]+", "_"):sub(1, 60), h)
end

local function cache_load()
    local name = cache_name()
    if not name or not hebnix.read_file then return nil end
    local raw = hebnix.read_file(hebnix.plugin_dir() .. "/assets/lyrics/" .. name .. ".json")
    if not raw or #raw == 0 then return nil end
    local ok, j = pcall(hebnix.json_decode, raw)
    if ok and type(j) == "table" and type(j.lines) == "table" and #j.lines > 0 then return j end
    return nil
end

local function cache_save(src, lines)
    local name = cache_name()
    if not name then return end
    local n = hebnix.get_number("media_overlay_lyric_cache_n", 0)
    if n >= CACHE_MAX then
        hebnix.clear_asset_dir("lyrics")
        n = 0
    end
    if hebnix.write_asset("lyrics/" .. name .. ".json", hebnix.json_encode({ src = src, lines = lines })) then
        hebnix.set("media_overlay_lyric_cache_n", n + 1)
    end
end

-- no delete-one-asset api, so forgetting overwrites it with an empty entry
local function cache_forget()
    local name = cache_name()
    if name then hebnix.write_asset("lyrics/" .. name .. ".json", "{}") end
end

local function set_lyrics(lines, src)
    S.lyrics = lines
    S.lyrics_src = src
    S.kw = nil
end

local lyr_seq = 0
local function lyrics_reset()
    lyr_seq = lyr_seq + 1
    S.lf = { seq = lyr_seq, n = S.track_n, sig = S.now and lyric_sig(), step = 1, round = 1,
        tries = 0, next_at = 0, state = any_source() and "searching" or "no sources", mode = video_mode() }
    local saved = hebnix.get_bool("media_overlay_src_saved", true) and cache_load()
    if saved then
        set_lyrics(saved.lines, "saved")
        S.lf.state = "found"
    end
end

local SRC_SETTING = {
    ["Better Lyrics"] = "media_overlay_src_betterlyrics",
    lrclib = "media_overlay_src_lrclib",
    saved = "media_overlay_src_saved",
}

-- one request for a step. the youtube step is three in a row, each stage
-- has its own id so a late answer to an earlier stage is ignored
local function send_step(lf, step)
    lf.pending = "lyr:" .. lf.seq .. ":" .. lf.step .. ":" .. (step.stage or "")
    lf.pending_step = step
    lf.sent_at = mono()
    hebnix.http_request_async(lf.pending, step.method or "GET", step.url, step.body,
        step.headers or { ["User-Agent"] = LRC_UA })
end

local function yt_player_step(vid)
    return { yt = true, stage = "player", method = "POST", url = YT_PLAYER,
        body = hebnix.json_encode({ context = { client = YT_IOS }, videoId = vid }),
        headers = { ["Content-Type"] = "application/json", ["User-Agent"] = YT_IOS_UA } }
end

local function lyrics_tick()
    if not S.now or not text_on() then return end
    local lf = S.lf
    if S.lyrics then
        -- switching video mode, or unticking the source the shown lyrics
        -- came from, takes them away
        local key = SRC_SETTING[S.lyrics_src or ""]
        if (lf and lf.mode ~= video_mode()) or (key and not hebnix.get_bool(key, true)) then
            set_lyrics(nil, nil)
            lf = nil
        else
            return
        end
    end
    if not lf or lf.n ~= S.track_n or lf.sig ~= lyric_sig() then
        -- new track, or the session filled in more details: start over with them
        lyrics_reset()
        lf = S.lf
    end
    if lf.state ~= "searching" then return end
    local t = mono()
    if lf.pending then
        if t - lf.sent_at < LYR_TIMEOUT then return end
        -- never answered, move on
        lf.pending = nil
        lf.step = lf.step + 1
        lf.tries = 0
    end
    if t < lf.next_at then return end
    local steps = video_mode() and yt_steps() or lyric_steps()
    while lf.round > 1 and steps[lf.step] and steps[lf.step].once do
        lf.step = lf.step + 1
    end
    if lf.step > #steps then
        if lf.round > #LYR_ROUND_DELAY then
            lf.state = "not found"
            return
        end
        lf.next_at = t + LYR_ROUND_DELAY[lf.round]
        lf.round = lf.round + 1
        lf.step = 1
        return
    end
    local step = steps[lf.step]
    send_step(lf, step)
end

local function lyrics_result(id, status, body)
    local lf = S.lf
    if not lf or id ~= lf.pending then return end
    local step = lf.pending_step
    lf.pending = nil
    local lines, src
    if status == 200 and #body > 0 then
        local ok, j = pcall(hebnix.json_decode, body)
        if ok and type(j) == "table" then
            if step.yt then
                -- search -> player -> captions. a stage that finds nothing
                -- falls through to the miss handling below like any step
                if step.stage == "search" then
                    local vid = yt_pick(j)
                    if vid then
                        S.yt_vid = vid -- the full thumbnail can use it too
                        return send_step(lf, yt_player_step(vid))
                    end
                elseif step.stage == "player" then
                    local url, asr = yt_track(j)
                    if url then
                        return send_step(lf, { yt = true, stage = "captions", url = url, asr = asr,
                            headers = { ["User-Agent"] = YT_IOS_UA } })
                    end
                else
                    local pok, parsed = pcall(parse_json3, j, step.asr)
                    if pok and parsed then lines, src = parsed, "YouTube captions" end
                end
            elseif step.bl then
                if type(j.ttml) == "string" and #j.ttml > 0 then
                    local pok, parsed = pcall(parse_ttml, j.ttml)
                    if pok and parsed then lines, src = parsed, "Better Lyrics" end
                end
            else
                local found
                if step.get then
                    if type(j.syncedLyrics) == "string" and #j.syncedLyrics > 0 then found = j.syncedLyrics end
                else
                    found = pick_synced(j, step.strict)
                end
                if found then
                    lines = parse_lrc(found)
                    if #lines == 0 then lines = nil else src = "lrclib" end
                end
            end
        end
    end
    if lines then
        set_lyrics(lines, src)
        lf.state = "found"
        if hebnix.get_bool("media_overlay_src_saved", true) then cache_save(src, lines) end
        return
    end
    -- status 0 is a network error or timeout. those and 429/5xx say nothing
    -- about whether the lyrics exist, so ask the same thing again. Better
    -- Lyrics' 401 means "not in our cache", that falls through to the next step
    if (status == 0 or status == 429 or status >= 500) and lf.tries < LYR_TRANSIENT_TRIES then
        lf.tries = lf.tries + 1
        lf.next_at = mono() + 2 * lf.tries
        return
    end
    lf.step = lf.step + 1
    lf.tries = 0
    lf.next_at = 0
end

-- image::open goes by extension, so name the cover after its magic bytes
local function image_ext(b)
    if b:sub(1, 4) == "\137PNG" then return "png" end
    if b:sub(1, 2) == "\255\216" then return "jpg" end
    if b:sub(1, 4) == "RIFF" and b:sub(9, 12) == "WEBP" then return "webp" end
    if b:sub(1, 2) == "BM" then return "bmp" end
    return nil
end

local function load_cover()
    hebnix.clear_asset_dir("temp")
    S.cover_file = nil
    S.palette = DEFAULT_PALETTE
    local bytes = hebnix.media_thumbnail()
    if not bytes or #bytes == 0 then return end
    local ext = image_ext(bytes)
    if not ext then return end
    local fname = "cover_" .. hex(6) .. "." .. ext
    if hebnix.write_asset("temp/" .. fname, bytes) then
        S.cover_file = fname
        local pal = hebnix.image_palette("temp/" .. fname)
        if pal then S.palette = pal end
    end
end

-- lyric timing: a global offset plus one remembered per song, since music
-- videos have intros the album version doesn't. positive = lyrics show sooner
local function song_key()
    if not S.now then return nil end
    local a, t = lyric_query(S.now)
    return (a .. "|" .. t):lower()
end

local function song_offsets()
    local raw = hebnix.get_string("media_overlay_song_offsets", "")
    if raw == "" then return {} end
    local ok, j = pcall(hebnix.json_decode, raw)
    return (ok and type(j) == "table") and j or {}
end

local function song_offset()
    if S.song_off == nil then
        local key = song_key()
        S.song_off = key and tonumber(song_offsets()[key]) or 0
    end
    return S.song_off
end

local function set_song_offset(ms)
    local key = song_key()
    if not key then return end
    ms = math.max(-40000, math.min(40000, math.floor(ms)))
    S.song_off = ms
    local all = song_offsets()
    local n = 0
    for _ in pairs(all) do n = n + 1 end
    if n > 300 then all = {} end
    all[key] = (ms ~= 0) and ms or nil
    hebnix.set("media_overlay_song_offsets", hebnix.json_encode(all))
    S.sync_msg = string.format("lyrics sync %+.2fs", ms / 1000)
    S.sync_until = mono() + 2
end

local function nudge_song_offset(delta_ms)
    set_song_offset(song_offset() + delta_ms)
end

-- some lyric files stamp each line with when it ends instead of when it
-- starts. per song, remembered like the offset
local function song_end_times()
    if S.song_end == nil then
        local key = song_key()
        local raw = hebnix.get_string("media_overlay_song_end_times_map", "")
        local ok, j = false, nil
        if raw ~= "" then ok, j = pcall(hebnix.json_decode, raw) end
        S.song_end = (key and ok and type(j) == "table" and j[key] == true) or false
    end
    return S.song_end
end

local function set_song_end_times(on)
    local key = song_key()
    if not key then return end
    local raw = hebnix.get_string("media_overlay_song_end_times_map", "")
    local ok, j = false, nil
    if raw ~= "" then ok, j = pcall(hebnix.json_decode, raw) end
    local all = (ok and type(j) == "table") and j or {}
    all[key] = on and true or nil
    hebnix.set("media_overlay_song_end_times_map", hebnix.json_encode(all))
    S.song_end = on and true or false
end

local function total_offset()
    return hebnix.get_number("media_overlay_lyrics_offset", 0) + song_offset()
end

local function apply_media(m)
    local visible = m and (m.status == "playing" or m.status == "paused" or m.status == "changing")
    if not visible then
        if S.key then
            S.key = nil
            S.now = nil
            S.lyrics = nil
        end
        return
    end

    S.app = m.app
    local key = (m.app or "") .. "\1" .. (m.title or "") .. "\1" .. (m.artist or "")
    local new_track = key ~= S.key
    if new_track then
        S.key = key
        S.track_n = S.track_n + 1
        set_lyrics(nil, nil)
        S.lyric_i = -1
        S.now = nil
        S.song_off = nil
        S.song_end = nil
        S.yt_vid = nil
        S.th = nil
        S.full_cover = nil
        hebnix.clear_asset_dir("full")
    end

    if m.thumb_rev ~= S.thumb_rev then
        S.thumb_rev = m.thumb_rev
        load_cover()
    end

    local artist = clean_artist(m.artist)
    if #artist == 0 then artist = clean_artist(m.album_artist) end
    if S.now and S.now.updated == m.updated_unix_ms and S.now.status == m.status then
        S.now.duration_ms = m.duration_ms
    else
        local base = m.position_ms or 0
        if m.is_playing and (m.updated_unix_ms or 0) > 0 then
            local drift = hebnix.unix_millis() - m.updated_unix_ms
            if drift >= 0 and drift < 3600000 then base = base + drift end
        end
        S.now = {
            title = m.title,
            artist = artist,
            album = m.album,
            is_playing = m.is_playing,
            status = m.status,
            position_ms = base,
            duration_ms = m.duration_ms or 0,
            at = mono(),
            updated = m.updated_unix_ms,
        }
    end
end

-- the whole video thumbnail. browsers hand windows a square crop of it, so
-- the full 16:9 one comes straight from youtube by video id. the id comes
-- from youtube video mode's caption search when it ran, else its own search
local function full_thumb_wanted()
    return S.now and hebnix.get_bool("media_overlay_full_thumb", false)
        and hebnix.get_bool("media_overlay_show_cover", true) and is_browser(S.app)
end

local function thumb_get(th, size)
    hebnix.http_request_async("thumb:" .. th.n .. ":img:" .. size, "GET",
        string.format(YT_THUMB, S.yt_vid, size), nil, { ["User-Agent"] = YT_WEB_UA })
end

local function thumb_tick()
    if not full_thumb_wanted() then return end
    local th = S.th
    if not th or th.n ~= S.track_n then
        th = { n = S.track_n, state = "start", at = mono() }
        S.th = th
    end
    if th.state ~= "start" then return end
    if S.yt_vid then
        th.state = "img"
        thumb_get(th, "maxresdefault")
        return
    end
    -- in video mode the caption lookup searches for this video anyway
    if video_mode() and mono() - th.at < 4 then return end
    if #(S.now.title or "") == 0 then return end
    th.state = "search"
    hebnix.http_request_async("thumb:" .. th.n .. ":search", "POST", YT_SEARCH,
        hebnix.json_encode({ context = { client = YT_WEB }, query = S.now.title }),
        { ["Content-Type"] = "application/json", ["User-Agent"] = YT_WEB_UA })
end

local function thumb_result(id, status, body)
    local th = S.th
    local n, what = id:match("^thumb:(%d+):(%a+)")
    if not th or tonumber(n) ~= th.n or th.n ~= S.track_n then return end
    if what == "search" then
        local vid
        if status == 200 then
            local ok, j = pcall(hebnix.json_decode, body)
            if ok and type(j) == "table" then vid = yt_pick(j) end
        end
        if vid then
            S.yt_vid = vid
            th.state = "start"
        else
            th.state = "none" -- not a youtube video, keep the square cover
        end
        return
    end
    local ext = status == 200 and image_ext(body)
    if ext then
        local fname = "full/thumb_" .. hex(6) .. "." .. ext
        if hebnix.write_asset(fname, body) then S.full_cover = fname end
        th.state = "done"
    elseif id:match(":img:maxresdefault$") then
        -- not every video has a max-res thumbnail, the 320x180 one always exists
        thumb_get(th, "mqdefault")
    else
        th.state = "none"
    end
end

function plugin.on_http_result(id, status, body, headers)
    if id:sub(1, 4) == "lyr:" then
        lyrics_result(id, status, body or "")
    elseif id:sub(1, 6) == "thumb:" then
        thumb_result(id, status, body or "")
    end
end

function plugin.on_load()
    reset_state()
    -- the bottom-middle tickbox became a lyrics position
    if hebnix.get_bool("media_overlay_lyrics_bottom", false) then
        hebnix.set("media_overlay_lyrics_pos", "Bottom middle of screen")
        hebnix.set("media_overlay_lyrics_bottom", false)
    end
    hebnix.write_asset("temp/.keep", "")
    hebnix.clear_asset_dir("temp")
    hebnix.write_asset("full/.keep", "")
    hebnix.clear_asset_dir("full")
    math.randomseed(os.time() + math.floor(mono() * 1000))
end

function plugin.on_unload()
    hebnix.clear_asset_dir("temp")
    hebnix.clear_asset_dir("full")
    reset_state()
end

-- set further down, needs position_ms and lyric_index
local sync_now_fn = nil

-- edge-detect the nudge binds and the sync-now bind
local function update_nudge_binds()
    local sync_bind = hebnix.get_string("media_overlay_sync_now_bind", "")
    if sync_bind ~= "" then
        local pressed = hebnix.is_bind_pressed(sync_bind)
        if pressed and not S.sync_now_was and S.now and sync_now_fn then sync_now_fn() end
        S.sync_now_was = pressed
    end
    local step = hebnix.get_number("media_overlay_nudge_step", 500)
    for _, d in ipairs({ { "sooner", step }, { "later", -step } }) do
        local name = "media_overlay_nudge_" .. d[1] .. "_bind"
        local bind = hebnix.get_string(name, "")
        if bind ~= "" then
            local pressed = hebnix.is_bind_pressed(bind)
            if pressed and not S["nudge_" .. d[1]] and S.now then nudge_song_offset(d[2]) end
            S["nudge_" .. d[1]] = pressed
        end
    end
    if S.capturing then
        local status, result = hebnix.capture_bind_result()
        if status == "done" then
            if S.capturing == "sync_now" then
                hebnix.set("media_overlay_sync_now_bind", result)
            else
                hebnix.set("media_overlay_nudge_" .. S.capturing .. "_bind", result)
            end
            S.capturing = nil
        elseif status == "timeout" then
            S.capturing = nil
        end
    end
end

function plugin.on_tick()
    update_nudge_binds()
    local t = mono()
    if t - S.last_poll < POLL then return end
    S.last_poll = t
    apply_media(hebnix.media_session())
    lyrics_tick()
    thumb_tick()
end

local SYNC_MODES = { "First line", "Next line" }
local CORNERS = { "Bottom Left", "Bottom Right", "Top Left", "Top Right" }
local LYRIC_ANIMS = { "Slide", "Fade", "Scale", "None" }
local LYRIC_POS = { "Below card", "Above card", "Bottom middle of screen" }
local POS_BOTTOM = "Bottom middle of screen"

-- lyrics at the bottom middle of the screen like subtitles: picked as the
-- lyrics position, or just for captions in youtube video mode
local function subtitles_on()
    return hebnix.get_string("media_overlay_lyrics_pos", "Below card") == POS_BOTTOM
        or (video_mode() and hebnix.get_bool("media_overlay_yt_bottom", false))
end

local function position_ms()
    if not S.now then return 0 end
    local pos = S.now.position_ms or 0
    if S.now.is_playing then pos = pos + math.floor((mono() - S.now.at) * 1000) end
    local dur = S.now.duration_ms or 0
    if dur > 0 and pos > dur then pos = dur end
    return pos
end

local function fmt_time(ms)
    local s = math.max(0, math.floor((ms or 0) / 1000))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function lyric_index(pos_s)
    if not S.lyrics or #S.lyrics == 0 then return 0 end
    local idx = 0
    for i, l in ipairs(S.lyrics) do
        if l.t <= pos_s then idx = i else break end
    end
    return idx
end

local function fmt_time_ms(ms)
    ms = math.max(0, math.floor(ms or 0))
    return string.format("%d:%02d.%03d", math.floor(ms / 60000), math.floor(ms / 1000) % 60, ms % 1000)
end

-- "sync now": press it the moment you hear a lyric line start and this song's
-- offset is set so that line lines up right then. which line depends on the
-- sync mode: the first line of the song, or whichever is next
sync_now_fn = function()
    if not S.lyrics or #S.lyrics == 0 then return end
    local nxt
    if hebnix.get_string("media_overlay_sync_mode", "First line") == "First line" then
        nxt = S.lyrics[1]
    else
        nxt = S.lyrics[lyric_index((position_ms() + total_offset()) / 1000) + 1]
    end
    if not nxt then return end
    local global = hebnix.get_number("media_overlay_lyrics_offset", 0)
    set_song_offset(nxt.t * 1000 - position_ms() - global)
end

local function with_alpha(hex, a)
    a = math.max(0, math.min(255, math.floor(a * 255 + 0.5)))
    return hex:sub(1, 7) .. string.format("%02x", a)
end

local function opposite(hex)
    local r = tonumber(hex:sub(2, 3), 16) or 255
    local g = tonumber(hex:sub(4, 5), 16) or 255
    local b = tonumber(hex:sub(6, 7), 16) or 255
    return string.format("#%02x%02x%02x", 255 - r, 255 - g, 255 - b)
end

local BORDER_OFF = {
    { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 },
    { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 },
}

local function scroll_text(draw, s, x, y, size, color, cl, cw)
    s = s or ""
    local tw = hebnix.measure_text(s, size, true)
    if tw <= cw then
        draw.text(x, y, s, { color = color, size = size, bold = true })
        return
    end
    local gap = 40 * (size / 15)
    local period = tw + gap
    local off = (mono() * 30) % period
    draw.text(x - off, y, s .. string.rep(" ", 6) .. s,
        { color = color, size = size, bold = true, clip_x = cl, clip_w = cw })
end

-- width of the line up to its end-th byte, remembered per line and size so
-- measure_text isn't called for every word every frame
local function prefix_width(l, stop, size, bold)
    local kw = S.kw
    if not kw or kw.line ~= l or kw.size ~= size or kw.bold ~= bold then
        kw = { line = l, size = size, bold = bold, w = {} }
        S.kw = kw
    end
    if stop <= 0 then return 0 end
    local v = kw.w[stop]
    if not v then
        v = hebnix.measure_text(l.text:sub(1, stop), size, bold)
        kw.w[stop] = v
    end
    return v
end

-- how much of the line is sung: whole words up to the current one, plus the
-- current word filled by how far through it we are
local function karaoke_width(l, clock_s, size, bold)
    local wi = 0
    for i, w in ipairs(l.words) do
        if w.t <= clock_s then wi = i else break end
    end
    if wi == 0 then return 0 end
    local w = l.words[wi]
    local a = prefix_width(l, wi > 1 and l.words[wi - 1].stop or 0, size, bold)
    local b = prefix_width(l, w.stop, size, bold)
    local f = 1
    if w.e > w.t then f = math.max(0, math.min(1, (clock_s - w.t) / (w.e - w.t))) end
    return a + (b - a) * f
end

function plugin.on_overlay(draw, w, h)
    if not S.now then return end
    if hebnix.get_bool("media_overlay_hide_paused", false) and not S.now.is_playing then return end
    if hebnix.get_bool("media_overlay_ignore_spotify", false)
        and (S.app or ""):lower():find("spotify", 1, true) then return end
    -- lyrics / captions can sit at the bottom middle of the screen like
    -- subtitles, out of the card. then the card can be hidden on its own
    local lyrics_on = text_on()
    local bottom = lyrics_on and subtitles_on()
    local card_on = hebnix.get_bool("media_overlay_enabled", true)
    if not card_on and not bottom then return end

    local s = hebnix.get_number("media_overlay_scale", 100) / 100
    local p = S.palette or DEFAULT_PALETTE

    -- the cover box is the square left of the text panel. with cover art off
    -- the whole box goes and only the text panel is shown
    local cover_on = hebnix.get_bool("media_overlay_show_cover", true)
    local art = 130 * s
    local gap = cover_on and (16 * s) or 0
    -- the whole youtube thumbnail is 16:9, the cover box widens to fit it
    local full = cover_on and S.full_cover and full_thumb_wanted()
    local art_w = cover_on and (full and art * 16 / 9 or art) or 0
    local panel_w = 360 * s
    local panel_h = art
    local prog_h = 5 * s
    local prog_gap = 6 * s
    local in_card = lyrics_on and not bottom
    local lyr_scale = hebnix.get_number("media_overlay_lyrics_scale", 100) / 100
    -- subtitles go by the screen size, not the card scale
    local lyr_size = bottom and (h / 40 * lyr_scale) or (15 * s * lyr_scale)
    local row_h = lyr_size * 1.45
    local block_h = in_card and (row_h * 3) or 0
    local lyr_gap = in_card and (10 * s) or 0
    local above = in_card
        and hebnix.get_string("media_overlay_lyrics_pos", "Below card") == "Above card"
    local top_reserve = above and (block_h + lyr_gap) or 0
    local card_w = art_w + gap + panel_w
    local card_h = panel_h + prog_gap + prog_h + (in_card and (block_h + lyr_gap) or 0)
    local margin = 24 * s

    local corner = hebnix.get_string("media_overlay_corner", "Bottom Left")
    local x, y
    if corner == "Bottom Right" then
        x, y = w - card_w - margin, h - card_h - margin
    elseif corner == "Top Left" then
        x, y = margin, margin
    elseif corner == "Top Right" then
        x, y = w - card_w - margin, margin
    else
        x, y = margin, h - card_h - margin
    end

    local cy0 = y + top_reserve

    if S.sync_msg and mono() < (S.sync_until or 0) then
        draw.text(x, y - 18 * s, S.sync_msg, { color = p.text, size = 14 * s, bold = true })
    end

    -- what the plugin thinks the video time is, to compare with youtube's own
    -- player time while lining the lyrics up
    if hebnix.get_bool("media_overlay_sync_debug", false) then
        local pos_ms = position_ms()
        local clock = pos_ms + total_offset()
        local idx = S.lyrics and lyric_index(clock / 1000) or 0
        local cur = S.lyrics and S.lyrics[idx]
        local nxt = S.lyrics and S.lyrics[idx + 1]
        local l1 = string.format("video time (plugin): %s    lyric clock: %s    offset %+d ms",
            fmt_time_ms(pos_ms), fmt_time_ms(clock), math.floor(total_offset()))
        local l2
        if not S.lyrics or #S.lyrics == 0 then
            l2 = "no synced lyrics loaded"
        else
            l2 = string.format("line %d at %s    next line at %s (in %.2fs)",
                idx, cur and fmt_time_ms(cur.t * 1000) or "--",
                nxt and fmt_time_ms(nxt.t * 1000) or "--",
                nxt and (nxt.t * 1000 - clock) / 1000 or 0)
        end
        local below = corner == "Top Left" or corner == "Top Right"
        local dy = below and (y + card_h + 8 * s) or (y - 54 * s)
        local dw = math.max(hebnix.measure_text(l1, 13 * s, true), hebnix.measure_text(l2, 13 * s, true)) + 16 * s
        draw.rect(x, dy, dw, 40 * s, { color = "#000000b0", filled = true, radius = 6 * s })
        draw.text(x + 8 * s, dy + 4 * s, l1, { color = "#ffffff", size = 13 * s, bold = true })
        draw.text(x + 8 * s, dy + 21 * s, l2, { color = "#ffd166", size = 13 * s, bold = true })
    end

    local dur = S.now.duration_ms or 0
    local pos = position_ms()
    local by = cy0 + panel_h + prog_gap

    if not card_on then
        -- subtitles only, no card
    elseif not cover_on then
        -- no cover box at all
    elseif full then
        draw.image("assets/" .. S.full_cover, x, cy0, art_w, art, { opacity = 1.0, radius = 10 * s })
    elseif S.cover_file then
        draw.image("assets/temp/" .. S.cover_file, x, cy0, art, art, { opacity = 1.0, radius = 10 * s })
    else
        draw.rect(x, cy0, art, art, { color = p.dark, filled = true, radius = 10 * s })
        draw.text(x + art / 2, cy0 + art / 2 - 14 * s, "\u{266A}",
            { color = p.vibrant, size = 34 * s, halign = "center" })
    end

    if card_on then
        local px = x + art_w + gap
        draw.gradient(px, cy0, panel_w, panel_h,
            { color = p.grad1, color2 = p.grad2, radius = 12, angle = 135 })

        local pad_x = 18 * s
        local cl = px + pad_x
        local cr = px + panel_w - pad_x
        local cw = cr - cl

        local sub = S.now.artist
        if not sub or #sub == 0 then sub = S.now.album or "" end
        scroll_text(draw, S.now.title or "Unknown", cl, cy0 + 18 * s, 21 * s, p.text, cl, cw)
        scroll_text(draw, sub, cl, cy0 + 47 * s, 15 * s, p.text .. "cc", cl, cw)

        local row_cy = cy0 + panel_h - 26 * s
        local time_w = 46 * s
        -- some players (and live streams) report no timeline, skip the clock then
        if dur > 0 then
            draw.text(cl, row_cy - 8 * s, fmt_time(pos),
                { color = p.text, size = 13 * s, bold = true })
            draw.text(cr, row_cy - 8 * s, fmt_time(dur),
                { color = p.text, size = 13 * s, halign = "right", bold = true })
        end

        local heights = { 6, 14, 10, 18, 8, 20, 12, 16, 6, 10, 14, 22, 12, 18,
            8, 14, 10, 16, 6, 12, 8, 18, 10, 14 }
        local vl = cl + time_w + 12 * s
        local vr = cr - time_w - 12 * s
        local n = #heights
        local bw = 3 * s
        local t = mono()
        for i = 1, n do
            local amp = S.now.is_playing and (0.55 + 0.45 * math.abs(math.sin(t * 5 + i * 0.7))) or 1.0
            local bh = heights[i] * amp * 1.2 * s
            local bx = vl + (vr - vl - bw) * (i - 1) / (n - 1)
            draw.rect(bx, row_cy - bh / 2, bw, bh, { color = p.accent or p.vibrant, filled = true, radius = 2 })
        end

        draw.rect(x, by, card_w, prog_h, { color = "#00000073", filled = true, radius = 2 })
        if dur > 0 then
            local frac = math.max(0, math.min(1, pos / dur))
            draw.rect(x, by, card_w * frac, prog_h, { color = p.vibrant, filled = true, radius = 2 })
        end
    end -- card_on

    if lyrics_on and S.lyrics and #S.lyrics > 0 then
        local offset = total_offset()
        local idx = lyric_index((pos + offset) / 1000)
        -- stamped with line ends: the line being sung is the one after the last stamp
        if song_end_times() then idx = idx + 1 end
        if idx ~= S.lyric_i then
            S.lyric_i = idx
            S.lyric_t0 = mono()
        end
        -- subtitles sit over the game rather than the card, so auto colour
        -- is plain white there
        local base_color = bottom and "#ffffff" or p.text
        if not hebnix.get_bool("media_overlay_lyrics_auto_color", true) then
            base_color = hebnix.get_string("media_overlay_lyrics_color", "#ffffff")
        end
        local border = hebnix.get_number("media_overlay_lyrics_border", 0) * s
        local border_color = opposite(base_color)
        if not hebnix.get_bool("media_overlay_lyrics_border_auto", true) then
            border_color = hebnix.get_string("media_overlay_lyrics_border_color", "#000000")
        end
        local anim = hebnix.get_string("media_overlay_lyrics_anim", "Slide")
        local p_a = anim == "None" and 1.0 or math.min(1.0, (mono() - S.lyric_t0) / 0.30)

        local shift = anim == "Slide" and ((1 - p_a) * row_h) or 0
        local cx, rows
        if bottom then
            -- subtitles: just the line being sung, bottom middle of the screen
            cx = w / 2
            rows = { { i = idx, c = h - h * 0.08 - row_h / 2, cur = true } }
        else
            local region_top = above and y or (by + prog_h + lyr_gap)
            local cy = region_top + block_h / 2
            cx = x + card_w / 2
            rows = {
                { i = idx, c = cy - row_h, cur = true },
                { i = idx + 1, c = cy, cur = false },
                { i = idx + 2, c = cy + row_h, cur = false },
            }
        end
        local sub_box = bottom and hebnix.get_bool("media_overlay_lyrics_bottom_box", true)
        local clock_s = (pos + offset) / 1000
        local karaoke = hebnix.get_bool("media_overlay_karaoke", true)
        for _, r in ipairs(rows) do
            local l = S.lyrics[r.i]
            -- lines with a real end time (Better Lyrics, captions) stop looking
            -- current once sung, when a long gap follows
            local cur = r.cur
            if l and cur and l.e and clock_s > l.e + 0.5 then
                local nx = S.lyrics[r.i + 1]
                if not nx or nx.t - clock_s > 3 then
                    cur = false
                    -- subtitles go away once their line is over, like youtube's
                    if bottom then l = nil end
                end
            end
            if l and l.text and #l.text > 0 then
                local size = r.cur and lyr_size or (lyr_size * 0.82)
                local alpha = cur and 1.0 or 0.7
                if cur and anim == "Fade" then alpha = 0.35 + 0.65 * p_a end
                if r.cur and anim == "Scale" then size = lyr_size * (0.7 + 0.3 * p_a) end
                local ty = r.c - size / 2 + shift
                local word_fill = karaoke and cur and l.words
                -- karaoke draws left-aligned from a measured start so the dim
                -- and filled passes sit exactly on top of each other
                local tx, halign = cx, "center"
                if word_fill then
                    tx, halign = cx - hebnix.measure_text(l.text, size, cur) / 2, "left"
                end
                -- youtube-style dark box behind subtitles, readable over any game
                if sub_box then
                    local tw = hebnix.measure_text(l.text, size, cur)
                    local bx, bpy = size * 0.45, size * 0.2
                    draw.rect(cx - tw / 2 - bx, ty - bpy, tw + bx * 2, size * 1.25 + bpy * 2,
                        { color = with_alpha("#000000", 0.6 * alpha), filled = true, radius = size * 0.2 })
                end
                if border > 0 then
                    local bcol = with_alpha(border_color, alpha)
                    for _, o in ipairs(BORDER_OFF) do
                        draw.text(tx + o[1] * border, ty + o[2] * border, l.text,
                            { color = bcol, size = size, halign = halign, bold = cur })
                    end
                end
                if word_fill then
                    draw.text(tx, ty, l.text,
                        { color = with_alpha(base_color, alpha * 0.45), size = size, bold = cur })
                    local fill = karaoke_width(l, clock_s, size, cur)
                    if fill > 0 then
                        draw.text(tx, ty, l.text,
                            { color = with_alpha(base_color, alpha), size = size, bold = cur,
                                clip_x = tx, clip_w = fill })
                    end
                else
                    draw.text(tx, ty, l.text,
                        { color = with_alpha(base_color, alpha), size = size,
                            halign = halign, bold = cur })
                end
            end
        end
    end
end

-- one row for a bind setting: label, current bind, set / clear. `who` is what
-- the capture code in update_nudge_binds uses to know which setting to write
local function bind_row(ui, name, label, who)
    local bind = hebnix.get_string(name, "")
    ui.horizontal(function()
        ui.label(label .. ": " .. (bind ~= "" and bind or "(none set)"))
        if S.capturing == who then
            ui.colored_label("#d35400", "press any key/button...")
        else
            if ui.button("set") then
                if hebnix.capture_bind_async(10) then S.capturing = who end
            end
            if bind ~= "" and ui.button("clear") then hebnix.set(name, "") end
        end
    end)
end

function plugin.on_settings(ui)
    ui.label("Shows whatever media Windows reports as playing (browser, Spotify, VLC, etc.) as an overlay card.")
    if not hebnix.media_session then
        ui.colored_label("#e74c3c", "error: this Hebnix build has no media_session API")
    elseif S.now then
        ui.colored_label("#1db954", S.now.status .. " (" .. app_name(S.app) .. "): " .. (S.now.title or "?"))
    else
        ui.colored_label("#e0a030", "nothing playing")
    end

    ui.space(6)
    ui.heading("YouTube video mode")
    ui.checkbox("media_overlay_youtube_mode", "YouTube video mode", false)
    ui.label("Made for watching YouTube videos in your browser: shows the video's captions (subtitles) where the lyrics go.")
    ui.label("It works on music videos too, but it isn't meant for music. Captions are often missing or worse than the lyric sources, so leave it off if you mostly listen to music.")
    local pos_bottom = hebnix.get_string("media_overlay_lyrics_pos", "Below card") == POS_BOTTOM
    if hebnix.get_bool("media_overlay_youtube_mode", false) then
        ui.label("Only browser videos are affected, Spotify and other apps keep using lyrics. Gets captions the way the YouTube app does, without signing in. English is preferred, auto-generated captions fill in word by word.")
        ui.checkbox("media_overlay_yt_bottom", "Show captions at the bottom middle of the screen, like subtitles", false)
        if pos_bottom then
            ui.label("(Lyrics position is already set to bottom middle of screen, so captions go there anyway.)")
        elseif hebnix.get_bool("media_overlay_yt_bottom", false) then
            ui.checkbox("media_overlay_lyrics_bottom_box", "Dark box behind the text", true)
            ui.label("Shows the current caption only. Untick \"Show overlay card\" below for subtitles on their own.")
        end
    end

    ui.space(6)
    ui.heading("Card")
    ui.checkbox("media_overlay_enabled", "Show overlay card", true)
    ui.checkbox("media_overlay_hide_paused", "Hide while paused", false)
    ui.checkbox("media_overlay_ignore_spotify", "Ignore Spotify (use Spotify Overlay for it)", false)
    ui.checkbox("media_overlay_show_cover", "Show cover art", true)
    ui.checkbox("media_overlay_full_thumb", "Show the whole video thumbnail instead of a square crop (YouTube in your browser)", false)
    if hebnix.get_bool("media_overlay_full_thumb", false) then
        ui.label("Browsers only give Windows a square crop, so this finds the video on YouTube and downloads its full thumbnail. Other media keeps the square cover.")
    end
    ui.combo_box("media_overlay_corner", "Position", CORNERS)
    ui.slider("media_overlay_scale", "Scale", 60, 160, 100)

    ui.space(8)
    ui.heading("Lyrics")
    ui.checkbox("media_overlay_lyrics", "Show synced lyrics", true)
    ui.checkbox("media_overlay_karaoke", "Karaoke: highlight each word as it's sung (when the lyrics have word timing)", true)
    ui.collapsing("Lyric sources", function(ui)
        ui.label("Tried top to bottom, the first one with lyrics wins.")
        ui.checkbox("media_overlay_src_saved", "Saved lyrics (ones found before, instant and offline)", true)
        ui.checkbox("media_overlay_src_betterlyrics",
            "Better Lyrics (better-lyrics.boidu.dev): Apple Music lyrics with word timing, popular songs only", true)
        ui.checkbox("media_overlay_src_lrclib", "lrclib.net: community lyrics, line timing", true)
        if video_mode() then
            ui.colored_label("#e0a030", "YouTube video mode is on: this browser video uses its captions instead of these.")
        end
    end)
    if S.now and text_on() then
        local lf = S.lf
        local what = video_mode() and "captions" or "lyrics"
        if S.lyrics then
            local timed = false
            for _, l in ipairs(S.lyrics) do
                if l.words then timed = true break end
            end
            ui.colored_label("#1db954", what .. ": found (" .. (S.lyrics_src or "?") .. ")"
                .. (timed and ", word timing" or ", line timing only"))
            if ui.button("Forget saved " .. what .. " for this " .. (video_mode() and "video" or "song")) then
                cache_forget()
                set_lyrics(nil, nil)
                lyrics_reset()
            end
        elseif lf and lf.state == "no sources" then
            ui.colored_label("#e0a030", "lyrics: no lyric sources ticked")
        elseif lf and lf.state == "not found" then
            ui.colored_label("#e0a030", video_mode() and "captions: couldn't find this video's captions on YouTube"
                or "lyrics: none of the ticked sources have this song")
        elseif lf then
            ui.colored_label("#e0a030", string.format("%s: searching (round %d of %d)",
                what, lf.round, #LYR_ROUND_DELAY + 1))
        end
        if not S.lyrics and ui.button("Retry " .. what) then lyrics_reset() end
    end
    ui.combo_box("media_overlay_lyrics_anim", "Animation", LYRIC_ANIMS)
    ui.combo_box("media_overlay_lyrics_pos", "Position", LYRIC_POS)
    if hebnix.get_string("media_overlay_lyrics_pos", "Below card") == POS_BOTTOM then
        ui.checkbox("media_overlay_lyrics_bottom_box", "Dark box behind the text", true)
        ui.label("Like subtitles: the current line only. Untick \"Show overlay card\" above for lyrics on their own.")
    end
    ui.slider("media_overlay_lyrics_scale", "Scale", 60, 200, 100)
    ui.checkbox("media_overlay_lyrics_auto_color", "Auto lyrics colour", true)
    if not hebnix.get_bool("media_overlay_lyrics_auto_color", true) then
        ui.color_picker("media_overlay_lyrics_color", "Lyrics colour", "#ffffff")
    end
    ui.slider("media_overlay_lyrics_border", "Border", 0, 1.5, 0)
    ui.checkbox("media_overlay_lyrics_border_auto", "Auto border colour (opposite)", true)
    if not hebnix.get_bool("media_overlay_lyrics_border_auto", true) then
        ui.color_picker("media_overlay_lyrics_border_color", "Border colour", "#000000")
    end

    ui.space(8)
    ui.heading("Lyrics out of sync?")
    ui.label("Press the sync now key the moment you hear the lyric line start.")
    bind_row(ui, "media_overlay_sync_now_bind", "sync now key", "sync_now")
    ui.combo_box("media_overlay_sync_mode", "Sync now lines up", SYNC_MODES)
    if S.now then
        -- a view of this song's remembered setting, like the sync sliders
        local cur = song_end_times()
        if S.end_view ~= cur then
            hebnix.set("media_overlay_song_end_times", cur)
            S.end_view = cur
        end
        ui.checkbox("media_overlay_song_end_times",
            "Lyrics change when a line ends instead of starts (this song)", false)
        local v = hebnix.get_bool("media_overlay_song_end_times", false)
        if v ~= cur then
            set_song_end_times(v)
            S.end_view = v
        end
    end
    if S.now then
        ui.label(string.format("this song's sync: %+.2fs (remembered for next time)", song_offset() / 1000))
    end

    ui.space(8)
    ui.collapsing("Music video alignment (advanced)", function(ui)
        ui.label("Fine tuning. Positive = lyrics show sooner, negative = later.")
        ui.slider("media_overlay_lyrics_offset", "All songs (ms)", -5000, 5000, 0)
        if S.now then
            -- the slider is a view of this song's remembered offset: push changes
            -- made by the keys into it and write slider moves back
            local cur = song_offset()
            if S.slider_off ~= cur then
                hebnix.set("media_overlay_song_sync", cur)
                S.slider_off = cur
            end
            ui.slider("media_overlay_song_sync", "This song (ms)", -40000, 40000, 0)
            local v = math.floor(hebnix.get_number("media_overlay_song_sync", 0))
            if v ~= cur then
                set_song_offset(v)
                S.slider_off = song_offset()
            end
        else
            ui.label("This song: (nothing playing)")
        end
        ui.space(4)
        ui.slider("media_overlay_nudge_step", "Nudge key step (ms)", 100, 2000, 500)
        bind_row(ui, "media_overlay_nudge_sooner_bind", "lyrics sooner key", "sooner")
        bind_row(ui, "media_overlay_nudge_later_bind", "lyrics later key", "later")
        ui.space(4)
        ui.checkbox("media_overlay_sync_debug", "Show lyric timing (compare with YouTube's player time)", false)
    end)
    ui.space(6)
end

return plugin
