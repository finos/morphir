/**
 * Collection type — corresponds to `specs/language/expressions/collection.md`.
 *
 * Registers a subset of the 24 collection operations. Additional
 * operations can be added as the spec stabilises.
 */
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/collection.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "size-operation",
        { arity: 1, evaluate: (args) => (args[0] as unknown as readonly unknown[]).length },
    ],
]);
