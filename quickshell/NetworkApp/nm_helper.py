#!/usr/bin/env python3
"""nmcli bridge for the Quickshell network panel.

Every subcommand prints a single JSON object (or array) on stdout so the QML
side never has to parse nmcli output itself. Errors are classified the same
way the network_controls Flutter app does, so the panel can tell "needs a
password", "needs sudo" and "just failed" apart.

Subcommands:
    snapshot [--ifname IF] [--rescan]   full state of the network stack
    op NAME JSON_ARGS                   one user action, see OPS below
    props device NAME KIND              key/value dump for a NIC
    props profile UUID                  key/value dump for a saved profile
    sudo JSON_COMMANDS                  rerun argv lists via sudo -S (stdin)
"""

import json
import os
import subprocess
import sys

ENV = dict(os.environ, LC_ALL="C")
TIMEOUT = 60


# --------------------------------------------------------------- process glue

class Result:
    def __init__(self, code, out, err):
        self.code = code
        self.out = out
        self.err = err

    @property
    def ok(self):
        return self.code == 0

    @property
    def raw(self):
        return "\n".join(s for s in (self.err.strip(), self.out.strip()) if s).strip()


def run(argv, stdin=None):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, env=ENV,
                           input=stdin, timeout=TIMEOUT)
        return Result(p.returncode, p.stdout or "", p.stderr or "")
    except FileNotFoundError:
        return Result(-1, "", "No such file or directory: %s" % argv[0])
    except subprocess.TimeoutExpired:
        return Result(-2, "", "%s timed out." % argv[0])


def nmcli(args):
    return run(["nmcli"] + args)


# ------------------------------------------------------------------- parsing

def split_terse(line):
    """Split one `nmcli -t` line; nmcli escapes ':' as '\\:' and '\\' as '\\\\'."""
    fields, buf, escaped = [], [], False
    for ch in line:
        if escaped:
            buf.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == ":":
            fields.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    fields.append("".join(buf))
    return fields


def split_kv(line):
    """Split one `KEY:value` line of `nmcli -t <obj> show`; only the first colon."""
    i = line.find(":")
    if i <= 0:
        return None
    return [line[:i], line[i + 1:]]


def lines(text):
    return [l for l in text.splitlines() if l.strip()]


DEVICE_KINDS = {
    "ethernet": "ethernet",
    "wifi": "wifi",
    "wifi-p2p": "wifiP2p",
    "bridge": "bridge",
    "loopback": "loopback",
    "tun": "tun",
}

PROFILE_KINDS = {
    "802-3-ethernet": "wired",
    "802-11-wireless": "wifi",
}


def parse_devices(out):
    devices = []
    for line in lines(out):
        f = split_terse(line)
        if len(f) < 4:
            continue
        state = f[2]
        devices.append({
            "name": f[0],
            "typeRaw": f[1],
            "kind": DEVICE_KINDS.get(f[1], "other"),
            "stateRaw": state,
            "connectionName": f[3],
            "connected": state.startswith("connected"),
            "connecting": state.startswith("connecting"),
            "unavailable": state.startswith("unavailable"),
            "disconnected": state.startswith("disconnected"),
        })
    return devices


def parse_wifi_list(out):
    aps = []
    for line in lines(out):
        # IN-USE:SSID:BSSID:MODE:CHAN:FREQ:RATE:SIGNAL:SECURITY
        f = split_terse(line)
        if len(f) < 9:
            continue
        security = f[8].strip()
        secured = security != "" and security != "--"
        try:
            signal = int(f[7].strip())
        except ValueError:
            signal = 0
        aps.append({
            "inUse": f[0].strip() == "*",
            "ssid": f[1],
            "bssid": f[2],
            "mode": f[3],
            "channel": f[4].strip(),
            "freq": f[5].strip(),
            "rate": f[6].strip(),
            "signal": signal,
            "security": security,
            "secured": secured,
            "enterprise": "802.1X" in security,
            "hidden": f[1] == "",
        })
    return aps


