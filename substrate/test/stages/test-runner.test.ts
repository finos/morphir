import { describe, it, expect } from "vitest";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root } from "mdast";
import { runTestCases } from "../../src/stages/test-runner.js";

function parse(md: string): Root {
    return unified().use(remarkParse).use(remarkGfm).parse(md) as Root;
}

describe("runTestCases", () => {
    it("passes for correct NOT truth table with named columns and signature", () => {
        const md = `### NOT [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md)_

Inverts a Boolean.

#### Inputs
- \`value\`: [Boolean][bool]

#### Outputs
- \`result\`: [Boolean][bool]

#### [Test cases][tc]

| \`value\` | \`result\` |
| --------- | ---------- |
| true      | false      |
| false     | true       |

[bool]: boolean.md#literals
[tc]: ../concepts/test-case.md
`;
        const root = parse(md);
        const diags = runTestCases(root, "expressions/boolean.md");
        expect(diags.filter((d) => d.severity === "error")).toHaveLength(0);
        const pass = diags.find((d) => d.ruleId === "test-pass");
        expect(pass).toBeDefined();
    });

    it("reports failure for incorrect expected values", () => {
        const md = `### NOT [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md)_

#### Inputs
- \`value\`: [Boolean][bool]

#### Outputs
- \`result\`: [Boolean][bool]

#### [Test cases][tc]

| \`value\` | \`result\` |
| --------- | ---------- |
| true      | true       |

[bool]: boolean.md#literals
[tc]: ../concepts/test-case.md
`;
        const root = parse(md);
        const diags = runTestCases(root, "expressions/boolean.md");
        const fail = diags.find((d) => d.ruleId === "test-failure");
        expect(fail).toBeDefined();
    });

    it("reports warning when operation is not in registry", () => {
        const md = `### Custom [Operation](../concepts/operation.md)

#### Inputs
- \`value\`: [Boolean][bool]

#### Outputs
- \`result\`: [Boolean][bool]

#### [Test cases][tc]

| \`value\` | \`result\` |
| --------- | ---------- |
| true      | false      |

[bool]: boolean.md#literals
[tc]: ../concepts/test-case.md
`;
        const root = parse(md);
        const diags = runTestCases(root, "custom/thing.md");
        const errors = diags.filter((d) => d.severity === "error");
        expect(errors).toHaveLength(0);
    });

    it("handles addition with named columns and signature", () => {
        const md = `### Addition [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md)_

Adds two numbers.

#### Inputs
- \`left\`: [Number][num]
- \`right\`: [Number][num]

#### Outputs
- \`result\`: [Number][num]

#### [Test cases][tc]

| \`left\` | \`right\` | \`result\` |
| -------- | --------- | ---------- |
| 1        | 2         | 3          |
| 0        | 0         | 0          |
| -1       | 1         | 0          |

[num]: number.md#literals
[tc]: ../concepts/test-case.md
`;
        const root = parse(md);
        const diags = runTestCases(root, "expressions/number.md");
        expect(diags.filter((d) => d.severity === "error")).toHaveLength(0);
        const pass = diags.find((d) => d.ruleId === "test-pass");
        expect(pass).toBeDefined();
    });

    it("resolves type-class operation from heading link", () => {
        // Simulates boolean.md Type Class Instances: the Equal operation
        // is referenced via [Equal][eq-equal] in the heading, with the
        // definition resolving to equality.md#equal-operation.
        const md = `#### [Equal][eq-equal] [Operation][op]

##### [Test cases][tc]

| \`left\` | \`right\` | \`result\` |
| -------- | --------- | ---------- |
| true     | true      | true       |
| true     | false     | false      |

[eq-equal]: equality.md#equal-operation
[op]: ../concepts/operation.md
[tc]: ../concepts/test-case.md
`;
        const root = parse(md);
        // The evaluator is in equality.md — filePath here just provides context
        const diags = runTestCases(root, "expressions/boolean.md");
        expect(diags.filter((d) => d.severity === "error")).toHaveLength(0);
        const pass = diags.find((d) => d.ruleId === "test-pass");
        expect(pass).toBeDefined();
    });

    it("parses string literals correctly from signature-typed columns", () => {
        const md = `### Length [Operation](../concepts/operation.md)

#### Inputs
- \`value\`: [String][str]

#### Outputs
- \`result\`: [Integer][int]

#### [Test cases][tc]

| \`value\` | \`result\` |
| --------- | ---------- |
| \`""\`    | 0          |
| \`"abc"\` | 3          |

[str]: string.md#literals
[int]: integer.md
[tc]: ../concepts/test-case.md
`;
        const root = parse(md);
        const diags = runTestCases(root, "expressions/string.md");
        expect(diags.filter((d) => d.severity === "error")).toHaveLength(0);
        const pass = diags.find((d) => d.ruleId === "test-pass");
        expect(pass).toBeDefined();
    });
});
