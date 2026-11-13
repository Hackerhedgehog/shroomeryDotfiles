-- Pure helpers for unity.lua (no hl calls, so tests/unitylogic.lua can run them
-- in plain Lua).
local M = {}

M.MARGIN = 8     -- kept free at the screen edges
M.TOLERANCE = 4  -- px a window may stick out of a monitor and still count as on it
M.MAX_FIXES = 10 -- moves per opened window, so we never fight Unity forever
-- Unity moves some windows again ~0.5 s after they open, without an event:
-- check a new floating Unity window every 30 ms for its first 2 s.
M.WATCH_INTERVAL_MS = 30
M.WATCH_TICKS = 67

-- The asset picker ("Select Material", "Select Texture 2D", ...) opened by the
-- small circle next to an Inspector field. Its first title is the editor class.
-- Unity closes it as soon as it loses keyboard focus.
M.PICKER_TITLE = "UnityEditor.ObjectSelector"

-- Floating Unity windows Unity itself places next to something (tooltips,
-- dropdowns): these are not opened under the cursor, only rescued when off
-- screen. Unnamed popup menus have the class as their first title.
M.SELF_PLACED = {
    ["UnityTooltipWindow"] = true,
    ["UnityEditor.AddComponent.AddComponentWindow"] = true,
}

function M.is_unity(class)
    return type(class) == "string" and class:find("^Unity") ~= nil
end

function M.is_picker(class, initial_title)
    return M.is_unity(class) and initial_title == M.PICKER_TITLE
end

-- A floating Unity window that opens under the cursor (picker, color picker,
-- Package Manager, ...), as opposed to a tooltip or menu.
function M.opens_at_cursor(class, initial_title)
    if not M.is_unity(class) or type(initial_title) ~= "string" then return false end
    if initial_title == "" or initial_title == class then return false end
    return not M.SELF_PLACED[initial_title]
end

local function clamp(v, lo, hi)
    if hi < lo then return lo end
    return math.max(lo, math.min(hi, v))
end

-- True when the box { x, y, w, h } lies inside one of `areas` (logical px).
function M.on_screen(box, areas)
    local t = M.TOLERANCE
    for _, a in ipairs(areas) do
        if box.x >= a.x - t and box.y >= a.y - t
            and box.x + box.w <= a.x + a.w + t
            and box.y + box.h <= a.y + a.h + t then
            return true
        end
    end
    return false
end

-- Top-left of a w×h window centered on the cursor (cx, cy) and kept inside
-- `area` ({ x, y, w, h }, logical px).
function M.under_cursor(area, cx, cy, w, h)
    local x = clamp(cx - w / 2, area.x + M.MARGIN, area.x + area.w - M.MARGIN - w)
    local y = clamp(cy - h / 2, area.y + M.MARGIN, area.y + area.h - M.MARGIN - h)
    return math.floor(x + 0.5), math.floor(y + 0.5)
end

-- True when the window at (x, y) is not where we put it (tx, ty).
function M.moved_away(x, y, tx, ty)
    return math.abs(x - tx) > 1 or math.abs(y - ty) > 1
end

return M
