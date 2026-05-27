/**
 * Tests for the Simplified Morphir IR decoder against the US LCR regulation
 * reference sample at `D:/ws/finos/open-reg-tech-us-lcr/simplified-ir/`.
 *
 * The test is skipped if that directory is not present, so CI on a fresh
 * checkout doesn't fail.
 */

import { readFile, readdir, stat } from "node:fs/promises";
import { join, relative, sep } from "node:path";
import { describe, it, expect } from "vitest";

import {
    buildDistribution,
    decodeModule,
    decodeType,
    decodeValue,
    decodePattern,
    decodeValueDefinition,
    fqnFromString,
    inferPackageName,
    nameFromCased,
    pathFromDotted,
    type SimplifiedModuleFile,
} from "../../src/ir/simplified.js";

const REG_ROOT = "D:/ws/finos/open-reg-tech-us-lcr/simplified-ir";

async function exists(p: string): Promise<boolean> {
    try { await stat(p); return true; } catch { return false; }
}

async function loadAllModules(root: string): Promise<SimplifiedModuleFile[]> {
    const out: SimplifiedModuleFile[] = [];
    async function walk(dir: string): Promise<void> {
        const entries = await readdir(dir, { withFileTypes: true });
        for (const e of entries) {
            const abs = join(dir, e.name);
            if (e.isDirectory()) {
                await walk(abs);
            } else if (e.isFile() && e.name.toLowerCase().endsWith(".json")) {
                const raw = await readFile(abs, "utf8");
                const rel = relative(root, abs).split(sep).join("/");
                out.push({ relPath: rel, json: JSON.parse(raw) });
            }
        }
    }
    await walk(root);
    return out;
}

// ---------------------------------------------------------------------------
// Unit tests for the small primitives
// ---------------------------------------------------------------------------

describe("nameFromCased", () => {
    it("splits TitleCase into lowercase words", () => {
        expect(nameFromCased("ProductID")).toEqual(["product", "i", "d"]);
        expect(nameFromCased("SDK")).toEqual(["s", "d", "k"]);
        expect(nameFromCased("Basics")).toEqual(["basics"]);
    });
    it("handles camelCase too", () => {
        expect(nameFromCased("padLeft")).toEqual(["pad", "left"]);
        expect(nameFromCased("productID")).toEqual(["product", "i", "d"]);
    });
    it("keeps digits attached to the current word", () => {
        expect(nameFromCased("Level1")).toEqual(["level1"]);
        expect(nameFromCased("Issue210")).toEqual(["issue210"]);
    });
});

describe("pathFromDotted / fqnFromString", () => {
    it("parses dotted paths", () => {
        expect(pathFromDotted("Morphir.SDK")).toEqual([["morphir"], ["s", "d", "k"]]);
    });
    it("parses FQNames", () => {
        expect(fqnFromString("Morphir.SDK:Basics:int")).toEqual([
            [["morphir"], ["s", "d", "k"]],
            [["basics"]],
            ["int"],
        ]);
    });
});

// ---------------------------------------------------------------------------
// Inline shape tests
// ---------------------------------------------------------------------------

describe("decodeType", () => {
    it("decodes a bare Reference", () => {
        const t = decodeType({ Reference: "Morphir.SDK:Basics:int" });
        expect(t.kind).toBe("Reference");
        if (t.kind === "Reference") expect(t.typeParams).toEqual([]);
    });
    it("decodes a parameterised Reference", () => {
        const t = decodeType({
            Reference: { name: "Morphir.SDK:List:list", params: [{ Reference: "Morphir.SDK:Basics:int" }] },
        });
        expect(t.kind).toBe("Reference");
        if (t.kind === "Reference") expect(t.typeParams).toHaveLength(1);
    });
    it("decodes Function and Record", () => {
        const t = decodeType({
            Function: {
                from: { Reference: "Morphir.SDK:Basics:int" },
                to: { Record: { Name: { Reference: "Morphir.SDK:String:string" } } },
            },
        });
        expect(t.kind).toBe("Function");
    });
    it("decodes Unit as the string 'Unit'", () => {
        expect(decodeType("Unit").kind).toBe("Unit");
    });
});

