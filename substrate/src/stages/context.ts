/**
 * Stage 5: Context — compose the entry file plus everything it transitively
 * links to into a single self-contained mdast tree. Cross-file references are
 * rewritten as in-document anchors. The composed tree replaces the expanded
 * root for all downstream stages (typecheck, test).
 *
 * See specs/backlog/spec-implementation-alignment.md design decisions 6 and 7.
 */
import { dirname } from "node:path";
import type { Root } from "mdast";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Diagnostic } from "../types.js";
import { context } from "../commands/context.js";

/**
 * Compose the transitive closure of the spec corpus rooted at `entryFile`.
 * Returns the composed mdast tree; on failure returns null with diagnostics.
 */
export async function composeContext(
    entryFile: string,
    _root: Root,
): Promise<{ readonly diagnostics: readonly Diagnostic[]; readonly data: Root | null }> {
    const cwd = dirname(entryFile);
    // noTreeShaking: include the full entry file (not just its Summary section)
    // so the test runner sees all operation definitions and test-case tables.
    const result = await context(cwd, [entryFile], { noTreeShaking: true });

    if (result.errors.length > 0) {
        const diagnostics: Diagnostic[] = result.errors.map((msg) => ({
            stage: "context" as const,
            severity: "error" as const,
            file: entryFile,
            message: msg,
            ruleId: "context-error",
        }));
        return { diagnostics, data: null };
    }

    const parser = unified().use(remarkParse).use(remarkGfm);
    const composed = parser.parse(result.markdown) as Root;

    return { diagnostics: [], data: composed };
}
