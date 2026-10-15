//
// How the launcher filters its lists. Free of QML imports and of
// `.pragma library` so it loads in QML and in Node for the unit tests.
//
// filter(items, query, nameOf, fieldsOf): the items where every word of the
// query occurs (case-insensitively) in the name or one of the other fields,
// best first: name starts with the query, then name contains it, then the
// rest. Ties keep the input order, so a sorted input stays sorted.
function filter(items, query, nameOf, fieldsOf) {
    var words = `${query}`.toLowerCase().split(/\s+/).filter(function (w) { return w.length > 0; });
    if (words.length === 0)
        return items.slice();
    var whole = words.join(" ");
    var ranked = [];
    for (var i = 0; i < items.length; i++) {
        var name = `${nameOf(items[i]) || ""}`.toLowerCase();
        var haystack = [name].concat(fieldsOf(items[i]).map(function (f) {
            return `${f || ""}`.toLowerCase();
        })).join("\n");
        var all = true;
        for (var w = 0; w < words.length && all; w++)
            all = haystack.indexOf(words[w]) !== -1;
        if (!all)
            continue;
        var rank = name.indexOf(whole) === 0 ? 0 : (name.indexOf(whole) !== -1 ? 1 : 2);
        ranked.push({ item: items[i], rank: rank, index: i });
    }
    ranked.sort(function (a, b) { return a.rank - b.rank || a.index - b.index; });
    return ranked.map(function (r) { return r.item; });
}

if (typeof module !== "undefined") {
    module.exports = { filter: filter };
}
