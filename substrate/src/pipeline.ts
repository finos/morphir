/**
 * Verification pipeline — orchestrates all six stages in sequence.
 *
 * Each stage receives the accumulated state from previous stages and
 * returns diagnostics. The pipeline reports progress via an optional
 * listener callback.
 */
import { resolve } from "node:path";
import type {
    Diagnostic,
    StageResult,
    StageName,
    VerificationResult,
    ProgressListener,
} from "./types.js";
import { parseFile } from "./stages/parse.js";
import { resolveInclusions } from "./stages/include.js";
import { lintDocument } from "./stages/lint.js";
import { checkReferences } from "./stages/references.js";
import { typecheckDocument } from "./stages/typecheck.js";
import { runTestCases } from "./stages/test-runner.js";

/**
 * Run the full verification pipeline on an entry file.
 */
export async function verify(
    filePath: string,
    listener?: ProgressListener,
): Promise<VerificationResult> {
    const absPath = resolve(filePath);
    const startTime = performance.now();
    const stages: StageResult[] = [];

    // Stage 1: Parse
    const parseResult = await runStage("parse", listener, async () => {
        const { doc, diagnostics } = await parseFile(absPath);
        return { diagnostics, data: doc };
    });
    stages.push(parseResult.stage);

    if (
        parseResult.data === null ||
        parseResult.stage.diagnostics.some((d) => d.severity === "error")
    ) {
        return finalise(absPath, stages, startTime);
    }
    const doc = parseResult.data;

    // Stage 2: Include
    const includeResult = await runStage("include", listener, async () => {
        const { root, diagnostics, includedFiles } = await resolveInclusions(
            doc.root,
            absPath,
        );
        return { diagnostics, data: { root, includedFiles } };
    });
    stages.push(includeResult.stage);

    const expandedRoot = includeResult.data?.root ?? doc.root;

    // Stage 3: Lint
    const lintResult = await runStage("lint", listener, () => {
        const diagnostics = lintDocument(expandedRoot, absPath);
        return { diagnostics, data: null };
    });
    stages.push(lintResult.stage);

    // Stage 4: References
    const refResult = await runStage("references", listener, async () => {
        const diagnostics = await checkReferences(expandedRoot, absPath);
        return { diagnostics, data: null };
    });
    stages.push(refResult.stage);

    // Stage 5: Typecheck
    const typecheckResult = await runStage("typecheck", listener, () => {
        const diagnostics = typecheckDocument(expandedRoot, absPath);
        return { diagnostics, data: null };
    });
    stages.push(typecheckResult.stage);

    // Stage 6: Test
    const testResult = await runStage("test", listener, () => {
        const diagnostics = runTestCases(expandedRoot, absPath);
        return { diagnostics, data: null };
    });
    stages.push(testResult.stage);

    return finalise(absPath, stages, startTime);
}

// ---------------------------------------------------------------------------
// Stage runner
// ---------------------------------------------------------------------------

interface StageOutput<T> {
    readonly diagnostics: readonly Diagnostic[];
    readonly data: T;
}

interface StageRunResult<T> {
    readonly stage: StageResult;
    readonly data: T | null;
}

async function runStage<T>(
    name: StageName,
    listener: ProgressListener | undefined,
    fn: () => StageOutput<T> | Promise<StageOutput<T>>,
): Promise<StageRunResult<T>> {
    listener?.({ kind: "stage-start", stage: name });
    const t0 = performance.now();

    let output: StageOutput<T>;
    try {
        output = await fn();
    } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        const diag: Diagnostic = {
            stage: name,
            severity: "error",
            file: "",
            message: `Stage "${name}" threw: ${message}`,
        };
        const result: StageResult = {
            stage: name,
            diagnostics: [diag],
            durationMs: performance.now() - t0,
        };
        listener?.({ kind: "stage-end", stage: name, result });
        return { stage: result, data: null };
    }

    for (const d of output.diagnostics) {
        listener?.({ kind: "diagnostic", diagnostic: d });
    }

    const result: StageResult = {
        stage: name,
        diagnostics: output.diagnostics,
        durationMs: performance.now() - t0,
    };
    listener?.({ kind: "stage-end", stage: name, result });
    return { stage: result, data: output.data };
}

function finalise(
    entryFile: string,
    stages: readonly StageResult[],
    startTime: number,
): VerificationResult {
    return {
        entryFile,
        stages,
        totalDurationMs: performance.now() - startTime,
    };
}
