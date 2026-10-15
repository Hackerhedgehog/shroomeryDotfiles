-- Game Mode
function activate_gamemode()
    -- Apply Performance Settings
    hl.config({
        animations = { enabled = false },
        decoration = {
            shadow = { enabled = false },
            blur = { enabled = false },
            active_opacity = 1.0,
            inactive_opacity = 1.0,
            fullscreen_opacity = 1.0,
            rounding = 0
        },
        general = {
            gaps_in = 0,
            gaps_out = 0,
            border_size = 1
        }
    })
    print("Gamemode ON")
end

-- Load Variant
--function load_variant(variant_file,variant_name)
--    variant_file = variant_file:gsub(".lua", "")
--    require("conf." .. variant_name .. "." .. variant_file)
--end
-- Visualizer mode (quickshell VisualizerApp) takes over some binds while its
-- runtime flag exists; Quickshell deletes the flag when the mode ends.
local visualizer_flag = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/shroomery/visualizer-active"

function visualizer_active()
    local f = io.open(visualizer_flag, "r")
    if f then
        f:close()
        return true
    end
    return false
end

function visualizer(action)
    hl.dispatch(hl.dsp.exec_cmd("qs ipc call visualizer " .. action))
end
