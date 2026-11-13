-- Unity Editor (XWayland) window placement.
--
-- XWayland lays the monitors out on its own (here DP-2 sits right of DP-3,
-- while Hyprland has it on the left), so Unity places windows such as the
-- asset picker "next to the Inspector" at a spot no monitor covers, and may
-- move them there again ~0.5 s after they opened (that move sends no event).
--
-- 1. A floating Unity window (picker, color picker, Package Manager, ...)
--    opens centered on the cursor, kept on screen, and is held there for its
--    first 2 s: when Unity moves it, it goes straight back. After that it can
--    be moved freely. Tooltips and menus (unitylogic.SELF_PLACED, unnamed
--    popups) keep Unity's spot and are only brought back when off screen.
--    The tiled main editor window is left alone.
-- 2. The asset picker closes as soon as it loses keyboard focus, and with
--    input:follow_mouse = 1 the first mouse move over the editor takes it
--    away. While one is open, follow_mouse is 2 (hover doesn't move keyboard
--    focus, a click does), so clicking outside still closes it.
local L = require("unitylogic")
local pip = require("piplogic")

hl.window_rule({
    name = "unity-object-picker",
    match = { class = "^Unity", initial_title = "^UnityEditor\\.ObjectSelector$" },
    float = true,
})

-- Without this every move back is animated: the window visibly flies in.
hl.window_rule({
    name = "unity-popups-no-anim",
    match = { class = "^Unity", float = true },
    no_anim = true,
})

-- address -> { fixes, at_cursor, cx, cy, mon }: windows opened in the last 2 s
-- (cx, cy, mon: cursor and its monitor area when the window opened)
local tracked = {}
local open_pickers = {}
local saved_follow_mouse = nil

local function sel(win) return "address:" .. win.address end

local function logical_area(m)
    return pip.screen_area({
        x = m.x, y = m.y, width = m.width, height = m.height,
        scale = m.scale, transform = m.transform,
    })
end

local function monitor_areas()
    local areas = {}
    for _, m in ipairs(hl.get_monitors()) do
        areas[#areas + 1] = logical_area(m)
    end
    return areas
end

local function move(win, t, x, y)
    t.fixes = t.fixes + 1
    hl.dispatch(hl.dsp.window.move({ window = sel(win), x = x, y = y }))
end

-- Put the window where it belongs, if Unity moved it elsewhere.
local function check(win)
    local t = win and tracked[win.address]
    if not (t and win.floating and win.at and win.size) or t.fixes >= L.MAX_FIXES then return end
    local w, h = win.size.x, win.size.y
    if t.at_cursor then
        -- Centered on where the cursor was at open, for the current size.
        local x, y = L.under_cursor(t.mon, t.cx, t.cy, w, h)
        if L.moved_away(win.at.x, win.at.y, x, y) then move(win, t, x, y) end
        return
    end
    if L.on_screen({ x = win.at.x, y = win.at.y, w = w, h = h }, monitor_areas()) then return end
    local c = hl.get_cursor_pos()
    local m = hl.get_monitor_at_cursor()
    if not (c and m) then return end
    local x, y = L.under_cursor(logical_area(m), c.x, c.y, w, h)
    move(win, t, x, y)
end

-- Unity's own late move sends no event, so check a new window for a while.
local function watch(address)
    local ticks = 0
    local timer
    timer = hl.timer(function()
        ticks = ticks + 1
        local win = tracked[address] and hl.get_window("address:" .. address)
        if win then check(win) end
        if not win or ticks >= L.WATCH_TICKS then
            timer:set_enabled(false)
            tracked[address] = nil
        end
    end, { timeout = L.WATCH_INTERVAL_MS, type = "repeat" })
end

hl.on("window.open", function(win)
    if not (win and win.floating and L.is_unity(win.class)) then return end
    local t = { fixes = 0, at_cursor = L.opens_at_cursor(win.class, win.initial_title) }
    if t.at_cursor then
        local c = hl.get_cursor_pos()
        local m = hl.get_monitor_at_cursor()
        if c and m then
            t.cx, t.cy, t.mon = c.x, c.y, logical_area(m)
        else
            t.at_cursor = false
        end
    end
    tracked[win.address] = t
    check(win)
    watch(win.address)

    if not L.is_picker(win.class, win.initial_title) then return end
    if next(open_pickers) == nil then
        saved_follow_mouse = hl.get_config("input.follow_mouse")
        if saved_follow_mouse == 1 then
            hl.config({ input = { follow_mouse = 2 } })
        end
    end
    open_pickers[win.address] = true
end)

-- Fires on geometry changes too, e.g. when Unity moves its window again.
hl.on("window.update_rules", function(win)
    if win and tracked[win.address] then check(win) end
end)

hl.on("window.close", function(win)
    if not win then return end
    tracked[win.address] = nil
    if not open_pickers[win.address] then return end
    open_pickers[win.address] = nil
    if next(open_pickers) ~= nil then return end
    if saved_follow_mouse == 1 then
        hl.config({ input = { follow_mouse = 1 } })
    end
    saved_follow_mouse = nil
end)
