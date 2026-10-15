#!/usr/bin/env bash
# Animated wallpapers (videos, GIFs) played by mpvpaper above awww's still image.
# On battery and in gamemode they pause: awww gets a still of the frame on screen,
# mpvpaper is stopped, and resume starts it again where it was.
#
# Usage: animated-wallpaper.sh start FILE [OUTPUT]  play FILE on OUTPUT (default ALL = every monitor)
#        animated-wallpaper.sh stop [OUTPUT]        stop it on OUTPUT (default: everywhere)
#        animated-wallpaper.sh sync                 pause or resume, whichever the power/gamemode state calls for
#        animated-wallpaper.sh pause | resume
#        animated-wallpaper.sh status
# What should play is kept in ANIMATED_STATE_FILE (lib.sh), so it survives a reboot.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

# profile=fast: mpv's default scalers cost ~30 W more GPU power on a 4K screen for no visible gain.
MPV_OPTIONS="no-audio loop hwdec=auto profile=fast panscan=1.0"

should_pause() { on_battery || gamemode_on; }

pid_file()   { echo "$ANIMATED_RUNTIME/$1.pid"; }
sock_file()  { echo "$ANIMATED_RUNTIME/$1.sock"; }
still_file() { echo "$ANIMATED_RUNTIME/paused-$1.png"; }

running() {
    local pid
    pid=$(cat "$(pid_file "$1")" 2>/dev/null) || return 1
    [ -n "$pid" ] && [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = mpvpaper ]
}

# --- state: OUTPUT<TAB>FILE<TAB>SECONDS lines ---

state_lines() {
    [ -f "$ANIMATED_STATE_FILE" ] && cat "$ANIMATED_STATE_FILE"
    return 0
}

state_del() {
    [ -f "$ANIMATED_STATE_FILE" ] || return 0
    local tmp="$ANIMATED_STATE_FILE.$$"
    awk -F'\t' -v out="$1" '$1 != out' "$ANIMATED_STATE_FILE" > "$tmp"
    mv -f "$tmp" "$ANIMATED_STATE_FILE"
    [ -s "$ANIMATED_STATE_FILE" ] || rm -f "$ANIMATED_STATE_FILE"
}

state_set() {
    state_del "$1"
    mkdir -p "$SHROOMERY_CACHE"
    printf '%s\t%s\t%s\n' "$1" "$2" "${3:-0}" >> "$ANIMATED_STATE_FILE"
}

# --- mpv IPC ---

# Send one command (a JSON array) to OUTPUT's mpv; print the reply's data.
mpv_ipc() {
    python3 -I - "$(sock_file "$1")" "$2" <<'PY'
import json, socket, sys
try:
    with socket.socket(socket.AF_UNIX) as s:
        s.settimeout(5)
        s.connect(sys.argv[1])
        s.sendall(json.dumps({"command": json.loads(sys.argv[2])}).encode() + b"\n")
        buf = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                sys.exit(1)
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                reply = json.loads(line)
                if "error" in reply:   # events have no "error"
                    if reply["error"] != "success":
                        sys.exit(1)
                    print(reply.get("data", ""))
                    sys.exit(0)
except (OSError, ValueError):
    sys.exit(1)
PY
}

# --- mpvpaper instances ---

launch() {
    local out="$1" file="$2" start="${3:-0}" opts
    mkdir -p "$ANIMATED_RUNTIME"
    opts="$MPV_OPTIONS input-ipc-server=$(sock_file "$out")"
    [[ "$start" =~ ^[0-9.]+$ ]] && [ "$start" != 0 ] && opts+=" start=$start"
    info "Playing $file on $out"
    # -p: pause while the wallpaper is hidden; -a FULL: also while a window is fullscreen.
    # 9>&-: mpvpaper must not inherit (and hold) this script's lock.
    setsid mpvpaper -p -a FULL -o "$opts" "$out" "$file" </dev/null >/dev/null 2>&1 9>&- &
    echo $! > "$(pid_file "$out")"
    rm -f "$(still_file "$out")"
}

kill_instance() {
    local out="$1" pid count=0
    if running "$out"; then
        pid=$(cat "$(pid_file "$out")")
        kill "$pid" 2>/dev/null
        while kill -0 "$pid" 2>/dev/null && (( count++ < 20 )); do sleep 0.1; done
        kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$(pid_file "$out")" "$(sock_file "$out")"
}

# Show IMAGE with awww on OUTPUT (ALL = every monitor), without a transition.
show_still() {
    local out="$1" image="$2"
    wait_for_awww || return 1
    # shellcheck disable=SC2046
    awww img "$image" $([ "$out" != ALL ] && echo "-o $out") --transition-type none
}

monitors() {
    hyprctl monitors 2>/dev/null | awk '/^Monitor /{ print $2 }'
}

