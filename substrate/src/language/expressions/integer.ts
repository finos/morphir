/**
 * Integer type — generated from horizontals/typescript/expressions/integer.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/integer.md";

/** Integer attributes (not generated — structural metadata). */
export interface IntegerAttributes {
    readonly sizeInBits?: number;
    readonly signed?: boolean;
}

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "integer-division-required-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (dividend: number, divisor: number): number =>
                    Math.floor(dividend / divisor);
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
    [
        "remainder-required-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (dividend: number, divisor: number): number =>
                    ((dividend % divisor) + Math.abs(divisor)) % Math.abs(divisor);
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
]);
