"""Hyprland queries (hyprctl JSON) and the current wallpaper path."""
import json
import os
import subprocess


def hypr_json(what, run=subprocess.run):
    """`hyprctl -j <what>` parsed, or [] when it fails."""
    try:
        out = run(["hyprctl", "-j", what], capture_output=True, timeout=2.0, check=True).stdout
        return json.loads(out)
    except (OSError, subprocess.SubprocessError, ValueError):
        return []


def focused_monitor(monitors):
    for m in monitors:
        if m.get("focused"):
            return m["name"]
    return monitors[0]["name"] if monitors else ""


def read_wallpaper(cache_file):
    """The path in ~/.cache/shroomery/current_wallpaper, if that image exists."""
    try:
        with open(cache_file) as f:
            path = f.readline().strip()
    except OSError:
        return ""
    return path if path and os.path.isfile(path) else ""


def shown_wallpaper(displayed_file, current_file):
    """The image actually on screen: wallpaper.sh's effect copy (recorded in
    displayed_wallpaper) when it exists, else the original wallpaper."""
    return read_wallpaper(displayed_file) or read_wallpaper(current_file)


def opacities(run=subprocess.run):
    """How Hyprland draws windows: decoration:active/inactive/fullscreen_opacity
    (1.0 for any it can't read)."""
    out = {}
    for key in ("active", "inactive", "fullscreen"):
        try:
            raw = run(["hyprctl", "-j", "getoption", f"decoration:{key}_opacity"],
                      capture_output=True, timeout=2.0).stdout
            out[key] = float(json.loads(raw).get("float", 1.0))
        except (OSError, subprocess.SubprocessError, ValueError, TypeError, AttributeError):
            out[key] = 1.0
    return out

