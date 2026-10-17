local plugin = {}

local recording = false
local events_by_type = {}
local counts = {}
local event_types = {}
local selected_key = ""
local selected_payload = "{}"
local sequence = 0

local function pretty_json(value)
    local ok, encoded = pcall(hebnix.json_encode, value)
    if not ok then return "{\"error\":\"payload could not be encoded\"}" end
    local output, indent, quoted, escaped = {}, 0, false, false
    for index = 1, #encoded do
        local ch = encoded:sub(index, index)
        if quoted then
            table.insert(output, ch)
            if escaped then escaped = false
            elseif ch == "\\" then escaped = true
            elseif ch == "\"" then quoted = false end
        elseif ch == "\"" then
            quoted = true
            table.insert(output, ch)
        elseif ch == "{" or ch == "[" then
            indent = indent + 1
            table.insert(output, ch .. "\n" .. string.rep("  ", indent))
        elseif ch == "}" or ch == "]" then
            indent = math.max(0, indent - 1)
            table.insert(output, "\n" .. string.rep("  ", indent) .. ch)
        elseif ch == "," then
            table.insert(output, ",\n" .. string.rep("  ", indent))
        elseif ch == ":" then
            table.insert(output, ": ")
        else
            table.insert(output, ch)
        end
    end
    return table.concat(output)
end

local function known_types()
    local options = { "All" }
    for event_type, _ in pairs(event_types) do
        table.insert(options, event_type)
    end
    table.sort(options, function(a, b)
        if a == "All" then return true end
        if b == "All" then return false end
        return a < b
    end)
    return options
end

local function filtered_history(filter)
    local output = {}
    if filter == "All" then
        for _, history in pairs(events_by_type) do
            for _, item in ipairs(history) do table.insert(output, item) end
        end
        table.sort(output, function(a, b) return a.sequence > b.sequence end)
    else
        for _, item in ipairs(events_by_type[filter] or {}) do
            table.insert(output, item)
        end
        table.sort(output, function(a, b) return a.sequence > b.sequence end)
    end
    return output
end

local function clear_recording()
    events_by_type = {}
    counts = {}
    event_types = {}
    selected_key = ""
    selected_payload = "{}"
    sequence = 0
end

local function selected_event(history)
    for _, item in ipairs(history) do
        if item.key == selected_key then
            selected_payload = item.payload
            return
        end
    end
    selected_payload = "{}"
end

function plugin.on_load()
    hebnix.log("Event Viewer loaded")
end

function plugin.on_game_event(event_type, event)
    if not recording then return end
    counts[event_type] = (counts[event_type] or 0) + 1
    event_types[event_type] = true
    sequence = sequence + 1

    local history = events_by_type[event_type] or {}
    events_by_type[event_type] = history
    table.insert(history, {
        key = string.format("%s #%d", event_type, sequence),
        payload = pretty_json(event),
        sequence = sequence,
    })
    if #history > 500 then table.remove(history, 1) end
end

function plugin.on_settings(ui)
    ui.heading("Event Viewer")
    ui.label("Inspect Hebnix game events and their payloads.")
    if ui.button("Open Event Viewer") then
        hebnix.window.open({ title = "Event Viewer", width = 760, height = 620, opacity = 0.96 })
    end
end

function plugin.on_window(ui)
    ui.heading("Event Viewer")
    if ui.button("Close Event Viewer") then
        hebnix.window.close()
        return
    end

    local retained = 0
    for _, history in pairs(events_by_type) do retained = retained + #history end
    ui.label(string.format("Retained: %d  |  up to 500 per event type  |  Recording: %s", retained, recording and "on" or "off"))
    if recording then
        if ui.button("Stop") then recording = false end
    elseif ui.button("Record") then
        recording = true
    end
    if ui.button("Clear recording and counts") then clear_recording() end

    ui.space(6)
    ui.heading("Event calls")
    local lines = {}
    for event_type, count in pairs(counts) do
        table.insert(lines, string.format("%s: %d", event_type, count))
    end
    table.sort(lines)
    ui.label(#lines == 0 and "Recording is stopped." or table.concat(lines, "  |  "))

    ui.space(8)
    ui.heading("Recorded history")
    local filter = ui.combo_box("event_viewer_filter", "Event type", known_types())
    local history = filtered_history(filter)
    if #history == 0 then
        ui.label("Click Record to retain incoming events.")
        return
    end

    local choices = {}
    for _, item in ipairs(history) do table.insert(choices, item.key) end
    selected_key = ui.combo_box("event_viewer_history", "Event", choices)
    selected_event(history)
    ui.label("Payload")
    ui.readonly_textbox(selected_payload, 300)
end

return plugin
