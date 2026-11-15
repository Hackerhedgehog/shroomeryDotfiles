-- Picture-in-picture geometry and settings, without Hyprland calls (pip.lua
-- does those). Tested by tests/piplogic.lua: `lua ~/.config/hypr/tests/piplogic.lua`.
local M = {}

M.defaults = { opacity = 0.9, width = 0.25, corner = "br" }
M.OPACITY_STEP, M.OPACITY_MIN, M.OPACITY_MAX = 0.02, 0.10, 1.00
M.WIDTH_STEP, M.WIDTH_MIN, M.WIDTH_MAX = 0.04, 0.10, 0.70 -- fractions of the monitor width
M.MARGIN = 16 -- px between the window and the screen edge
M.ASPECT_MIN, M.ASPECT_MAX = 0.5, 3.0

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Round to 2 decimals so repeated 0.02 steps land on clean values.
local function round2(v)
    return math.floor(v * 100 + 0.5) / 100
end

function M.valid_corner(c)
    return c == "tl" or c == "tr" or c == "bl" or c == "br"
end

-- Settings file: "key=value" lines. Unknown keys and bad values fall back to the defaults.
function M.parse_settings(text)
    local s = { opacity = M.defaults.opacity, width = M.defaults.width, corner = M.defaults.corner }
    for key, value in (text or ""):gmatch("([%w_]+)%s*=%s*([^\n]*)") do
        value = value:gsub("%s+$", "")
        local n = tonumber(value)
        if key == "opacity" and n then
            s.opacity = clamp(n, M.OPACITY_MIN, M.OPACITY_MAX)
        elseif key == "width" and n then
            s.width = clamp(n, M.WIDTH_MIN, M.WIDTH_MAX)
        elseif key == "corner" and M.valid_corner(value) then
            s.corner = value
        end
    end
    return s
end

function M.format_settings(s)
    return string.format("opacity=%.2f\nwidth=%.3f\ncorner=%s\n", s.opacity, s.width, s.corner)
end

function M.step_opacity(opacity, dir)
    return clamp(round2(opacity + dir * M.OPACITY_STEP), M.OPACITY_MIN, M.OPACITY_MAX)
end

function M.step_width(width, dir)
    return clamp(width + dir * M.WIDTH_STEP, M.WIDTH_MIN, M.WIDTH_MAX)
end

-- Move toward an edge: up/down set the vertical side, left/right the horizontal one.
function M.move_corner(corner, direction)
    local v, h = corner:sub(1, 1), corner:sub(2, 2)
    if direction == "up" then v = "t"
    elseif direction == "down" then v = "b"
    elseif direction == "left" then h = "l"
    elseif direction == "right" then h = "r" end
    return v .. h
end

-- True when the corner already sits on the `direction` side (pressing it again
-- leaves the corner as it is, so the PiP should go to the next monitor).
function M.at_edge(corner, direction)
    local v, h = corner:sub(1, 1), corner:sub(2, 2)
    return (direction == "up" and v == "t") or (direction == "down" and v == "b")
        or (direction == "left" and h == "l") or (direction == "right" and h == "r")
end

-- Corner on the monitor the PiP enters when it crosses in `direction`: the side
-- it comes in from (going right it lands in a left corner), the other half kept.
function M.entry_corner(corner, direction)
    local v, h = corner:sub(1, 1), corner:sub(2, 2)
    if direction == "up" then v = "b"
    elseif direction == "down" then v = "t"
    elseif direction == "left" then h = "r"
    elseif direction == "right" then h = "l" end
    return v .. h
end

