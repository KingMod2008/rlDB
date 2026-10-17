local plugin = {}

local saves = {}
local save_lookup = {}
local settings = {}
local categories = { "All", "Controller", "Camera", "Gameplay / Interface", "Audio", "Video", "Matchmaking" }
local status = "Choose a save, then load its settings."
local selected_path = ""

local function setting_key(value)
    return "save_inspector_value_" .. value.id
end

local function reload_saves()
    saves = {}
    save_lookup = {}
    for _, account in ipairs(kingmod.find_save_accounts()) do
        local label = string.format("%s  (%s)", account.display_name, account.account_id)
        table.insert(saves, label)
        save_lookup[label] = account.path
    end
    if #saves == 0 then
        status = "No active Rocket League account saves were found."
        selected_path = ""
        return
    end
    if selected_path == "" then selected_path = save_lookup[saves[1]] end
end

local function load_settings()
    if selected_path == "" then
        status = "Choose a save file first."
        return
    end
    local result = kingmod.load_save_configuration(selected_path)
    if result.error then
        status = "Could not read save: " .. result.error
        return
    end
    settings = result.values or {}
    for _, value in ipairs(settings) do
        if value.editor_kind ~= "read_only" then
            kingmod.set(setting_key(value), value.value)
        end
    end
    status = string.format("Loaded %d settings. Rocket League must be closed to edit or restore.", #settings)
end

local function should_show(value, category, filter)
    if category ~= "All" and value.category ~= category then return false end
    filter = string.lower(filter or "")
    return filter == "" or string.find(string.lower(value.name), filter, 1, true) ~= nil
end

local function render_binding(ui, value)
    ui.horizontal(function(row)
        row.label(value.name)
        row.label(value.value)
    end)
end

local function render_controller_bindings(ui)
    local bindings = {}
    for _, value in ipairs(settings) do
        if value.category == "Controller Bindings" then table.insert(bindings, value) end
    end
    if #bindings == 0 then return end
    table.sort(bindings, function(left, right) return left.name < right.name end)
    ui.heading("Controller Bindings")
    ui.label("Action                                      Assigned key")
    for _, value in ipairs(bindings) do render_binding(ui, value) end
    ui.space(10)
end

local function render_setting(ui, value)
    ui.horizontal(function(row)
        row.label(value.name)
        if value.editor_kind == "read_only" then
            row.label(value.value)
            return
        end

        local key = setting_key(value)
        local input
        if value.editor_kind == "boolean" then
            input = row.combo_box(key, "", { "true", "false" })
        else
            input = row.text_input(key, "Value")
        end

        if row.button("Apply " .. value.name) then
            local result = kingmod.update_save_configuration(selected_path, value.id, input)
            if result.error then
                status = "Not changed: " .. result.error
            else
                status = "Saved. Backup: " .. result.backup
                load_settings()
            end
        end
    end)
end

function plugin.on_load()
    reload_saves()
end

function plugin.on_settings(ui)
    ui.label("Reads the same Controller, Camera, Gameplay, Audio, Video and Matchmaking settings.")
    ui.label(status)
    ui.space(6)

    if ui.button("Refresh save files") then reload_saves() end
    if #saves > 0 then
        local selected = ui.combo_box("save_inspector_path", "Account save", saves)
        selected_path = save_lookup[selected] or selected_path
    end
    if ui.button("Load save settings") then load_settings() end
    if #settings == 0 then return end

    render_controller_bindings(ui)
    ui.space(8)
    local category = ui.combo_box("save_inspector_category", "Category", categories)
    local filter = ui.text_input("save_inspector_filter", "Filter settings by name")
    local previous_category = ""
    local shown = 0

    for _, value in ipairs(settings) do
        if value.category ~= "Controller Bindings" and should_show(value, category, filter) then
            if value.category ~= previous_category then
                ui.space(6)
                ui.heading(value.category)
                previous_category = value.category
            end
            render_setting(ui, value)
            shown = shown + 1
        end
    end
    if shown == 0 then ui.label("No settings match this filter.") end

    ui.space(8)
    ui.heading("Backups")
    if ui.button("Create backup beside save") then
        local result = kingmod.backup_save_configuration(selected_path)
        status = result.error and ("Backup failed: " .. result.error) or ("Backup: " .. result.backup)
    end
    local restore_path = ui.text_input("save_inspector_restore_path", "Full path to a .save or .bak backup")
    if ui.button("Restore selected backup") then
        local result = kingmod.restore_save_configuration(selected_path, restore_path)
        if result.error then
            status = "Restore failed: " .. result.error
        else
            status = "Restored. Safety backup: " .. result.backup
            load_settings()
        end
    end
end

return plugin
