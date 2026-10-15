// Keybind logic for the Keybinds panel: naming a captured key press the way
// Hyprland does, comparing combos, finding clashes and labelling keys.
// Free of QML imports and of `.pragma library` so it loads in QML and in Node
// for the unit tests.

// Modifiers in the order they are written ("SUPER + CTRL + ALT + SHIFT + Q").
var MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"];

var MOD_ALIASES = {
    "SUPER": "SUPER", "WIN": "SUPER", "LOGO": "SUPER", "MOD4": "SUPER", "META": "SUPER",
    "CTRL": "CTRL", "CONTROL": "CTRL",
    "ALT": "ALT", "MOD1": "ALT",
    "SHIFT": "SHIFT"
};

// Qt.KeyboardModifier bits.
var QT_MODS = [
    [0x10000000, "SUPER"],   // Qt.MetaModifier (the Super/Windows key on Wayland)
    [0x04000000, "CTRL"],    // Qt.ControlModifier
    [0x08000000, "ALT"],     // Qt.AltModifier
    [0x02000000, "SHIFT"]    // Qt.ShiftModifier
];

// Qt.Key values of keys that only modify (Shift, Control, Meta, Alt, AltGr,
// Super_L/R, Hyper_L/R, CapsLock, NumLock).
var QT_MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01001103,
    0x01000053, 0x01000054, 0x01000056, 0x01000057, 0x01000024, 0x01000025];

var MODIFIER_KEYSYMS = /^(Shift|Control|Alt|Meta|Super|Hyper)_[LR]$|^(ISO_Level[35]_(Shift|Latch|Lock)|Caps_Lock|Num_Lock|Mode_switch|ISO_Group_Shift)$/;

// Fallback names for keys missing from the keymap (Qt.Key -> keysym).
var QT_KEY_NAMES = {
    0x01000000: "Escape", 0x01000001: "Tab", 0x01000003: "BackSpace", 0x01000004: "Return",
    0x01000005: "KP_Enter", 0x01000006: "Insert", 0x01000007: "Delete", 0x01000009: "Print",
    0x01000010: "Home", 0x01000011: "End", 0x01000012: "Left", 0x01000013: "Up",
    0x01000014: "Right", 0x01000015: "Down", 0x01000016: "Prior", 0x01000017: "Next",
    0x20: "space",
    0x01000070: "XF86AudioLowerVolume", 0x01000071: "XF86AudioMute", 0x01000072: "XF86AudioRaiseVolume",
    0x01000080: "XF86AudioPlay", 0x01000081: "XF86AudioStop", 0x01000082: "XF86AudioPrev",
    0x01000083: "XF86AudioNext", 0x01000085: "XF86AudioPause",
    0x010000f2: "XF86MonBrightnessUp", 0x010000f3: "XF86MonBrightnessDown",
    0x01000113: "XF86AudioMicMute", 0x01100004: "XF86Calculator"
};

// How a key is shown on a key cap.
var KEY_LABELS = {
    "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
    "mouse:275": "Thumb 1", "mouse:276": "Thumb 2", "mouse:277": "Thumb 3", "mouse:278": "Thumb 4",
    "mouse_down": "Scroll down", "mouse_up": "Scroll up",
    "mouse_left": "Scroll left", "mouse_right": "Scroll right",
    "xf86audioraisevolume": "Volume up", "xf86audiolowervolume": "Volume down",
    "xf86audiomute": "Mute", "xf86audiomicmute": "Mic mute",
    "xf86monbrightnessup": "Brightness up", "xf86monbrightnessdown": "Brightness down",
    "xf86audionext": "Next track", "xf86audioprev": "Previous track",
    "xf86audioplay": "Play", "xf86audiopause": "Pause", "xf86audiostop": "Stop",
    "control": "CTRL",
    "period": ".", "comma": ",", "minus": "-", "plus": "+", "equal": "=", "slash": "/",
    "backslash": "\\", "semicolon": ";", "apostrophe": "'", "grave": "`", "less": "<",
    "bracketleft": "[", "bracketright": "]",
    "left": "←", "right": "→", "up": "↑", "down": "↓",
    "return": "Enter", "kp_enter": "Enter", "print": "Print", "space": "Space", "tab": "Tab",
    "escape": "Esc", "backspace": "Backspace", "delete": "Delete", "insert": "Insert",
    "home": "Home", "end": "End", "prior": "Page up", "next": "Page down",
    "udiaeresis": "Ü", "otilde": "Õ", "odiaeresis": "Ö", "adiaeresis": "Ä",
    "scaron": "Š", "zcaron": "Ž"
};

