-- -----------------------------------------------------
-- Input
-- -----------------------------------------------------
-- Keyboard layout and mouse speed are set in the InputApp (SUPER+I): they
-- live in the shroomery_input block below, written by
-- ~/.config/shroomery/scripts/input.sh.

hl.config({
    input = {
        kb_model     = "",
        kb_options   = "",
        kb_rules     = "",

        numlock_by_default = true,

        follow_mouse   = 1,
        focus_on_close = 13,

        touchpad     = {
            natural_scroll = false,
        },
    },
})

-- BEGIN shroomery_input
-- Written by ~/.config/shroomery/scripts/input.sh from settings/input.json;
-- change it in the InputApp (SUPER+I). The speed is a flat multiplier (no
-- acceleration); listeners/input-speed.sh adjusts it per monitor.
hl.config({
    input = {
        kb_layout     = "ee",
        kb_variant    = "",
        accel_profile = "custom 1 0 0.563",
    },
})
-- END shroomery_input
