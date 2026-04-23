/**
 * `substrate context` — produce a self-contained, tree-shaken markdown
 * document covering only the sections reachable from one or more roots.
 *
 * See `specs/tools/cli/packages.md` for the user-facing description and
 * the algorithm specification.
 */
import { readFile } from "node:fs/promises";
import { dirname, isAbsolute, resolve } from "node:path";
import type {
    Content,
    Definition,
    Heading,
    Link,
    LinkReference,
    Root,
} from "mdast";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkStringify from "remark-stringify";

import { nodeText, slugify } from "../language/mdast-utils.js";
import { locatePackage } from "../package/corpus.js";

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/** A `<file.md[#section]>` argument parsed into its parts. */
interface Job {
    readonly filePath: string;
    readonly anchor: string | null;
}

export interface ContextResult {
    readonly markdown: string;
    readonly errors: readonly string[];
}

/**
 * Build a self-contained markdown context document from a list of
 * `<file.md[#section]>` roots. Returns the rendered document and any
 * fatal errors (missing files / unresolvable initial anchors).
 */
export async function context(
    cwd: string,
    args: readonly string[],
): Promise<ContextResult> {
    if (args.length === 0) {
        return {
            markdown: "",
            errors: ["substrate context: at least one <file.md[#section]> argument required"],
        };
    }

    const errors: string[] = [];
    const packageRootCache = new Map<string, string>();
    const rootJobs: Job[] = [];
    for (const arg of args) {
        const { filePath, anchor } = parseArg(arg, cwd);
        rootJobs.push({ filePath, anchor });
    }

    // Phase 1 + 2 + 3: parse files, mark inclusions, walk links.
    const files = new Map<string, FileTree>();
    const inclusions = new Map<string, FileInclusion>();
    const queue: Job[] = [...rootJobs];
    const seenJobs = new Set<string>();

    while (queue.length > 0) {
        const job = queue.shift()!;
        const key = jobKey(job);
        if (seenJobs.has(key)) continue;
        seenJobs.add(key);

        let tree = files.get(job.filePath);
        if (tree === undefined) {
            const loaded = await loadFile(job.filePath);
            if (loaded === null) {
                if (rootJobs.includes(job)) {
                    errors.push(`Cannot read file: ${job.filePath}`);
                }
                continue;
            }
            tree = loaded;
            files.set(job.filePath, tree);
        }

        let inc = inclusions.get(job.filePath);
        if (inc === undefined) {
            inc = { whole: false, marked: new Set() };
            inclusions.set(job.filePath, inc);
        }

        const newSections = applyJob(tree, inc, job, errors, rootJobs.includes(job));
        const packageRoot = await getPackageRoot(job.filePath, packageRootCache);
        for (const sec of newSections) {
            // Walk links in the newly-included nodes
            const linkSources = collectLinkUrls(tree, sec);
            const definitions = collectDefinitions(tree.root);
            for (const url of linkSources) {
                const resolved = resolveUrl(url, definitions);
                if (resolved === null) continue;
                const next = resolveLinkTarget(resolved, job.filePath, packageRoot);
                if (next !== null) queue.push(next);
            }
        }
    }

    if (errors.length > 0) {
        return { markdown: "", errors };
    }

    // Ensure package roots are cached for every loaded file.
    for (const filePath of files.keys()) {
        await getPackageRoot(filePath, packageRootCache);
    }

    // Phase 4: file-level dependency graph + topological order.
    const order = topoOrderFiles(files, inclusions, packageRootCache);

    // Phase 5: choose, for each file, the indices of root.children to emit.
    const emissionPlans = new Map<string, EmissionPlan>();
    for (const filePath of order) {
        const tree = files.get(filePath)!;
        const inc = inclusions.get(filePath)!;
        emissionPlans.set(filePath, planEmission(tree, inc));
    }

    // Phase 6: assign globally-unique anchors to every emitted section.
    const globalAnchors = assignGlobalAnchors(order, files, emissionPlans);

    // Phase 7: render — for each file, clone the included nodes, rewrite
    // their links and definitions, then stringify.
    const stringifier = unified().use(remarkStringify).use(remarkGfm);
    const parts: string[] = [];
    for (const filePath of order) {
        const tree = files.get(filePath)!;
        const plan = emissionPlans.get(filePath)!;
        const nodes = plan.indices.map((i) => tree.root.children[i]!);
        const rewritten = nodes.map((n) =>
            rewriteLinks(n, filePath, files, globalAnchors),
        );
        const rendered = stringifier.stringify({ type: "root", children: rewritten });
        parts.push(rendered.toString().trimEnd());
    }

    return { markdown: parts.join("\n\n") + "\n", errors: [] };
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

function parseArg(arg: string, cwd: string): { filePath: string; anchor: string | null } {
    const hashIdx = arg.indexOf("#");
    const rawPath = hashIdx >= 0 ? arg.slice(0, hashIdx) : arg;
    const anchor = hashIdx >= 0 ? arg.slice(hashIdx + 1) : null;
    const filePath = isAbsolute(rawPath) ? resolve(rawPath) : resolve(cwd, rawPath);
    return { filePath, anchor };
}

function jobKey(job: Job): string {
    return `${job.filePath}\x00${job.anchor ?? "*"}`;
}

// ---------------------------------------------------------------------------
// File loading + section-tree construction
// ---------------------------------------------------------------------------

/** A parsed file plus its section tree (top-level sections only). */
interface FileTree {
    readonly filePath: string;
    readonly root: Root;
    readonly topSections: readonly SectionNode[];
    /** All sections, flattened, indexed by local slug → section. Collisions get -2, -3 suffix. */
    readonly bySlug: ReadonlyMap<string, SectionNode>;
    /** All sections in document order. */
    readonly all: readonly SectionNode[];
}

interface SectionNode {
    readonly heading: Heading;
    readonly depth: number;
    /** Local slug (within file), uniquified on collision. */
    readonly slug: string;
    /** Index of the heading node within root.children. */
    readonly headingIdx: number;
    /** Exclusive end of this section's subtree within root.children. */
    readonly subtreeEnd: number;
    readonly children: SectionNode[];
    parent: SectionNode | null;
}

async function loadFile(filePath: string): Promise<FileTree | null> {
    let source: string;
    try {
        source = await readFile(filePath, "utf8");
    } catch {
        return null;
    }
    const root = unified().use(remarkParse).use(remarkGfm).parse(source) as Root;
    const { topSections, all, bySlug } = buildSectionTree(root);
    return { filePath, root, topSections, all, bySlug };
}

function buildSectionTree(root: Root): {
    topSections: SectionNode[];
    all: SectionNode[];
    bySlug: Map<string, SectionNode>;
} {
    const all: SectionNode[] = [];
    const bySlug = new Map<string, SectionNode>();
    const slugCounts = new Map<string, number>();

    for (let i = 0; i < root.children.length; i++) {
        const node = root.children[i]!;
        if (node.type !== "heading") continue;
        const heading = node as Heading;
        const baseSlug = slugify(nodeText(heading));
        let slug = baseSlug;
        const prior = slugCounts.get(baseSlug) ?? 0;
        if (prior > 0) slug = `${baseSlug}-${prior + 1}`;
        slugCounts.set(baseSlug, prior + 1);

        const sec: SectionNode = {
            heading,
            depth: heading.depth,
            slug,
            headingIdx: i,
            subtreeEnd: 0, // filled in below
            children: [],
            parent: null,
        };
        all.push(sec);
        bySlug.set(slug, sec);
    }

    // Compute subtreeEnd: from this heading up to the next heading at depth <= self.depth.
    for (let s = 0; s < all.length; s++) {
        const sec = all[s]!;
        let end = root.children.length;
        for (let t = s + 1; t < all.length; t++) {
            if (all[t]!.depth <= sec.depth) {
                end = all[t]!.headingIdx;
                break;
            }
        }
        (sec as { subtreeEnd: number }).subtreeEnd = end;
    }

    // Build parent/child links via stack.
    const stack: SectionNode[] = [];
    const top: SectionNode[] = [];
    for (const sec of all) {
        while (stack.length > 0 && stack[stack.length - 1]!.depth >= sec.depth) {
            stack.pop();
        }
        const parent = stack.length > 0 ? stack[stack.length - 1]! : null;
        sec.parent = parent;
        if (parent === null) top.push(sec);
        else parent.children.push(sec);
        stack.push(sec);
    }

    return { topSections: top, all, bySlug };
}

// ---------------------------------------------------------------------------
// Inclusion bookkeeping
// ---------------------------------------------------------------------------

interface FileInclusion {
    whole: boolean;
    /** Sections explicitly marked (their full subtree is included). */
    marked: Set<SectionNode>;
}

/**
 * Apply a job to a file's inclusion record. Returns the *new* sections
 * (whose link content has not yet been walked) so the caller can
 * enqueue follow-up jobs.
 */
function applyJob(
    tree: FileTree,
    inc: FileInclusion,
    job: Job,
    errors: string[],
    isRoot: boolean,
): SectionNode[] {
    if (inc.whole) return []; // already covers everything

    if (job.anchor === null) {
        // Prefer a `Summary` section when the file declares one — it
        // exists precisely so consumers can pull a focused synopsis
        // instead of the entire document.
        const summary = tree.bySlug.get("summary");
        if (summary !== undefined) {
            if (inc.marked.has(summary)) return [];
            inc.marked.add(summary);
            return [summary];
        }
        inc.whole = true;
        const newly = tree.all.filter((s) => !inc.marked.has(s));
        for (const s of tree.all) inc.marked.add(s);
        return newly;
    }

    const sec = tree.bySlug.get(job.anchor);
    if (sec === undefined) {
        if (isRoot) {
            errors.push(`Section "${job.anchor}" not found in ${job.filePath}`);
        }
        return [];
    }
    if (inc.marked.has(sec)) return [];
    inc.marked.add(sec);
    return [sec];
}

// ---------------------------------------------------------------------------
// Link discovery within an included section
// ---------------------------------------------------------------------------

/**
 * Collect every link URL (or reference identifier) reachable from a
 * newly-included section *and* from the framing context of its
 * ancestors. We over-collect for ancestors (their intro prose) — the
 * job dedupe queue absorbs duplicates.
 */
function collectLinkUrls(tree: FileTree, sec: SectionNode): string[] {
    const urls: string[] = [];
    // Walk the section subtree.
    for (let i = sec.headingIdx; i < sec.subtreeEnd; i++) {
        collectFromNode(tree.root.children[i]!, urls);
    }
    // Walk each ancestor's framing context (heading + intro prose).
    let p = sec.parent;
    while (p !== null) {
        const introEnd = p.children.length > 0 ? p.children[0]!.headingIdx : p.subtreeEnd;
        for (let i = p.headingIdx; i < introEnd; i++) {
            collectFromNode(tree.root.children[i]!, urls);
        }
        p = p.parent;
    }
    return urls;
}

function collectFromNode(node: unknown, out: string[]): void {
    if (typeof node !== "object" || node === null) return;
    const obj = node as Record<string, unknown>;
    if (obj["type"] === "link" && typeof obj["url"] === "string") {
        out.push(obj["url"] as string);
    } else if (obj["type"] === "linkReference" && typeof obj["identifier"] === "string") {
        // Mark with sentinel so resolveUrl knows to look up the definition.
        out.push(`\x01ref:${obj["identifier"] as string}`);
    }
    const children = obj["children"];
    if (Array.isArray(children)) for (const c of children) collectFromNode(c, out);
}

function collectDefinitions(root: Root): Map<string, string> {
    const out = new Map<string, string>();
    for (const n of root.children) {
        if (n.type === "definition") {
            const d = n as Definition;
            out.set(d.identifier, d.url);
        }
    }
    return out;
}

function resolveUrl(url: string, definitions: ReadonlyMap<string, string>): string | null {
    if (url.startsWith("\x01ref:")) {
        const id = url.slice(5);
        return definitions.get(id) ?? null;
    }
    return url;
}

function resolveLinkTarget(url: string, fromFile: string, baseDir: string): Job | null {
    if (/^https?:\/\//.test(url) || url.startsWith("mailto:")) return null;
    const hashIdx = url.indexOf("#");
    const filePart = hashIdx >= 0 ? url.slice(0, hashIdx) : url;
    const anchor = hashIdx >= 0 ? url.slice(hashIdx + 1) : null;
    if (filePart === "") return null; // same-file anchor; already covered
    if (filePart.startsWith("/")) {
        // Absolute path — resolve from base dir
        const target = resolve(baseDir, "." + filePart);
        return { filePath: target, anchor };
    } else {
        const target = resolve(dirname(fromFile), filePart);
        return { filePath: target, anchor };
    }
}

// ---------------------------------------------------------------------------
// Topological ordering of files (dependencies first)
// ---------------------------------------------------------------------------

async function getPackageRoot(
    filePath: string,
    cache: Map<string, string>,
): Promise<string> {
    const dir = dirname(filePath);
    const cached = cache.get(dir);
    if (cached !== undefined) return cached;
    try {
        const located = await locatePackage(dir);
        cache.set(dir, located.root);
        return located.root;
    } catch {
        cache.set(dir, dir);
        return dir;
    }
}

function topoOrderFiles(
    files: ReadonlyMap<string, FileTree>,
    inclusions: ReadonlyMap<string, FileInclusion>,
    packageRoots: ReadonlyMap<string, string>,
): string[] {
    // Build adjacency: F -> set of files G that F's emitted nodes link to.
    const outgoing = new Map<string, Set<string>>();
    for (const [filePath, tree] of files) {
        const inc = inclusions.get(filePath)!;
        const out = new Set<string>();
        outgoing.set(filePath, out);

        const definitions = collectDefinitions(tree.root);
        const visit = (idx: number): void => {
            const urls: string[] = [];
            collectFromNode(tree.root.children[idx]!, urls);
            for (const raw of urls) {
                const u = resolveUrl(raw, definitions);
                if (u === null) continue;
                const t = resolveLinkTarget(u, filePath, packageRoots.get(dirname(filePath)) ?? dirname(filePath));
                if (t === null) continue;
                if (files.has(t.filePath) && t.filePath !== filePath) {
                    out.add(t.filePath);
                }
            }
        };

        if (inc.whole) {
            for (let i = 0; i < tree.root.children.length; i++) visit(i);
        } else {
            const indices = collectIncludedIndices(tree, inc);
            for (const i of indices) visit(i);
        }
    }

    // Iterative DFS for topological sort (post-order). Cycles broken by
    // ignoring back-edges to nodes still on the stack.
    const order: string[] = [];
    const state = new Map<string, "white" | "grey" | "black">();
    for (const f of files.keys()) state.set(f, "white");

    const sortedKeys = [...files.keys()].sort();
    for (const start of sortedKeys) {
        if (state.get(start) !== "white") continue;
        const stack: { file: string; iter: Iterator<string> }[] = [
            { file: start, iter: outgoing.get(start)![Symbol.iterator]() },
        ];
        state.set(start, "grey");
        while (stack.length > 0) {
            const top = stack[stack.length - 1]!;
            const next = top.iter.next();
            if (next.done) {
                state.set(top.file, "black");
                order.push(top.file);
                stack.pop();
            } else {
                const child = next.value;
                if (state.get(child) === "white") {
                    state.set(child, "grey");
                    stack.push({ file: child, iter: outgoing.get(child)![Symbol.iterator]() });
                }
                // grey/black: skip (back-edge or already processed)
            }
        }
    }
    return order;
}

// ---------------------------------------------------------------------------
// Per-file emission plan (which root.children indices to emit)
// ---------------------------------------------------------------------------

interface EmissionPlan {
    /** Indices into root.children, ascending. */
    readonly indices: readonly number[];
    /** Sections that get emitted (their headingIdx is in `indices`). */
    readonly emittedSections: readonly SectionNode[];
}

function planEmission(tree: FileTree, inc: FileInclusion): EmissionPlan {
    const idxSet = collectIncludedIndices(tree, inc);
    const indices = [...idxSet].sort((a, b) => a - b);
    const emittedSections: SectionNode[] = [];
    for (const sec of tree.all) {
        if (idxSet.has(sec.headingIdx)) emittedSections.push(sec);
    }
    return { indices, emittedSections };
}

function collectIncludedIndices(tree: FileTree, inc: FileInclusion): Set<number> {
    const idx = new Set<number>();
    if (inc.whole) {
        for (let i = 0; i < tree.root.children.length; i++) idx.add(i);
        return idx;
    }
    for (const sec of inc.marked) {
        // Full subtree.
        for (let i = sec.headingIdx; i < sec.subtreeEnd; i++) idx.add(i);
        // Ancestors' framing context (heading + intro prose).
        let p = sec.parent;
        while (p !== null) {
            const introEnd = p.children.length > 0 ? p.children[0]!.headingIdx : p.subtreeEnd;
            for (let i = p.headingIdx; i < introEnd; i++) idx.add(i);
            p = p.parent;
        }
    }
    return idx;
}

// ---------------------------------------------------------------------------
// Global anchor assignment
// ---------------------------------------------------------------------------

/**
 * Map (filePath → localSlug → globalAnchor). Globally unique anchors
 * are derived from local slugs; collisions append -2, -3, …
 */
type GlobalAnchors = ReadonlyMap<string, ReadonlyMap<string, string>>;

function assignGlobalAnchors(
    order: readonly string[],
    files: ReadonlyMap<string, FileTree>,
    plans: ReadonlyMap<string, EmissionPlan>,
): GlobalAnchors {
    const used = new Set<string>();
    const out = new Map<string, Map<string, string>>();
    for (const filePath of order) {
        const plan = plans.get(filePath)!;
        const fileMap = new Map<string, string>();
        out.set(filePath, fileMap);
        for (const sec of plan.emittedSections) {
            const base = sec.slug;
            let chosen = base;
            let n = 2;
            while (used.has(chosen)) {
                chosen = `${base}-${n}`;
                n++;
            }
            used.add(chosen);
            fileMap.set(sec.slug, chosen);
        }
        // Ensure the file has a "primary" anchor reachable by bare-file links —
        // that's just the first emitted section's anchor, accessed via the
        // file's first emitted section in fileMap insertion order.
    }
    return out;
}

function primaryAnchor(filePath: string, anchors: GlobalAnchors): string | null {
    const fileMap = anchors.get(filePath);
    if (fileMap === undefined) return null;
    const first = fileMap.values().next();
    return first.done === true ? null : first.value;
}

// ---------------------------------------------------------------------------
// Link rewriting
// ---------------------------------------------------------------------------

function rewriteLinks(
    node: Content,
    fromFile: string,
    files: ReadonlyMap<string, FileTree>,
    anchors: GlobalAnchors,
): Content {
    // Collect the source file's definitions so reference-style links can
    // be resolved (we only rewrite the definition's URL, leaving the
    // identifier in place).
    return rewriteNode(node, fromFile, files, anchors) as Content;
}

function rewriteNode(
    node: unknown,
    fromFile: string,
    files: ReadonlyMap<string, FileTree>,
    anchors: GlobalAnchors,
): unknown {
    if (typeof node !== "object" || node === null) return node;
    const obj = node as Record<string, unknown>;

    if (obj["type"] === "link" && typeof obj["url"] === "string") {
        const link = obj as unknown as Link;
        const newUrl = rewriteUrl(link.url, fromFile, files, anchors);
        if (newUrl !== null) {
            return { ...link, url: newUrl } as Link;
        }
    } else if (obj["type"] === "definition" && typeof obj["url"] === "string") {
        const def = obj as unknown as Definition;
        const newUrl = rewriteUrl(def.url, fromFile, files, anchors);
        if (newUrl !== null) {
            return { ...def, url: newUrl } as Definition;
        }
    }

    const children = obj["children"];
    if (Array.isArray(children)) {
        const newChildren = children.map((c) => rewriteNode(c, fromFile, files, anchors));
        return { ...obj, children: newChildren };
    }
    return obj;
}

function rewriteUrl(
    url: string,
    fromFile: string,
    files: ReadonlyMap<string, FileTree>,
    anchors: GlobalAnchors,
): string | null {
    if (/^https?:\/\//.test(url) || url.startsWith("mailto:")) return null;
    const hashIdx = url.indexOf("#");
    const filePart = hashIdx >= 0 ? url.slice(0, hashIdx) : url;
    const anchor = hashIdx >= 0 ? url.slice(hashIdx + 1) : null;

    // Same-file anchor — possibly remap due to global collision suffix.
    if (filePart === "") {
        if (anchor === null) return null;
        const fileMap = anchors.get(fromFile);
        const remapped = fileMap?.get(anchor);
        return remapped !== undefined ? `#${remapped}` : null;
    }

    const target = resolve(dirname(fromFile), filePart);
    if (!files.has(target)) return null;

    if (anchor === null) {
        const a = primaryAnchor(target, anchors);
        return a !== null ? `#${a}` : null;
    }
    const fileMap = anchors.get(target);
    const remapped = fileMap?.get(anchor);
    return remapped !== undefined ? `#${remapped}` : null;
}
