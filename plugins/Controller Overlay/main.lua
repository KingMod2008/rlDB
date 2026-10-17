local plugin = {}

plugin.overlay_page = "hud-v4.html"

local CONTROLLER_TYPES = { "Xbox", "PlayStation" }
local POSITIONS = {
    "Top left", "Top middle", "Top right",
    "Bottom left", "Bottom middle", "Bottom right"
}

local function push_controller()
    local controllers = kingmod.controllers()
    local controller = controllers and controllers[1] or nil
    kingmod.overlay.send({
        controller = controller,
        controller_type = kingmod.get_string("controller_type", "Xbox"),
        position = kingmod.get_string("controller_position", "Bottom right"),
        scale = kingmod.get_number("controller_scale", 0.5),
        margin_top = kingmod.get_number("controller_margin_top", 28),
        margin_bottom = kingmod.get_number("controller_margin_bottom", 28),
        margin_left = kingmod.get_number("controller_margin_left", 28),
        margin_right = kingmod.get_number("controller_margin_right", 28),
    })
end

function plugin.on_load()
    kingmod.log("Controller overlay loaded")
    push_controller()
end

function plugin.on_tick()
    push_controller()
end

function plugin.on_settings(ui)
    ui.heading("Controller Overlay")
    ui.combo_box("controller_type", "Controller type", CONTROLLER_TYPES)
    ui.combo_box("controller_position", "Position", POSITIONS)
    ui.slider("controller_scale", "Scale", 0.25, 1.0, 0.5)
    ui.separator()
    ui.label("Margins")
    ui.slider("controller_margin_top", "Top", 0, 500, 28)
    ui.slider("controller_margin_bottom", "Bottom", 0, 500, 28)
    ui.slider("controller_margin_left", "Left", 0, 500, 28)
    ui.slider("controller_margin_right", "Right", 0, 500, 28)
    ui.label("The first connected controller is displayed in game.")
end

return plugin