function splitKeys(keys) {
    return String(keys || "").split("+").map(function (s) { return s.trim(); }).filter(function (s) { return s !== ""; });
}

// "SUPER + SHIFT + Q" -> { mods: ["SUPER", "SHIFT"], key: "Q" }.
function parseKeys(keys) {
    var parts = splitKeys(keys);
    var mods = [];
    var key = "";
    for (var i = 0; i < parts.length; i++) {
        var mod = MOD_ALIASES[parts[i].toUpperCase()];
        if (mod && i < parts.length - 1) {
            if (mods.indexOf(mod) < 0)
                mods.push(mod);
        } else {
            key = parts[i];
        }
    }
    return { mods: sortMods(mods), key: key };
}

function sortMods(mods) {
    return MOD_ORDER.filter(function (m) { return mods.indexOf(m) >= 0; });
}

// The string a combo is written as in keybindings.lua.
function keysString(mods, key) {
    return sortMods(mods).concat([key]).join(" + ");
}

// Comparable form of a combo: keysym names are case-insensitive in Hyprland.
function comboId(mods, key) {
    if (!key)
        return "";
    return sortMods(mods).join("+") + "|" + String(key).toLowerCase();
}

function comboIdOf(keys) {
    var c = parseKeys(keys);
    return comboId(c.mods, c.key);
}

function keyLabel(key) {
    var label = KEY_LABELS[String(key).toLowerCase()];
    if (label !== undefined)
        return label;
    return key.length === 1 ? key.toUpperCase() : key;
}

// Key caps for a combo string.
function chips(keys) {
    var c = parseKeys(keys);
    if (!c.key)
        return [];
    return c.mods.concat([keyLabel(c.key)]);
}

function modsFromQt(modifiers) {
    var out = [];
    for (var i = 0; i < QT_MODS.length; i++) {
        if (modifiers & QT_MODS[i][0])
            out.push(QT_MODS[i][1]);
    }
    return out;
}

// Qt.Key of a modifier key -> the modifier it is.
var QT_KEY_MODS = {
    0x01000020: "SHIFT", 0x01000021: "CTRL", 0x01000022: "SUPER", 0x01000023: "ALT",
    0x01000053: "SUPER", 0x01000054: "SUPER"
};

// Modifiers held after a press or release of qtKey: Qt may report the state
// from before the event, so the key itself is added or taken out.
function heldMods(qtKey, modifiers, pressed) {
    var mods = modsFromQt(modifiers);
    var own = QT_KEY_MODS[qtKey];
    if (own !== undefined) {
        if (pressed && mods.indexOf(own) < 0)
            mods.push(own);
        if (!pressed)
            mods = mods.filter(function (m) { return m !== own; });
    }
    return sortMods(mods);
}

// Name a key press for keybindings.lua. `keymap` maps xkb keycodes (Qt's
// nativeScanCode on Wayland) to the unshifted keysym on the active layout,
// which is what Hyprland matches binds against. Returns null for a press of a
// modifier on its own.
function comboFromEvent(qtKey, modifiers, scanCode, keymap) {
    if (QT_MODIFIER_KEYS.indexOf(qtKey) >= 0)
        return null;
    var name = keymap ? keymap[String(scanCode)] : undefined;
    if (name !== undefined && MODIFIER_KEYSYMS.test(name))
        return null;
    if (name === undefined || name === "" || name === "NoSymbol")
        name = qtKeyName(qtKey);
    if (!name)
        return null;
    if (name.length === 1)
        name = name.toUpperCase();
    return { mods: modsFromQt(modifiers), key: name };
}

function qtKeyName(qtKey) {
    if (QT_KEY_NAMES[qtKey] !== undefined)
        return QT_KEY_NAMES[qtKey];
    if ((qtKey >= 0x30 && qtKey <= 0x39) || (qtKey >= 0x41 && qtKey <= 0x5a))
        return String.fromCharCode(qtKey);
    if (qtKey >= 0x01000030 && qtKey <= 0x01000052)   // Qt.Key_F1 .. Qt.Key_F35
        return "F" + (qtKey - 0x01000030 + 1);
    return "";
}

