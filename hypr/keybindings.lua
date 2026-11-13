-- Configuration
local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Applications
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("kitty"), { description = "Open the terminal" })
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("firefox"), { description = "Open the browser" })
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("dolphin"), { description = "Open the filemanager" })
hl.bind(mainMod .. " + PERIOD", hl.dsp.exec_cmd("~/.config/quickshell/LauncherApp/toggle.sh emoji"), { description = "Open the emoji picker" })

-- Quick Shell Controls Panels
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("~/.config/quickshell/MonitorApp/toggle.sh"), { description = "Open the MonitorApp" })
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("~/.config/quickshell/BluetoothPanel/toggle.sh"), { description = "Open the BluetoothPanel" })
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("~/.config/quickshell/NetworkPanel/toggle.sh"), { description = "Open the NetworkPanel" })
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("~/.config/quickshell/KeybindsApp/toggle.sh"), { description = "Open the KeybindsApp" })
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("~/.config/quickshell/AudioPanel/toggle.sh"), { description = "Open the AudioPanel" })
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("~/.config/quickshell/WallpaperApp/toggle.sh"), { description = "Open the WallpaperApp" })
hl.bind(mainMod .. " + U", hl.dsp.exec_cmd("~/.config/shroomery/scripts/install-updates.sh"), { description = "Settings → Update" })
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("~/.config/quickshell/InputApp/toggle.sh"), { description = "Open the InputApp (keyboard layout, mouse speed)" })
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("~/.config/quickshell/TimeApp/toggle.sh"), { description = "Open the TimeApp (date, time, timezone, language)" })

-- fr keyboard layout setup
local is_fr = false
local f = io.open(os.getenv("HOME") .. "/.config/hypr/input.lua", "r")
if f then
    local content = f:read("*all")
    if content:match('kb_layout%s*=%s*"et"') and not content:match('kb_variant%s*=%s*"us"') then
        is_fr = true
    end
    f:close()
end

local fr_keys = {
    "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
    "minus", "egrave", "underscore", "ccedilla", "agrave"
}

-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    if is_fr then
        key = fr_keys[i]
    end
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}), { description = "Focus workspace " .. i })
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
    -- Bring workspace i to the focused monitor (swaps with the other monitor if it is shown there).
    hl.bind(mainMod .. " + SHIFT + F" .. i,      hl.dsp.focus({ workspace = i, on_current_monitor = true }), { description = "Bring workspace " .. i .. " to the active monitor" })
end

-- Windows killactive
hl.bind(mainMod .. " + C", hl.dsp.window.close(), { description = "Kill active window" })
-- Minimize: park the window on special:minimized. The status bar's taskbar
-- hover list (right click on a window) brings it back.
hl.bind(mainMod .. " + X", hl.dsp.window.move({ workspace = "special:minimized", follow = false }), { description = "Minimize active window" })
--hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("~/.config/hypr/scripts/killactive.sh"), { description = "Kill active window" })
-- hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { description = "Kill active window" })
-- Force kill (SIGKILL) the active window's process, for apps that froze and ignore Super+C.
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.window.kill(), { description = "Force kill the active window's process" })
hl.bind(mainMod .. " + F11", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "Toggle Fullscreen" })
hl.bind(mainMod .. " + F10", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), { description = "Toggle Maximize Window" })
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle Floating" })
hl.bind(mainMod .. " + mouse:274", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle Floating" })

hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("~/.config/hypr/scripts/toggleallfloat.sh"), { description = "Toggle floating for all windows of workspace" })
--hl.bind(mainMod .. " + ALT + T", function() hl.dispatch(hl.dsp.window.float({ action = "toggle" })); hl.dispatch(hl.dsp.window.pin()) end, { description = "Toggle floating + pinned" })
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "Toggle split" })
-- In visualizer mode: left/right change the style, up/down bars vs wave.
hl.bind(mainMod .. " + left", function()
    if visualizer_active() then visualizer("prevStyle") else hl.dispatch(hl.dsp.focus({ direction = "left" })) end
end, { description = "Move focus left (visualizer: previous style)" })
hl.bind(mainMod .. " + right", function()
    if visualizer_active() then visualizer("nextStyle") else hl.dispatch(hl.dsp.focus({ direction = "right" })) end
end, { description = "Move focus right (visualizer: next style)" })
hl.bind(mainMod .. " + up", function()
    if visualizer_active() then visualizer("prevMode") else hl.dispatch(hl.dsp.focus({ direction = "up" })) end
end, { description = "Move focus up (visualizer: previous draw mode)" })
hl.bind(mainMod .. " + down", function()
    if visualizer_active() then visualizer("nextMode") else hl.dispatch(hl.dsp.focus({ direction = "down" })) end
end, { description = "Move focus down (visualizer: next draw mode)" })
hl.bind(mainMod .. " + Escape", function()
    if visualizer_active() then visualizer("disable") end
end, { description = "Leave visualizer mode" })
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Move window with the mouse" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window with the mouse" })
--hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true }, { description = "Increase window width with keyboard" })
--hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true }, { description = "Reduce window width with keyboard" })
--hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true }, { description = "Increase window height with keyboard" })
--hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true }, { description = "Reduce window height with keyboard" })
--hl.bind(mainMod .. " + G", hl.dsp.group.toggle(), { description = "Toggle window group" })
-- hl.bind(mainMod .. " + SHIFT + G", hl.dsp.group.active("f"), { description = "Switch to next group window" })
--hl.bind(mainMod .. " + K", hl.dsp.layout("swapsplit"), { description = "Swapsplit" })
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.swap({ direction = "l" }), { description = "Swap tiled window left" })
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.swap({ direction = "r" }), { description = "Swap tiled window right" })
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.swap({ direction = "u" }), { description = "Swap tiled window up" })
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.swap({ direction = "d" }), { description = "Swap tiled window down" })
hl.bind(mainMod .. " + CONTROL + SHIFT + right", hl.dsp.window.move({ direction = "r" }), { description = "Move tiled window righttq" })

