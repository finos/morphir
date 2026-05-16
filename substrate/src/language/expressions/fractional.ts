/**
 * Fractional type class — generated from horizontals/typescript/expressions/fractional.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/fractional.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "division-required-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (dividend: number, divisor: number): number =>
                    dividend / divisor;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
]);
