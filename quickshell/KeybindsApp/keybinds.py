#!/usr/bin/env python3
"""Read and edit the Hyprland lua keybinds for the Quickshell Keybinds panel.

  keybinds.py list  <keybindings.lua> <input.lua>
      Print the binds as JSON: sections of binds (keys, description, command,
      where the hl.bind call sits in the file and whether it can be edited),
      plus the keyboard's keycode -> keysym table used to name captured keys.
      The workspace loop is expanded the same way the lua file does.

  keybinds.py apply <keybindings.lua> <ops.json>
      Apply a list of edits (rebind / unbind), write the file, reload Hyprland
      and put the old file back if the reload reports new config errors.

Unbinding comments the hl.bind call out with UNBOUND_MARK so it stays listed
(as "not bound") and can be given a key again later.
"""

import bisect
import ctypes
import ctypes.util
import json
import os
import re
import subprocess
import sys
import tempfile

HOME = os.environ.get("HOME", "")
HYPR = os.path.join(HOME, ".config", "hypr")

UNBOUND_MARK = "-- [unbound] "
UNBOUND_RE = re.compile(r"^([ \t]*)-- \[unbound\] ", re.M)

FR_KEYS = [
    "ampersand",
    "eacute",
    "quotedbl",
    "apostrophe",
    "parenleft",
    "minus",
    "egrave",
    "underscore",
    "ccedilla",
    "agrave",
]


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def is_fr_layout(path):
    text = read_text(path)
    return bool(re.search(r'kb_layout\s*=\s*"et"', text)) and not bool(
        re.search(r'kb_variant\s*=\s*"us"', text)
    )


