/**
 * Effect-based validation for the IR Checker.
 * Runs validation asynchronously (worker or yielded main-thread) so the UI stays responsive.
 */

import { Effect, Either } from "effect";
import Ajv from "ajv";
import addFormats from "ajv-formats";
import type { ValidationResult, SchemaVersionValue, ValidationError } from "../components/ir-checker/types";

export const MAIN_THREAD_MAX_BYTES = 50 * 1024; // 50KB — above this we require a worker
const VALIDATION_TIMEOUT_BASE_MS = 15_000; // Base timeout
const VALIDATION_TIMEOUT_PER_100KB_MS = 10_000; // Extra time per 100KB of input

/** Worker result / error message shapes */
interface WorkerResultMessage {
  type: "result";
  runId: number;
  valid: boolean;
  errors: ValidationError[];
  parsedJson: unknown;
  schemaVersion: string | null;
}
interface WorkerErrorMessage {
  type: "error";
  runId: number;
  message: string;
}

/**
 * Run validation in a Web Worker. Returns an Effect that completes when the worker posts a result.
 * Pass schemaUrl (not schema) when possible so postMessage doesn't block cloning a huge schema.
 */
function validateInWorker(
  worker: Worker,
  runId: number,
  jsonString: string,
  schema: object,
  schemaVersion: SchemaVersionValue,
  schemaUrl?: string
): Effect.Effect<ValidationResult> {
  return Effect.async<ValidationResult>((resume) => {
    const handleMessage = (e: MessageEvent<WorkerResultMessage | WorkerErrorMessage>): void => {
      const data = e.data;
      if (!data || data.runId !== runId) return;
      worker.removeEventListener("message", handleMessage);
      worker.removeEventListener("error", handleError);
      if (data.type === "result") {
        resume(
          Effect.succeed({
            valid: data.valid,
            errors: data.errors ?? [],
            parsedJson: data.parsedJson ?? null,
            schemaVersion: (data.schemaVersion as SchemaVersionValue) ?? schemaVersion,
          })
        );
      } else if (data.type === "error") {
        resume(
          Effect.succeed({
            valid: false,
            errors: [{ type: "system", message: data.message ?? "Worker error" }],
            parsedJson: null,
          })
        );
      }
    };
    const handleError = (): void => {
      worker.removeEventListener("message", handleMessage);
      worker.removeEventListener("error", handleError);
      resume(
        Effect.succeed({
          valid: false,
          errors: [
            {
              type: "system",
              message:
                "Worker failed. Validation for large files requires Web Worker support—try a modern browser or a smaller file.",
            },
          ],
          parsedJson: null,
        })
      );
    };
    worker.addEventListener("message", handleMessage);
    worker.addEventListener("error", handleError);
    const payload: Record<string, unknown> = {
      type: "validate",
      runId,
      jsonString,
      schemaVersion,
    };
    // On localhost, send schema directly to avoid potential fetch issues in worker.
    // In production, use schemaUrl to avoid blocking on large schema cloning.
    const isLocalhost =
      typeof window !== "undefined" &&
      (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1");
    if (schemaUrl && !isLocalhost) {
      payload.schemaUrl = schemaUrl;
    } else {
      payload.schema = schema;
    }
    worker.postMessage(payload);
  });
}

function extractLineNumber(jsonString: string, message: string): number | null {
  const match = message.match(/position (\d+)/);
  if (match) {
    const pos = parseInt(match[1], 10);
    return jsonString.substring(0, pos).split("\n").length;
  }
  return null;
}

/**
 * Run validation on the main thread, yielding between parse and validate so the UI can update.
 * Only safe for small payloads (under MAIN_THREAD_MAX_BYTES).
 */
function validateOnMainThread(
  jsonString: string,
  schema: object,
  schemaVersion: SchemaVersionValue
): Effect.Effect<ValidationResult> {
  return Effect.gen(function* () {
    // Wait for paint (rAF + setTimeout) so "Validating..." is visible before we block.
    yield* Effect.async<void>((resume) => {
      const done = () => resume(Effect.succeed(undefined));
      if (typeof requestAnimationFrame !== "undefined") {
        requestAnimationFrame(() => setTimeout(done, 0));
      } else {
        setTimeout(done, 0);
      }
    });

    const parseEither = yield* Effect.try({
      try: () => JSON.parse(jsonString) as unknown,
      catch: (e) => e as Error,
    }).pipe(Effect.either);

    if (Either.isLeft(parseEither)) {
      const err = parseEither.left;
      return {
        valid: false,
        errors: [
          {
            type: "parse" as const,
            message: err.message,
            line: extractLineNumber(jsonString, err.message),
          },
        ],
        parsedJson: null,
      };
    }
    const parsedJson = parseEither.right;

    yield* Effect.async<void>((resume) => setTimeout(() => resume(Effect.succeed(undefined)), 0));

    const compileEither = yield* Effect.try({
      try: () => {
        const ajv = new Ajv({ allErrors: true, verbose: true, strict: false });
        addFormats(ajv);
        return ajv.compile(schema);
      },
      catch: (e) => e as Error,
    }).pipe(Effect.either);

    if (Either.isLeft(compileEither)) {
      return {
        valid: false,
        errors: [{ type: "system", message: `Schema Error: ${compileEither.left.message}` }],
        parsedJson,
      };
    }
    const validate = compileEither.right;

    yield* Effect.async<void>((resume) => setTimeout(() => resume(Effect.succeed(undefined)), 0));

    const validateEither = yield* Effect.try({
      try: () => validate(parsedJson) as boolean,
      catch: (e) => e as Error,
    }).pipe(Effect.either);

    if (Either.isLeft(validateEither)) {
      return {
        valid: false,
        errors: [
          { type: "system", message: `Validation Error: ${validateEither.left.message}` },
        ],
        parsedJson,
      };
    }
    const valid = validateEither.right;
    return {
      valid,
      errors: (validate.errors ?? []).map(
        (err: { instancePath?: string; message?: string; keyword?: string; params?: unknown }) => ({
          type: "schema" as const,
          path: err.instancePath ?? "/",
          message: err.message ?? "",
          keyword: err.keyword,
          params: err.params as Record<string, unknown> | undefined,
        })
      ),
      parsedJson,
      schemaVersion,
    };
  });
}

/**
 * Worker validation with a timeout so the UI never stays stuck on "Validating"
 * if the worker never responds (e.g. worker not bundled or fails to load).
 * Timeout scales with input size: base + extra time per 100KB.
 */
function validateInWorkerWithTimeout(
  worker: Worker,
  runId: number,
  jsonString: string,
  schema: object,
  schemaVersion: SchemaVersionValue,
  schemaUrl?: string
): Effect.Effect<ValidationResult> {
  // Calculate dynamic timeout based on input size (base + extra time per 100KB)
  const sizeKB = jsonString.length / 1024;
  const timeoutMs = VALIDATION_TIMEOUT_BASE_MS + Math.ceil(sizeKB / 100) * VALIDATION_TIMEOUT_PER_100KB_MS;

  const timeoutResult: ValidationResult = {
    valid: false,
    errors: [
      {
        type: "system",
        message:
          `Validation timed out after ${Math.round(timeoutMs / 1000)}s. The file may be too large or complex. Try a smaller example.`,
      },
    ],
    parsedJson: null,
  };
  return Effect.race(
    validateInWorker(worker, runId, jsonString, schema, schemaVersion, schemaUrl),
    Effect.gen(function* () {
      yield* Effect.sleep(timeoutMs);
      return timeoutResult;
    })
  );
}

/**
 * Main validation Effect: uses worker if available, otherwise main thread (with yields) for small content.
 * For large content without a worker, returns a ValidationResult with an error message (no main-thread heavy work).
 */
export function runValidationEffect(
  worker: Worker | null,
  jsonString: string,
  schema: object,
  schemaVersion: SchemaVersionValue,
  runId: number,
  schemaUrl?: string
): Effect.Effect<ValidationResult> {
  const sizeBytes = new Blob([jsonString]).size;
  const mainThreadLimit = MAIN_THREAD_MAX_BYTES; // Same in dev/prod to avoid main-thread lock-up on large files

  if (worker) {
    return validateInWorkerWithTimeout(worker, runId, jsonString, schema, schemaVersion, schemaUrl);
  }

  if (sizeBytes > mainThreadLimit) {
    return Effect.succeed({
      valid: false,
      errors: [
        {
          type: "system",
          message:
            "File is large; validation runs in a Web Worker to keep the UI responsive. Use a smaller example, or run `npm run build:worker` in website/ and refresh to enable the worker.",
        },
      ],
      parsedJson: null,
    });
  }

  return validateOnMainThread(jsonString, schema, schemaVersion);
}

