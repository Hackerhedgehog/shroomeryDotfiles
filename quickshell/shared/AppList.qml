pragma Singleton

import Quickshell
import Quickshell.Wayland
// Desktop-entry lookup and the "pinned + running apps" list shared by the
// DockApp and the status bar's taskbar module. Each keeps its own pinned list
// and passes it to entries().
Singleton {
    id: root

    // The desktop entry for a window's app id or a pinned id, or null.
    function lookupEntry(appId: string): var {
        if (!appId)
            return null
        const direct = DesktopEntries.heuristicLookup(appId)
        if (direct)
            return direct
        // Pinned ids inherited from nwg-dock are executable names
        // ("claude-desktop"), which heuristicLookup does not match against an
        // entry named differently (com.anthropic.Claude). Fall back to the first
        // entry whose command runs that executable.
        const wanted = appId.toLowerCase()
        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; i++) {
            const command = apps[i].command
            if (!command || command.length === 0)
                continue
            if (`${command[0]}`.split("/").pop().toLowerCase() === wanted)
                return apps[i]
        }
        return null
    }

    // Group key shared by windows and pinned entries: the desktop entry id when
    // one can be found for the window's app id (so "org.mozilla.firefox",
    // "firefox" and the pinned "firefox" all land in the same slot), otherwise
    // the lowercased app id.
    function entryKey(appId: string): string {
        if (!appId)
            return ""
        const entry = root.lookupEntry(appId)
        return entry ? entry.id : appId.toLowerCase()
    }

    // Icon file for an app: the desktop entry's icon when there is one,
    // otherwise the app id itself as an icon-theme name — which is how apps
    // without an installed desktop entry (e.g. a pinned "obsidian") still get
    // their themed icon. The provider prefix and query string a desktop entry
    // may carry are stripped, the same way the overview does it.
    function iconFor(entry: var, appId: string): string {
        const raw = `${entry?.icon ?? ""}`.trim()
            .replace(/^image:\/\/icon\//, "").split("?")[0].trim()
        const name = raw.length > 0 ? raw : (appId ? appId : "")
        return Quickshell.iconPath(
            name.length > 0 ? name : "application-x-executable",
            "application-x-executable")
    }

    // The items for a dock/taskbar: the given pinned apps first, in their order,
    // followed by the running apps that are not pinned. Each item groups all
    // windows of one app and carries everything an AppButton needs:
    //   { key, appId, desktopEntry, name, iconSource, windows: [Toplevel], pinned }
    // Call it from a binding: it reads the toplevel and desktop-entry lists, so
    // the binding re-runs when windows open/close or entries are reindexed.
    function entries(pinned: var): var {
        DesktopEntries.applications.values
        const toplevels = ToplevelManager.toplevels.values
        let byKey = ({})
        let order = []

        function makeItem(key, appId, isPinned) {
            const desktopEntry = root.lookupEntry(appId)
            const name = desktopEntry && desktopEntry.name.length > 0
                ? desktopEntry.name : appId
            return { "key": key, "appId": appId, "desktopEntry": desktopEntry,
                     "name": name, "iconSource": root.iconFor(desktopEntry, appId),
                     "windows": [], "pinned": isPinned }
        }

        for (let i = 0; i < pinned.length; i++) {
            const key = root.entryKey(pinned[i])
            if (key === "" || byKey[key] !== undefined)
                continue
            byKey[key] = makeItem(key, pinned[i], true)
            order.push(key)
        }

        for (let i = 0; i < toplevels.length; i++) {
            const toplevel = toplevels[i]
            const key = root.entryKey(toplevel.appId)
            if (key === "")
                continue
            if (byKey[key] === undefined) {
                byKey[key] = makeItem(key, toplevel.appId, false)
                order.push(key)
            }
            byKey[key].windows.push(toplevel)
        }

        return order.map(key => byKey[key])
    }

    // Whether an app key is in a pinned list. Compared on resolved keys, not on
    // the raw strings: a stored id may be an executable name ("claude-desktop")
    // while the key is the desktop entry id it resolves to (com.anthropic.Claude).
    function isPinned(pinned: var, key: string): bool {
        for (let i = 0; i < pinned.length; i++)
            if (root.entryKey(pinned[i]) === key)
                return true
        return false
    }

    // The pinned list with key appended, or null when it is already there.
    function withPinned(pinned: var, key: string): var {
        if (!key || root.isPinned(pinned, key))
            return null
        return pinned.concat([key])
    }

    // The pinned list without key.
    function withoutPinned(pinned: var, key: string): var {
        return pinned.filter(id => root.entryKey(id) !== key)
    }
}
