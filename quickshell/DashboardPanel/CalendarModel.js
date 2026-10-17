//
// Month grid for the dashboard calendar (MonthCalendar.qml): six Monday-first
// weeks with ISO week numbers. Free of QML imports for the Node tests.

function isoWeek(y, m, d) {
    var t = new Date(Date.UTC(y, m, d));
    t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
    var yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
    return Math.ceil(((t - yearStart) / 86400000 + 1) / 7);
}

// month 0-11; today { y, m, d } or null.
function monthGrid(year, month, today) {
    var startCell = (new Date(year, month, 1).getDay() + 6) % 7;
    var days = [], weeks = [];
    for (var i = 0; i < 42; i++) {
        var date = new Date(year, month, 1 - startCell + i);
        var y = date.getFullYear(), m = date.getMonth(), d = date.getDate();
        days.push({ day: d, inMonth: m === month,
                    isToday: !!today && y === today.y && m === today.m && d === today.d });
        if (i % 7 === 0)
            weeks.push(isoWeek(y, m, d));
    }
    return { weeks: weeks, days: days };
}

function shiftMonth(year, month, delta) {
    var t = year * 12 + month + delta;
    return { year: Math.floor(t / 12), month: ((t % 12) + 12) % 12 };
}

if (typeof module !== "undefined") {
    module.exports = { isoWeek: isoWeek, monthGrid: monthGrid, shiftMonth: shiftMonth };
}
