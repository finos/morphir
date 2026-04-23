/**
 * `substrate validate` — walk every markdown file in the current
 * corpus and verify that every internal link target exists on disk.
 *
 * Vendored packages under `substrate/packages/` are excluded from the
 * walk but are valid link targets for corpus files.
 */
import { relative } from "node:path";

import { listMarkdownFiles, locatePackage } from "../package/corpus.js";
import { parseFile } from "../stages/parse.js";
import { checkReferences } from "../stages/references.js";
import type { Diagnostic } from "../types.js";

/** Result of validating a corpus. */
export interface ValidateResult {
    readonly root: string;
    readonly fileCount: number;
    readonly diagnostics: readonly Diagnostic[];
}

/**
 * Validate the package containing `startDir`. Returns diagnostics for
 * every unresolved link found. Missing links are reported as errors.
 */
export async function validate(startDir: string): Promise<ValidateResult> {
    const pkg = await locatePackage(startDir);
    const files = await listMarkdownFiles(pkg.root);

    const diagnostics: Diagnostic[] = [];
    for (const file of files) {
        const { doc, diagnostics: parseDiags } = await parseFile(file);
        for (const d of parseDiags) {
            if (d.severity === "error") diagnostics.push(d);
        }
        if (doc.root.children.length === 0) continue;
        const refDiags = await checkReferences(doc.root, file);
        diagnostics.push(...refDiags);
    }

    return { root: pkg.root, fileCount: files.length, diagnostics };
}

/**
 * Render a ValidateResult for stdout. Returns the exit code (0 or 1).
 */
export function reportValidate(result: ValidateResult): number {
    const relRoot = result.root;
    const errors = result.diagnostics.filter((d) => d.severity === "error");
    const warnings = result.diagnostics.filter((d) => d.severity === "warning");

    for (const d of result.diagnostics) {
        const loc = d.line !== undefined ? `:${d.line}` : "";
        const file = relative(relRoot, d.file) || d.file;
        const rule = d.ruleId !== undefined ? ` [${d.ruleId}]` : "";
        // eslint-disable-next-line no-console
        console.log(`  ${d.severity} ${file}${loc}: ${d.message}${rule}`);
    }

    if (errors.length > 0) {
        // eslint-disable-next-line no-console
        console.log(
            `✗ ${errors.length} error${errors.length === 1 ? "" : "s"}` +
                (warnings.length > 0 ? `, ${warnings.length} warning${warnings.length === 1 ? "" : "s"}` : "") +
                ` in ${result.fileCount} file${result.fileCount === 1 ? "" : "s"}`,
        );
        return 1;
    }
    if (warnings.length > 0) {
        // eslint-disable-next-line no-console
        console.log(
            `✓ Validation passed with ${warnings.length} warning${warnings.length === 1 ? "" : "s"} (${result.fileCount} file${result.fileCount === 1 ? "" : "s"})`,
        );
    } else {
        // eslint-disable-next-line no-console
        console.log(`✓ Validation passed (${result.fileCount} file${result.fileCount === 1 ? "" : "s"})`);
    }
    return 0;
}