# --- commands ---

stop_output() {
    local out="${1:-ALL}" line o file pos m
    if [ "$out" = ALL ]; then
        for pidf in "$ANIMATED_RUNTIME"/*.pid; do
            [ -f "$pidf" ] && kill_instance "$(basename "$pidf" .pid)"
        done
        rm -f "$ANIMATED_STATE_FILE" "$ANIMATED_RUNTIME"/paused-*.png
        return 0
    fi
    # An ALL mpvpaper covers this monitor too: keep the others playing on their own.
    line=$(state_lines | awk -F'\t' '$1 == "ALL"')
    if [ -n "$line" ]; then
        IFS=$'\t' read -r o file pos <<< "$line"
        running ALL && pos=$(mpv_ipc ALL '["get_property", "time-pos"]' || echo "$pos")
        kill_instance ALL
        state_del ALL
        rm -f "$(still_file ALL)"
        for m in $(monitors); do
            [ "$m" = "$out" ] && continue
            state_set "$m" "$file" "$pos"
            if should_pause; then
                show_still "$m" "$(video_frame "$file")"
            else
                launch "$m" "$file" "$pos"
            fi
        done
    fi
    kill_instance "$out"
    state_del "$out"
    rm -f "$(still_file "$out")"
}

start() {
    local file="$1" out="${2:-ALL}"
    [ -f "$file" ] || { error "No such file: $file"; return 1; }
    stop_output "$out"
    state_set "$out" "$file" 0
    if should_pause; then
        info "Paused (battery or gamemode): showing the first frame of $file"
        cp -f "$(video_frame "$file")" "$(still_file "$out")"
        show_still "$out" "$(still_file "$out")"
        still_file "$out" > "$DISPLAYED_WALLPAPER_FILE"
    else
        launch "$out" "$file" 0
    fi
}

# Swap each playing wallpaper for a still of its current frame. A wallpaper that
# isn't shown yet (not running, no still since boot) gets its first frame.
pause() {
    local out file pos still shown=""
    mkdir -p "$ANIMATED_RUNTIME"
    while IFS=$'\t' read -r out file pos; do
        [ -n "$out" ] || continue
        still=$(still_file "$out")
        if running "$out"; then
            pos=$(mpv_ipc "$out" '["get_property", "time-pos"]' || echo "$pos")
            mpv_ipc "$out" "$(python3 -c 'import json,sys; print(json.dumps(["screenshot-to-file", sys.argv[1], "video"]))' "$still")" >/dev/null \
                || cp -f "$(video_frame "$file")" "$still"
            show_still "$out" "$still"
            # Let awww draw the still before mpvpaper's layer goes away.
            sleep 0.3
            kill_instance "$out"
            state_set "$out" "$file" "$pos"
            info "Paused $out at ${pos}s"
        elif [ ! -f "$still" ]; then
            cp -f "$(video_frame "$file")" "$still" && show_still "$out" "$still"
        fi
        [ -n "$shown" ] || shown="$still"
    done < <(state_lines)
    [ -n "$shown" ] && echo "$shown" > "$DISPLAYED_WALLPAPER_FILE"
    return 0
}

resume() {
    local out file pos shown=""
    while IFS=$'\t' read -r out file pos; do
        [ -n "$out" ] || continue
        if [ ! -f "$file" ]; then
            warn "Animated wallpaper is gone: $file"
            state_del "$out"
            continue
        fi
        running "$out" || launch "$out" "$file" "$pos"
        [ -n "$shown" ] || shown="$file"
    done < <(state_lines)
    [ -n "$shown" ] && echo "$shown" > "$DISPLAYED_WALLPAPER_FILE"
    return 0
}

sync_state() {
    if should_pause; then pause; else resume; fi
}

status() {
    local out file pos
    while IFS=$'\t' read -r out file pos; do
        [ -n "$out" ] || continue
        if running "$out"; then
            echo "$out playing $file"
        else
            echo "$out paused $file (${pos}s)"
        fi
    done < <(state_lines)
}

# One change at a time (wallpaper.sh and the power listener can both call in).
mkdir -p "$ANIMATED_RUNTIME"
exec 9>"$ANIMATED_RUNTIME/lock"
flock -w 30 9 || { error "Another animated-wallpaper.sh is still running"; exit 1; }

case "${1:-}" in
    start)  [ -n "${2:-}" ] || { error "start needs a FILE"; exit 1; }; start "$2" "${3:-ALL}" ;;
    stop)   stop_output "${2:-ALL}" ;;
    pause)  pause ;;
    resume) resume ;;
    sync)   sync_state ;;
    status) status ;;
    *)
        sed -n '2,10s/^# \{0,1\}//p' "$0"
        exit 1
        ;;
esac
