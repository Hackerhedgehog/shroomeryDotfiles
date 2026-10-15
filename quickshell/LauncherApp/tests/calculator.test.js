const test = require("node:test");
const assert = require("node:assert");
const C = require("../Calculator.js");

function value(expr) {
  const r = C.evaluate(expr);
  assert.ok(r.ok, `expected "${expr}" to evaluate, got error: ${r.error}`);
  return r.value;
}

function fails(expr) {
  const r = C.evaluate(expr);
  assert.ok(!r.ok, `expected "${expr}" to fail, got ${r.value}`);
}

test("basic operators", () => {
  assert.strictEqual(value("1+2"), 3);
  assert.strictEqual(value("7-10"), -3);
  assert.strictEqual(value("6*7"), 42);
  assert.strictEqual(value("9/4"), 2.25);
});

test("precedence: * and / before + and -", () => {
  assert.strictEqual(value("2+3*4"), 14);
  assert.strictEqual(value("10-6/2"), 7);
  assert.strictEqual(value("8/4/2"), 1);
  assert.strictEqual(value("10-3-2"), 5);
});

test("^ is exponent, binds tighter than * and is right associative", () => {
  assert.strictEqual(value("2^10"), 1024);
  assert.strictEqual(value("2*3^2"), 18);
  assert.strictEqual(value("2^3^2"), 512);
  assert.strictEqual(value("4^0.5"), 2);
});

test("unary minus and plus", () => {
  assert.strictEqual(value("-5+2"), -3);
  assert.strictEqual(value("3*-2"), -6);
  assert.strictEqual(value("--4"), 4);
  assert.strictEqual(value("+4"), 4);
  // Like a math textbook: -2^2 is -(2^2), but 2^-1 works.
  assert.strictEqual(value("-2^2"), -4);
  assert.strictEqual(value("2^-1"), 0.5);
});

test("( ) and [ ] group, and may nest", () => {
  assert.strictEqual(value("(1+2)*3"), 9);
  assert.strictEqual(value("[1+2]*3"), 9);
  assert.strictEqual(value("[2*(3+4)]^2"), 196);
  assert.strictEqual(value("((2))"), 2);
});

test("a number or group directly before a group multiplies", () => {
  assert.strictEqual(value("2(3+4)"), 14);
  assert.strictEqual(value("(1+1)(2+2)"), 8);
  assert.strictEqual(value("2[3]"), 6);
});

test("decimals and whitespace", () => {
  assert.strictEqual(value(" 1.5 * 2 "), 3);
  assert.strictEqual(value(".5+.25"), 0.75);
  assert.strictEqual(value("3."), 3);
});

test("incomplete or invalid input fails", () => {
  fails("");
  fails("   ");
  fails("2+");
  fails("*2");
  fails("(1+2");
  fails("1+2)");
  fails("[1+2)");
  fails("()");
  fails("1..2");
  fails(".");
  fails("2 3");
  fails("firefox");
  fails("2+a");
});

test("non-finite results fail", () => {
  fails("1/0");
  fails("0/0");
  fails("(-8)^(1/3)");
  fails("10^400");
});

test("format hides float noise and keeps integers plain", () => {
  assert.strictEqual(C.format(0.1 + 0.2), "0.3");
  assert.strictEqual(C.format(42), "42");
  assert.strictEqual(C.format(-3.5), "-3.5");
  assert.strictEqual(C.format(1 / 3), "0.333333333333");
  assert.strictEqual(C.format(-0), "0");
  assert.strictEqual(C.format(2 ** 70), "1.18059162072e+21");
});

test("looksLikeMath: only inputs with an operator or bracket count", () => {
  assert.ok(C.looksLikeMath("1+2"));
  assert.ok(C.looksLikeMath("(4)"));
  assert.ok(C.looksLikeMath("-3"));
  assert.ok(!C.looksLikeMath("42"));
  assert.ok(!C.looksLikeMath("firefox"));
  assert.ok(!C.looksLikeMath(""));
});

test("answer: the formatted result for the search field, or empty", () => {
  assert.strictEqual(C.answer("2+2"), "4");
  assert.strictEqual(C.answer("0.1+0.2"), "0.3");
  assert.strictEqual(C.answer("42"), "");
  assert.strictEqual(C.answer("2+"), "");
  assert.strictEqual(C.answer("code"), "");
});
