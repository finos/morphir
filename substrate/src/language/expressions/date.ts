/**
 * Date type — corresponds to `specs/language/expressions/date.md`.
 *
 * Registers: Add Days, Days Between.
 */
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/date.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "add-days-operation",
        {
            arity: 2,
            evaluate: (args) => {
                // Simplified: args[0] is an ISO date string, args[1] is a day count.
                const date = new Date(args[0] as string);
                date.setDate(date.getDate() + (args[1] as number));
                return date.toISOString().slice(0, 10);
            },
        },
    ],
    [
        "days-between-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const a = new Date(args[0] as string).getTime();
                const b = new Date(args[1] as string).getTime();
                return Math.round((b - a) / 86_400_000);
            },
        },
    ],
]);
