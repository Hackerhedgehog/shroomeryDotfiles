pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.shared
import "KeybindsLogic.js" as Logic

// Keybinds read from Hyprland's keybindings.lua (Paths.hyprKeybinds) by
// keybinds.py, and the editing: record a shortcut (keys, mouse buttons or the
// wheel), check it against the other binds, add / change / move / delete binds
// and sections, write the file back and reload Hyprland (all in keybinds.py).
//
// While a shortcut is being recorded Hyprland sits in an empty submap
// (qs_keybind_capture) so its own binds don't fire and every key reaches the
// panel. A Hyprland timer drops back to the default submap after 20 s even if
// the shell dies mid-capture.
Singleton {
    id: root

    readonly property string helperPath: Quickshell.shellPath("KeybindsApp/keybinds.py")

    property bool panelOpen: false
    property bool refreshing: false
    property var sections: []
    property int count: 0
    property string errorMessage: ""
    property string query: ""
    // Label of the section shown alone, "" for all.
    property string section: ""
    // xkb keycode -> unshifted keysym name, for naming captured keys.
    property var keymap: ({})

    readonly property var allBinds: {
        const out = [];
        for (let s = 0; s < sections.length; s++)
            for (let i = 0; i < (sections[s].binds || []).length; i++)
                out.push(sections[s].binds[i]);
        return out;
    }

    // What the list shows: { bind, header } with header set on a section's first row.
    readonly property var rows: Logic.visibleBinds(sections, query, section)

    readonly property string statusLabel: {
        if (refreshing && count === 0)
            return "Reading…";
        if (errorMessage !== "" && count === 0)
            return "Unavailable";
        if (query.trim() !== "" || section !== "")
            return rows.length + " / " + count;
        if (count === 0)
            return "None";
        return count + " binds";
    }

    // Short-lived note under the title ("Saved", "Can't run this one", …).
    property string banner: ""
    property bool bannerError: false

    function notify(text, isError) {
        banner = text;
        bannerError = !!isError;
        bannerTimer.restart();
    }

    Timer {
        id: bannerTimer
        interval: 4000
        onTriggered: root.banner = ""
    }

    // --- Reading -------------------------------------------------------------

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: root._ingest(text)
        }
        onExited: exitCode => {
            root.refreshing = false;
            if (exitCode !== 0 && root.sections.length === 0)
                root.errorMessage = "Could not read Hyprland keybinds.";
        }
    }

    function refresh() {
        refreshing = true;
        errorMessage = "";
        listProc.exec(["python3", helperPath, "list", Paths.hyprKeybinds, Paths.hyprInput]);
    }

    function _ingest(text) {
        try {
            const parsed = JSON.parse((text || "").trim() || "{}");
            root.sections = parsed.sections || [];
            root.count = parsed.count || 0;
            root.keymap = parsed.keymap || {};
            root.errorMessage = parsed.error || "";
            if (root.section !== "" && !root.sections.some(s => s.label === root.section))
                root.section = "";
        } catch (e) {
            root.sections = [];
            root.count = 0;
            root.errorMessage = "Could not parse the keybind list.";
        }
    }

    // --- Running -------------------------------------------------------------

    // Returns false when the bind has nothing that can be run from here.
    function run(bind) {
        if (!bind || !bind.runnable)
            return false;
        if (bind.kind === "exec") {
            Quickshell.execDetached(["bash", "-c", bind.command]);
            return true;
        }
        const cmds = bind.commands || [];
        for (let i = 0; i < cmds.length; i++) {
            if (cmds[i])
                Hyprland.dispatch(cmds[i]);
        }
        return true;
    }

    // --- Editor ----------------------------------------------------------------

    // The editor sheet: `editing` is the bind being changed, null for a new one.
    // `combo` is a newly recorded shortcut (null keeps the current one).
    property bool editorOpen: false
    property var editing: null
    property bool recording: false
    property var combo: null
    property var heldMods: []
    property bool saving: false
    property string editError: ""

    readonly property bool isNew: editorOpen && editing === null
    // Drag binds (move/resize with the mouse) only take mouse buttons.
    readonly property bool dragBind: !!(editing && editing.mouse && editing.kind !== "exec")
    readonly property var clashes: combo ? Logic.conflicts(allBinds, combo.mods, combo.key, editing) : []
    readonly property bool canClearClashes: clashes.every(b => b.clearable)
    readonly property string comboProblem: Logic.comboProblem(combo, dragBind)
    readonly property bool comboUnchanged: !!(editing && combo && !editing.unbound
        && Logic.comboIdOf(editing.keys) === Logic.comboId(combo.mods, combo.key))
    // The shortcut the editor shows: the recorded one, else the bind's own.
    readonly property string shownKeys: combo ? Logic.keysString(combo.mods, combo.key)
        : (editing && !editing.unbound ? editing.keys : "")

    function openEditor(bind) {
        if (!bind)
            return;
        if (!bind.editable) {
            notify(bind.reason || "This bind can only be changed in keybindings.lua", true);
            return;
        }
        editing = bind;
        combo = null;
        editError = "";
        editorOpen = true;
        startRecording();
    }

    function newBind() {
        editing = null;
        combo = null;
        editError = "";
        stopRecording();
        editorOpen = true;
    }

    function closeEditor() {
        stopRecording();
        editorOpen = false;
        editing = null;
        combo = null;
        editError = "";
    }

    function startRecording() {
        heldMods = [];
        editError = "";
        recording = true;
        captureTimeout.restart();
    }

    function stopRecording() {
        captureTimeout.stop();
        recording = false;
        heldMods = [];
    }

    Timer {
        id: captureTimeout
        interval: 15000
        onTriggered: root.stopRecording()
    }

    function _recorded(c) {
        if (!c)
            return false;
        combo = c;
        stopRecording();
        return true;
    }

    // Key events from the editor while recording. Returns true when used.
    function captureKey(event, pressed) {
        if (!recording)
            return false;
        if (event.isAutoRepeat)
            return true;
        if (!pressed) {
            heldMods = Logic.heldMods(event.key, event.modifiers, false);
            return true;
        }
        const c = Logic.comboFromEvent(event.key, event.modifiers, event.nativeScanCode, keymap);
        if (!c)
            heldMods = Logic.heldMods(event.key, event.modifiers, true);
        else
            _recorded(c);
        return true;
    }

    function captureMouse(button, modifiers) {
        return recording && _recorded(Logic.comboFromMouse(button, modifiers));
    }

    function captureWheel(dx, dy, modifiers) {
        return recording && _recorded(Logic.comboFromWheel(dx, dy, modifiers));
    }

    function sectionRef(label) {
        const s = sections.find(x => x.label === label);
        return s ? { "offset": s.offset, "src": s.src, "label": s.label } : null;
    }

    function _clearOps() {
        const ops = [];
        const seen = {};
        for (let i = 0; i < clashes.length; i++) {
            const c = clashes[i];
            if (seen[c.offset])
                continue;
            seen[c.offset] = true;
            ops.push({ "op": "unbind", "offset": c.offset, "src": c.src });
        }
        return ops;
    }

    // draft: { description, command, section } from the editor's fields.
    // clashMode: "keep" leaves binds on the same shortcut alone, "clear" unbinds them.
    function save(draft, clashMode) {
        if (!editorOpen || saving || recording || comboProblem !== "")
            return;
        if (clashes.length > 0 && clashMode === "clear" && !canClearClashes)
            return;
        const description = (draft.description || "").trim();
        const command = (draft.command || "").trim();
        const ops = clashes.length > 0 && clashMode === "clear" ? _clearOps() : [];
        let label = "";

        if (isNew) {
            if (!combo) {
                editError = "Record a shortcut first";
                return;
            }
            if (command === "") {
                editError = "Type the command to run";
                return;
            }
            ops.push({
                "op": "add",
                "section": sectionRef(draft.section),
                "keys": combo,
                "command": command,
                "description": description
            });
            label = (description || command) + " added";
        } else {
            const op = { "op": "edit", "offset": editing.offset, "src": editing.src, "unbound": !!editing.unbound };
            let changed = false;
            if (combo && !comboUnchanged) {
                op.keys = combo;
                changed = true;
            }
            if (description !== (editing.hasDescription ? editing.description : "")) {
                op.description = description;
                changed = true;
            }
            if (editing.kind === "exec" && command !== editing.command) {
                if (command === "") {
                    editError = "The command can't be empty";
                    return;
                }
                op.command = command;
                changed = true;
            }
            if (draft.section && draft.section !== editing.section) {
                op.section = sectionRef(draft.section);
                changed = true;
            }
            if (!changed) {
                closeEditor();
                return;
            }
            ops.push(op);
            label = (description || editing.description) + (op.keys ? " → " + Logic.chips(shownKeys).join(" + ") : " updated");
        }
        if (clashMode === "clear" && clashes.length > 0)
            label += " (other bind cleared)";
        _apply(ops, label);
    }

    // Take the shortcut off the edited bind; it stays listed as not bound.
    function unbindEditing() {
        if (editing && !editing.unbound && editing.clearable)
            _apply([{ "op": "unbind", "offset": editing.offset, "src": editing.src }], editing.description + " is no longer bound");
    }

    function deleteEditing() {
        if (editing && editing.movable)
            _apply([{ "op": "delete", "offset": editing.offset, "src": editing.src }], editing.description + " deleted");
    }

    // --- Sections ---------------------------------------------------------------

    function addSection(name) {
        name = (name || "").trim();
        if (name === "")
            return;
        if (sections.some(s => s.label === name)) {
            notify("There already is a section called " + name, true);
            return;
        }
        _apply([{ "op": "add_section", "name": name }], "Section " + name + " added");
    }

    function renameSection(label, name) {
        name = (name || "").trim();
        const ref = sectionRef(label);
        if (!ref || name === "" || name === label)
            return;
        if (sections.some(s => s.label === name)) {
            notify("There already is a section called " + name, true);
            return;
        }
        _apply([Object.assign({ "op": "rename_section", "name": name }, ref)], label + " renamed to " + name);
        if (section === label)
            section = name;
    }

    // moveTo: label of the section its binds go to, "" to delete them too.
    function deleteSection(label, moveTo) {
        const ref = sectionRef(label);
        if (!ref)
            return;
        const op = Object.assign({ "op": "delete_section" }, ref);
        if (moveTo)
            op.move_to = sectionRef(moveTo);
        _apply([op], "Section " + label + " deleted" + (moveTo ? ", its binds moved to " + moveTo : ""));
        if (section === label)
            section = "";
    }

    // --- Saving -----------------------------------------------------------------

    property string _successMessage: ""

    Process {
        id: applyProc
        stdout: StdioCollector {
            onStreamFinished: root._applied(text)
        }
    }

    function _apply(ops, successMessage) {
        stopRecording();
        _successMessage = successMessage;
        editError = "";
        saving = true;
        applyProc.exec(["python3", helperPath, "apply", Paths.hyprKeybinds, JSON.stringify(ops)]);
    }

    function _applied(text) {
        saving = false;
        let result = null;
        try {
            result = JSON.parse((text || "").trim());
        } catch (e) {
            result = { "ok": false, "error": "The keybind helper failed." };
        }
        if (result.ok) {
            closeEditor();
            notify("Saved: " + _successMessage, false);
        } else if (editorOpen) {
            editError = result.error || "Could not save the change.";
        } else {
            notify(result.error || "Could not save the change.", true);
        }
        refresh();
    }

    // --- Capture submap --------------------------------------------------------

    readonly property bool wantSubmap: recording && panelOpen
    property bool submapActive: false

    readonly property string enterSubmapLua: [
        'if QS_KB_BIND then pcall(function() QS_KB_BIND:remove() end) end',
        'hl.define_submap("qs_keybind_capture", function()',
        '  QS_KB_BIND = hl.bind("SUPER + CTRL + ALT + SHIFT + F12", hl.dsp.submap("reset"), { description = "Leave keybind capture" })',
        'end)',
        'QS_KB_GEN = (QS_KB_GEN or 0) + 1',
        'local gen = QS_KB_GEN',
        'hl.dispatch(hl.dsp.submap("qs_keybind_capture"))',
        'hl.timer(function()',
        '  if QS_KB_GEN == gen and hl.get_current_submap() == "qs_keybind_capture" then hl.dispatch(hl.dsp.submap("reset")) end',
        'end, { timeout = 20000, type = "oneshot" })'
    ].join("\n")

    onWantSubmapChanged: _syncSubmap()

    // One hyprctl call at a time, so a quick cancel can't overtake the enter.
    function _syncSubmap() {
        if (submapProc.running || wantSubmap === submapActive)
            return;
        submapActive = wantSubmap;
        submapProc.exec(wantSubmap ? ["hyprctl", "eval", enterSubmapLua] : ["hyprctl", "dispatch", 'hl.dsp.submap("reset")']);
    }

    Process {
        id: submapProc
        onRunningChanged: if (!running) root._syncSubmap()
    }
}