// A mouse button press, named like Hyprland does: "mouse:" + the evdev code.
// Qt numbers the buttons 1 << (code - BTN_LEFT): left 272, right 273, middle
// 274, then the side/thumb buttons 275, 276, ...
function comboFromMouse(qtButton, modifiers) {
    if (!qtButton || qtButton <= 0)
        return null;
    var bit = 0;
    while ((1 << bit) !== qtButton && bit < 30)
        bit++;
    if ((1 << bit) !== qtButton)
        return null;
    return { mods: modsFromQt(modifiers), key: "mouse:" + (272 + bit) };
}

// A wheel step. Hyprland names physical scroll down "mouse_down"; Qt's
// angleDelta is positive for up and for left.
function comboFromWheel(dx, dy, modifiers) {
    var key = "";
    if (Math.abs(dy) >= Math.abs(dx) && dy !== 0)
        key = dy > 0 ? "mouse_up" : "mouse_down";
    else if (dx !== 0)
        key = dx > 0 ? "mouse_left" : "mouse_right";
    return key ? { mods: modsFromQt(modifiers), key: key } : null;
}

function isMouseButton(key) {
    return /^mouse:\d+$/.test(String(key));
}

// Keys that may be bound on their own: anything else (letters, Return,
// clicks, scrolling…) would stop working everywhere else.
function needsModifier(mods, key) {
    if (mods.length > 0)
        return false;
    return !/^(F\d+|XF86.*|Print|Pause|Scroll_Lock|Menu|Help|Cancel|mouse:(27[5-9]|2[89]\d))$/i.test(String(key));
}

// Why a combo can't be saved for this bind, or "".
function comboProblem(combo, dragBind) {
    if (!combo)
        return "";
    if (dragBind && !isMouseButton(combo.key))
        return "A drag bind needs a mouse button";
    if (needsModifier(combo.mods, combo.key))
        return "Add SUPER, CTRL, ALT or SHIFT, or " + keyLabel(combo.key) + " stops working everywhere else";
    return "";
}

// Bound binds other than `self` that already use the combo.
function conflicts(binds, mods, key, self) {
    var id = comboId(mods, key);
    if (id === "")
        return [];
    return binds.filter(function (b) {
        return b !== self && !b.unbound && comboIdOf(b.keys) === id
            && !(self && b.offset >= 0 && b.offset === self.offset);
    });
}

// Flatten the parsed sections for the list: a bind matches when every word of
// the query is in its keys, labels, description or command. `section` limits
// it to one section ("" = all). The first bind of each section gets `header`.
function visibleBinds(sections, query, section) {
    var words = String(query || "").toLowerCase().split(/\s+/).filter(function (w) { return w !== ""; });
    var out = [];
    for (var s = 0; s < sections.length; s++) {
        if (section !== "" && sections[s].label !== section)
            continue;
        var first = true;
        var binds = sections[s].binds || [];
        for (var i = 0; i < binds.length; i++) {
            var b = binds[i];
            var hay = [b.unbound ? "not bound" : b.keys, chips(b.keys).join(" "), b.description, b.command, sections[s].label]
                .join(" ").toLowerCase();
            if (!words.every(function (w) { return hay.indexOf(w) >= 0; }))
                continue;
            out.push({ bind: b, header: first ? sections[s].label : "" });
            first = false;
        }
    }
    return out;
}

if (typeof module !== "undefined") {
    module.exports = {
        MOD_ORDER: MOD_ORDER, parseKeys: parseKeys, keysString: keysString, comboId: comboId,
        comboIdOf: comboIdOf, keyLabel: keyLabel, chips: chips, modsFromQt: modsFromQt, heldMods: heldMods,
        comboFromEvent: comboFromEvent, comboFromMouse: comboFromMouse,
        comboFromWheel: comboFromWheel, isMouseButton: isMouseButton, needsModifier: needsModifier,
        comboProblem: comboProblem, conflicts: conflicts, visibleBinds: visibleBinds
    };
}
