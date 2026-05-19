import { describe, expect, it } from "vitest";

import { parseSubstrate } from "../../web/src/substrate/parse";
import type {
    Apply,
    IfExpr,
    MatchExpr,
    OneOfType,
    ValueDefinition,
    ValueExpression,
} from "../../web/src/substrate/ast";

const CTX = { file: "spec.md", sectionId: "overview" };

function parse(text: string) {
    return parseSubstrate(text, CTX);
}

function getValue(
    text: string,
    name = "v",
): { def: ValueDefinition; diagnostics: readonly unknown[] } {
    const r = parse(text);
    const def = r.module?.values.get(name);
    if (!def) throw new Error(`no value '${name}' in module`);
    return { def, diagnostics: r.diagnostics };
}

function getBody(text: string, name = "v"): ValueExpression {
    return getValue(text, name).def.body;
}

describe("parseSubstrate — module shape", () => {
    it("parses an empty substrate mapping", () => {
        const r = parse("substrate:\n");
        expect(r.module).toBeDefined();
        expect(r.module?.types.size).toBe(0);
        expect(r.module?.values.size).toBe(0);
    });

    it("returns diagnostic, not throw, on YAML syntax error", () => {
        const r = parse("substrate:\n  foo: : :\n");
        expect(r.diagnostics.some((d) => d.severity === "error")).toBe(true);
    });

    it("returns diagnostic when substrate is not a mapping", () => {
        const r = parse("substrate: 7\n");
        expect(r.module).toBeUndefined();
        expect(r.diagnostics[0]?.severity).toBe("error");
    });
});

describe("parseSubstrate — one-of type", () => {
    it("parses bare-string variants", () => {
        const r = parse(`
substrate:
  types:
    asset:
      one-of: [equity, bond]
`);
        const t = r.module?.types.get("asset") as OneOfType;
        expect(t.kind).toBe("one-of");
        expect(t.variants.map((v) => v.name)).toEqual(["equity", "bond"]);
    });

    it("parses tagged variants with src", () => {
        const r = parse(`
substrate:
  types:
    asset:
      one-of:
        - tag: equity
          src: "equities"
        - tag: bond
          src: "bonds"
      src: "type of asset"
`);
        const t = r.module?.types.get("asset") as OneOfType;
        expect(t.variants[0]?.name).toBe("equity");
        expect(t.variants[0]?.src[0]?.text).toBe("equities");
        expect(t.src[0]?.text).toBe("type of asset");
        expect(t.src[0]?.file).toBe("spec.md");
        expect(t.src[0]?.sectionId).toBe("overview");
    });
});

describe("parseSubstrate — source locations", () => {
    it("treats src as a single scalar", () => {
        const expr = getBody(`
substrate:
  values:
    v:
      equals: [a, 1]
      src: "single anchor"
`);
        expect(expr.src.length).toBe(1);
        expect(expr.src[0]?.text).toBe("single anchor");
    });

    it("accepts src as a sequence of strings", () => {
        const expr = getBody(`
substrate:
  values:
    v:
      equals: [a, 1]
      src:
        - "first anchor"
        - "second anchor"
`);
        expect(expr.src.map((s) => s.text)).toEqual([
            "first anchor",
            "second anchor",
        ]);
    });
});

describe("parseSubstrate — literals and variables", () => {
    it("classifies bare identifiers as variables", () => {
        const r = parse(`
substrate:
  values:
    v:
      equals: [risk_score, 0.5]
`);
        const apply = r.module?.values.get("v")?.body as Apply;
        expect(apply.kind).toBe("equals");
        const left = (apply as { left: ValueExpression }).left;
        expect(left.kind).toBe("variable");
        expect((left as { name: string }).name).toBe("risk_score");
    });

    it("parses quoted strings as string literals", () => {
        const r = parse(`
substrate:
  values:
    v:
      equals: ["x", 1]
`);
        const apply = r.module?.values.get("v")?.body as Apply;
        const left = (apply as { left: ValueExpression }).left;
        expect(left.kind).toBe("literal-string");
    });

    it("strips commas in unquoted numbers", () => {
        const r = parse(`
substrate:
  values:
    v:
      less-than:
        - notional
        - 1,000,000
`);
        const apply = r.module?.values.get("v")?.body as Apply;
        const right = (apply as { right: ValueExpression }).right;
        expect(right.kind).toBe("literal-number");
        expect((right as { value: number }).value).toBe(1_000_000);
    });
});

