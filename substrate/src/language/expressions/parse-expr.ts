/**
 * Expression tree parser — converts MDAST nested-list nodes into the
 * typed `Expr` AST defined in `../ast.ts`.
 *
 * Entry point: `parseExprList(list, definitions)` parses the expression
 * list that appears as the nested child of an output-column definition in
 * a Select step.  If the list has a single item it is a regular
 * expression (literal, variable, or operation call); if it has multiple
 * items at the same level it is a decision tree (if/then/else chain).
 */
import type { List, ListItem, Paragraph, InlineCode, Link, LinkReference } from "mdast";
import type { Expr, Value } from "../ast.js";
import { normaliseOperationKey } from "./index.js";

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/**
 * Parse the expression list nested under an output-column definition
 * into an `Expr` tree.
 *
 * @param list        The `List` node that is the column definition's
 *                    nested child.
 * @param definitions The document-level link definitions map, used to
 *                    resolve reference-style links (`[name][ref]`).
 */
export function parseExprList(
    list: List,
    definitions: ReadonlyMap<string, string>,
): Expr {
    const items = list.children as ListItem[];
    if (items.length === 0) throw new Error("Empty expression list");
    if (items.length === 1) return parseExprFromListItem(items[0]!, definitions);
    return parseDecisionTree(items, definitions);
}

// ---------------------------------------------------------------------------
// Single-item expression parsing
// ---------------------------------------------------------------------------

function parseExprFromListItem(
    item: ListItem,
    defs: ReadonlyMap<string, string>,
): Expr {
    const para = firstParagraph(item);
    if (!para) throw new Error("ListItem has no paragraph");

    const nestedList = firstNestedList(item);
    const links = extractLinks(para, defs);

    if (links.length === 0) throw new Error("No links found in expression item");

    const first = links[0]!;

    // Variable reference: [name][var] where var → #variables
    if (isVariableUrl(first.url)) {
        return { kind: "var", name: first.text };
    }

    // Literal: [value][ref] where ref → <type>.md#literals
    const litType = getLiteralType(first.url);
    if (litType !== null) {
        return { kind: "literal", value: parseLiteralValue(first.text, litType) };
    }

    // Operation with nested argument list: [op][ref] + nested List of args
    const opKey = normaliseOperationKey(first.url);
    if (opKey !== null && nestedList !== null) {
        const args = (nestedList.children as ListItem[]).map((child) =>
            parseExprFromListItem(child, defs),
        );
        return { kind: "call", op: opKey, args };
    }

    // Infix binary form: [left][ref] [op][ref] [right][ref]  (exactly 3 links)
    if (links.length === 3) {
        const infixExpr = tryParseInfix(links, defs);
        if (infixExpr !== null) return infixExpr;
    }

    throw new Error(
        `Cannot parse expression: ${links.length} links, first URL: ${first.url}`,
    );
}

// ---------------------------------------------------------------------------
// Decision-tree parsing  (multiple sibling items = if/then/else chain)
// ---------------------------------------------------------------------------

function parseDecisionTree(
    items: readonly ListItem[],
    defs: ReadonlyMap<string, string>,
): Expr {
    const clauses: Array<{ cond: Expr; thenVal: Expr }> = [];
    let elseVal: Expr | null = null;

    for (const item of items) {
        const para = firstParagraph(item);
        if (!para) continue;

        const links = extractLinks(para, defs);
        if (links.length === 0) continue;

        const keyword = getDecisionTreeKeyword(links[0]!.url);

        if (keyword === "if") {
            // Condition is the inline content after the "if" link
            const condLinks = links.slice(1);
            const cond = parseLinksAsExpr(condLinks, defs);

            // Then branch lives in the single nested list under the if item
            const nestedList = firstNestedList(item);
            if (!nestedList) throw new Error('"if" clause has no nested "then"');
            const thenItem = nestedList.children[0] as ListItem;
            const thenPara = firstParagraph(thenItem);
            if (!thenPara) throw new Error('"then" item has no paragraph');
            const thenLinks = extractLinks(thenPara, defs);
            if (
                thenLinks.length === 0 ||
                getDecisionTreeKeyword(thenLinks[0]!.url) !== "then"
            ) {
                throw new Error('Expected "then" keyword in nested item');
            }
            const thenVal = parseLinksAsExpr(thenLinks.slice(1), defs);
            clauses.push({ cond, thenVal });
        } else if (keyword === "else") {
            elseVal = parseLinksAsExpr(links.slice(1), defs);
        }
    }

    if (elseVal === null) throw new Error('Decision tree missing "else" branch');

    // Build right-to-left nested if-then-else
    let result: Expr = elseVal;
    for (let i = clauses.length - 1; i >= 0; i--) {
        const { cond, thenVal } = clauses[i]!;
        result = {
            kind: "call",
            op: "expressions/boolean.md#if-then-else-operation",
            args: [cond, thenVal, result],
        };
    }
    return result;
}

