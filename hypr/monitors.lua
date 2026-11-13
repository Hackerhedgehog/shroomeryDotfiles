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
  position = "-2560x365",
  scale = 1,
  transform = 0,
  mirror = "",
  disabled = false,
})
hl.monitor({
  output = "DP-3",
  mode = "3840x2160@144.05",
  position = "0x0",
  scale = 1.5,
  transform = 0,
  mirror = "",
  disabled = false,
})
hl.exec_cmd("for _ in 1 2 3 4 5 6 7 8 9 10; do xrandr --output 'DP-3' --primary 2>/dev/null && break; sleep 1; done")
-- END control_controls
