/**
 * Progress reporter — formats progress events for console output.
 *
 * This is the only module that writes to the console. All other modules
 * are pure and produce data structures.
 */
import type { ProgressEvent, VerificationResult, Diagnostic, StageResult } from "./types.js";

const STAGE_LABELS: Readonly<Record<string, string>> = {
    parse: "Parse",
    include: "Include",
    lint: "Lint",
    references: "References",
    context: "context",
    typecheck: "Typecheck",
    test: "Test",
};

const SEVERITY_ICONS: Readonly<Record<string, string>> = {
    error: "\u2717",   // ✗
    warning: "\u26A0", // ⚠
    info: "\u2139",    // ℹ
};

/**
 * Create a ProgressListener that writes to the console.
 */
export function consoleListener(): (event: ProgressEvent) => void {
    return (event: ProgressEvent): void => {
        switch (event.kind) {
            case "stage-start": {
                const label = STAGE_LABELS[event.stage] ?? event.stage;
                process.stdout.write(`\n  ${label}...`);
                break;
            }
            case "stage-end": {
                const { result } = event;
                const errors = result.diagnostics.filter((d) => d.severity === "error").length;
                const warnings = result.diagnostics.filter((d) => d.severity === "warning").length;
                const ms = result.durationMs.toFixed(0);

                if (errors === 0 && warnings === 0) {
                    process.stdout.write(` \u2713 (${ms}ms)\n`);
                } else {
                    const parts: string[] = [];
                    if (errors > 0) parts.push(`${errors} error${errors > 1 ? "s" : ""}`);
                    if (warnings > 0) parts.push(`${warnings} warning${warnings > 1 ? "s" : ""}`);
                    process.stdout.write(` ${parts.join(", ")} (${ms}ms)\n`);
                }
                break;
            }
            case "diagnostic": {
                printDiagnostic(event.diagnostic);
                break;
            }
            case "file-enter": {
                // Intentionally quiet; stage-start suffices
                break;
            }
        }
    };
}

function printDiagnostic(d: Diagnostic): void {
    const icon = SEVERITY_ICONS[d.severity] ?? "?";
    const loc = d.line !== undefined ? `:${d.line}` : "";
    const rule = d.ruleId ? ` [${d.ruleId}]` : "";
    console.log(`    ${icon} ${d.file}${loc}: ${d.message}${rule}`);
}

/**
 * Print a summary of the verification result.
 */
export function printSummary(result: VerificationResult): void {
    const totalErrors = result.stages.reduce(
        (sum, s) => sum + s.diagnostics.filter((d) => d.severity === "error").length,
        0,
    );
    const totalWarnings = result.stages.reduce(
        (sum, s) => sum + s.diagnostics.filter((d) => d.severity === "warning").length,
        0,
    );
    const ms = result.totalDurationMs.toFixed(0);

    console.log("");
    if (totalErrors === 0 && totalWarnings === 0) {
        console.log(`\u2713 Verification passed (${ms}ms)`);
    } else {
        const parts: string[] = [];
        if (totalErrors > 0) parts.push(`${totalErrors} error${totalErrors > 1 ? "s" : ""}`);
        if (totalWarnings > 0) parts.push(`${totalWarnings} warning${totalWarnings > 1 ? "s" : ""}`);
        console.log(`\u2717 Verification failed: ${parts.join(", ")} (${ms}ms)`);
    }
}

/**
 * Return the appropriate exit code for a verification result.
 */
export function exitCode(result: VerificationResult): number {
    const hasErrors = result.stages.some((s) =>
        s.diagnostics.some((d) => d.severity === "error"),
    );
    return hasErrors ? 1 : 0;
}

/**
 * Print a compact one-line result for one file in a multi-file run,
 * then return whether the file had errors.
 */
export function printFileResult(result: VerificationResult): boolean {
    const errors = result.stages.reduce(
        (n, s) => n + s.diagnostics.filter((d) => d.severity === "error").length,
        0,
    );
    const warnings = result.stages.reduce(
        (n, s) => n + s.diagnostics.filter((d) => d.severity === "warning").length,
        0,
    );
    const icon = errors > 0 ? "✗" : "✓";
    const parts: string[] = [];
    if (errors > 0) parts.push(`${errors} error${errors > 1 ? "s" : ""}`);
    if (warnings > 0) parts.push(`${warnings} warning${warnings > 1 ? "s" : ""}`);
    const detail = parts.length > 0 ? `  ${parts.join(", ")}` : "";
    console.log(`  ${icon} ${result.entryFile}${detail}`);

    // Print individual diagnostics for errors only (warnings clutter multi-file output)
    if (errors > 0) {
        for (const stage of result.stages) {
            for (const d of stage.diagnostics) {
                if (d.severity === "error") printDiagnostic(d);
            }
        }
    }
    return errors > 0;
}

/**
 * Print a final aggregate summary for a multi-file verification run.
 */
export function printMultiSummary(
    passed: number,
    failed: number,
    totalMs: number,
): void {
    const total = passed + failed;
    const ms = totalMs.toFixed(0);
    console.log("");
    if (failed === 0) {
        console.log(`✓ ${total} file${total === 1 ? "" : "s"} passed (${ms}ms)`);
    } else {
        console.log(
            `✗ ${failed}/${total} file${total === 1 ? "" : "s"} failed (${ms}ms)`,
        );
    }
}
