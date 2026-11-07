// Search for PickerList.qml (tests: tests/picker-logic.test.js).
// Items are { key, label, detail }.

// The text one item is searched in: label, detail and key, lower case, with
// "_" and "/" as spaces (timezones: "America/New_York" matches "new york").
function haystack(item) {
    var parts = [item.label || "", item.detail || "", item.key || ""];
    return parts.join(" ").toLowerCase().replace(/[_/]/g, " ");
}

// Items whose text holds every word of QUERY (any order, case-insensitive).
// Items whose label starts with the query come first; order is kept otherwise.
function filterItems(items, query) {
    var list = items || [];
    var q = String(query || "").trim().toLowerCase().replace(/[_/]/g, " ");
    if (q === "")
        return list.slice();
    var words = q.split(/\s+/);
    var first = [];
    var rest = [];
    for (var i = 0; i < list.length; i++) {
        var text = haystack(list[i]);
        var all = true;
        for (var w = 0; w < words.length; w++) {
            if (text.indexOf(words[w]) < 0) {
                all = false;
                break;
            }
        }
        if (!all)
            continue;
        var label = String(list[i].label || "").toLowerCase().replace(/[_/]/g, " ");
        (label.indexOf(q) === 0 ? first : rest).push(list[i]);
    }
    return first.concat(rest);
}

function indexOfKey(items, key) {
    for (var i = 0; i < (items || []).length; i++)
        if (items[i].key === key)
            return i;
    return -1;
}

if (typeof module !== "undefined")
    module.exports = { haystack: haystack, filterItems: filterItems, indexOfKey: indexOfKey };
