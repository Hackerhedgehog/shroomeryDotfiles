-- Tests for piplogic.lua. Run: lua ~/.config/hypr/tests/piplogic.lua
local dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/tests/") or "."
package.path = dir .. "/?.lua;" .. package.path
local L = require("piplogic")

local failed, passed = 0, 0
local function eq(name, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
    end
end

-- settings
local s = L.parse_settings(nil)
eq("defaults opacity", s.opacity, 0.9)
eq("defaults width", s.width, 0.25)
eq("defaults corner", s.corner, "br")
s = L.parse_settings("opacity=0.5\nwidth=0.3\ncorner=tl\n")
eq("parse opacity", s.opacity, 0.5)
eq("parse width", s.width, 0.3)
eq("parse corner", s.corner, "tl")
s = L.parse_settings("opacity=5\nwidth=abc\ncorner=middle\n")
eq("clamp opacity", s.opacity, 1.0)
eq("bad width -> default", s.width, 0.25)
eq("bad corner -> default", s.corner, "br")
s = L.parse_settings(L.format_settings({ opacity = 0.42, width = 0.33, corner = "bl" }))
eq("roundtrip opacity", s.opacity, 0.42)
eq("roundtrip width", s.width, 0.33)
eq("roundtrip corner", s.corner, "bl")

-- opacity steps
eq("opacity up", L.step_opacity(0.9, 1), 0.92)
eq("opacity down", L.step_opacity(0.9, -1), 0.88)
eq("opacity max", L.step_opacity(0.99, 1), 1.0)
eq("opacity min", L.step_opacity(0.11, -1), 0.1)
local o = 0.9
for _ = 1, 5 do o = L.step_opacity(o, -1) end
eq("opacity 5 steps clean", o, 0.8)

-- width steps
eq("width max", L.step_width(0.69, 1), 0.70)
eq("width min", L.step_width(0.11, -1), 0.10)

-- corners
eq("up from br", L.move_corner("br", "up"), "tr")
eq("left from br", L.move_corner("br", "left"), "bl")
eq("down from tl", L.move_corner("tl", "down"), "bl")
eq("right from tl", L.move_corner("tl", "right"), "tr")
eq("up from tr stays", L.move_corner("tr", "up"), "tr")

-- crossing to another monitor
eq("at edge right", L.at_edge("br", "right"), true)
eq("not at edge left", L.at_edge("br", "left"), false)
eq("at edge up", L.at_edge("tl", "up"), true)
eq("entry going right", L.entry_corner("br", "right"), "bl")
eq("entry going left", L.entry_corner("tl", "left"), "tr")
eq("entry going up", L.entry_corner("tr", "up"), "br")
eq("entry going down", L.entry_corner("bl", "down"), "tl")
-- 4K@1.5 at 0,0 (2560x1440) with a 2560x1080 monitor on its left at -2560,365
local mons = { { x = 0, y = 0, w = 2560, h = 1440 }, { x = -2560, y = 365, w = 2560, h = 1080 } }
eq("neighbor left", L.neighbor(mons, 1, "left"), 2)
eq("no neighbor right", L.neighbor(mons, 1, "right"), nil)
eq("neighbor back right", L.neighbor(mons, 2, "right"), 1)
eq("no neighbor up", L.neighbor(mons, 1, "up"), nil)
eq("no neighbor of single", L.neighbor({ mons[1] }, 1, "left"), nil)
-- three in a row: the nearest one wins
local row = { { x = 0, y = 0, w = 1920, h = 1080 }, { x = 1920, y = 0, w = 1920, h = 1080 }, { x = 3840, y = 0, w = 1920, h = 1080 } }
eq("nearest right", L.neighbor(row, 1, "right"), 2)
eq("nearest left", L.neighbor(row, 3, "left"), 2)
-- stacked: one above
local stack = { { x = 0, y = 1080, w = 1920, h = 1080 }, { x = 0, y = 0, w = 1920, h = 1080 } }
eq("neighbor up", L.neighbor(stack, 1, "up"), 2)
eq("neighbor down", L.neighbor(stack, 2, "down"), 1)
eq("stacked no right", L.neighbor(stack, 1, "right"), nil)
-- fractional rounding slack: right monitor starts 1 px inside
eq("slack", L.neighbor({ { x = 0, y = 0, w = 1706.67, h = 960 }, { x = 1706, y = 0, w = 1920, h = 1080 } }, 1, "right"), 2)

-- area: 4K at scale 1.5 (the bar's reserved space is not subtracted)
local mon = { x = 0, y = 0, width = 3840, height = 2160, scale = 1.5, transform = 0 }
local a = L.screen_area(mon)
eq("area x", a.x, 0)
eq("area y", a.y, 0)
eq("area w", a.w, 2560)
eq("area h", a.h, 1440)
local rot = L.screen_area({ x = 2560, y = 0, width = 1920, height = 1080, scale = 1, transform = 1 })
eq("rotated w", rot.w, 1080)
eq("rotated h", rot.h, 1920)
eq("second monitor x", rot.x, 2560)

-- size
local w, h = L.size(a, 0.25, 16 / 9)
eq("size w", w, 640)
eq("size h", h, 360)
w, h = L.size(a, 0.7, 0.5) -- tall window: limited by height
eq("tall fits h", h, 1440 - 2 * L.MARGIN)
eq("tall keeps aspect", w, math.floor((1440 - 2 * L.MARGIN) * 0.5 + 0.5))

-- position
local x, y = L.position(a, "br", 640, 360)
eq("br x", x, 2560 - 16 - 640)
eq("br y", y, 1440 - 16 - 360)
x, y = L.position(a, "tl", 640, 360)
eq("tl x", x, 16)
eq("tl y", y, 16)

-- restore record
local r = L.parse_restore(L.format_restore({ address = "0xabc", floating = true, pinned = false,
    x = -5, y = 10, w = 800, h = 600, aspect = 16 / 9 }))
eq("restore aspect", math.abs(r.aspect - 16 / 9) < 0.001, true)
eq("restore no workspace", r.workspace, nil)
local r2 = L.parse_restore(L.format_restore({ address = "0xabc", floating = false, pinned = false,
    x = 0, y = 0, w = 10, h = 10, aspect = 1, workspace = "name:my games" }))
eq("restore workspace with space", r2.workspace, "name:my games")

-- workspace selectors
eq("numbered workspace", L.workspace_selector(3, "3", false), "3")
eq("special workspace", L.workspace_selector(-98, "special:scratchpad", true), "special:scratchpad")
eq("named workspace", L.workspace_selector(-1337, "games", false), "name:games")
eq("restore address", r.address, "0xabc")
eq("restore floating", r.floating, true)
eq("restore pinned", r.pinned, false)
eq("restore x", r.x, -5)
eq("restore h", r.h, 600)
eq("restore garbage", L.parse_restore("nope"), nil)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