def parse_connections(out):
    profiles = []
    for line in lines(out):
        # NAME:UUID:TYPE:DEVICE:AUTOCONNECT:AUTOCONNECT-PRIORITY:ACTIVE:STATE:
        # TIMESTAMP:TIMESTAMP-REAL
        f = split_terse(line)
        if len(f) < 10:
            continue
        try:
            priority = int(f[5])
        except ValueError:
            priority = 0
        try:
            timestamp = int(f[8])
        except ValueError:
            timestamp = 0
        profiles.append({
            "name": f[0],
            "uuid": f[1],
            "typeRaw": f[2],
            "kind": PROFILE_KINDS.get(f[2], "other"),
            "device": f[3],
            "autoconnect": f[4] == "yes",
            "autoconnectPriority": priority,
            "isActive": f[6] == "yes",
            "stateRaw": f[7],
            "timestamp": timestamp,
            "lastUsed": "" if f[9] == "never" else f[9],
            "ssid": "",
        })
    return profiles


def resolve_ssids(profiles):
    for p in profiles:
        if p["kind"] != "wifi":
            continue
        r = nmcli(["-t", "-f", "802-11-wireless.ssid", "connection", "show",
                   "uuid", p["uuid"]])
        if r.ok:
            kv = split_kv(r.out.strip())
            if kv:
                p["ssid"] = kv[1]
    return profiles


# -------------------------------------------------------------- error mapping

def looks_like_auth(text):
    t = text.lower()
    return any(s in t for s in ("not authorized", "insufficient privileges",
                                "permission denied", "access denied", "polkit"))


def looks_like_secrets(text):
    t = text.lower()
    return any(s in t for s in ("secrets were required", "no key available",
                                "802.1x supplicant failed"))


def looks_like_not_running(text):
    t = text.lower()
    return any(s in t for s in ("networkmanager is not running",
                                "could not connect: no such file or directory",
                                "failed to get d-bus connection"))


def classify(friendly, argv, r):
    """None when [r] succeeded, otherwise a JSON-ready error dict."""
    if r.ok:
        return None
    raw = r.raw
    if looks_like_secrets(raw):
        return {
            "kind": "wifiPassword",
            "message": "A Wi-Fi password is required (or the stored one was rejected).",
            "detail": raw,
        }
    if looks_like_auth(raw):
        return {
            "kind": "needsAuth",
            "message": "%s Administrator privileges are required." % friendly,
            "detail": raw,
            "argv": argv,
        }
    if looks_like_not_running(raw):
        return {"kind": "failure", "message": "NetworkManager is not running.",
                "detail": raw}
    return {"kind": "failure", "message": friendly, "detail": raw}


def action(friendly, args):
    return classify(friendly, ["nmcli"] + args, nmcli(args))


# ------------------------------------------------------------------ snapshot

