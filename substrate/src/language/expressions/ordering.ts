/**
 * Ordering type class — generated from horizontals/typescript/expressions/ordering.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/ordering.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "compare-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): string =>
                    left < right ? "Less" : left > right ? "Greater" : "Equal";
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
    [
        "less-than-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): boolean => left < right;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
    [
        "greater-than-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): boolean => left > right;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
    [
        "less-than-or-equal-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): boolean => left <= right;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
    [
        "greater-than-or-equal-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): boolean => left >= right;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
]);
