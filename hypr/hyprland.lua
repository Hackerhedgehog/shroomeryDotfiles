--    __  _____  _____      __  ____  ____
--   /  |/  / / / / / | /| / / / __ \/ __/
--  / /|_/ / /_/_  _/ |/ |/ / / /_/ /\ \  
-- /_/  /_/____//_/ |__/|__/  \____/___/
--   
-- Advanced configuration for Hyprland

-- FUNCTIONS
require("functions")

-- MONITORS
require("monitors")

-- INPUT
require("input")

-- GESTURE
require("gestures")

-- AUTOSTART
require("autostart")

-- COLORS
require("colors")

-- CONFIGURATION
require("environments")
require("decorations")
require("layouts")
require("misc")
require("pip")
require("keybindings")
require("windowrules")
require("unity")
require("animations")

-- CUSTOM
local f = io.open(os.getenv("HOME") .. "/.config/hypr/custom.lua", "r")
if f then
    f:close()
    require("custom")
end

-- HYPRMOD
require("hyprland-gui")

-- GAMEMODE
-- scripts/gamemode.sh records the mode in a flag file; re-apply it on every
-- config load, so it survives a reboot and the `hyprctl reload` that matugen
-- runs on every theme change.
local gamemode = io.open(os.getenv("HOME") .. "/.config/shroomery/settings/gamemode-enabled", "r")
if gamemode then
    gamemode:close()
    activate_gamemode()
end
