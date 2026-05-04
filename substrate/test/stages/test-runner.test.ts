import { describe, it, expect } from "vitest";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root } from "mdast";
import { runTestCases } from "../../src/stages/test-runner.js";

function parse(md: string): Root {
    return unified().use(remarkParse).use(remarkGfm).parse(md);
}

describe("runTestCases", () => {
    it("passes for correct Not truth table", () => {
        const md = `### Not [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md)_

Description.

#### Test cases

| A | Not A |
|---|-------|
| \`true\` | \`false\` |
| \`false\` | \`true\` |
`;
        const root = parse(md);
        const diags = runTestCases(root, "expressions/boolean.md");
        expect(diags.filter((d) => d.severity === "error")).toHaveLength(0);
    });

    it("reports failure for incorrect expected values", () => {
        const md = `### Not [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md)_

Description.

#### Test cases

| A | Not A |
|---|-------|
| \`true\` | \`true\` |
`;
        const root = parse(md);
        const diags = runTestCases(root, "expressions/boolean.md");
        const fail = diags.find((d) => d.ruleId === "test-failure");
        expect(fail).toBeDefined();
    });

    it("reports info diagnostic when operation is not in registry", () => {
        const md = `### Custom [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md)_

Description.

#### Test cases

| A | Result |
|---|--------|
| \`1\` | \`2\` |
`;
        const root = parse(md);
        // Use a path that won't match any known expression module
        const diags = runTestCases(root, "custom/thing.md");
        // Should either skip or produce info (not error)
        const errors = diags.filter((d) => d.severity === "error");
        expect(errors).toHaveLength(0);
    });

    it("handles addition operation test cases", () => {
        const md = `### Addition [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md)_

Adds two numbers.

#### Test cases

| A | B | A + B |
|---|---|-------|
| \`1\` | \`2\` | \`3\` |
| \`0\` | \`0\` | \`0\` |
| \`-1\` | \`1\` | \`0\` |
`;
        const root = parse(md);
        const diags = runTestCases(root, "expressions/number.md");
        expect(diags.filter((d) => d.severity === "error")).toHaveLength(0);
    });
});
