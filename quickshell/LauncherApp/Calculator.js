//
// The launcher's calculator: evaluates what is typed in the search field.
// Deliberately free of QML imports and of `.pragma library` so the same file
// loads in QML (`import "Calculator.js" as Calculator`) and in Node for the
// unit tests (like AudioApp/Loudness.js).
//
// Grammar (lowest to highest precedence):
//   expr   := term (("+" | "-") term)*
//   term   := unary (("*" | "/") unary | group)*   "2(3)" multiplies
//   unary  := ("+" | "-") unary | power             "-2^2" is -(2^2)
//   power  := atom ("^" unary)?                     right associative
//   atom   := number | "(" expr ")" | "[" expr "]"

var CLOSING = { "(": ")", "[": "]" };

// [{ type: "num", value } | { type: "op", value }], or null on a stray char.
function tokenize(text) {
    var tokens = [];
    var i = 0;
    while (i < text.length) {
        var c = text[i];
        if (c === " " || c === "\t") {
            i++;
            continue;
        }
        var number = /^(\d+\.?\d*|\.\d+)/.exec(text.slice(i));
        if (number) {
            tokens.push({ type: "num", value: parseFloat(number[0]) });
            i += number[0].length;
            continue;
        }
        if ("+-*/^()[]".indexOf(c) === -1)
            return null;
        tokens.push({ type: "op", value: c });
        i++;
    }
    return tokens;
}

function Parser(tokens) {
    this.tokens = tokens;
    this.pos = 0;
}

Parser.prototype.peek = function () {
    return this.tokens[this.pos];
};

Parser.prototype.isOp = function (ops) {
    var t = this.peek();
    return !!t && t.type === "op" && ops.indexOf(t.value) !== -1;
};

Parser.prototype.fail = function (message) {
    throw new Error(message);
};

Parser.prototype.expr = function () {
    var value = this.term();
    while (this.isOp("+-")) {
        var op = this.tokens[this.pos++].value;
        var rhs = this.term();
        value = op === "+" ? value + rhs : value - rhs;
    }
    return value;
};

Parser.prototype.term = function () {
    var value = this.unary();
    for (;;) {
        if (this.isOp("*/")) {
            var op = this.tokens[this.pos++].value;
            var rhs = this.unary();
            value = op === "*" ? value * rhs : value / rhs;
        } else if (this.isOp("([")) {
            value = value * this.unary();
        } else {
            return value;
        }
    }
};

Parser.prototype.unary = function () {
    if (this.isOp("+-")) {
        var op = this.tokens[this.pos++].value;
        var value = this.unary();
        return op === "-" ? -value : value;
    }
    return this.power();
};

Parser.prototype.power = function () {
    var base = this.atom();
    if (this.isOp("^")) {
        this.pos++;
        return Math.pow(base, this.unary());
    }
    return base;
};

Parser.prototype.atom = function () {
    var t = this.peek();
    if (!t)
        this.fail("incomplete expression");
    if (t.type === "num") {
        this.pos++;
        return t.value;
    }
    if (t.value === "(" || t.value === "[") {
        this.pos++;
        var value = this.expr();
        var close = this.peek();
        if (!close || close.value !== CLOSING[t.value])
            this.fail("expected " + CLOSING[t.value]);
        this.pos++;
        return value;
    }
    this.fail("unexpected " + t.value);
};

// { ok: true, value } or { ok: false, error }.
function evaluate(text) {
    var tokens = tokenize(`${text}`);
    if (tokens === null)
        return { ok: false, error: "invalid character" };
    if (tokens.length === 0)
        return { ok: false, error: "empty" };
    var parser = new Parser(tokens);
    var value;
    try {
        value = parser.expr();
    } catch (e) {
        return { ok: false, error: e.message };
    }
    if (parser.pos < tokens.length)
        return { ok: false, error: "unexpected " + tokens[parser.pos].value };
    if (!isFinite(value))
        return { ok: false, error: "not a finite number" };
    return { ok: true, value: value };
}

// A result as text: 12 significant digits, which hides float noise
// (0.1 + 0.2 shows as 0.3).
function format(value) {
    var rounded = Number(value.toPrecision(12));
    return rounded === 0 ? "0" : String(rounded);
}

// Whether the input is meant as a calculation rather than a search: it has an
// operator or a bracket (a lone number is a search).
function looksLikeMath(text) {
    return /[-+*/^()[\]]/.test(`${text}`);
}

// The formatted answer to show for the search field, or "" when it is not a
// complete calculation.
function answer(text) {
    if (!looksLikeMath(text))
        return "";
    var result = evaluate(text);
    return result.ok ? format(result.value) : "";
}

if (typeof module !== "undefined") {
    module.exports = {
        evaluate: evaluate,
        format: format,
        looksLikeMath: looksLikeMath,
        answer: answer
    };
}
