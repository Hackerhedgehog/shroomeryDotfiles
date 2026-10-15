# screencolors: screen-reactive colors for the desktop (and, later, LEDs)

This is the documentation for the whole "colors follow what's on screen" project:
the sampler daemon that lives here, the audio visualizer in Quickshell that
uses it, and the LED strip controller planned for later. Read this first
before adding a consumer, a controller, or a new field to the protocol.

> **Status (2026-10-15):** the sampler daemon (protocol v2, sampling regions), visualizer mode and
> shared cava spectrum are built. Design specs in `~/.config/quickshell/docs/superpowers/specs/`:
> `2026-10-13-audio-visualizer-design.md`, `2026-10-14-visualizer-panel-design.md`,
> `2026-10-14-sampling-regions-design.md` (plans next to them in `../plans/`).
> Update the status table below as pieces land.

| Piece | Where | Status |
|---|---|---|
| Sampler daemon (`screen-colors.py` + this package) | `~/.config/shroomery/` | built (2026-10-14) |
| Sampling regions (protocol v2: ring / edges / rects per client) | `~/.config/shroomery/screencolors/` | built (2026-10-15) |
| Audio visualizer mode (setup panel, GPU renderer, 3 styles × bars/wave/line) | `~/.config/quickshell/VisualizerApp/` | built (2026-10-14) |
| Shared cava spectrum | `~/.config/quickshell/shared/CavaSpectrum.qml` | built (2026-10-14) |
| LED bridge (PC side) | — | idea |
| LED controller (microcontroller) | — | idea |
| Audio spectrum in the protocol | — | idea |

---

## 1. The big picture

```
                    ┌─────────────────────────────── PC ───────────────────────────────────┐
                    │  screen-colors.py  (one copy running, started on demand)             │
 hyprctl ─────────► │   per monitor, 5 Hz:  layout ─► wallpaper base ─► paste windows      │
 (monitors,clients) │                       (grim -T <window> -t png -l 0 -, piped,        │
                    │                        never a file; alpha blended by opacity)        │
                    │   per client, 30 Hz:  its regions on that picture ─► zones ─►        │
                    │                       smoothing ─► frame                              │
                    │                                   │                                   │
                    │        $XDG_RUNTIME_DIR/shroomery/screen-colors.sock (JSON lines)     │
                    │          ┌────────────────────────┼──────────────────────┐            │
                    │          ▼                        ▼                      ▼            │
                    │  VisualizerApp overlay    setup panel preview    led-bridge (later)   │
                    │  (ring / edges "viz")     (its own "viz")        (rects / edges)      │
                    └───────────────────────────────────────────────────────┬──────────────┘
                                                                            │ Wi-Fi (UDP / WebSocket)
                                                                            ▼
                                                                  microcontroller + LED strip
```

