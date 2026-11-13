-- Run: lua ~/.config/hypr/tests/unitylogic.lua
package.path = os.getenv("HOME") .. "/.config/hypr/?.lua;" .. package.path
local L = require("unitylogic")

local failed = 0
local function eq(name, got, want)
    if got ~= want then
        failed = failed + 1
        print(("FAIL %s: got %s, want %s"):format(name, tostring(got), tostring(want)))
    end
end

local CLS = "Unity-6000.6.8f1"
eq("unity", L.is_unity(CLS), true)
eq("not unity", L.is_unity("kitty"), false)
eq("nil class", L.is_unity(nil), false)
eq("picker", L.is_picker(CLS, "UnityEditor.ObjectSelector"), true)
eq("color window is no picker", L.is_picker(CLS, "Color"), false)
eq("picker title, other app", L.is_picker("kitty", "UnityEditor.ObjectSelector"), false)

eq("picker at cursor", L.opens_at_cursor(CLS, "UnityEditor.ObjectSelector"), true)
eq("color at cursor", L.opens_at_cursor(CLS, "Color"), true)
eq("package manager at cursor", L.opens_at_cursor(CLS, "Package Manager"), true)
eq("tooltip not", L.opens_at_cursor(CLS, "UnityTooltipWindow"), false)
eq("add component not", L.opens_at_cursor(CLS, "UnityEditor.AddComponent.AddComponentWindow"), false)
eq("unnamed menu not", L.opens_at_cursor(CLS, CLS), false)
eq("empty title not", L.opens_at_cursor(CLS, ""), false)
eq("other app not", L.opens_at_cursor("kitty", "Color"), false)

-- Layout from the bug: DP-3 0,0 at 2560x1440 logical, DP-2 left of it.
local areas = {
    { x = 0, y = 0, w = 2560, h = 1440 },
    { x = -2560, y = 365, w = 2560, h = 1080 },
}
eq("picker Unity put right of DP-3", L.on_screen({ x = 2560, y = 502, w = 360, h = 578 }, areas), false)
eq("half off the right edge", L.on_screen({ x = 2300, y = 502, w = 360, h = 578 }, areas), false)
eq("on DP-3", L.on_screen({ x = 2121, y = 400, w = 360, h = 578 }, areas), true)
eq("on DP-2", L.on_screen({ x = -2000, y = 400, w = 360, h = 578 }, areas), true)
eq("within tolerance", L.on_screen({ x = 2202, y = 0, w = 360, h = 578 }, areas), true)
eq("across both monitors", L.on_screen({ x = -100, y = 400, w = 360, h = 578 }, areas), false)
eq("above DP-2 (gap)", L.on_screen({ x = -2000, y = 0, w = 360, h = 300 }, areas), false)

local area = areas[1]
local x, y = L.under_cursor(area, 1000, 700, 360, 578)
eq("centered x", x, 820)
eq("centered y", y, 411)

x, y = L.under_cursor(area, 2550, 20, 360, 578)
eq("right clamp x", x, 2560 - 8 - 360)
eq("top clamp y", y, 8)
x, y = L.under_cursor(area, 5, 1430, 360, 578)
eq("left clamp x", x, 8)
eq("bottom clamp y", y, 1440 - 8 - 578)

x, y = L.under_cursor(areas[2], -2500, 400, 360, 578)
eq("side monitor left clamp", x, -2552)
eq("side monitor top clamp", y, 373)

x, y = L.under_cursor({ x = 0, y = 0, w = 800, h = 400 }, 400, 200, 360, 578)
eq("too tall -> top", y, 8)

eq("not moved", L.moved_away(100, 200, 100, 200), false)
eq("rounding jitter", L.moved_away(101, 199, 100, 200), false)
eq("moved by Unity", L.moved_away(2560, 502, 820, 411), true)

if failed > 0 then
    print(failed .. " failed")
    os.exit(1)
end
print("ok")