describe("parseSubstrate — if/then/else", () => {
    it("parses an if expression", () => {
        const expr = getBody(`
substrate:
  values:
    v:
      if:
        less-than: [risk_score, 0.5]
      then: true
      else: false
`) as IfExpr;
        expect(expr.kind).toBe("if");
        expect(expr.condition.kind).toBe("less-than");
        expect(expr.then.kind).toBe("literal-boolean");
        expect(expr.else.kind).toBe("literal-boolean");
    });
});

describe("parseSubstrate — match", () => {
    it("parses match with on and cases", () => {
        const expr = getBody(`
substrate:
  values:
    v:
      match:
        on: asset
        cases:
          - when: equity
            then: true
          - when: bond
            then: false
`) as MatchExpr;
        expect(expr.kind).toBe("match");
        expect(expr.cases.length).toBe(2);
        expect((expr.on as { name?: string }).name).toBe("asset");
    });
});

describe("parseSubstrate — Apply operators", () => {
    for (const op of [
        "equals",
        "not-equals",
        "less-than",
        "less-than-or-equal",
        "greater-than",
        "greater-than-or-equal",
        "add",
        "subtract",
        "multiply",
        "divide",
        "contains",
        "starts-with",
        "ends-with",
    ]) {
        it(`parses binary operator ${op}`, () => {
            const body = getBody(`
substrate:
  values:
    v:
      ${op}: [a, b]
`) as Apply;
            expect(body.kind).toBe(op);
            const bin = body as { left: ValueExpression; right: ValueExpression };
            expect(bin.left.kind).toBe("variable");
            expect(bin.right.kind).toBe("variable");
        });
    }

    it("parses binary mapping form (left/right)", () => {
        const body = getBody(`
substrate:
  values:
    v:
      equals:
        left: a
        right: b
`) as Apply;
        expect(body.kind).toBe("equals");
    });

    it("parses unary not", () => {
        const body = getBody(`
substrate:
  values:
    v:
      not: a
`) as Apply;
        expect(body.kind).toBe("not");
        expect(
            (body as { operand: ValueExpression }).operand.kind,
        ).toBe("variable");
    });

    for (const op of ["and", "or", "concat"]) {
        it(`parses n-ary operator ${op}`, () => {
            const body = getBody(`
substrate:
  values:
    v:
      ${op}: [a, b, c]
`) as Apply;
            expect(body.kind).toBe(op);
            const args = (body as { args: readonly ValueExpression[] }).args;
            expect(args.length).toBe(3);
        });
    }

    it("aliases all-of to and", () => {
        const body = getBody(`
substrate:
  values:
    v:
      all-of: [a, b]
`) as Apply;
        expect(body.kind).toBe("and");
    });
});

describe("parseSubstrate — diagnostics, not throws", () => {
    it("reports unknown operator key without throwing", () => {
        const r = parse(`
substrate:
  values:
    v:
      bogus-op: [a, b]
`);
        expect(r.module?.values.has("v")).toBe(true);
        expect(
            r.diagnostics.some(
                (d) =>
                    d.severity === "error" &&
                    /unknown expression shape/.test(d.message),
            ),
        ).toBe(true);
    });

    it("reports wrong arity on a binary op", () => {
        const r = parse(`
substrate:
  values:
    v:
      equals: [a, b, c]
`);
        expect(
            r.diagnostics.some(
                (d) => /binary operator expects 2/.test(d.message),
            ),
        ).toBe(true);
        // Module still produced.
        expect(r.module?.values.has("v")).toBe(true);
    });

    it("reports missing one-of on a type", () => {
        const r = parse(`
substrate:
  types:
    asset:
      foo: bar
`);
        expect(
            r.diagnostics.some(
                (d) => /one-of/.test(d.message) && d.severity === "error",
            ),
        ).toBe(true);
    });
});