-- Actions
hl.bind(mainMod .. " + CTRL + R", hl.dsp.exec_cmd("hyprctl reload"), { description = "Reload Hyprland configuration" })
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-animations.sh"), { description = "Toggle animations" })
hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh"), { description = "Take a screenshot" })
--hl.bind(mainMod .. " + ALT + F", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh --instant"), { description = "Take an instant full-screen screenshot" })
--hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh --instant-area"), { description = "Take an instant area screenshot" })
hl.bind(mainMod .. " + ALT + A", hl.dsp.exec_cmd("~/.config/quickshell/OcrApp/toggle.sh capture"), { description = "Extract text from an area" })
hl.bind(mainMod .. " + CTRL + P", hl.dsp.exec_cmd("~/.config/quickshell/PowerPanel/toggle.sh"), { description = "Start Power Menu" })
--hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.config/shroomery/scripts/wallpaper.sh --random"), { description = "Change the wallpaper" })
--hl.bind(mainMod .. " + CTRL + W", hl.dsp.exec_cmd("~/.config/quickshell/WallpaperApp/toggle.sh"), { description = "Open wallpaper selector" })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("~/.config/hypr/scripts/launcher.sh"), { description = "Open application launcher" })
hl.bind(mainMod .. " + CTRL + K", hl.dsp.exec_cmd("~/.config/quickshell/KeybindsApp/toggle.sh"), { description = "Show keybindings" })
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("qs ipc call statusbar reload"), { description = "Reload Status Bar" })
hl.bind(mainMod .. " + CTRL + B", hl.dsp.exec_cmd("~/.config/quickshell/StatusbarApp/toggle.sh"), { description = "Toggle Status Bar" })
hl.bind(mainMod .. " + ALT + D", hl.dsp.exec_cmd("qs ipc call dock reload"), { description = "Reload Dock" })
hl.bind(mainMod .. " + CTRL + D", hl.dsp.exec_cmd("~/.config/quickshell/DockApp/toggle.sh"), { description = "Toggle Dock" })
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/loadconfig.sh"), { description = "Reload hyprland config" })
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("~/.config/shroomery/scripts/toggle-theme.sh"), { description = "Toggle between light and dark mode" })
hl.bind(mainMod .. " + CTRL + S", hl.dsp.exec_cmd("~/.config/quickshell/QuickSettingsPanel/toggle.sh"), { description = "Open the quick settings" })
hl.bind(mainMod .. " + CTRL + C", hl.dsp.exec_cmd("~/.config/quickshell/DashboardPanel/toggle.sh"), { description = "Open the dashboard" })
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("qs ipc call statusbar focus"), { description = "Expand statusbar and focus it for keyboard navigation" })
hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd("~/.config/quickshell/SettingsApp/toggle.sh"), { description = "Open the SettingsApp" })
hl.bind(mainMod .. " + ALT + G", hl.dsp.exec_cmd("~/.config/hypr/scripts/gamemode.sh"), { description = "Toggle game mode" })
hl.bind(mainMod .. " + ALT + V", hl.dsp.exec_cmd("~/.config/quickshell/VisualizerApp/toggle.sh"), { description = "Visualizer: open setup / stop" })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("~/.config/shroomery/scripts/power.sh -l"), { description = "Lock Screen" })
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("~/.config/shroomery/scripts/hyprsunset.sh"), { description = "Toggle night light" })
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd("~/.config/quickshell/OverviewApp/toggle.sh"), { description = "Open Select Window Menu" })

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("scratchpad"), { description = "Toggle special workspace scratchpad" })
hl.bind(mainMod .. " + SHIFT + S", function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    hl.dispatch(hl.dsp.window.move({ workspace = "special:scratchpad" }))
end)

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Switch to next workspace" })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Switch to previous workspace" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Move window with the mouse" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window with the mouse" })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "Raise volume" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true, description = "Lower volume" })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true, description = "Mute audio" })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true, description = "Mute microphone" })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true, description = "Increase brightness" })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true, description = "Decrease brightness" })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Pause audio" })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play audio" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Previous track" })