// ---------------------------------------------------------------------------
// Helpers for parsing link arrays into expressions
// ---------------------------------------------------------------------------

/**
 * Parse an array of resolved links (already extracted from a paragraph)
 * into an Expr.  Handles single leaves and infix binary expressions.
 */
function parseLinksAsExpr(
    links: Array<{ url: string; text: string }>,
    defs: ReadonlyMap<string, string>,
): Expr {
    if (links.length === 0) throw new Error("No links to parse as expression");
    if (links.length === 1) return parseLeafLink(links[0]!);
    if (links.length === 3) {
        const infix = tryParseInfix(links, defs);
        if (infix !== null) return infix;
    }
    throw new Error(`Cannot parse ${links.length} links as expression`);
}

/**
 * Try to parse three links as an infix binary call: left op right.
 * Returns null when the middle link is not a known operation.
 */
function tryParseInfix(
    links: Array<{ url: string; text: string }>,
    _defs: ReadonlyMap<string, string>,
): Expr | null {
    const [left, op, right] = links;
    if (!left || !op || !right) return null;
    const opKey = normaliseOperationKey(op.url);
    if (opKey === null) return null;
    return {
        kind: "call",
        op: opKey,
        args: [parseLeafLink(left), parseLeafLink(right)],
    };
}

/** Parse a single link as a literal or variable leaf. */
function parseLeafLink(link: { url: string; text: string }): Expr {
    if (isVariableUrl(link.url)) return { kind: "var", name: link.text };
    const litType = getLiteralType(link.url);
    if (litType !== null) {
        return { kind: "literal", value: parseLiteralValue(link.text, litType) };
    }
    throw new Error(`Cannot parse leaf from URL "${link.url}" text "${link.text}"`);
}

// ---------------------------------------------------------------------------
// URL classifiers
// ---------------------------------------------------------------------------

/** Returns true when the URL targets the Variables section of the expression README. */
function isVariableUrl(url: string): boolean {
    return url.endsWith("#variables");
}

/** Returns the literal primitive type if the URL points to a `#literals` section. */
function getLiteralType(
    url: string,
): "string" | "boolean" | "number" | null {
    if (!url.endsWith("#literals")) return null;
    if (/string\.md#literals$/.test(url)) return "string";
    if (/boolean\.md#literals$/.test(url)) return "boolean";
    if (/(?:number|integer|decimal|floating-point)\.md#literals$/.test(url))
        return "number";
    return null;
}

/**
 * Returns the decision-tree keyword ("if" | "then" | "else") when the
 * URL targets the corresponding anchor of decision-tree.md.
 */
function getDecisionTreeKeyword(
    url: string,
): "if" | "then" | "else" | null {
    if (/decision-tree\.md#if$/.test(url)) return "if";
    if (/decision-tree\.md#then$/.test(url)) return "then";
    if (/decision-tree\.md#else$/.test(url)) return "else";
    return null;
}

// ---------------------------------------------------------------------------
// Literal value parsing
// ---------------------------------------------------------------------------

function parseLiteralValue(
    text: string,
    type: "string" | "boolean" | "number",
): Value {
    if (type === "string") {
        // Strip outer double quotes: "value" → value
        if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
            return text.slice(1, -1);
        }
        return text;
    }
    if (type === "boolean") return text === "true";
    const n = Number(text);
    return Number.isNaN(n) ? 0 : n;
}

// ---------------------------------------------------------------------------
// MDAST traversal helpers
// ---------------------------------------------------------------------------

/** Extract all link/linkReference nodes from a paragraph's children. */
function extractLinks(
    para: Paragraph,
    defs: ReadonlyMap<string, string>,
): Array<{ url: string; text: string }> {
    const result: Array<{ url: string; text: string }> = [];
    for (const child of para.children) {
        if (child.type === "link") {
            const link = child as Link;
            result.push({ url: link.url, text: linkText(link) });
        } else if (child.type === "linkReference") {
            const ref = child as LinkReference;
            const url = defs.get(ref.identifier.toLowerCase());
            if (url !== undefined) {
                result.push({ url, text: linkText(ref) });
            }
        }
    }
    return result;
}

/** Extract the visible text from a link or linkReference node. */
function linkText(node: Link | LinkReference): string {
    const parts: string[] = [];
    for (const child of node.children) {
        if (child.type === "text") parts.push((child as { value: string }).value);
        else if (child.type === "inlineCode")
            parts.push((child as InlineCode).value);
    }
    return parts.join("").trim();
}

function firstParagraph(item: ListItem): Paragraph | null {
    return (item.children.find((c) => c.type === "paragraph") as Paragraph) ?? null;
}

function firstNestedList(item: ListItem): List | null {
    return (item.children.find((c) => c.type === "list") as List) ?? null;
}
