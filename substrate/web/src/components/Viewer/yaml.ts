/**
 * Minimal indentation-based YAML parser, tolerant of the small
 * inconsistencies in substrate authoring (e.g. odd indentation on
 * `src` lines, unquoted numbers with commas). Covers only the subset
 * the substrate dev UI needs to visualise — block mappings, block
 * sequences, and scalars.
 */

export type YamlScalar = string | number | boolean | null;

export type YamlNode =
    | { readonly kind: "scalar"; readonly value: YamlScalar }
    | {
          readonly kind: "mapping";
          readonly entries: ReadonlyArray<readonly [string, YamlNode]>;
      }
    | { readonly kind: "sequence"; readonly items: readonly YamlNode[] };

interface Line {
    readonly raw: string;
    readonly indent: number;
    readonly content: string;
}

const stripComment = (s: string): string => {
    // Strip inline comments outside of quoted strings.
    let inSingle = false;
    let inDouble = false;
    for (let i = 0; i < s.length; i++) {
        const c = s[i];
        if (c === '"' && !inSingle) inDouble = !inDouble;
        else if (c === "'" && !inDouble) inSingle = !inSingle;
        else if (c === "#" && !inSingle && !inDouble) {
            const before = i > 0 ? s[i - 1] : "";
            if (before === "" || before === " " || before === "\t") {
                return s.slice(0, i).trimEnd();
            }
        }
    }
    return s.trimEnd();
};

const splitLines = (src: string): Line[] => {
    const out: Line[] = [];
    for (const raw0 of src.split(/\r?\n/)) {
        const raw = stripComment(raw0);
        if (!raw.trim()) continue;
        let indent = 0;
        while (indent < raw.length && raw[indent] === " ") indent++;
        out.push({ raw, indent, content: raw.slice(indent) });
    }
    return out;
};

const parseScalar = (s: string): YamlScalar => {
    const t = s.trim();
    if (t === "" || t === "~" || t.toLowerCase() === "null") return null;
    if (t === "true") return true;
    if (t === "false") return false;
    // Quoted strings.
    if (
        (t.startsWith('"') && t.endsWith('"')) ||
        (t.startsWith("'") && t.endsWith("'"))
    ) {
        return t.slice(1, -1);
    }
    // Numbers (allow underscores). We treat numbers-with-commas as strings
    // because substrate authors write things like `1,000,000`.
    if (/^-?\d+(\.\d+)?$/.test(t)) return Number(t);
    return t;
};

const parseBlock = (
    lines: readonly Line[],
    start: number,
    indent: number,
): { node: YamlNode; next: number } => {
    const first = lines[start];
    if (!first || first.indent < indent) {
        return { node: { kind: "scalar", value: null }, next: start };
    }
    const childIndent = first.indent;
    if (first.content.startsWith("- ") || first.content === "-") {
        const items: YamlNode[] = [];
        let i = start;
        while (true) {
            const ln = lines[i];
            if (!ln) break;
            if (ln.indent > childIndent) {
                // Misindented continuation we couldn't absorb — skip
                // rather than abandoning the rest of the document.
                i++;
                continue;
            }
            if (ln.indent !== childIndent) break;
            if (!(ln.content.startsWith("- ") || ln.content === "-")) break;
            const after = ln.content === "-" ? "" : ln.content.slice(2);
            if (after === "") {
                const { node, next } = parseBlock(lines, i + 1, childIndent + 1);
                items.push(node);
                i = next;
                continue;
            }
            const itemColumn = childIndent + 2;
            const colonIdx = findMappingColon(after);
            if (colonIdx >= 0) {
                const synthetic: Line[] = [];
                synthetic.push({
                    raw: " ".repeat(itemColumn) + after,
                    indent: itemColumn,
                    content: after,
                });
                let j = i + 1;
                while (true) {
                    const nxt = lines[j];
                    if (!nxt || nxt.indent <= childIndent) break;
                    synthetic.push(nxt);
                    j++;
                }
                const { node } = parseBlock(synthetic, 0, itemColumn);
                items.push(node);
                i = j;
            } else {
                items.push({ kind: "scalar", value: parseScalar(after) });
                i++;
            }
        }
        return { node: { kind: "sequence", items }, next: i };
    }
    const entries: Array<[string, YamlNode]> = [];
    let i = start;
    while (true) {
        const ln = lines[i];
        if (!ln) break;
        if (ln.indent > childIndent) {
            // Over-indented line. If it looks like a sibling key, treat
            // it as one at this level — substrate authors occasionally
            // over-indent `src:` lines. Otherwise skip so the rest of
            // the document still parses.
            const colonIdx = findMappingColon(ln.content);
            if (colonIdx >= 0 && !ln.content.startsWith("- ")) {
                const key = ln.content.slice(0, colonIdx).trim();
                const rest = ln.content.slice(colonIdx + 1).trim();
                if (rest === "") {
                    const { node, next } = parseBlock(
                        lines,
                        i + 1,
                        ln.indent + 1,
                    );
                    entries.push([key, node]);
                    i = next;
                } else {
                    entries.push([
                        key,
                        { kind: "scalar", value: parseScalar(rest) },
                    ]);
                    i++;
                }
                continue;
            }
            i++;
            continue;
        }
        if (ln.indent !== childIndent) break;
        if (ln.content.startsWith("- ")) break;
        const colonIdx = findMappingColon(ln.content);
        if (colonIdx < 0) {
            // Not a key — bail out so the parent loop can handle it.
            break;
        }
        const key = ln.content.slice(0, colonIdx).trim();
        const rest = ln.content.slice(colonIdx + 1).trim();
        if (rest === "") {
            const { node, next } = parseBlock(lines, i + 1, childIndent + 1);
            entries.push([key, node]);
            i = next;
        } else {
            entries.push([key, { kind: "scalar", value: parseScalar(rest) }]);
            i++;
        }
    }
    return { node: { kind: "mapping", entries }, next: i };
};

const findMappingColon = (s: string): number => {
    // Find the first colon that is followed by a space or end-of-line and
    // is not inside quotes.
    let inSingle = false;
    let inDouble = false;
    for (let i = 0; i < s.length; i++) {
        const c = s[i];
        if (c === '"' && !inSingle) inDouble = !inDouble;
        else if (c === "'" && !inDouble) inSingle = !inSingle;
        else if (c === ":" && !inSingle && !inDouble) {
            const next = s[i + 1];
            if (next === undefined || next === " " || next === "\t") return i;
        }
    }
    return -1;
};

export const parseYaml = (src: string): YamlNode => {
    const lines = splitLines(src);
    if (lines.length === 0) return { kind: "scalar", value: null };
    const baseIndent = lines[0]?.indent ?? 0;
    return parseBlock(lines, 0, baseIndent).node;
};
