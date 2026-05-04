/** Severity of a diagnostic message. */
export type Severity = "error" | "warning" | "info";

/** Name of a verification stage. */
export type StageName =
    | "parse"
    | "include"
    | "lint"
    | "references"
    | "typecheck"
    | "test";

/** A diagnostic message emitted during verification. */
export interface Diagnostic {
    readonly stage: StageName;
    readonly severity: Severity;
    readonly file: string;
    readonly line?: number | undefined;
    readonly column?: number | undefined;
    readonly message: string;
    readonly ruleId?: string | undefined;
}

/** Result of running a single verification stage. */
export interface StageResult {
    readonly stage: StageName;
    readonly diagnostics: readonly Diagnostic[];
    readonly durationMs: number;
}

/** Aggregate result of the full verification pipeline. */
export interface VerificationResult {
    readonly entryFile: string;
    readonly stages: readonly StageResult[];
    readonly totalDurationMs: number;
}

/** Callback for progress events during verification. */
export type ProgressListener = (event: ProgressEvent) => void;

/** Events emitted during verification for progress reporting. */
export type ProgressEvent =
    | { readonly kind: "stage-start"; readonly stage: StageName }
    | {
        readonly kind: "stage-end";
        readonly stage: StageName;
        readonly result: StageResult;
    }
    | { readonly kind: "file-enter"; readonly file: string }
    | { readonly kind: "diagnostic"; readonly diagnostic: Diagnostic };
