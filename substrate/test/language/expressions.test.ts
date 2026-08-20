import { describe, it, expect } from "vitest";
import {
    resolveOperation,
    normaliseOperationKey,
    allOperations,
} from "../../src/language/expressions/index.js";

describe("normaliseOperationKey", () => {
    it("strips leading slashes and normalises backslashes", () => {
        expect(normaliseOperationKey("/expressions/boolean.md#not-operation"))
            .toBe("expressions/boolean.md#not-operation");
    });

    it("returns null for paths without two segments", () => {
        expect(normaliseOperationKey("boolean.md#not-operation"))
            .toBeNull();
    });
});

describe("resolveOperation", () => {
    it("finds the Not operation", () => {
        const ev = resolveOperation("expressions/boolean.md#not-operation");
        expect(ev).not.toBeNull();
        expect(ev!.arity).toBe(1);
    });

    it("evaluates Not correctly", () => {
        const ev = resolveOperation("expressions/boolean.md#not-operation")!;
        expect(ev.evaluate([true])).toBe(false);
        expect(ev.evaluate([false])).toBe(true);
    });

    it("finds the Addition operation", () => {
        const ev = resolveOperation("expressions/number.md#addition-operation");
        expect(ev).not.toBeNull();
        expect(ev!.arity).toBe(2);
        expect(ev!.evaluate([3, 4])).toBe(7);
    });

    it("returns null for unknown keys", () => {
        expect(resolveOperation("expressions/nonexistent.md#nope")).toBeUndefined();
    });
});

describe("allOperations", () => {
    it("returns a non-empty map", () => {
        const ops = allOperations();
        expect(ops.size).toBeGreaterThan(0);
    });
});

// ---------------------------------------------------------------------------
// Boolean evaluators
// ---------------------------------------------------------------------------

describe("boolean evaluators", () => {
    const get = (anchor: string) =>
        resolveOperation(`expressions/boolean.md#${anchor}`)!;

    it("and-operation", () => {
        const ev = get("and-operation");
        expect(ev.evaluate([true, true])).toBe(true);
        expect(ev.evaluate([true, false])).toBe(false);
        expect(ev.evaluate([false, true])).toBe(false);
        expect(ev.evaluate([false, false])).toBe(false);
    });

    it("or-operation", () => {
        const ev = get("or-operation");
        expect(ev.evaluate([true, true])).toBe(true);
        expect(ev.evaluate([true, false])).toBe(true);
        expect(ev.evaluate([false, false])).toBe(false);
    });

    it("xor-operation", () => {
        const ev = get("xor-operation");
        expect(ev.evaluate([true, true])).toBe(false);
        expect(ev.evaluate([true, false])).toBe(true);
    });

    it("implies-operation", () => {
        const ev = get("implies-operation");
        expect(ev.evaluate([true, true])).toBe(true);
        expect(ev.evaluate([true, false])).toBe(false);
        expect(ev.evaluate([false, true])).toBe(true);
        expect(ev.evaluate([false, false])).toBe(true);
    });

    it("if-then-else-operation", () => {
        const ev = get("if-then-else-operation");
        expect(ev.evaluate([true, "yes", "no"])).toBe("yes");
        expect(ev.evaluate([false, "yes", "no"])).toBe("no");
    });
});

// ---------------------------------------------------------------------------
// Number evaluators
// ---------------------------------------------------------------------------

describe("number evaluators", () => {
    const get = (anchor: string) =>
        resolveOperation(`expressions/number.md#${anchor}`)!;

    it("subtraction-operation", () => {
        expect(get("subtraction-operation").evaluate([10, 3])).toBe(7);
    });

    it("multiplication-operation", () => {
        expect(get("multiplication-operation").evaluate([4, 5])).toBe(20);
    });

    it("division-operation", () => {
        expect(get("division-operation").evaluate([10, 2])).toBe(5);
    });

    it("negation-operation", () => {
        expect(get("negation-operation").evaluate([7])).toBe(-7);
    });

    it("absolute-value-operation", () => {
        expect(get("absolute-value-operation").evaluate([-5])).toBe(5);
        expect(get("absolute-value-operation").evaluate([3])).toBe(3);
    });

    it("modulus-operation", () => {
        expect(get("modulus-operation").evaluate([10, 3])).toBe(1);
    });
});

// ---------------------------------------------------------------------------
// Equality evaluators
// ---------------------------------------------------------------------------

describe("equality evaluators", () => {
    it("equal-operation", () => {
        const ev = resolveOperation("expressions/equality.md#equal-operation")!;
        expect(ev.evaluate([1, 1])).toBe(true);
        expect(ev.evaluate([1, 2])).toBe(false);
        expect(ev.evaluate(["a", "a"])).toBe(true);
    });

    it("not-equal-operation", () => {
        const ev = resolveOperation("expressions/equality.md#not-equal-operation")!;
        expect(ev.evaluate([1, 2])).toBe(true);
        expect(ev.evaluate([1, 1])).toBe(false);
    });
});

// ---------------------------------------------------------------------------
// Ordering evaluators
// ---------------------------------------------------------------------------

describe("ordering evaluators", () => {
    it("less-than-operation", () => {
        const ev = resolveOperation("expressions/ordering.md#less-than-operation")!;
        expect(ev.evaluate([1, 2])).toBe(true);
        expect(ev.evaluate([2, 1])).toBe(false);
        expect(ev.evaluate([1, 1])).toBe(false);
    });

    it("greater-than-or-equal-operation", () => {
        const ev = resolveOperation("expressions/ordering.md#greater-than-or-equal-operation")!;
        expect(ev.evaluate([2, 1])).toBe(true);
        expect(ev.evaluate([1, 1])).toBe(true);
        expect(ev.evaluate([0, 1])).toBe(false);
    });
});

// ---------------------------------------------------------------------------
// String evaluators
// ---------------------------------------------------------------------------

describe("string evaluators", () => {
    it("length-operation", () => {
        const ev = resolveOperation("expressions/string.md#length-operation")!;
        expect(ev.evaluate(["hello"])).toBe(5);
        expect(ev.evaluate([""])).toBe(0);
    });

    it("concatenate-operation", () => {
        const ev = resolveOperation("expressions/string.md#concatenate-operation")!;
        expect(ev.evaluate(["ab", "cd"])).toBe("abcd");
    });

    it("contains-operation", () => {
        const ev = resolveOperation("expressions/string.md#contains-operation")!;
        expect(ev.evaluate(["abcdef", "cde"])).toBe(true);
        expect(ev.evaluate(["abc", "xyz"])).toBe(false);
    });
});
