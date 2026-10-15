#!/usr/bin/env bash
#                                      __
#   ___ ____ ___ _  ___ __ _  ___  ___/ /__
#  / _ `/ _ `/  ' \/ -_)  ' \/ _ \/ _  / -_)
#  \_, /\_,_/_/_/_/\__/_/_/_/\___/\_,_/\__/
# /___/
#


# Notifications
source "$HOME/.config/shroomery/notify.sh"
APP_NAME="System"
NOTIFICATION_ICON="joystick"

if [ -f $HOME/.config/shroomery/settings/gamemode-enabled ]; then
  # Remove the flag first: hyprland.lua re-applies gamemode on load while it exists.
  rm $HOME/.config/shroomery/settings/gamemode-enabled
  hyprctl reload
  notify_user --a "${APP_NAME}" \
            --i "${NOTIFICATION_ICON}" \
            --s "Gamemode deactivated" \
            --m "Animations and blur are now enabled."
else
  hyprctl eval "activate_gamemode()"
  touch $HOME/.config/shroomery/settings/gamemode-enabled
  notify_user --a "${APP_NAME}" \
          --i "${NOTIFICATION_ICON}" \
          --s "Gamemode activated" \
          --m "Animations and blur are now disabled."
fi

# An animated wallpaper pauses in gamemode (unless on battery, where it stays paused).
$HOME/.config/shroomery/scripts/animated-wallpaper.sh sync >/dev/null 2>&1 &
