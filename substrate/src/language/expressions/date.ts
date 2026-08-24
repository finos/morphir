/**
 * Date type — generated from horizontals/typescript/expressions/date.md
 * DO NOT EDIT — regenerate with the ts-horizontal-regen skill.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/date.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "add-days-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (date: string, days: number): string => {
                    const d = new Date(date + "T00:00:00Z");
                    d.setUTCDate(d.getUTCDate() + days);
                    return d.toISOString().slice(0, 10);
                };
                return lambda(args[0] as string, args[1] as number) as Value;
            },
        },
    ],
    [
        "days-between-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const lambda = (from: string, to: string): number =>
                    Math.round(
                        (new Date(to + "T00:00:00Z").getTime() -
                         new Date(from + "T00:00:00Z").getTime()) / 86_400_000,
                    );
                return lambda(args[0] as string, args[1] as string) as Value;
            },
        },
    ],
]);
