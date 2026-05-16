/**
 * Equality type class — generated from horizontals/typescript/expressions/equality.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/equality.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "equal-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: unknown, right: unknown): boolean => left === right;
                return lambda(args[0], args[1]) as Value;
            },
        },
    ],
    [
        "not-equal-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: unknown, right: unknown): boolean => left !== right;
                return lambda(args[0], args[1]) as Value;
            },
        },
    ],
]);
