/**
 * Collection type — generated from horizontals/typescript/expressions/collection.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/collection.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "size-operation",
        {
            arity: 1,
            evaluate: (args) => {
                const lambda = (collection: readonly unknown[]): number =>
                    collection.length;
                return lambda(args[0] as unknown as readonly unknown[]) as Value;
            },
        },
    ],
]);
