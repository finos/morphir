import { describe, it, expect } from "vitest";
import { nameToKebab, pathToFileSegment, generateModuleMarkdown } from "../../src/commands/migrate.js";

// ── nameToKebab ───────────────────────────────────────────────────────────────

describe("nameToKebab", () => {
    it("single word", () => {
        expect(nameToKebab(["morphir"])).toBe("morphir");
    });

    it("two words", () => {
        expect(nameToKebab(["my", "value"])).toBe("my-value");
    });

    it("abbreviation as separate letters", () => {
        expect(nameToKebab(["l", "c", "r"])).toBe("l-c-r");
    });
});

// ── pathToFileSegment ─────────────────────────────────────────────────────────

describe("pathToFileSegment", () => {
    it("single segment", () => {
        expect(pathToFileSegment([["finance"]])).toBe("finance");
    });

    it("package + module path", () => {
        expect(pathToFileSegment([["morphir"], ["finance"], ["outflow"]])).toBe(
            "morphir/finance/outflow",
        );
    });

    it("multi-word segments", () => {
        expect(pathToFileSegment([["order", "status"], ["line", "item"]])).toBe(
            "order-status/line-item",
        );
    });
});

// ── generateModuleMarkdown ────────────────────────────────────────────────────

const emptyModuleDef = {
    types: new Map(),
    values: new Map(),
    doc: null,
};

describe("generateModuleMarkdown", () => {
    it("produces an H1 from the module path", () => {
        const md = generateModuleMarkdown([["finance"], ["pricing"]], emptyModuleDef);
        expect(md).toContain("# Finance.Pricing");
    });

    it("includes module doc when present", () => {
        const md = generateModuleMarkdown([["core"]], {
            ...emptyModuleDef,
            doc: "The core module.",
        });
        expect(md).toContain("The core module.");
    });

    it("omits Types section when there are no public types", () => {
        const md = generateModuleMarkdown([["core"]], emptyModuleDef);
        expect(md).not.toContain("## Types");
    });

    it("omits Values section when there are no public values", () => {
        const md = generateModuleMarkdown([["core"]], emptyModuleDef);
        expect(md).not.toContain("## Values");
    });

    it("renders a public type alias", () => {
        const moduleDef = {
            ...emptyModuleDef,
            types: new Map([
                [
                    ["price"],
                    {
                        access: { kind: "Public" as const },
                        value: {
                            doc: "A price amount.",
                            value: {
                                kind: "TypeAliasDefinition" as const,
                                typeParams: [],
                                typeExp: {
                                    kind: "Reference" as const,
                                    attrs: [] as [],
                                    typeName: [
                                        [["morphir"], ["sdk"]],
                                        [["basics"]],
                                        ["float"],
                                    ] as [[string[][], string[][], string[]]],
                                    typeParameters: [],
                                },
                            },
                        },
                    },
                ],
            ]),
        };
        const md = generateModuleMarkdown([["pricing"]], moduleDef as any);
        expect(md).toContain("### Price");
        expect(md).toContain("A price amount.");
        expect(md).toContain("type alias Price =");
        expect(md).toContain("Float");
    });

    it("renders a public custom type", () => {
        const moduleDef = {
            ...emptyModuleDef,
            types: new Map([
                [
                    ["order", "status"],
                    {
                        access: { kind: "Public" as const },
                        value: {
                            doc: "",
                            value: {
                                kind: "CustomTypeDefinition" as const,
                                typeParams: [],
                                ctors: {
                                    access: { kind: "Public" as const },
                                    value: new Map([
                                        [["open"], []],
                                        [["closed"], []],
                                    ]),
                                },
                            },
                        },
                    },
                ],
            ]),
        };
        const md = generateModuleMarkdown([["order"]], moduleDef as any);
        expect(md).toContain("### OrderStatus");
        expect(md).toContain("type OrderStatus");
        expect(md).toContain("Open");
        expect(md).toContain("Closed");
    });

    it("skips private types", () => {
        const moduleDef = {
            ...emptyModuleDef,
            types: new Map([
                [
                    ["internal"],
                    {
                        access: { kind: "Private" as const },
                        value: {
                            doc: "",
                            value: {
                                kind: "TypeAliasDefinition" as const,
                                typeParams: [],
                                typeExp: { kind: "Unit" as const, attrs: [] as [] },
                            },
                        },
                    },
                ],
            ]),
        };
        const md = generateModuleMarkdown([["core"]], moduleDef as any);
        expect(md).not.toContain("### Internal");
    });

    it("renders a public value signature", () => {
        const floatRef = {
            kind: "Reference" as const,
            attrs: [] as [],
            typeName: [[["morphir"], ["sdk"]], [["basics"]], ["float"]] as any,
            typeParameters: [],
        };
        const moduleDef = {
            ...emptyModuleDef,
            values: new Map([
                [
                    ["calculate", "price"],
                    {
                        access: { kind: "Public" as const },
                        value: {
                            doc: "Calculates a price.",
                            value: {
                                inputTypes: [
                                    [["quantity"], [] as [], floatRef],
                                    [["rate"], [] as [], floatRef],
                                ],
                                outputType: floatRef,
                                body: { kind: "Unit" as const, attrs: [] as [] },
                            },
                        },
                    },
                ],
            ]),
        };
        const md = generateModuleMarkdown([["pricing"]], moduleDef as any);
        expect(md).toContain("### calculatePrice");
        expect(md).toContain("Calculates a price.");
        expect(md).toContain("calculatePrice : Float -> Float -> Float");
    });
});