def unescape_lua(body):
    out = []
    i = 0
    while i < len(body):
        if body[i] == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            out.append({"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\"}.get(nxt, nxt))
            i += 2
        else:
            out.append(body[i])
            i += 1
    return "".join(out)


def lua_string(token):
    token = token.strip()
    if len(token) >= 2 and token[0] == token[-1] and token[0] in "\"'":
        return unescape_lua(token[1:-1])
    return token


def split_concat(expr):
    parts = []
    buf = []
    quote = None
    i = 0
    while i < len(expr):
        ch = expr[i]
        if quote:
            buf.append(ch)
            if ch == "\\" and i + 1 < len(expr):
                buf.append(expr[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'":
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if expr.startswith("..", i):
            parts.append("".join(buf).strip())
            buf = []
            i += 2
            continue
        buf.append(ch)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        parts.append(tail)
    return parts


def eval_key_expr(expr, env):
    chunks = []
    for part in split_concat(expr):
        if part in env:
            chunks.append(str(env[part]))
        elif (part.startswith('"') and part.endswith('"')) or (part.startswith("'") and part.endswith("'")):
            chunks.append(lua_string(part))
        else:
            chunks.append(part)
    return re.sub(r"\s+", " ", "".join(chunks)).strip()


def split_top_args(inner):
    args = []
    buf = []
    depth = 0
    quote = None
    i = 0
    while i < len(inner):
        ch = inner[i]
        if quote:
            buf.append(ch)
            if ch == "\\" and i + 1 < len(inner):
                buf.append(inner[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'":
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if ch in "({":
            depth += 1
            buf.append(ch)
        elif ch in ")}":
            depth = max(0, depth - 1)
            buf.append(ch)
        elif ch == "," and depth == 0:
            args.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        args.append(tail)
    return args


def extract_option_expr(opts, name):
    m = re.search(rf"{name}\s*=", opts)
    if not m:
        return None
    rest = opts[m.end():].lstrip()
    buf = []
    depth = 0
    quote = None
    i = 0
    while i < len(rest):
        ch = rest[i]
        if quote:
            buf.append(ch)
            if ch == "\\" and i + 1 < len(rest):
                buf.append(rest[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'":
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if ch in "({":
            depth += 1
            buf.append(ch)
        elif ch in ")}":
            if depth == 0 and ch == "}":
                break
            depth = max(0, depth - 1)
            buf.append(ch)
        elif ch == "," and depth == 0:
            break
        else:
            buf.append(ch)
        i += 1
    expr = "".join(buf).strip()
    return expr or None


def subst_idents(expr, env):
    out = []
    quote = None
    i = 0
    while i < len(expr):
        ch = expr[i]
        if quote:
            out.append(ch)
            if ch == "\\" and i + 1 < len(expr):
                out.append(expr[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'":
            quote = ch
            out.append(ch)
            i += 1
            continue
        ident = re.match(r"[A-Za-z_][A-Za-z0-9_]*", expr[i:])
        if ident:
            name = ident.group(0)
            if name in env:
                val = env[name]
                out.append(json.dumps(val) if isinstance(val, str) else str(val))
            else:
                out.append(name)
            i += len(name)
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def eval_lua_expr(expr, env):
    expr = subst_idents(expr.strip(), env)
    if ".." in expr:
        return eval_key_expr(expr, env)
    if (expr.startswith('"') and expr.endswith('"')) or (expr.startswith("'") and expr.endswith("'")):
        return lua_string(expr)
    return expr


def option_true(opts, name):
    return bool(re.search(rf"{name}\s*=\s*true", opts))


def extract_dispatch_calls(body):
    commands = []
    i = 0
    needle = "hl.dispatch("
    while True:
        j = body.find(needle, i)
        if j < 0:
            break
        close = find_matching(body, j + len("hl.dispatch") - 1)
        if close < 0:
            break
        inner = body[j + len(needle) : close].strip()
        if inner:
            commands.append(re.sub(r"\s+", " ", inner).strip())
        i = close + 1
    return commands


def parse_action(action, env):
    action = subst_idents(action.strip(), env)
    action = re.sub(r"\s+", " ", action).strip()
    m = re.match(r"hl\.dsp\.exec_cmd\((.*)\)\s*$", action, re.S)
    if m:
        cmd = lua_string(m.group(1).strip())
        return {
            "kind": "exec",
            "command": cmd,
            "commands": [cmd],
            "runnable": True,
        }

    if action.startswith("function"):
        commands = extract_dispatch_calls(action)
        compact = action
        return {
            "kind": "function" if not commands else "dispatch",
            "command": "; ".join(commands) if commands else compact,
            "commands": commands,
            "runnable": bool(commands),
        }

    if action.startswith("hl.dsp."):
        mouse_only = bool(re.search(r"window\.(drag|resize)\s*\(", action))
        return {
            "kind": "dispatch",
            "command": action,
            "commands": [] if mouse_only else [action],
            "runnable": not mouse_only,
        }

    return {
        "kind": "unknown",
        "command": action,
        "commands": [],
        "runnable": False,
    }


def find_matching(text, start, open_ch="(", close_ch=")"):
    depth = 0
    quote = None
    i = start
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == "\\" and i + 1 < len(text):
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'":
            quote = ch
            i += 1
            continue
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def iter_bind_calls(text):
    i = 0
    while True:
        j = text.find("hl.bind(", i)
        if j < 0:
            return
        close = find_matching(text, j + len("hl.bind") - 1)
        if close < 0:
            return
        yield j, text[j + len("hl.bind(") : close]
        i = close + 1


LOOP_RE = re.compile(r"for\s+i\s*=\s*1\s*,\s*10\s+do\b")


def comment_label(line, prev_line):
    """A heading candidate: the first line of a comment block after a blank line."""
    s = line.strip()
    if not s.startswith("--") or prev_line.strip() != "":
        return None
    body = s[2:].lstrip()
    # Commented-out and unbound binds are not headings.
    if body.startswith("hl.bind") or body.startswith("[unbound]"):
        return None
    if not body or set(body) <= set("-"):
        return None
    return body


def is_bind_line(line):
    s = line.strip()
    return bool(UNBOUND_RE.match(line)) or s.startswith("hl.bind(") or bool(LOOP_RE.match(s))


def section_label(lines, idx):
    """The section a heading comment starts, or None when it is a note above
    other code (e.g. `-- Configuration` above `local mainMod`). A heading
    starts a section when the next code after it is a bind, the workspace
    loop, another heading or the end of the file."""
    label = comment_label(lines[idx][1], lines[idx - 1][1] if idx > 0 else "")
    if label is None:
        return None
    j = idx + 1
    while j < len(lines):
        line = lines[j][1]
        s = line.strip()
        if is_bind_line(line):
            return label
        if s.startswith("--"):
            if lines[j - 1][1].strip() == "" and comment_label(line, ""):
                return label  # the next heading: this section is empty
        elif s != "":
            return None
        j += 1
    return label


def match_block_end(text, body_start):
    depth = 1
    k = body_start
    quote = None
    while k < len(text) and depth > 0:
        if quote:
            if text[k] == "\\" and k + 1 < len(text):
                k += 2
                continue
            if text[k] == quote:
                quote = None
            k += 1
            continue
        if text.startswith("--", k):
            nl = text.find("\n", k)
            k = len(text) if nl < 0 else nl + 1
            continue
        if text[k] in "\"'":
            quote = text[k]
            k += 1
            continue
        word = re.match(r"\b(function|then|do|end|repeat|until)\b", text[k:])
        if word:
            tok = word.group(1)
            if tok in ("function", "then", "do", "repeat"):
                depth += 1
            else:
                depth -= 1
            k += len(tok)
            continue
        k += 1
    return k, text[body_start : k - 3] if depth == 0 else ""


def parse_bind_args(inner, env):
    args = split_top_args(inner)
    if len(args) < 2:
        return None
    keys = eval_key_expr(args[0], env)
    action = parse_action(args[1], env)
    opts = args[2] if len(args) > 2 else ""
    desc_expr = extract_option_expr(opts, "description") or extract_option_expr(opts, "desc")
    description = eval_lua_expr(desc_expr, env) if desc_expr else ""
    mouse = option_true(opts, "mouse") or (action["kind"] == "dispatch" and not action["runnable"])
    if mouse and action["kind"] != "exec":
        action["runnable"] = False
        action["commands"] = []
    return {
        "keys": keys,
        "description": description or "Custom action",
        "hasDescription": bool(description),
        "command": action["command"],
        "commands": action.get("commands") or [],
        "kind": action["kind"],
        "runnable": bool(action["runnable"]),
        "mouse": bool(mouse),
        "locked": option_true(opts, "locked"),
        "repeating": option_true(opts, "repeating"),
    }


def expand_workspace_loop(body, main_mod, fr):
    binds = []
    for i in range(1, 11):
        key = i % 10
        if fr:
            key = FR_KEYS[i - 1]
        env = {"mainMod": main_mod, "i": i, "key": key}
        for _, inner in iter_bind_calls(body):
            parsed = parse_bind_args(inner, env)
            if parsed:
                binds.append(parsed)
    return binds


def line_bounds(text, start, end):
    """Start of the line holding `start` and end of the line holding `end - 1`."""
    line_start = text.rfind("\n", 0, start) + 1
    line_end = text.find("\n", end)
    return line_start, len(text) if line_end < 0 else line_end


def owns_its_lines(text, start, end):
    """True when text[start:end] is alone on its lines (bar a trailing comment),
    so it can be commented out, moved or deleted line by line."""
    line_start, line_end = line_bounds(text, start, end)
    before = text[line_start:start]
    after = text[end:line_end].strip()
    return before.strip() == "" and (after == "" or after.startswith("--"))


def split_lines(text):
    out = []
    pos = 0
    for line in text.split("\n"):
        out.append((pos, line))
        pos += len(line) + 1
    return out


def parse_file(text, main_mod, fr):
    """Sections in file order, each with its binds. A section knows its
    heading line (offset/src; -1/"" for binds above the first heading) and
    `insert_at`, the position after its last line, where new binds go."""
    lines = split_lines(text)
    starts = [p for p, _ in lines]

    def after_line(idx):
        return min(len(text), lines[idx][0] + len(lines[idx][1]) + 1)

    def line_of(pos):
        return max(0, bisect.bisect_right(starts, pos) - 1)

    sections = [{"label": "Keybinds", "offset": -1, "src": "", "binds": [], "insert_at": 0}]
    cur = sections[0]

    def add_bind(bind, offset, src, movable):
        bind.update({
            "section": cur["label"],
            "offset": offset,
            "src": src,
            "movable": movable,
        })
        cur["binds"].append(bind)

    idx = 0
    while idx < len(lines):
        pos, line = lines[idx]
        stripped = line.strip()

        label = section_label(lines, idx)
        if label:
            cur = {"label": label, "offset": pos, "src": line, "binds": [], "insert_at": after_line(idx)}
            sections.append(cur)
            # New binds go below the whole comment block.
            j = idx + 1
            while j < len(lines) and lines[j][1].strip().startswith("--") and not is_bind_line(lines[j][1]) \
                    and not lines[j][1].strip()[2:].lstrip().startswith("hl.bind"):
                cur["insert_at"] = after_line(j)
                j += 1
            idx += 1
            continue

        # A bind commented out by "unbind": every line carries UNBOUND_MARK.
        if UNBOUND_RE.match(line):
            j = idx
            while j < len(lines) and UNBOUND_RE.match(lines[j][1]):
                j += 1
            block = "\n".join(l for _, l in lines[idx:j])
            for _, inner in iter_bind_calls(UNBOUND_RE.sub(r"\1", block)):
                parsed = parse_bind_args(inner, {"mainMod": main_mod})
                if parsed:
                    parsed.update({"unbound": True, "editable": True, "clearable": False, "reason": ""})
                    add_bind(parsed, pos, block, True)
                break
            cur["insert_at"] = after_line(j - 1)
            idx = j
            continue

        loop = LOOP_RE.match(stripped)
        if loop:
            loop_start = pos + len(line) - len(line.lstrip())
            k, body = match_block_end(text, loop_start + loop.end())
            for bind in expand_workspace_loop(body, main_mod, fr):
                bind.update({
                    "unbound": False,
                    "editable": False,
                    "clearable": False,
                    "reason": "Set for every workspace by a loop in keybindings.lua",
                })
                add_bind(bind, -1, "", False)
            end_idx = line_of(max(loop_start, k - 1))
            cur["insert_at"] = after_line(end_idx)
            idx = end_idx + 1
            continue

        if stripped.startswith("hl.bind("):
            start = pos + len(line) - len(line.lstrip())
            close = find_matching(text, start + len("hl.bind") - 1)
            if close < 0:
                break
            src = text[start : close + 1]
            parsed = parse_bind_args(src[len("hl.bind(") : -1], {"mainMod": main_mod})
            own = owns_its_lines(text, start, close + 1)
            if parsed:
                parsed.update({
                    "unbound": False,
                    "editable": True,
                    "clearable": own,
                    "reason": "",
                })
                add_bind(parsed, start, src, own)
            end_idx = line_of(close)
            cur["insert_at"] = after_line(end_idx)
            idx = end_idx + 1
            continue

        idx += 1

    if not sections[0]["binds"]:
        sections.pop(0)
    for s in sections:
        # A section can be deleted when every bind in it can be moved or removed.
        s["removable"] = s["offset"] >= 0 and all(b["movable"] for b in s["binds"])
    return sections


def main_mod_from(text):
    m = re.search(r'local\s+mainMod\s*=\s*"([^"]+)"', text)
    return m.group(1) if m else "SUPER"


# --- Keyboard map -------------------------------------------------------------

class _RuleNames(ctypes.Structure):
    _fields_ = [(name, ctypes.c_char_p) for name in ("rules", "model", "layout", "variant", "options")]


def main_keyboard():
    try:
        out = subprocess.run(["hyprctl", "-j", "devices"], capture_output=True, text=True, timeout=3).stdout
        boards = json.loads(out).get("keyboards", [])
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}
    for kb in boards:
        if kb.get("main"):
            return kb
    return boards[0] if boards else {}


def keysym_table():
    """xkb keycode -> name of the unshifted keysym on the main keyboard's first layout.
    Hyprland matches binds against that keysym, so captured keys are named with it."""
    kb = main_keyboard()

    def enc(value):
        value = (value or "").split(",")[0].strip()
        return value.encode() if value else None

    lib_name = ctypes.util.find_library("xkbcommon") or "libxkbcommon.so.0"
    try:
        xkb = ctypes.CDLL(lib_name)
    except OSError:
        return {}
    xkb.xkb_context_new.restype = ctypes.c_void_p
    xkb.xkb_context_new.argtypes = [ctypes.c_int]
    xkb.xkb_keymap_new_from_names.restype = ctypes.c_void_p
    xkb.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(_RuleNames), ctypes.c_int]
    xkb.xkb_state_new.restype = ctypes.c_void_p
    xkb.xkb_state_new.argtypes = [ctypes.c_void_p]
    xkb.xkb_state_key_get_one_sym.restype = ctypes.c_uint32
    xkb.xkb_state_key_get_one_sym.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    xkb.xkb_keysym_get_name.restype = ctypes.c_int
    xkb.xkb_keysym_get_name.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
    for fn in ("xkb_state_unref", "xkb_keymap_unref", "xkb_context_unref"):
        getattr(xkb, fn).argtypes = [ctypes.c_void_p]

    ctx = xkb.xkb_context_new(0)
    if not ctx:
        return {}
    names = _RuleNames(None, None, enc(kb.get("layout")) or b"us", enc(kb.get("variant")), (kb.get("options") or "").encode() or None)
    keymap = xkb.xkb_keymap_new_from_names(ctx, ctypes.byref(names), 0)
    table = {}
    if keymap:
        state = xkb.xkb_state_new(keymap)
        buf = ctypes.create_string_buffer(64)
        for code in range(8, 256):
            sym = xkb.xkb_state_key_get_one_sym(state, code)
            if sym and xkb.xkb_keysym_get_name(sym, buf, 64) > 0:
                table[str(code)] = buf.value.decode()
        xkb.xkb_state_unref(state)
        xkb.xkb_keymap_unref(keymap)
    xkb.xkb_context_unref(ctx)
    return table


# --- Editing ------------------------------------------------------------------

MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"]
KEY_NAME_RE = re.compile(r"^[A-Za-z0-9_:]+$")
STALE = "keybindings.lua changed since it was read. Refresh and try again."


def lua_quote(value):
    value = str(value)
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'


def one_line(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def key_expr(mods, key, main_mod, has_main_mod):
    """The lua expression for a combo, using mainMod like the rest of the file."""
    if not KEY_NAME_RE.match(key or ""):
        raise ValueError("Unsupported key name: %r" % key)
    mods = [m for m in MOD_ORDER if m in mods]
    if has_main_mod and main_mod in mods:
        rest = [m for m in mods if m != main_mod] + [key]
        return 'mainMod .. " + %s"' % " + ".join(rest)
    return '"%s"' % " + ".join(mods + [key])


def arg_spans(inner):
    """(start, end) of each top-level argument in a call's argument text, trimmed."""
    spans = []
    depth = 0
    quote = None
    start = 0
    i = 0

    def push(a, b):
        seg = inner[a:b]
        lead = len(seg) - len(seg.lstrip())
        trail = len(seg) - len(seg.rstrip())
        if seg.strip():
            spans.append((a + lead, b - trail))

    while i < len(inner):
        ch = inner[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
        elif ch == "," and depth == 0:
            push(start, i)
            start = i + 1
        elif inner.startswith("--", i):
            nl = inner.find("\n", i)
            i = len(inner) if nl < 0 else nl
            continue
        i += 1
    push(start, len(inner))
    return spans


def call_parts(call):
    """(prefix up to and including "hl.bind(", argument text, suffix from ")")."""
    start = call.find("hl.bind(")
    if start < 0:
        raise ValueError("Could not find the bind")
    close = find_matching(call, start + len("hl.bind") - 1)
    if close < 0:
        raise ValueError("Could not find the end of the bind")
    head = start + len("hl.bind(")
    return call[:head], call[head:close], call[close:]


def replace_arg(call, n, expr):
    head, inner, tail = call_parts(call)
    spans = arg_spans(inner)
    if len(spans) <= n:
        raise ValueError("The bind has no argument %d" % (n + 1))
    a, b = spans[n]
    return head + inner[:a] + expr + inner[b:] + tail


def replace_keys(call, expr):
    return replace_arg(call, 0, expr)


def option_value_span(table, names):
    """(start, end) of the value of `name = value` directly inside a lua table literal."""
    depth = 0
    quote = None
    i = 0
    while i < len(table):
        ch = table[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
        elif depth == 1:
            m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*", table[i:])
            if m and m.group(1) in names and (i == 0 or not re.match(r"[A-Za-z0-9_]", table[i - 1])):
                v = i + m.end()
                j = v
                d = 0
                q = None
                while j < len(table):
                    c = table[j]
                    if q:
                        if c == "\\":
                            j += 2
                            continue
                        if c == q:
                            q = None
                    elif c in "\"'":
                        q = c
                    elif c in "({[":
                        d += 1
                    elif c in ")}]":
                        if d == 0:
                            break
                        d -= 1
                    elif c == "," and d == 0:
                        break
                    j += 1
                return v, len(table[:j].rstrip())
            if m:
                i += len(m.group(1))
                continue
        i += 1
    return None


def set_description(call, description):
    head, inner, tail = call_parts(call)
    spans = arg_spans(inner)
    value = lua_quote(description)
    if len(spans) >= 3 and inner[spans[2][0]] == "{":
        a, b = spans[2]
        table = inner[a:b]
        span = option_value_span(table, ("description", "desc"))
        if span:
            table = table[: span[0]] + value + table[span[1] :]
        else:
            body = table[1:-1].rstrip()
            if body.strip() == "":
                table = "{ description = %s }" % value
            else:
                sep = " " if body.endswith(",") else ", "
                table = "{" + body + sep + "description = " + value + " }"
        return head + inner[:a] + table + inner[b:] + tail
    if len(spans) == 2:
        b = spans[1][1]
        return head + inner[:b] + ", { description = %s }" % value + inner[b:] + tail
    raise ValueError("Could not set the description of this bind")


def mark_unbound(block):
    out = []
    for line in block.split("\n"):
        indent = line[: len(line) - len(line.lstrip())]
        out.append(indent + UNBOUND_MARK + line.lstrip())
    return "\n".join(out)


def locate(text, offset, src):
    """Where src is in text: at offset when it still is, else its nearest copy."""
    if not src:
        raise ValueError(STALE)
    if offset >= 0 and text[offset : offset + len(src)] == src:
        return offset
    hits = [m.start() for m in re.finditer(re.escape(src), text)]
    if not hits:
        raise ValueError(STALE)
    return min(hits, key=lambda h: abs(h - offset))


def bind_lines(text, at, src):
    """(start, end) of the whole lines holding the bind at `at`; end excludes the newline."""
    if not owns_its_lines(text, at, at + len(src)):
        raise ValueError("This bind shares its line with other code; edit keybindings.lua by hand.")
    return line_bounds(text, at, at + len(src))


def cut_lines(text, start, end):
    """Remove text[start:end] (whole lines) and its newline; returns (text, removed)."""
    removed = text[start:end]
    if end < len(text) and text[end] == "\n":
        end += 1
    elif start > 0 and text[start - 1] == "\n":
        start -= 1
    return text[:start] + text[end:], removed


def squeeze_blank_lines(text, around):
    """Collapse a run of 3+ newlines at `around` (left by a removal) to one blank line."""
    a = around
    while a > 0 and text[a - 1] == "\n":
        a -= 1
    b = around
    while b < len(text) and text[b] == "\n":
        b += 1
    if b - a > 2:
        text = text[:a] + "\n\n" + text[b:]
    return text


def insert_lines(text, at, block):
    if at > 0 and text[at - 1] != "\n":
        block = "\n" + block
    return text[:at] + block + "\n" + text[at:]


class Editor:
    def __init__(self, text, fr):
        self.text = text
        self.fr = fr

    @property
    def main_mod(self):
        return main_mod_from(self.text)

    def sections(self):
        return parse_file(self.text, self.main_mod, self.fr)

    def section(self, ref):
        """The parsed section a {offset, src, label} reference points at."""
        sections = self.sections()
        if ref is None:
            return sections[-1] if sections else None
        offset = int(ref.get("offset", -1))
        if offset < 0:
            for s in sections:
                if s["offset"] < 0:
                    return s
            raise ValueError(STALE)
        hits = [s for s in sections if s["src"] == ref.get("src")]
        if not hits:
            raise ValueError(STALE)
        return min(hits, key=lambda s: abs(s["offset"] - offset))

    def keys(self, combo):
        has_main_mod = bool(re.search(r"local\s+mainMod\s*=", self.text))
        return key_expr(combo.get("mods", []), combo.get("key", ""), self.main_mod, has_main_mod)

    def insert_in(self, ref, block):
        sec = self.section(ref)
        at = sec["insert_at"] if sec else len(self.text)
        self.text = insert_lines(self.text, at, block)

    # Ops ---------------------------------------------------------------------

    def op_edit(self, op):
        src = op["src"]
        at = locate(self.text, int(op.get("offset", -1)), src)
        unbound = bool(op.get("unbound"))
        call = UNBOUND_RE.sub(r"\1", src) if unbound else src
        if op.get("keys"):
            call = replace_keys(call, self.keys(op["keys"]))
            unbound = False
        if op.get("command") is not None:
            if not one_line(op["command"]):
                raise ValueError("The command can't be empty")
            call = replace_arg(call, 1, "hl.dsp.exec_cmd(%s)" % lua_quote(one_line(op["command"])))
        if op.get("description") is not None:
            call = set_description(call, one_line(op["description"]))
        if unbound:
            call = mark_unbound(call)
        self.text = self.text[:at] + call + self.text[at + len(src) :]
        if op.get("section") is not None:
            if UNBOUND_RE.match(call):
                start, end = at, at + len(call)
            else:
                start, end = bind_lines(self.text, at, call)
            self.text, block = cut_lines(self.text, start, end)
            self.text = squeeze_blank_lines(self.text, min(start, len(self.text)))
            self.insert_in(op["section"], block)

    def op_add(self, op):
        command = one_line(op.get("command"))
        if not command:
            raise ValueError("The command can't be empty")
        line = "hl.bind(%s, hl.dsp.exec_cmd(%s), { description = %s })" % (
            self.keys(op["keys"]), lua_quote(command), lua_quote(one_line(op.get("description")) or command))
        self.insert_in(op.get("section"), line)

    def op_unbind(self, op):
        at = locate(self.text, int(op.get("offset", -1)), op["src"])
        start, end = bind_lines(self.text, at, op["src"])
        self.text = self.text[:start] + mark_unbound(self.text[start:end]) + self.text[end:]

    def op_delete(self, op):
        src = op["src"]
        at = locate(self.text, int(op.get("offset", -1)), src)
        start, end = (at, at + len(src)) if UNBOUND_RE.match(src) else bind_lines(self.text, at, src)
        self.text, _ = cut_lines(self.text, start, end)
        self.text = squeeze_blank_lines(self.text, min(start, len(self.text)))

    def op_add_section(self, op):
        name = one_line(op.get("name"))
        if not name:
            raise ValueError("The section needs a name")
        if any(s["label"] == name for s in self.sections()):
            raise ValueError("There already is a section called %s" % name)
        self.text = self.text.rstrip("\n") + "\n\n-- " + name + "\n"

    def op_rename_section(self, op):
        name = one_line(op.get("name"))
        if not name:
            raise ValueError("The section needs a name")
        sec = self.section(op)
        line = sec["src"]
        indent = line[: len(line) - len(line.lstrip())]
        at = sec["offset"]
        self.text = self.text[:at] + indent + "-- " + name + self.text[at + len(line) :]

    def op_delete_section(self, op):
        sec = self.section(op)
        if not sec["removable"]:
            raise ValueError("%s holds binds that can only be changed in keybindings.lua" % sec["label"])
        # Cut the binds back to front, then the heading's comment block.
        cuts = []
        for b in sec["binds"]:
            if UNBOUND_RE.match(b["src"]):
                cuts.append((b["offset"], b["offset"] + len(b["src"])))
            else:
                cuts.append(bind_lines(self.text, b["offset"], b["src"]))
        head_start = sec["offset"]
        blocks = []
        for start, end in sorted(cuts, reverse=True):
            self.text, removed = cut_lines(self.text, start, end)
            blocks.insert(0, removed)
        # The heading block: the heading line plus plain comment lines under it.
        lines = split_lines(self.text)
        idx = next(i for i, (p, _) in enumerate(lines) if p == head_start)
        j = idx + 1
        while j < len(lines) and lines[j][1].strip().startswith("--") and not is_bind_line(lines[j][1]) \
                and not lines[j][1].strip()[2:].lstrip().startswith("hl.bind"):
            j += 1
        end = lines[j - 1][0] + len(lines[j - 1][1])
        self.text, _ = cut_lines(self.text, head_start, end)
        self.text = squeeze_blank_lines(self.text, min(head_start, len(self.text)))
        if op.get("move_to") and blocks:
            self.insert_in(op["move_to"], "\n".join(blocks))
        self.text = self.text.rstrip("\n") + "\n"

    def apply(self, ops):
        for op in ops:
            handler = getattr(self, "op_" + str(op.get("op")), None)
            if handler is None:
                raise ValueError("Unknown edit: %r" % op.get("op"))
            handler(op)
        return self.text


def apply_ops(text, ops, fr=False):
    return Editor(text, fr).apply(ops)


def write_atomic(path, text):
    real = os.path.realpath(path)
    mode = os.stat(real).st_mode & 0o7777
    fd, tmp = tempfile.mkstemp(prefix=".keybinds-", dir=os.path.dirname(real))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, real)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def hypr(*args):
    try:
        return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def config_errors():
    try:
        errors = json.loads(hypr("-j", "configerrors") or "[]")
    except ValueError:
        return set()
    return {e for e in errors if e.strip()}


def apply_cmd(path, ops_json):
    try:
        ops = json.loads(ops_json)
        old = read_text(path)
        if not old:
            raise ValueError("Could not read %s" % path)
        new = apply_ops(old, ops)
    except (ValueError, KeyError, TypeError) as e:
        return {"ok": False, "error": str(e)}
    before = config_errors()
    try:
        write_atomic(path, new)
    except OSError as e:
        return {"ok": False, "error": "Could not write %s: %s" % (path, e.strerror)}
    hypr("reload", "config-only")
    added = config_errors() - before
    if added:
        write_atomic(path, old)
        hypr("reload", "config-only")
        return {"ok": False, "error": "Hyprland rejected the change, so it was undone: " + sorted(added)[0]}
    return {"ok": True, "error": ""}


def list_cmd(path, input_path):
    text = read_text(path)
    if not text:
        return {"error": "Could not read %s" % path, "path": path, "sections": [], "count": 0, "keymap": {}}
    main_mod = main_mod_from(text)
    sections = parse_file(text, main_mod, is_fr_layout(input_path))
    return {
        "error": "",
        "path": path,
        "mainMod": main_mod,
        "sections": sections,
        "count": sum(len(s["binds"]) for s in sections),
        "keymap": keysym_table(),
    }


def main():
    args = sys.argv[1:]
    cmd = args.pop(0) if args and args[0] in ("list", "apply") else "list"
    path = args[0] if args else os.path.join(HYPR, "keybindings.lua")
    if cmd == "apply":
        result = apply_cmd(path, args[1] if len(args) > 1 else "[]")
    else:
        result = list_cmd(path, args[1] if len(args) > 1 else os.path.join(HYPR, "input.lua"))
    json.dump(result, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