**The core idea:** one process captures each monitor *once* per tick and builds a
small picture of what is on screen; every client says which areas of it it
wants (a ring around the visualizer's circle, the screen edges, any rectangles)
and gets those areas' colors, smoothed, on its own stream. Consumers only decide
how to *show* the colors (the visualizer brightens them so they stay readable
over video; LEDs apply gamma and a power cap). They never sample the screen themselves.

### Why a daemon and not something inside Quickshell

- **Every consumer gets the colors:** Quickshell could sample on the GPU (`ScreencopyView` + a shader), but the colors would never leave the GPU, so an LED bridge couldn't use them.
- **The overlay is never sampled:** the picture is rebuilt from the wallpaper and each window's own buffer (`grim -T`); layer-shell surfaces (the visualizer overlay, the bar) are never in it.
- **Testable:** regions, compositing and smoothing are plain Python with unit tests.

---

## 2. Components

### 2.1 Sampler daemon: `scripts/screen-colors.py` + `screencolors/`

| Module | Job |
|---|---|
| `hypr.py` | `hyprctl -j` queries, the current wallpaper path, Hyprland's window opacities. |
| `compose.py` | The rebuilt picture (monitor logical size ÷ 8): wallpaper base (center-cropped like awww), visible windows in paint order (tiled, then floating oldest-focus first, special workspace on top; a fullscreen window alone), which windows to capture (those under a subscribed area, at most 6), and pasting them (alpha × Hyprland opacity). |
| `video.py` | An animated wallpaper as the wallpaper base: `ffmpeg` decodes it (CUDA + `scale_cuda` when available, else keyframes on the CPU) straight to picture size at 5 fps, starting at the playing mpvpaper's position (its IPC socket in `$XDG_RUNTIME_DIR/shroomery/mpvpaper/`) and restarted there when it drifts more than 1 s (e.g. mpv paused behind a fullscreen window). About 4% of one core for a 4K video. |
| `capture.py` | `grim -T <stableId>`: uncompressed PNG (keeps translucent windows' alpha; opaque windows switch to the cheaper PPM after their first capture), piped into numpy, long side ≤ 256 px. |
| `regions.py` | Subscription validation (protocol v2 limits), zone label maps for ring / edges / rects, per-zone means in linear light, empty-zone fill, the `--pattern` picture. |
| `zones.py` | Letterbox/pillarbox detection (edges regions are sampled inside the bars). |
| `smoothing.py` | Per-zone OKLab smoothing (see §4), one per client region. |
| `server.py` | Unix socket, per-client send, single instance (a lock), idle exit. |
| `daemon.py` | The loop: per-monitor `Builder`s on worker threads, per-client `ClientState`s. |
| `color.py` | sRGB / linear / OKLab helpers. |
| `tests/` | `cd ~/.config/shroomery && python3 -m unittest discover -s screencolors/tests -t .` |

Usage:

```bash
screen-colors.py                          # serve (clients subscribe; see §3)
                 --rate 5                 # captures per second per monitor (default 5)
                 --idle-exit 5            # seconds after the last client leaves (0 = never)
                 --pattern                # sample a fixed test picture instead of the screen:
                                          # up red, right green, down blue, left yellow ("source": "pattern")
screen-colors.py --watch [--monitor DP-2] # subscribe to the screen edges and print frames
screen-colors.py --watch --subscribe '{"v":2,"type":"subscribe",…}'   # or @file.json
```

Starting a second copy while one is running exits at once with status 0, so
any consumer can just start it and then connect. `--pattern` only takes over
when no other copy is running.

**Cost (measured on this machine, daemon process, 5 Hz):**
- Wallpaper only: about 3% of one core.
- A ring over a tiled 2560×1080 desktop (2 windows): about 13%.
- A ring over a large browser window on the 4K monitor: about 24%.
- Accuracy: a ring's colors are within about 5/255 of a direct screenshot averaged
  in the same area (translucent windows included; Hyprland's blur behind them is
  not modelled).
- The visualizer overlay itself (GPU shader, 60 fps) costs about 13% of one core in `qs`
  with still colors and about 17% while colors change.
- Don't use `grim -s` (scaled capture). It's *slower* (about 430 ms) because it scales on the CPU.

### 2.2 Audio visualizer: `~/.config/quickshell/VisualizerApp/`

- **Turning it on:** Super+Alt+V (or the SettingsApp switch, or `VisualizerApp/toggle.sh`) opens the setup panel; **Start** runs it. Super+Alt+V again stops it. `qs ipc call visualizer enable` starts straight away with the saved settings.
- **Setup panel:** style, bars / wave / line, bar width, spacing, line thickness, minimum length, sensitivity, smoothness, outline, monitor, **Wallpaper only**, and for the circle styles the circle's position and diameter (drag it on the live mini preview, which subscribes to the daemon too and shows the real sampled colors). The "Controller" section is a placeholder for the LED project.
- **What happens:** the bar, dock and normal notification popups hide (critical ones still show), and a transparent, click-through overlay appears on the monitor chosen in the setup panel (the focused one if it isn't connected).
- **Keys while running:** Super+←/→ change the style (center-out / center-in / border), Super+↑/↓ cycle bars / wave / line, Super+Esc exits. Outside the mode, those keys do what they always did.
- **Saved:** every panel setting goes to `~/.config/shroomery/settings/visualizer.json` on Start (keys in the shroomery README). The mode itself is never saved.
- **Audio:** comes from cava (`shared/CavaSpectrum.qml`).
- **Drawing:** one fragment shader (`VisualizerApp/shaders/visualizer.frag`) works out per pixel which bar it belongs to, so bars are equally thin in every style. Between cava bands the shader follows a smooth (Catmull-Rom) curve, after a Smoothness blur across bands in JS; lengths use a soft limit (`1 − e^(−3·v·sensitivity)`) that never goes flat. The dark outline is a setting (0 = off).
- **Colors:** `VisualizerLogic.visualizerRegions` subscribes to region `viz` where the bars can be: a **ring** around the circle (from the base past the bar tips, plus 10%; 72 sectors) or the screen **edges** for the border style (32 zones on top/bottom). Ring sectors become a color ring around the circle's own center, so a circle on the left shows what's on the left. "Wallpaper only" subscribes with `source: "wallpaper"`.

### 2.3 Files and runtime paths

| Path | What |
|---|---|
| `$XDG_RUNTIME_DIR/shroomery/screen-colors.sock` | The protocol socket (§3) |
| `$XDG_RUNTIME_DIR/shroomery/screen-colors.lock` | Single-instance lock |
| `$XDG_RUNTIME_DIR/shroomery/visualizer-active` | Flag: visualizer mode on (Hyprland binds read it) |
| `$XDG_RUNTIME_DIR/shroomery/cava-<bars>-<fps>.conf` | Generated cava configs (`cava-96-60` overlay, `cava-96-30` setup preview, `cava-24-30` dashboard) |
| `~/.config/shroomery/settings/visualizer.json` | Every setup-panel setting; keys and defaults in the shroomery README |
| `~/.cache/shroomery/displayed_wallpaper` | Written by `wallpaper.sh`: what is shown (the effect copy, the original image, or a video — decoded by `video.py`; while an animated wallpaper is paused, its still). The daemon's wallpaper base; falls back to `current_wallpaper`. |

Everything in `$XDG_RUNTIME_DIR` is gone after a reboot, which is intentional.
No screenshots are ever written anywhere.

---

## 3. Protocol v2

**Transport:** a Unix stream socket. Each message is one UTF-8 JSON object on its own line (`\n`).
A client first **subscribes**; the daemon then sends it frames until it disconnects. A client
can subscribe again at any time to change what it gets.

### Client → daemon: `subscribe`

```json
{"v":2,"type":"subscribe","monitor":"HDMI-A-1","source":"screen",
 "regions":[
   {"id":"viz","shape":"ring","cx":0.5,"cy":0.5,"inner":0.10,"outer":0.42,"sectors":72},
   {"id":"tv","shape":"edges","top":40,"right":22,"bottom":40,"left":22,"depth":0.15},
   {"id":"lamp","shape":"rects","rects":[[0.0,0.4,0.05,0.2],[0.95,0.4,0.05,0.2]]}
 ]}
```

| Field | Meaning | Valid |
|---|---|---|
| `monitor` | Output name | a connected output |
| `source` | `screen` (the rebuilt screen) or `wallpaper` (wallpaper only) | one of the two |
| `regions` | The areas to sample, each with a unique `id` (1–32 characters) | 1–8 regions |
| ring `cx`, `cy` | Center, as fractions of the monitor's width / height | 0–1 |
| ring `inner`, `outer` | Radii, as fractions of the monitor's **short side** (so a ring stays round) | 0 ≤ inner < outer ≤ 2 |
| ring `sectors` | Zones around the ring | 4–360 |
| edges `top` / `right` / `bottom` / `left` | Zones per side | 1–200 each |
| edges `depth` | How far the band reaches in, fraction of the short side | 0.01–0.5 |
| rects `rects` | `[x, y, w, h]` fractions of width / height (may overlap) | 1–256, inside 0–1, w and h > 0 |

**Zone order:**
- **ring:** sectors clockwise from 12 o'clock (sector *i* spans `[i/n, (i+1)/n)` of a turn).
- **edges:** clockwise from the top-left corner: the top edge left→right, the right edge
  top→bottom, the bottom edge right→left, the left edge bottom→top (corners belong to the
  top and bottom bands). Edges are sampled inside letterbox/pillarbox bars.
- **rects:** in the order given.

A bad subscription gets `{"v":2,"type":"error","message":"<what is wrong>"}` back and is
ignored (the previous one stays). If the monitor disconnects, its clients get
`{"v":2,"type":"error","message":"monitor gone"}` once and no frames until they subscribe again.

### Daemon → client: `frame` (about 30 per second)

```json
{"v":2,"type":"frame","t":1760389012345,"monitor":"HDMI-A-1","source":"screen","windows":2,
 "regions":{"viz":{"colors":["#1a2b3c","…72"],"average":"#223344"},
            "tv":{"colors":["…124"],"average":"#…"},
            "lamp":{"colors":["…2"],"average":"#…"}}}
```

| Field | Meaning |
|---|---|
| `t` | Unix time in ms when this frame was published. |
| `source` | `screen`, `wallpaper`, or `pattern` (`--pattern` test frames). |
| `windows` | How many windows were pasted into the picture this tick (0 for wallpaper only). |
| `regions.<id>.colors` | `#rrggbb` per zone in zone order, **smoothed, true colors** (black means black). |
| `regions.<id>.average` | The smoothed mean of the whole region. |

### Compatibility rules

- **Adding** a field is allowed within v2, and clients must ignore fields they don't know.
- **Renaming or removing** a field, or changing a zone order, means v3.
- **Planned v2 addition, for music-reactive LEDs:** `"spectrum":[0.0–1.0, …]`, the cava bars in the same frame, so a controller doesn't need its own audio capture.

### Watching the stream by hand

```bash
~/.config/shroomery/scripts/screen-colors.py --watch --monitor DP-2 | head -3
~/.config/shroomery/scripts/screen-colors.py --watch --subscribe @my-subscription.json | head -3
```

---

## 4. Smoothing: how colors morph

All of this happens in **OKLab**, a color space where equal distances look
equally different, so a red→blue fade doesn't pass through muddy grey. ΔE below
is the OKLab distance: about 0.4 for opposite hues, 1.0 for black→white. Each
region of each client has its own smoother; re-subscribing with an unchanged
region keeps it (no color jump).

1. **Dead zone:** a change of ΔE ≤ 0.02 is ignored (noise, compression artifacts).
2. **Flash filter:** a new color must appear in **two samples in a row** (each within ΔE 0.08 of the other) before it becomes the target. A one-frame flash or cut to black never reaches the LEDs. It costs one sample period (200 ms at 5 Hz).
3. **Duration:** `duration = lerp(2000 ms, 500 ms, clamp(ΔE / 0.4))`. Opposite colors take about 0.5 s and similar ones about 2 s.
4. **Motion:** exponential approach, `current += (target − current)·(1 − e^(−dt/τ))` with `τ = duration/3`, which reaches 95% at about `duration`. A new target mid-fade continues from the current color, with no jump.

To make it calmer or snappier, change the constants at the top of `smoothing.py`. The tests in `tests/test_smoothing.py` pin the timing.

---

## 5. Writing a consumer

The minimal Python client:

```python
import json, os, socket

path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "shroomery", "screen-colors.sock")
subscribe = {"v": 2, "type": "subscribe", "monitor": "HDMI-A-1", "source": "screen",
             "regions": [{"id": "tv", "shape": "edges", "top": 40, "right": 22,
                          "bottom": 40, "left": 22, "depth": 0.15}]}
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.connect(path)
    s.sendall((json.dumps(subscribe) + "\n").encode())
    for line in s.makefile("r", encoding="utf-8"):
        msg = json.loads(line)
        if msg.get("type") == "error":
            print("refused:", msg["message"])
        elif msg.get("type") == "frame":
            tv = msg["regions"]["tv"]
            print(msg["source"], tv["average"], len(tv["colors"]))
```

**Rules for consumers:**
- **Starting the daemon:** if the socket is missing, start `screen-colors.py` and retry the connection every 500 ms (back off if it keeps failing). Never sample the screen yourself.
- **Subscribe on every (re)connect,** and only re-send when what you want changed (the daemon keeps your smoothing for regions that didn't change).
- **Display rules belong to you:** gamma, brightness caps and minimum lightness live in the consumer. The stream stays true colors.
- **Disconnects:** keep showing the last frame you received and reconnect quietly.
- **Write it down:** add the new consumer to the status table at the top of this README.

---

## 6. Later: the LED strip controller

None of this exists yet. These are the notes needed to build it without
redesigning anything above.

### 6.1 Shape of it

```
screen-colors.sock ──► led-bridge.py (PC) ──Wi-Fi──► microcontroller ──data pin──► LED strip
```

- **`led-bridge.py`** goes in `shroomery/scripts/` (or `screencolors/bridge/`). It's just another consumer (§5). It does the following:
  - **Mapping:** maps every LED to a position on the perimeter (0–1, clockwise from the top-left, the same as the zones) and blends the two nearest zone colors.
  - **Output corrections:** applies gamma (≈ 2.2), a white balance per strip, a global brightness, and a **power cap**. At full white, a WS2812-class LED draws about 60 mA, so 120 LEDs draw about 7 A at 5 V. The bridge should scale frames so they stay under the power supply's rating.
  - **Black:** sends black as off.
  - **Sending:** sends one packet per frame (30 fps is plenty, because the colors are already smoothed).
- **The microcontroller:** any ESP32 with Wi-Fi drives the strip. It only shows the pixels it receives. All the logic stays on the PC, where it's easy to change and test.

### 6.2 LED layout config (bridge side)

```json
{
  "controller": {"host": "ledstrip.local", "protocol": "ddp"},
  "monitor": "HDMI-A-1",
  "strip": {"start": "bottom-center", "direction": "clockwise",
            "counts": {"top": 40, "right": 22, "bottom": 40, "left": 22},
            "gap_bottom_center": 4},
  "gamma": 2.2, "brightness": 0.8, "max_current_ma": 4000
}
```

Strips usually start behind the TV's bottom center and skip the stand, so
`start`, `direction` and gaps have to be configurable. Don't assume the
strip starts at zone 0.

With protocol v2 the bridge subscribes to exactly what its strip needs: an
`edges` region with the strip's own counts (one zone per LED, e.g. 40/22/40/22
and a small `depth`), or `rects` for LEDs that sit somewhere else (a lamp, a
shelf). It then only has to map zone order to the strip's start corner and
direction; the daemon does the sampling and smoothing.

### 6.3 Network transport: HTTP vs WebSocket vs UDP

Per frame there's very little data: 124 LEDs × 3 bytes = 372 bytes, so about 11 KB/s at 30 fps.
**Bandwidth is never the problem. Latency and jitter over Wi-Fi are.**

| Transport | Fit for 30 fps frames | Notes |
|---|---|---|
| **HTTP request per frame** | ✗ poor | Every frame pays for request/response handling, often a new TCP connection, and the microcontroller's HTTP parsing. Small web servers on microcontrollers usually manage a few dozen requests per second at best, with jitter. HTTP is fine for **settings** (brightness, on/off), not frames. |
| **WebSocket** | ✓ OK | One persistent connection, small binary messages, works through anything. It runs on TCP, so a lost Wi-Fi packet holds up the frames behind it (stutter, then a burst). Fine for a first version. Good for **control** plus frames on a clean network. |
| **UDP** | ✓✓ best for frames | Fire-and-forget: a lost frame is simply replaced by the next one 33 ms later. This is what ambient-light systems use. Existing LED protocols: **DDP** (port 4048), **E1.31/sACN** (5568), and WLED's own realtime UDP (port 21324). |

**Suggested path:**
1. **Try WLED firmware first** on an ESP32. It already receives DDP/E1.31/realtime UDP, handles the strip, and has a web UI for setup. The bridge then only has to speak DDP, with no firmware code at all. (Check the WLED docs for the current protocol details before building.)
2. **If custom firmware is needed:** use UDP for frames and a WebSocket or HTTP for control (brightness, mode, layout). Use a binary frame: `magic(2) seq(2) count(2) rgb[count×3]`. The sequence number lets the controller drop late packets.
3. **Avoid a wired connection** unless Wi-Fi drops frames in practice. USB serial at 921600 baud handles 124 LEDs at 30 fps easily, so it's a good fallback, and the bridge's output stage should be swappable (`--output ddp|ws|serial`).

### 6.4 Latency budget (what the LEDs will lag behind the picture)

| Stage | Typical |
|---|---|
| Capture interval (5 Hz) | 0–200 ms |
| Flash filter (one sample) | 200 ms |
| Smoothing (by design) | 500–2000 ms of fade |
| Bridge + Wi-Fi + strip | < 30 ms |

That's deliberately "ambient", not frame-accurate. For snappier LEDs, raise `--rate`
and lower the durations. That trades CPU and flicker for responsiveness.

---

## 7. Troubleshooting

| Symptom | Check |
|---|---|
| Visualizer shows only theme colors | Is the daemon running (`pgrep -f screen-colors.py`)? Does the socket exist? Try `screen-colors.py --watch` (§3). |
| Colors are always black | Is that area of the screen really black (a DRM-protected video can capture as black)? Check `source` and `windows` in a frame (`--watch --subscribe` with the same region). |
| The overlay's own colors look sampled | Can't happen: the picture is rebuilt from the wallpaper and each window's own buffer (`grim -T`), never from a full-output grab. If it does, that's a bug. |
| High CPU | Lower `--rate`. Smaller regions touch fewer windows (look at `windows` in the frames); a large 4K window costs about 24% of a core at 5 Hz. |
| Super+arrows stuck controlling the visualizer | `rm "$XDG_RUNTIME_DIR/shroomery/visualizer-active"`. Quickshell also deletes it at startup. |
| Normal notifications still pop up in visualizer mode (or with Do Not Disturb) | Check who owns the bus: `busctl --user status org.freedesktop.Notifications`. It must be `qs`. If it is `swaync`, D-Bus started it (its unit should be masked: `systemctl --user mask swaync.service`); stop it and restart `qs`. |
| A QML consumer never connects | A Quickshell `Socket` makes one connection attempt; after a refusal, setting `connected` again does nothing. Create a fresh `Socket` per retry (see `VisualizerApp/ScreenColors.qml`). |
| No bars move | Is cava installed? Is audio playing to the default sink (`wpctl status`)? |

---

## 8. Known (potential) issues

Found in the final reviews (2026-10-14, 2026-10-15) and left for later. None breaks
normal use; each line says what would happen and the likely fix.

| Area | What can happen | Likely fix |
|---|---|---|
| Hyprland binds | If `qs` crashes during visualizer mode and isn't restarted, the flag file stays and Super+arrows / Super+Esc call a dead IPC (no focus moves) until it is removed (`rm $XDG_RUNTIME_DIR/shroomery/visualizer-active`) or the next qs start. | Write qs's PID into the flag; `visualizer_active()` checks `/proc/<pid>`. |
| Flag file | Turning the mode on and off very quickly can run the `rm` before the create, leaving the flag set while the mode is off. | Write/remove it synchronously (a `FileView`). |
| Daemon | A wallpaper that fails to decode (or a `magick` timeout on a huge image) leaves the base black until the wallpaper path or the picture size changes. | Don't cache a failed decode; retry slowly. |
| Audio | If cava dies after the first 2 s (e.g. a PipeWire restart), the visualizer silently shows only its base ring. | Restart cava, or notify. |
| Notifications | Critical popups already on screen are hidden when the mode starts (new critical ones still show). | Skip critical entries in `hideAllPopups()` for this case. |
| Server | A client that sends data without a newline grows its input buffer without limit (local, 0600 socket: low risk). | Cap the inbox and drop the client. |
| Daemon | A 0×0 window capture (not produced by grim in practice) would raise while pasting; the tick is logged and skipped, the daemon keeps running. | Skip empty captures before pasting. |
| Setup panel | `qs ipc call visualizer-setup open` (the panel's own IPC) opens it even while the visualizer runs; Start then saves but the panel stays open. Super+Alt+V and the switch are not affected. | Clear `setupOpen` in `start()` and close the panel when it opens while running. |
| Setup panel | The Monitor combo always saves an explicit name, so "follow the focused monitor" (`""`) can't be chosen again; a monitor unplugged while the panel is open stays in the working copy. | A "Focused monitor" entry; re-pick on screen changes while open. |
| Renderer | The shader samples the ring at `(t·359+0.5)/360` (a leftover of the per-texel convention; up to 0.5° off), and `colorRing`/`ringFromStops` + their tests are no longer used by QML. | Sample at `t`; drop or label the helpers. |
| Setup preview | At mini-screen scale (~0.19) bars are sub-pixel, so Bars mode previews as a haze; width/spacing can't be judged there. | Supersample the preview renderer, or show a zoomed strip. |
| Renderer | Bars are rounded at the base as well as the tip, so the silent ring is a row of small pills. | Round only the tip end of the box. |
| Renderer | Switching style or draw mode is instant (the part-0 renderer cross-faded 150 ms). | Fade the renderer's opacity around the switch. |
| Renderer | Thin lines keep their thickness on slopes up to about 8 px per px (gradient clamp); steeper jumps still thin slightly. | Raise the clamp or compute the slope analytically. |
| Daemon | A translucent window marked "opaque" after one fully opaque capture stays on the cheaper PPM path until the set of windows changes, so lowering kitty's opacity later (`dynamic_background_opacity`) isn't picked up. | Re-check cached-opaque windows with PNG every few seconds. |
| Visualizer | On a style switch the new shape is drawn with the old region's colors for up to about 350 ms (debounce + next capture), e.g. 100 edge colors as 100 ring sectors. | Take `shape` from the subscription last sent and drop frames whose color count doesn't match it. |
| Daemon | If grim stops writing filter-0 PNG rows, translucent windows silently fall back to opaque PPM (two grim calls on the first capture, accuracy back to about 16/255), with no log line. | Log once when the PNG fallback is taken. |
| Daemon | A translucent 4K window's PNG path holds roughly 100 MB of buffers per capture (stdout, chunks, joined, decompressed). | Stream with `zlib.decompressobj` and keep only the rows the downsample needs. |
| Protocol | A `wallpaper`-source client gets the monitor's `windows` count when another client on that monitor samples the screen; wallpaper-source regions also widen which windows get captured. | Report 0 for wallpaper subscriptions; build capture boxes from screen-source regions only. |
| Daemon | An empty window list can't be told from a hyprctl failure (`hypr_json` returns `[]` for both), so closing the last window keeps the old layout for a tick or three (3 failed grims, then the wallpaper, which happens to be right). | Return None from `hypr_json` on failure. |
| Daemon | A maximized window (`fullscreen` 1) is treated like exclusive fullscreen: drawn alone, at `fullscreen_opacity`. | Use `fullscreen & 2` for the "alone" rule. |
| Regions | A tiny ring (outer below about 0.006 of the short side, or a thin ring that misses every pixel center at ÷8) comes back black. The visualizer never asks for one. | Fall back to the pixel under the center. |
| Daemon | Rotated monitors (`transform` 1/3/5/7) would need width and height swapped for the picture size. | Swap them for odd transforms. |
| Regions | A `rects` region's `average` weights overlapping rectangles twice (the spec says the mean over its pixels). | Average the union of the boxes. |
| Setup preview | The mini screen's background is the original wallpaper, not the effect copy that `displayed_wallpaper` points to, so with an effect on the preview's backdrop differs from what's sampled. | Read `displayed_wallpaper` in MiniScreen too (add it to `Paths`). |

