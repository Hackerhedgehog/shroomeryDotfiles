hl.on("hyprland.start", function()
	local HOME = os.getenv("HOME")

	-- Export variables to systemd
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

	-- Restart portals so they catch the environment
	hl.exec_cmd("systemctl --user stop xdg-desktop-portal xdg-desktop-portal-hyprland")
	hl.exec_cmd("systemctl --user start xdg-desktop-portal-hyprland xdg-desktop-portal")

	-- awww daemon
	hl.exec_cmd("awww-daemon")

	-- Load cursor
	hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")

	-- Start listeners
	hl.exec_cmd("~/.config/shroomery/listeners.sh --startall")

	-- Start waybar
	--hl.exec_cmd(HOME .. "/.config/waybar/launch.sh")

	-- Start polkit daemon
	hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

	-- Quickshell + wallpaper/theme restore
	hl.exec_cmd("mkdir -p ~/.cache/shroomery && ~/.config/shroomery/scripts/autostart.sh > ~/.cache/shroomery/autostart.log 2>&1")

	-- Load GTK settings
	hl.exec_cmd("~/.config/hypr/scripts/gtk.sh")

	-- swaync is replaced by Quickshell's NotificationPanel (the notification
	-- daemon now lives in the qs shell). Its systemd user unit is masked
	-- (`systemctl --user mask swaync.service`) so D-Bus can't start it when a
	-- notification arrives before qs is up. To go back to swaync:
	-- `systemctl --user unmask swaync.service` and uncomment the next line.
	--hl.exec_cmd("swaync")

	-- Start hypridle
	hl.exec_cmd("hypridle")

	-- Keep clipboard contents after the source app closes
	hl.exec_cmd("wl-clip-persist --clipboard regular")

	-- Load cliphist history
	hl.exec_cmd("wl-paste --watch cliphist store")

	-- Start autostart cleanup
	hl.exec_cmd("~/.config/hypr/scripts/cleanup.sh")

	hl.exec_cmd("~/.config/shroomery/scripts/power.sh -l")
end)
