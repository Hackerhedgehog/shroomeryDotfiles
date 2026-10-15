-- -----------------------------------------------------
-- General window decoration
-- name: "Default"
-- -----------------------------------------------------
require("colors")

hl.config({
	general = {
		border_size = 2,
		resize_on_border = true,
		gaps_in = 3,
		gaps_out = 20,
		locale = "et_EE",

		snap = {
			enabled = true,
			border_overlap = false,
		},
		col = {
			active_border = {
				colors = { primary, secondary, tertiary },
				angle = 90,
			},
		},
	},

	decoration = {
		dim_special = 0.4,
		rounding = 10,
		active_opacity = 1.0,
		inactive_opacity = 0.97,
		fullscreen_opacity = 1.0,
		rounding_power = 2,
		shadow = {
			enabled = true,
			range = 32,
			render_power = 2,
			color = "rgba(00000050)",
		},

		blur = {
			enabled = true,
			size = 4,
			passes = 4,
			new_optimizations = on,
			ignore_opacity = true,
			xray = true,
			vibrancy = 0.1696,
		},
	},
})