describe("decodeValue", () => {
    it("unfolds curried Apply", () => {
        const v = decodeValue({
            Apply: [
                { Reference: "Morphir.SDK:Basics:add" },
                { Int: 1 },
                { Int: 2 },
            ],
        });
        expect(v.kind).toBe("Apply");
        if (v.kind === "Apply") {
            expect(v.argument.kind).toBe("Literal");
            expect(v.function.kind).toBe("Apply");
        }
    });
    it("decodes If/Match/Let/Lambda", () => {
        const v = decodeValue({
            If: { cond: { Bool: true }, then: { Int: 1 }, else: { Int: 2 } },
        });
        expect(v.kind).toBe("IfThenElse");

        const m = decodeValue({
            Match: {
                on: { Variable: "X" },
                cases: [["_", { Bool: false }]],
            },
        });
        expect(m.kind).toBe("PatternMatch");

        const l = decodeValue({
            Let: { name: "Foo", def: { body: { Int: 1 } }, in: { Variable: "Foo" } },
        });
        expect(l.kind).toBe("LetDefinition");

        const lam = decodeValue({
            Lambda: { arg: { As: "X" }, body: { Variable: "X" } },
        });
        expect(lam.kind).toBe("Lambda");
    });
});

describe("decodePattern", () => {
    it("handles all tag forms", () => {
        expect(decodePattern("_").kind).toBe("WildcardPattern");
        expect(decodePattern("[]").kind).toBe("EmptyListPattern");
        expect(decodePattern("()").kind).toBe("UnitPattern");
        expect(decodePattern({ As: "X" }).kind).toBe("AsPattern");
        expect(decodePattern({ Ctor: "Morphir.SDK:Maybe:nothing" }).kind).toBe("ConstructorPattern");
        const ctor = decodePattern({ Ctor: { "Morphir.SDK:Maybe:just": [{ As: "V" }] } });
        expect(ctor.kind).toBe("ConstructorPattern");
        if (ctor.kind === "ConstructorPattern") expect(ctor.args).toHaveLength(1);
    });
});

describe("decodeValueDefinition", () => {
    it("parses inputs / returns / body", () => {
        const def = decodeValueDefinition({
            inputs: [{ X: { Reference: "Morphir.SDK:Basics:int" } }],
            returns: { Reference: "Morphir.SDK:Basics:int" },
            body: { Variable: "X" },
        });
        expect(def.inputTypes).toHaveLength(1);
        expect(def.inputTypes[0]![0]).toEqual(["x"]);
        expect(def.outputType.kind).toBe("Reference");
        expect(def.body.kind).toBe("Variable");
    });
});

describe("decodeModule (small inline)", () => {
    it("parses a tiny module", () => {
        const m = decodeModule({
            types: { Balance: { Alias: { Reference: "Morphir.SDK:Basics:float" } } },
            values: { Zero: { returns: { Reference: "Morphir.SDK:Basics:float" }, body: { Float: 0 } } },
        });
        expect(m.value.types).toHaveLength(1);
        expect(m.value.values).toHaveLength(1);
        const [, type0] = m.value.types[0]!;
        expect(type0.value.value.kind).toBe("TypeAliasDefinition");
    });
});

// ---------------------------------------------------------------------------
// Integration test: US LCR sample
// ---------------------------------------------------------------------------

describe("US LCR simplified IR sample", () => {
    it("decodes every module file without error", async () => {
        if (!(await exists(REG_ROOT))) {
            console.warn(`skip: ${REG_ROOT} not present`);
            return;
        }
        const files = await loadAllModules(REG_ROOT);
        expect(files.length).toBeGreaterThan(0);

        const pkg = inferPackageName(files);
        expect(pkg).not.toBeNull();
        const dist = buildDistribution(pkg ?? [], files);

        expect(dist.kind).toBe("Library");
        expect(dist.packageDef.modules.length).toBe(files.length);

        // Spot-check that the LCR.Calculations module roundtripped its
        // top-level `Lcr` value with two inputs.
        const calc = dist.packageDef.modules.find(([p]) =>
            p.length === 3 && p[0]![0] === "u" && p[1]![0] === "l" && p[2]![0] === "calculations",
        );
        expect(calc).toBeDefined();
        if (!calc) return;
        const lcr = calc[1].value.values.find(([n]) => n.join(".") === "lcr");
        expect(lcr).toBeDefined();
        if (!lcr) return;
        expect(lcr[1].value.value.inputTypes).toHaveLength(2);
        expect(lcr[1].value.value.body.kind).toBe("Apply");
    });
});