def read_sys(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def rfkill_state():
    soft = hard = False
    base = "/sys/class/rfkill"
    if os.path.isdir(base):
        for name in os.listdir(base):
            p = os.path.join(base, name)
            if read_sys(os.path.join(p, "type")) != "wlan":
                continue
            if read_sys(os.path.join(p, "soft")) == "1":
                soft = True
            if read_sys(os.path.join(p, "hard")) == "1":
                hard = True
    return {"soft": soft, "hard": hard}


def service_state():
    return {
        "active": run(["systemctl", "is-active", "NetworkManager.service"]).out.strip(),
        "enabled": run(["systemctl", "is-enabled", "NetworkManager.service"]).out.strip(),
    }


def snapshot(ifname, rescan):
    out = {
        "nmcliMissing": False,
        "running": False,
        "statusError": "",
        "statusDetail": "",
        "wifiEnabled": False,
        "wifiHwEnabled": True,
        "devices": [],
        "profiles": [],
        "aps": [],
        "service": service_state(),
        "rfkill": rfkill_state(),
    }

    r = nmcli(["-t", "-f", "RUNNING", "general"])
    if not r.ok:
        raw = r.raw
        if r.code == -1:
            out["nmcliMissing"] = True
            out["statusError"] = "nmcli was not found. Install NetworkManager."
            out["statusDetail"] = raw
            return out
        if not looks_like_not_running(raw):
            out["statusError"] = "Could not query NetworkManager."
            out["statusDetail"] = raw
            return out
    else:
        out["running"] = r.out.strip() == "running"
    if not out["running"]:
        return out

    r = nmcli(["-t", "-f", "WIFI,WIFI-HW", "radio"])
    if r.ok:
        f = split_terse(r.out.strip())
        if len(f) >= 2:
            out["wifiEnabled"] = f[0] == "enabled"
            out["wifiHwEnabled"] = f[1] == "enabled"

    r = nmcli(["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"])
    if r.ok:
        out["devices"] = parse_devices(r.out)
    else:
        out["statusError"] = "Could not list network devices."
        out["statusDetail"] = r.raw

    r = nmcli(["-t", "-f",
               "NAME,UUID,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY,ACTIVE,"
               "STATE,TIMESTAMP,TIMESTAMP-REAL", "connection", "show"])
    if r.ok:
        out["profiles"] = resolve_ssids(parse_connections(r.out))
    elif not out["statusError"]:
        out["statusError"] = "Could not list connections."
        out["statusDetail"] = r.raw

    args = ["-t", "-f", "IN-USE,SSID,BSSID,MODE,CHAN,FREQ,RATE,SIGNAL,SECURITY",
            "device", "wifi", "list"]
    if ifname:
        args += ["ifname", ifname]
    args += ["--rescan", "yes" if rescan else "no"]
    r = nmcli(args)
    if r.ok:
        out["aps"] = parse_wifi_list(r.out)
    # Radio off / no adapter are normal situations here, not errors.
    return out


# ---------------------------------------------------------------- properties

def device_properties(name, kind):
    r = nmcli(["-t", "device", "show", name])
    if not r.ok:
        return {"error": classify("Could not read device details.", [], r)}
    rows = [kv for kv in (split_kv(l) for l in lines(r.out)) if kv]
    if kind == "ethernet":
        speed = read_sys("/sys/class/net/%s/speed" % name)
        if speed and speed.lstrip("-").isdigit() and int(speed) > 0:
            rows.append(["LINK.SPEED", "%s Mbit/s" % speed])
    if kind == "wifi":
        rows += iw_link(name)
    return {"rows": rows}


def iw_link(name):
    r = run(["iw", "dev", name, "link"])
    if not r.ok:
        return []
    rows = []
    for line in lines(r.out):
        t = line.strip()
        if t.startswith("Connected to "):
            rows.append(["WIFI-LINK.AP", t[len("Connected to "):]])
            continue
        i = t.find(":")
        if i > 0:
            rows.append(["WIFI-LINK.%s" % t[:i].strip().upper(), t[i + 1:].strip()])
    return rows


def profile_properties(uuid):
    r = nmcli(["-t", "connection", "show", "uuid", uuid])
    if not r.ok:
        return {"error": classify("Could not read connection details.", [], r)}
    return {"rows": [kv for kv in (split_kv(l) for l in lines(r.out)) if kv]}


# ---------------------------------------------------------------- operations

PREFERRED_PRIORITY = 100
PREFERRED_METRIC = 50
OTHER_METRIC = 200


def op_wifi_radio(a):
    on = bool(a.get("enabled"))
    return action("Could not %s Wi-Fi." % ("enable" if on else "disable"),
                  ["radio", "wifi", "on" if on else "off"])


def op_device_connect(a):
    name = a["device"]
    return action("Could not connect %s." % name,
                  ["-w", "25", "device", "connect", name])


def op_device_disconnect(a):
    name = a["device"]
    return action("Could not disconnect %s." % name,
                  ["device", "disconnect", name])


def op_profile_up(a):
    return action("Could not activate the connection.",
                  ["-w", "25", "connection", "up", "uuid", a["uuid"]])


def op_profile_down(a):
    return action("Could not deactivate the connection.",
                  ["connection", "down", "uuid", a["uuid"]])


def op_profile_delete(a):
    return action("Could not delete the connection.",
                  ["connection", "delete", "uuid", a["uuid"]])


def op_wifi_connect(a):
    """Connect to a Wi-Fi network, saved profile or brand new."""
    uuid = a.get("uuid") or ""
    password = a.get("password") or ""
    ssid = a.get("ssid") or ""
    ifname = a.get("ifname") or ""
    if uuid:
        if password:
            err = action("Could not update the stored password.",
                         ["connection", "modify", "uuid", uuid,
                          "wifi-sec.psk", password])
            if err:
                return err
        return op_profile_up({"uuid": uuid})
    if a.get("enterprise"):
        return {
            "kind": "failure",
            "message": "This is an 802.1X enterprise network; connecting to it "
                       "is not supported here. Create a profile with "
                       "nm-connection-editor first.",
            "detail": "",
        }
    args = ["-w", "35", "device", "wifi", "connect", ssid]
    if password:
        args += ["password", password]
    if ifname:
        args += ["ifname", ifname]
    err = classify('Could not connect to "%s".' % ssid, ["nmcli"] + args,
                   nmcli(args))
    if err:
        # A failed first attempt leaves a never-used profile behind which would
        # shadow the next attempt; remove it so a retry starts clean.
        delete_never_used(ssid)
    return err


def delete_never_used(ssid):
    r = nmcli(["-t", "-f",
               "NAME,UUID,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY,ACTIVE,"
               "STATE,TIMESTAMP,TIMESTAMP-REAL", "connection", "show"])
    if not r.ok:
        return
    for p in resolve_ssids(parse_connections(r.out)):
        if (p["kind"] == "wifi" and p["timestamp"] == 0 and not p["isActive"]
                and ssid in (p["ssid"], p["name"])):
            nmcli(["connection", "delete", "uuid", p["uuid"]])


def op_wifi_disconnect(a):
    uuid = a.get("uuid") or ""
    if uuid:
        return op_profile_down({"uuid": uuid})
    device = a.get("device") or ""
    if device:
        return op_device_disconnect({"device": device})
    return None


def op_ethernet(a):
    """"Off" disconnects every wired NIC; "on" reconnects the idle ones."""
    enabled = bool(a.get("enabled"))
    devices = [d for d in a.get("devices", [])]
    if not enabled:
        first = None
        for d in devices:
            if d.get("connected"):
                first = first or op_device_disconnect({"device": d["name"]})
        return first
    candidates = [d for d in devices if d.get("disconnected")]
    if not candidates:
        if devices and all(d.get("unavailable") for d in devices):
            return {
                "kind": "failure",
                "message": "No wired network available. Is a cable (or USB "
                           "tethering) plugged in?",
                "detail": "",
            }
        return None
    last, connected = None, 0
    for d in candidates:
        err = op_device_connect({"device": d["name"]})
        if err is None:
            connected += 1
        else:
            last = err
    return None if connected else last


def op_prefer_wired(a):
    uuid = a["uuid"]
    wired = a.get("wired", [])
    for p in wired:
        preferred = p["uuid"] == uuid
        err = action('Could not update priority of "%s".' % p["name"], [
            "connection", "modify", "uuid", p["uuid"],
            "connection.autoconnect-priority",
            str(PREFERRED_PRIORITY) if preferred else "0",
            "ipv4.route-metric",
            str(PREFERRED_METRIC if preferred else OTHER_METRIC),
            "ipv6.route-metric",
            str(PREFERRED_METRIC if preferred else OTHER_METRIC),
        ])
        if err:
            return err
    return reapply_active(wired, uuid)


def op_clear_wired(a):
    wired = a.get("wired", [])
    for p in wired:
        err = action('Could not reset priority of "%s".' % p["name"], [
            "connection", "modify", "uuid", p["uuid"],
            "connection.autoconnect-priority", "0",
            "ipv4.route-metric", "-1",
            "ipv6.route-metric", "-1",
        ])
        if err:
            return err
    return reapply_active(wired, None)


def reapply_active(wired, last_uuid):
    """Route metrics only apply on (re)activation, so bounce active profiles."""
    active = [p for p in wired if p.get("isActive")]
    active.sort(key=lambda p: 1 if p["uuid"] == last_uuid else 0)
    failures = []
    for p in active:
        r = nmcli(["-w", "25", "connection", "up", "uuid", p["uuid"]])
        if not r.ok:
            failures.append("%s: %s" % (p["name"], r.err.strip()))
    if not failures:
        return None
    return {
        "kind": "failure",
        "message": "Priorities were saved, but reapplying a connection failed.",
        "detail": "\n".join(failures),
    }


def op_unblock_wifi(a):
    argv = ["rfkill", "unblock", "wifi"]
    r = run(argv)
    if r.ok:
        return None
    return {
        "kind": "needsAuth",
        "message": "Could not unblock the Wi-Fi radio. Administrator "
                   "privileges are required.",
        "detail": r.err.strip(),
        "argv": argv,
    }


OPS = {
    "wifiRadio": op_wifi_radio,
    "deviceConnect": op_device_connect,
    "deviceDisconnect": op_device_disconnect,
    "profileUp": op_profile_up,
    "profileDown": op_profile_down,
    "profileDelete": op_profile_delete,
    "wifiConnect": op_wifi_connect,
    "wifiDisconnect": op_wifi_disconnect,
    "ethernet": op_ethernet,
    "preferWired": op_prefer_wired,
    "clearWired": op_clear_wired,
    "unblockWifi": op_unblock_wifi,
}


# --------------------------------------------------------------------- sudo

def sudo(commands, password):
    """Rerun argv lists as root. rfkill is retried unprivileged first."""
    for cmd in commands:
        if cmd and cmd[0] == "rfkill" and run(cmd).ok:
            continue
        r = run(["sudo", "-S", "-k"] + cmd, stdin=password + "\n")
        blob = ((r.err or "") + (r.out or "")).lower()
        if not r.ok and any(s in blob for s in ("sorry", "try again",
                                                "incorrect password",
                                                "authentication failure")):
            return {"kind": "wrongPassword"}
        if not r.ok:
            return {"kind": "failure", "detail": r.raw[:500]}
    return {"kind": "success"}


# --------------------------------------------------------------------- entry

def main(argv):
    if not argv:
        print(json.dumps({"error": "no subcommand"}))
        return
    cmd = argv[0]
    if cmd == "snapshot":
        ifname = ""
        rescan = False
        rest = argv[1:]
        while rest:
            if rest[0] == "--ifname" and len(rest) > 1:
                ifname, rest = rest[1], rest[2:]
            elif rest[0] == "--rescan":
                rescan, rest = True, rest[1:]
            else:
                rest = rest[1:]
        print(json.dumps(snapshot(ifname, rescan)))
    elif cmd == "op":
        name = argv[1]
        args = json.loads(argv[2]) if len(argv) > 2 else {}
        handler = OPS.get(name)
        if handler is None:
            print(json.dumps({"kind": "failure",
                              "message": "Unknown operation %s." % name}))
            return
        error = handler(args)
        print(json.dumps(error if error else {"kind": "success"}))
    elif cmd == "props":
        if argv[1] == "device":
            print(json.dumps(device_properties(argv[2], argv[3])))
        else:
            print(json.dumps(profile_properties(argv[2])))
    elif cmd == "sudo":
        password = sys.stdin.readline().rstrip("\n")
        print(json.dumps(sudo(json.loads(argv[1]), password)))
    else:
        print(json.dumps({"error": "unknown subcommand %s" % cmd}))


if __name__ == "__main__":
    main(sys.argv[1:])