-- Index of the monitor next to areas[cur] in `direction`, or nil. A monitor
-- counts when it lies wholly past that edge (2 px slack for rounding); the one
-- with the smallest gap wins, ties go to the one best lined up on the other axis.
-- areas = { { x, y, w, h }, ... } (screen_area of each monitor)
function M.neighbor(areas, cur, direction)
    local c = areas[cur]
    if not c then return nil end
    local SLACK = 2
    local best, best_gap, best_off
    for i, a in ipairs(areas) do
        if i ~= cur then
            local gap, off
            if direction == "right" then
                gap = a.x - (c.x + c.w)
            elseif direction == "left" then
                gap = c.x - (a.x + a.w)
            elseif direction == "down" then
                gap = a.y - (c.y + c.h)
            elseif direction == "up" then
                gap = c.y - (a.y + a.h)
            end
            if direction == "left" or direction == "right" then
                off = math.abs((a.y + a.h / 2) - (c.y + c.h / 2))
            else
                off = math.abs((a.x + a.w / 2) - (c.x + c.w / 2))
            end
            if gap and gap >= -SLACK then
                gap = math.max(gap, 0)
                if not best or gap < best_gap or (gap == best_gap and off < best_off) then
                    best, best_gap, best_off = i, gap, off
                end
            end
        end
    end
    return best
end

-- The whole monitor in global logical coordinates (scaled, rotated). The space
-- the bar reserves is ignored on purpose: the PiP sits in the real screen corner
-- (over a fullscreen game the bar isn't there anyway).
-- mon = { x, y, width, height (physical px), scale, transform }
function M.screen_area(mon)
    local w, h = mon.width / mon.scale, mon.height / mon.scale
    if (mon.transform or 0) % 2 == 1 then w, h = h, w end
    return { x = mon.x, y = mon.y, w = w, h = h }
end

-- Size of the PiP: `width` (fraction of the monitor width) at `aspect` (w/h),
-- shrunk so it fits the screen.
function M.size(area, width, aspect)
    aspect = clamp(aspect, M.ASPECT_MIN, M.ASPECT_MAX)
    local w = area.w * width
    local h = w / aspect
    local max_w, max_h = area.w - 2 * M.MARGIN, area.h - 2 * M.MARGIN
    if w > max_w then w = max_w; h = w / aspect end
    if h > max_h then h = max_h; w = h * aspect end
    return math.floor(w + 0.5), math.floor(h + 0.5)
end

-- Top-left position of a w×h window in `corner` of the area.
function M.position(area, corner, w, h)
    local x, y
    if corner:sub(2, 2) == "l" then x = area.x + M.MARGIN else x = area.x + area.w - M.MARGIN - w end
    if corner:sub(1, 1) == "t" then y = area.y + M.MARGIN else y = area.y + area.h - M.MARGIN - h end
    return math.floor(x + 0.5), math.floor(y + 0.5)
end

-- Workspace selector for a move dispatcher: the id for a numbered workspace,
-- "special:x" for a special one (its name already has the prefix), "name:x" otherwise.
function M.workspace_selector(id, name, special)
    if special then return name end
    if id and id > 0 then return tostring(id) end
    return "name:" .. name
end

-- Record kept while a window is PiP:
-- "address floating(0/1) pinned(0/1) x y w h aspect workspace"
-- x y w h and workspace (a selector, last since names may hold spaces) = the
-- window before PiP, to put it back; aspect = the PiP's width/height, fixed when
-- it starts. Resizes use it instead of the window's current size, which drifts:
-- rounding, and apps that won't go below a minimum width (browsers).
function M.format_restore(r)
    return string.format("%s %d %d %d %d %d %d %.4f %s\n", r.address, r.floating and 1 or 0, r.pinned and 1 or 0,
        r.x, r.y, r.w, r.h, r.aspect, r.workspace or "")
end

function M.parse_restore(text)
    local a, f, p, x, y, w, h, asp, ws =
        (text or ""):match("^(%S+) (%d) (%d) (%-?%d+) (%-?%d+) (%d+) (%d+) ([%d.]+) ?([^\n]*)")
    if not a then return nil end
    return { address = a, floating = f == "1", pinned = p == "1",
        x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h), aspect = tonumber(asp),
        workspace = ws ~= "" and ws or nil }
end

return M
