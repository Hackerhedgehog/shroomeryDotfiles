//
// The rules behind the status bar popouts (PopoutState.qml): which panel is
// open, on which monitor, from which bar button, and whether it is pinned.
// Deliberately free of QML imports and of `.pragma library` so the same file
// loads in QML and in Node for the unit tests (like AudioApp/Loudness.js).
//
// state: { name, screen, anchor, pinned, pending }
//   name     open panel, "" when closed; screen: the monitor showing it
//   anchor   the bar button it grew out of (opaque here), null for IPC
//   pinned   opened by a press inside, IPC or the keyboard: the pointer
//            leaving does not close it
//   pending  { screen, name, anchor } waiting for the hover-open delay
// Events: hover, unhover, openTimer, pointer, closeTimer, press, click, open,
// toggle, close, forget (a button went away), forgetScreen (a bar went away).
//
// Most bar buttons open their panel on click only (pinned); once a panel is
// pinned, hovering another button moves it there. Buttons whose hover event
// has `opens: true` (the taskbar's window lists) also open on hover, unpinned.
//
// reduce(state, event) returns { state, effects }; PopoutState runs the
// effects: "startOpenTimer" / "stopOpenTimer" (150 ms hover delay) and
// "startCloseTimer" / "stopCloseTimer" (300 ms grace after leaving).

function initial() {
    return { name: "", screen: "", anchor: null, pinned: false, pending: null };
}

function withChanges(state, changes) {
    return Object.assign({}, state, changes);
}

function result(state, effects) {
    return { state: state, effects: effects || [] };
}

function opened(name, screen, anchor, pinned) {
    return { name: name, screen: screen, anchor: anchor, pinned: pinned, pending: null };
}

function reduce(state, ev) {
    switch (ev.type) {
    case "hover":
        // Already open (on any monitor): move over at once, keep pinned. A
        // click-only button takes over only a pinned panel, so a window list
        // that hover opened does not turn into it.
        if (state.name !== "" && (ev.opens || state.pinned))
            return result(withChanges(state, { name: ev.name, screen: ev.screen, anchor: ev.anchor, pending: null }),
                          ["stopOpenTimer", "stopCloseTimer"]);
        if (state.name !== "" || !ev.opens)
            return result(state);
        return result(withChanges(state, { pending: { screen: ev.screen, name: ev.name, anchor: ev.anchor } }),
                      ["startOpenTimer"]);

    case "unhover":
        if (state.pending && state.pending.anchor === ev.anchor)
            return result(withChanges(state, { pending: null }), ["stopOpenTimer"]);
        return result(state);

    case "openTimer":
        if (!state.pending || state.name !== "")
            return result(withChanges(state, { pending: null }));
        return result(opened(state.pending.name, state.pending.screen, state.pending.anchor, false));

    case "pointer":
        if (state.name === "" || ev.screen !== state.screen)
            return result(state);
        if (ev.inside)
            return result(state, ["stopCloseTimer"]);
        return result(state, state.pinned ? [] : ["startCloseTimer"]);

    case "closeTimer":
        if (state.name === "" || state.pinned)
            return result(state);
        return result(initial());

    case "press":
        if (state.name === "")
            return result(state);
        return result(withChanges(state, { pinned: true }), ["stopCloseTimer"]);

    case "click":
        // A bar button: clicking the button whose panel is open closes it,
        // any other opens its panel pinned.
        if (state.name === ev.name && state.anchor === ev.anchor)
            return result(initial(), ["stopOpenTimer", "stopCloseTimer"]);
        return reduce(state, { type: "open", name: ev.name, screen: ev.screen, anchor: ev.anchor });

    case "open":
        return result(opened(ev.name, ev.screen, ev.anchor, true), ["stopOpenTimer", "stopCloseTimer"]);

    case "toggle":
        if (state.name === ev.name)
            return result(initial(), ["stopOpenTimer", "stopCloseTimer"]);
        return reduce(state, { type: "open", name: ev.name, screen: ev.screen, anchor: ev.anchor });

    case "close":
        if (ev.name !== undefined && ev.name !== state.name)
            return result(state);
        return result(initial(), ["stopOpenTimer", "stopCloseTimer"]);

    case "forget":
        if (state.name !== "" && state.anchor === ev.anchor)
            return result(initial(), ["stopOpenTimer", "stopCloseTimer"]);
        if (state.pending && state.pending.anchor === ev.anchor)
            return result(withChanges(state, { pending: null }), ["stopOpenTimer"]);
        return result(state);

    case "forgetScreen":
        // A monitor (and its bar) went away: close what it showed, also when
        // it was opened through IPC without a button.
        if (state.name !== "" && state.screen === ev.screen)
            return result(initial(), ["stopOpenTimer", "stopCloseTimer"]);
        if (state.pending && state.pending.screen === ev.screen)
            return result(withChanges(state, { pending: null }), ["stopOpenTimer"]);
        return result(state);
    }
    return result(state);
}

if (typeof module !== "undefined") {
    module.exports = { initial: initial, reduce: reduce };
}
