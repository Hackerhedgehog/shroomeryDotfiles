-- Picture-in-picture: turn the focused window into a small pinned, see-through
-- window in a screen corner, above everything including fullscreen games
-- (Hyprland draws pinned floating windows after fullscreen ones).
-- Keybinds in keybindings.lua call the pip_* functions below.
--
-- The PiP window carries the static tag "pip", so it is found again after a
-- config reload (Lua state is rebuilt then). Its pre-PiP geometry is kept in
-- $XDG_RUNTIME_DIR/shroomery/pip; opacity, size and corner are remembered in
-- ~/.config/shroomery/settings/pip. Geometry rules live in piplogic.lua.
--
-- Note (Hyprland 0.56): float() and pin() take action "enable"/"disable";
-- "set"/"unset" are not recognized there and toggle instead. fullscreen()
-- does take "set"/"unset".
local L = require("piplogic")

local HOME = os.getenv("HOME") or ""
local SETTINGS_FILE = HOME .. "/.config/shroomery/settings/pip"
local RUNTIME_DIR = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/shroomery"
local RESTORE_FILE = RUNTIME_DIR .. "/pip"
local TAG = "pip"

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("a")
    f:close()
    return text
end

local function write_file(path, text)
    local f = io.open(path, "w")
    if not f then
        os.execute("mkdir -p '" .. path:match("(.*)/") .. "'")
        f = io.open(path, "w")
        if not f then return end
    end
    f:write(text)
    f:close()
end

local function load_settings() return L.parse_settings(read_file(SETTINGS_FILE)) end
local function save_settings(s) write_file(SETTINGS_FILE, L.format_settings(s)) end

local function sel(win) return "address:" .. win.address end

local function pip_window()
    for _, w in ipairs(hl.get_windows({ tag = TAG })) do
        if w.mapped then return w end
    end
    return nil
end

local function monitor_area(m)
    return L.screen_area({
        x = m.x, y = m.y, width = m.width, height = m.height,
        scale = m.scale, transform = m.transform,
    })
end

local function area_of(win)
    local m = win.monitor or hl.get_active_monitor()
    if not m then return nil end
    return monitor_area(m)
end

local function set_prop(win, prop, value)
    hl.dispatch(hl.dsp.window.set_prop({ window = sel(win), prop = prop, value = value }))
end

-- Absolute opacity, the same whether the PiP or the game has focus.
local function apply_opacity(win, opacity)
    local v = string.format("%.2f", opacity)
    set_prop(win, "opacity", v)
    set_prop(win, "opacity_inactive", v)
    set_prop(win, "opacity_override", "1")
    set_prop(win, "opacity_inactive_override", "1")
end

-- No blur on the PiP: with decoration.blur.xray a blurred floating window shows
-- the wallpaper through itself instead of the windows below it.
local function apply_props(win, opacity)
    set_prop(win, "keep_aspect_ratio", "1")
    set_prop(win, "no_blur", "1")
    apply_opacity(win, opacity)
end

-- While a PiP exists, resizing by dragging a window border is off (Hyprland has
-- no per-window switch): over a game the cursor often rests on the PiP's border
-- and a click there started a resize. Super+right-drag still resizes.
-- The configured value is kept here; a config reload rebuilds this state and
-- resets the option, so config.reloaded below takes it again.
local saved_resize_on_border = nil

local function hold_border_resize()
    if saved_resize_on_border == nil then
        saved_resize_on_border = hl.get_config("general.resize_on_border")
    end
    hl.config({ general = { resize_on_border = false } })
end

local function release_border_resize()
    if saved_resize_on_border ~= nil then
        hl.config({ general = { resize_on_border = saved_resize_on_border } })
        saved_resize_on_border = nil
    end
end

-- The record for this PiP window, or nil.
local function record_of(win)
    local r = L.parse_restore(read_file(RESTORE_FILE))
    if r and r.address == win.address then return r end
    return nil
end

