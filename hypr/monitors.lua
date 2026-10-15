-- BEGIN control_controls
hl.monitor({
  output = "",
  mode = "highres highrr",
  position = "auto",
  scale = 1,
})
hl.monitor({
  output = "DP-2",
  mode = "2560x1080@143.95",
  position = "-2560x342",
  scale = 1,
  transform = 0,
  mirror = "",
  disabled = false,
})
hl.monitor({
  output = "HDMI-A-1",
  mode = "3840x2160@144.05",
  position = "0x0",
  scale = 1.5,
  transform = 0,
  mirror = "",
  disabled = false,
})
hl.monitor({
  output = "eDP-1",
  disabled = true,
})
hl.exec_cmd("for _ in 1 2 3 4 5 6 7 8 9 10; do xrandr --output 'HDMI-A-1' --primary 2>/dev/null && break; sleep 1; done")
-- END control_controls
