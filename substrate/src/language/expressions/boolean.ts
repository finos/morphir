/**
 * Boolean expressions — generated from horizontals/typescript/expressions/boolean.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/boolean.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "not-operation",
        {
            arity: 1,
            evaluate: (args) => {
                const lambda = (value: boolean): boolean => !value;
                return lambda(args[0] as boolean) as Value;
            },
        },
    ],
    [
        "and-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: boolean, right: boolean): boolean => left && right;
                return lambda(args[0] as boolean, args[1] as boolean) as Value;
            },
        },
    ],
    [
        "or-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: boolean, right: boolean): boolean => left || right;
                return lambda(args[0] as boolean, args[1] as boolean) as Value;
            },
        },
    ],
    [
        "xor-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: boolean, right: boolean): boolean => left !== right;
                return lambda(args[0] as boolean, args[1] as boolean) as Value;
            },
        },
    ],
    [
        "implies-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: boolean, right: boolean): boolean => !left || right;
                return lambda(args[0] as boolean, args[1] as boolean) as Value;
            },
        },
    ],
    // if-then-else is not in the spec but kept for pipeline evaluator use
    [
        "if-then-else-operation",
        {
            arity: 3,
            evaluate: (args) => (args[0] as boolean) ? args[1]! : args[2]!,
        },
    ],
]);
