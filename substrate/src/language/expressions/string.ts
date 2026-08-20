/**
 * String type — generated from horizontals/typescript/expressions/string.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/string.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "length-operation",
        {
            arity: 1,
            evaluate: (args) => {
                const lambda = (value: string): number => value.length;
                return lambda(args[0] as string) as Value;
            },
        },
    ],
    [
        "concatenate-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: string, right: string): string => left + right;
                return lambda(args[0] as string, args[1] as string) as Value;
            },
        },
    ],
    [
        "is-empty-operation",
        {
            arity: 1,
            evaluate: (args) => {
                const lambda = (value: string): boolean => value.length === 0;
                return lambda(args[0] as string) as Value;
            },
        },
    ],
    [
        "contains-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (value: string, substring: string): boolean =>
                    value.includes(substring);
                return lambda(args[0] as string, args[1] as string) as Value;
            },
        },
    ],
]);