-- Size from the settings at the aspect ratio fixed when the PiP started, snapped
-- to the corner of `area` (default: the window's monitor).
local function place(win, s, area)
    area = area or area_of(win)
    if not area then return end
    local r = record_of(win)
    local aspect = r and r.aspect or (win.size.x / math.max(win.size.y, 1))
    local w, h = L.size(area, s.width, aspect)
    local x, y = L.position(area, s.corner, w, h)
    hl.dispatch(hl.dsp.window.resize({ window = sel(win), x = w, y = h }))
    hl.dispatch(hl.dsp.window.move({ window = sel(win), x = x, y = y }))
end

local function start(win)
    local s = load_settings()
    if win.fullscreen ~= 0 then
        hl.dispatch(hl.dsp.window.fullscreen({ window = sel(win), action = "unset" }))
    end
    -- A floating window (a browser's own PiP popup) keeps its shape; a tiled one gets 16:9.
    local aspect = win.floating and (win.size.x / math.max(win.size.y, 1)) or 16 / 9
    write_file(RESTORE_FILE, L.format_restore({
        address = win.address, floating = win.floating, pinned = win.pinned,
        x = win.at.x, y = win.at.y, w = win.size.x, h = win.size.y, aspect = aspect,
        workspace = win.workspace and L.workspace_selector(win.workspace.id, win.workspace.name, win.workspace.special),
    }))
    hl.dispatch(hl.dsp.window.tag({ window = sel(win), tag = "+" .. TAG }))
    hl.dispatch(hl.dsp.window.float({ window = sel(win), action = "enable" }))
    hl.dispatch(hl.dsp.window.pin({ window = sel(win), action = "enable" }))
    apply_props(win, s.opacity)
    hold_border_resize()
    place(win, s)
end

local function stop(win)
    local r = record_of(win)
    hl.dispatch(hl.dsp.window.tag({ window = sel(win), tag = "-" .. TAG }))
    set_prop(win, "keep_aspect_ratio", "0")
    set_prop(win, "no_blur", "0")
    release_border_resize()
    -- Float props can't be "unset": opacity multiplier 1 without override = the normal decoration opacity.
    set_prop(win, "opacity", "1.0")
    set_prop(win, "opacity_inactive", "1.0")
    set_prop(win, "opacity_override", "0")
    set_prop(win, "opacity_inactive_override", "0")
    if not (r and r.pinned) then
        hl.dispatch(hl.dsp.window.pin({ window = sel(win), action = "disable" }))
        -- A pinned window lives on whatever workspace is shown; send it back to
        -- the one it came from, without following it there.
        if r and r.workspace then
            hl.dispatch(hl.dsp.window.move({ window = sel(win), workspace = r.workspace, follow = false }))
        end
    end
    if r and r.floating then
        hl.dispatch(hl.dsp.window.resize({ window = sel(win), x = r.w, y = r.h }))
        hl.dispatch(hl.dsp.window.move({ window = sel(win), x = r.x, y = r.y }))
    else
        hl.dispatch(hl.dsp.window.float({ window = sel(win), action = "disable" }))
    end
    os.remove(RESTORE_FILE)
end

-- Ctrl+Super+V: stop the PiP if there is one, else make the focused window PiP.
function pip_toggle()
    local win = pip_window()
    if win then
        stop(win)
        return
    end
    win = hl.get_active_window()
    if win then start(win) end
end

-- dir: +1 / -1 (one 2 % step)
function pip_opacity(dir)
    local win = pip_window()
    if not win then return end
    local s = load_settings()
    s.opacity = L.step_opacity(s.opacity, dir)
    save_settings(s)
    apply_opacity(win, s.opacity)
end

-- dir: +1 bigger / -1 smaller
function pip_resize(dir)
    local win = pip_window()
    if not win then return end
    local s = load_settings()
    s.width = L.step_width(s.width, dir)
    save_settings(s)
    place(win, s)
end

-- Move the PiP onto monitor `m`: a coordinate move alone leaves it assigned to
-- the old monitor, so it first goes (silently) to the workspace shown there.
local function move_to_monitor(win, m)
    local ws = hl.get_active_workspace(m.name)
    if ws then
        hl.dispatch(hl.dsp.window.move({ window = sel(win),
            workspace = L.workspace_selector(ws.id, ws.name, ws.special), follow = false }))
    end
end

-- direction: "up" | "down" | "left" | "right". Already in a corner on that side:
-- cross to the monitor next to this one on that side, if there is one, entering
-- at the near corner (going right from a right corner lands in a left corner).
function pip_corner(direction)
    local win = pip_window()
    if not win then return end
    local s = load_settings()
    if L.at_edge(s.corner, direction) then
        local monitors = hl.get_monitors()
        local areas, cur = {}, nil
        local own = win.monitor and win.monitor.name
        for i, m in ipairs(monitors) do
            areas[i] = monitor_area(m)
            if m.name == own then cur = i end
        end
        local next = cur and L.neighbor(areas, cur, direction)
        if not next then return end
        s.corner = L.entry_corner(s.corner, direction)
        save_settings(s)
        move_to_monitor(win, monitors[next])
        place(win, s, areas[next])
        return
    end
    s.corner = L.move_corner(s.corner, direction)
    save_settings(s)
    place(win, s)
end

-- Window rules are re-applied on a config reload (matugen reloads on every theme
-- change); put the PiP's props back so it doesn't turn opaque.
hl.on("config.reloaded", function()
    local win = pip_window()
    if win then
        apply_props(win, load_settings().opacity)
        hold_border_resize()
    end
end)

-- The PiP window closed while PiP: border resizing back on, record gone.
hl.on("window.close", function(win)
    if not win then return end
    local r = L.parse_restore(read_file(RESTORE_FILE))
    if r and r.address == win.address then
        release_border_resize()
        os.remove(RESTORE_FILE)
    end
end)
