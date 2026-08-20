/**
 * Number type class — generated from horizontals/typescript/expressions/number.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/number.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "addition-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): number => left + right;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
    [
        "subtraction-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): number => left - right;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
    [
        "multiplication-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): number => left * right;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
    [
        "division-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): number => left / right;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
    [
        "negation-operation",
        {
            arity: 1,
            evaluate: (args) => {
                const lambda = (value: number): number => -value;
                return lambda(args[0] as number) as Value;
            },
        },
    ],
    [
        "absolute-value-operation",
        {
            arity: 1,
            evaluate: (args) => {
                const lambda = (value: number): number => Math.abs(value);
                return lambda(args[0] as number) as Value;
            },
        },
    ],
    [
        "modulus-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (left: number, right: number): number => left % right;
                return lambda(args[0] as number, args[1] as number) as Value;
            },
        },
    ],
]);
