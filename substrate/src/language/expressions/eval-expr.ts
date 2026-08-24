/**
 * Expression tree evaluator — recursively evaluates an `Expr` tree
 * against a variable binding environment.
 */
import type { Expr, Value } from "../ast.js";
import { resolveOperation } from "./index.js";

/**
 * Evaluate an expression tree given a variable environment.
 *
 * @param expr  The expression to evaluate.
 * @param env   Map from variable name to its current value.
 * @throws      If a variable is unbound or an operation has no evaluator.
 */
export function evalExpr(
    expr: Expr,
    env: Readonly<Record<string, Value>>,
): Value {
    switch (expr.kind) {
        case "literal":
            return expr.value;

        case "var": {
            const val = env[expr.name];
            if (val === undefined) {
                throw new Error(`Undefined variable: "${expr.name}"`);
            }
            return val;
        }

        case "call": {
            const evaluator = resolveOperation(expr.op);
            if (!evaluator) {
                throw new Error(`No evaluator registered for operation: ${expr.op}`);
            }
            const args = expr.args.map((a) => evalExpr(a, env));
            return evaluator.evaluate(args);
        }
    }
}
