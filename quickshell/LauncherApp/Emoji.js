//
// Data for the launcher's emoji tab. Free of QML imports and of
// `.pragma library` so it loads in QML and in Node for the unit tests.
//
// emojis.tsv rows are emoji<TAB>group<TAB>name<TAB>keywords, with the
// Unicode group names below; lines starting with # are comments.

// The category tabs above the grid, in Unicode order.
var CATEGORIES = [
    { key: "smileys", group: "Smileys & Emotion", icon: "😀", label: "Smileys & Emotion" },
    { key: "people", group: "People & Body", icon: "👋", label: "People & Body" },
    { key: "nature", group: "Animals & Nature", icon: "🐻", label: "Animals & Nature" },
    { key: "food", group: "Food & Drink", icon: "🍔", label: "Food & Drink" },
    { key: "travel", group: "Travel & Places", icon: "✈️", label: "Travel & Places" },
    { key: "activities", group: "Activities", icon: "⚽", label: "Activities" },
    { key: "objects", group: "Objects", icon: "💡", label: "Objects" },
    { key: "symbols", group: "Symbols", icon: "🔣", label: "Symbols" },
    { key: "flags", group: "Flags", icon: "🏁", label: "Flags" }
];

// [{ emoji, category, name, keywords }] from the TSV text.
function parse(text) {
    var keyOf = {};
    for (var c = 0; c < CATEGORIES.length; c++)
        keyOf[CATEGORIES[c].group] = CATEGORIES[c].key;
    var list = [];
    var lines = `${text}`.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line === "" || line[0] === "#")
            continue;
        var parts = line.split("\t");
        if (parts.length < 3 || keyOf[parts[1]] === undefined)
            continue;
        list.push({
            emoji: parts[0],
            category: keyOf[parts[1]],
            name: parts[2],
            keywords: parts.length > 3 ? parts[3] : ""
        });
    }
    return list;
}

// The cell after moving `step` cells (±1 for a column, ±columns for a row),
// kept inside a grid of `count` cells.
function gridMove(index, step, count) {
    if (count <= 0)
        return 0;
    return Math.max(0, Math.min(count - 1, index + step));
}

// Left (dir -1) or Right (+1) in a grid of `count` cells, `columns` wide:
// { index, category: 0 } for a step within the row, or, from the first column
// going left / the last column or last cell going right,
// { index: -1, category: dir, row } to continue in the neighbouring category.
function sideStep(index, dir, count, columns) {
    var column = index % columns;
    var atEdge = dir < 0 ? column === 0 : (column === columns - 1 || index >= count - 1);
    if (!atEdge)
        return { index: index + dir, category: 0 };
    return { index: -1, category: dir, row: Math.floor(index / columns) };
}

// Where a sideStep into a category of `count` cells lands: the same row (or
// its last one), at the side it was entered from — the row's last cell when
// moving left, its first when moving right.
function landing(row, dir, count, columns) {
    if (count <= 0)
        return 0;
    var r = Math.min(row, Math.floor((count - 1) / columns));
    return dir < 0 ? Math.min(r * columns + columns - 1, count - 1) : r * columns;
}

if (typeof module !== "undefined") {
    module.exports = {
        CATEGORIES: CATEGORIES, parse: parse, gridMove: gridMove,
        sideStep: sideStep, landing: landing
    };
}
