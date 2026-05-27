/**
 * `substrate dev` — local development server.
 *
 * Starts an HTTP server that hosts a React-based markdown viewer over the
 * specified directory. Watches the directory recursively and pushes
 * change notifications to connected clients over WebSocket so the UI
 * reloads automatically when files change on disk.
 *
 * See `specs/tools/cli/dev.md` for behaviour.
 */
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { dirname, extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import chokidar from "chokidar";
import { marked } from "marked";
import { WebSocketServer, type WebSocket } from "ws";

import { locatePackage } from "../package/corpus.js";
import type { Manifest } from "../package/manifest.js";
import { decodeSubstrateDistribution, tryDecodeSubstrateDistribution } from "../ir/codec.js";
import { buildSourceLocationIndex } from "../ir/source-location.js";
import type { SimplifiedModuleFile } from "../ir/simplified.js";

export interface DevOptions {
    readonly dir?: string;
    readonly port?: number;
    readonly host?: string;
    readonly open?: boolean;
}

export interface DevServer {
    readonly url: string;
    readonly root: string;
    readonly manifestPath: string;
    readonly manifest: Manifest;
    close(): Promise<void>;
}

const MIME: Record<string, string> = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".json": "application/json; charset=utf-8",
    ".woff2": "font/woff2",
};

export async function startDev(opts: DevOptions = {}): Promise<DevServer> {
    const startDir = resolve(opts.dir ?? process.cwd());
    const startStat = await stat(startDir).catch(() => null);
    if (!startStat || !startStat.isDirectory()) {
        throw new Error(`dev: ${startDir} is not a directory`);
    }

    // Walk up from the requested directory to the closest enclosing
    // `substrate.json`. The located package's root becomes the served
    // directory, so the dev UI sees the whole project — including its
    // vendored dependencies under `substrate/` — rather than an
    // arbitrary subdirectory of it.
    const located = await locatePackage(startDir);
    const root = located.root;

    const webRoot = await locateWebAssetsRoot();

    const server = createServer((req, res) => {
        handle(req, res, { root, webRoot }).catch((err) => {
            console.error(err);
            if (!res.headersSent) {
                res.writeHead(500, { "content-type": "text/plain" });
            }
            res.end(String(err));
        });
    });

    const wss = new WebSocketServer({ server, path: "/_ws" });
    const clients = new Set<WebSocket>();
    wss.on("connection", (ws) => {
        clients.add(ws);
        ws.on("close", () => clients.delete(ws));
    });

    // Track raw TCP sockets so shutdown can forcibly close them; otherwise
    // `server.close()` waits for every keep-alive / WebSocket connection
    // to drain on its own, which means Ctrl+C appears to hang.
    const sockets = new Set<import("node:net").Socket>();
    server.on("connection", (socket) => {
        sockets.add(socket);
        socket.once("close", () => sockets.delete(socket));
    });

    const broadcast = (msg: object): void => {
        const data = JSON.stringify(msg);
        for (const ws of clients) {
            if (ws.readyState === ws.OPEN) ws.send(data);
        }
    };

    const watcher = chokidar.watch(root, {
        ignored: (p) => {
            const base = p.split(/[\\/]/).pop() ?? "";
            return (
                base.startsWith(".") ||
                base === "node_modules" ||
                base === "dist"
            );
        },
        ignoreInitial: true,
        awaitWriteFinish: { stabilityThreshold: 80, pollInterval: 30 },
    });

    const notify = (type: string) => (absPath: string) => {
        const rel = relative(root, absPath).split(sep).join("/");
        broadcast({ type, path: rel });
    };
    watcher.on("add", notify("add"));
    watcher.on("change", notify("change"));
    watcher.on("unlink", notify("unlink"));
    watcher.on("addDir", notify("addDir"));
    watcher.on("unlinkDir", notify("unlinkDir"));

    const host = opts.host ?? "127.0.0.1";
    const port = opts.port ?? 0;
    await new Promise<void>((res2, rej) => {
        server.once("error", rej);
        server.listen(port, host, () => res2());
    });
    const addr = server.address();
    if (!addr || typeof addr === "string") {
        throw new Error("dev: failed to bind server");
    }
    const url = `http://${host}:${addr.port}/`;

    return {
        url,
        root,
        manifestPath: located.manifestPath,
        manifest: located.manifest,
        close: (() => {
            let closing: Promise<void> | null = null;
            return () => {
                if (closing) return closing;
                closing = (async () => {
                    await watcher.close();
                    for (const ws of clients) {
                        try { ws.terminate(); } catch { /* ignore */ }
                    }
                    clients.clear();
                    await new Promise<void>((res2) => wss.close(() => res2()));
                    for (const socket of sockets) {
                        try { socket.destroy(); } catch { /* ignore */ }
                    }
                    sockets.clear();
                    await new Promise<void>((res2) => server.close(() => res2()));
                })();
                return closing;
            };
        })(),
    };
}

interface HandlerCtx {
    root: string;
    webRoot: string;
}

async function handle(
    req: IncomingMessage,
    res: ServerResponse,
    ctx: HandlerCtx,
): Promise<void> {
    const url = new URL(req.url ?? "/", "http://localhost");
    const pathname = decodeURIComponent(url.pathname);

    // API: list tree of markdown files.
    if (pathname === "/api/tree") {
        const tree = await buildTree(ctx.root);
        return sendJSON(res, tree);
    }

    // API: get a single markdown file rendered to HTML.
    if (pathname === "/api/doc") {
        const rel = url.searchParams.get("path") ?? "";
        const safe = safeJoin(ctx.root, rel);
        if (!safe) return send(res, 400, "Bad path");
        try {
            const [raw, st] = await Promise.all([
                readFile(safe, "utf8"),
                stat(safe),
            ]);
            const html = marked.parse(raw, { async: false }) as string;
            return sendJSON(res, {
                path: rel,
                html,
                raw,
                lastModified: st.mtime.toISOString(),
            });
        } catch {
            return send(res, 404, "Not found");
        }
    }

    if (pathname === "/api/ir") {
        const morphirJsonPath = safeJoin(ctx.root, "morphir.json");
        if (!morphirJsonPath) return send(res, 400, "Bad path");
        let raw: string;
        try {
            raw = await readFile(morphirJsonPath, "utf8");
        } catch {
            return send(res, 404, "morphir.json not found");
        }
        let parsed: unknown;
        try {
            parsed = JSON.parse(raw);
        } catch {
            return send(res, 500, "morphir.json is not valid JSON");
        }
        const result = tryDecodeSubstrateDistribution(parsed);
        if (!result.ok) {
            return send(res, 500, `IR decode error: ${result.error.message}`);
        }
        const index = buildSourceLocationIndex(result.value);
        return sendJSON(res, {
            distribution: parsed,
            forwardIndex: Array.from(index.forward.entries()),
            reverseIndex: Array.from(index.reverse.entries()).map(
                ([k, v]) => [k, Array.from(v)] as const,
            ),
        });
    }

    // API: simplified IR — walks a `simplified-ir/` directory in the
    // served root (the output of `morphir simplify`) and returns each
    // per-module JSON file together with its module path.  The browser
    // decodes them into a Distribution using `web/src/ir/simplified.ts`.
    if (pathname === "/api/simplified-ir") {
        const dir = safeJoin(ctx.root, "simplified-ir");
        if (!dir) return send(res, 400, "Bad path");
        try {
            const st = await stat(dir);
            if (!st.isDirectory()) return send(res, 404, "simplified-ir not found");
        } catch {
            return send(res, 404, "simplified-ir not found");
        }
        const files = await readSimplifiedDir(dir);
        return sendJSON(res, { files });
    }

    // Static web client assets.
    const webPath = pathname === "/" ? "/index.html" : pathname;
    const filePath = safeJoin(ctx.webRoot, webPath);
    if (filePath) {
        try {
            const ext = extname(filePath).toLowerCase();
            const mime = MIME[ext] ?? "application/octet-stream";
            return await sendFile(res, filePath, mime);
        } catch {
            // fall through
        }
    }
    return send(res, 404, "Not found");
}

interface TreeNode {
    name: string;
    path: string;
    type: "file" | "dir";
    children?: TreeNode[];
}

async function buildTree(root: string): Promise<TreeNode> {
    const { readdir } = await import("node:fs/promises");

    async function walk(absDir: string): Promise<TreeNode[]> {
        const entries = await readdir(absDir, { withFileTypes: true });
        const nodes: TreeNode[] = [];
        for (const entry of entries) {
            const name = entry.name;
            if (name.startsWith(".") || name === "node_modules" || name === "dist") continue;
            const abs = join(absDir, name);
            const rel = relative(root, abs).split(sep).join("/");
            if (entry.isDirectory()) {
                const children = await walk(abs);
                if (children.length > 0) {
                    nodes.push({ name, path: rel, type: "dir", children });
                }
            } else if (entry.isFile() && name.toLowerCase().endsWith(".md")) {
                nodes.push({ name, path: rel, type: "file" });
            }
        }
        nodes.sort((a, b) => {
            if (a.type !== b.type) return a.type === "dir" ? -1 : 1;
            return a.name.localeCompare(b.name);
        });
        return nodes;
    }

    return {
        name: root.split(sep).pop() ?? root,
        path: "",
        type: "dir",
        children: await walk(root),
    };
}

async function readSimplifiedDir(dir: string): Promise<SimplifiedModuleFile[]> {
    const { readdir } = await import("node:fs/promises");
    const out: SimplifiedModuleFile[] = [];
    async function walk(abs: string): Promise<void> {
        const entries = await readdir(abs, { withFileTypes: true });
        for (const entry of entries) {
            const childAbs = join(abs, entry.name);
            if (entry.isDirectory()) {
                await walk(childAbs);
            } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".json")) {
                const raw = await readFile(childAbs, "utf8");
                const rel = relative(dir, childAbs).split(sep).join("/");
                try {
                    out.push({ relPath: rel, json: JSON.parse(raw) });
                } catch {
                    // Skip malformed files but don't fail the whole index.
                }
            }
        }
    }
    await walk(dir);
    return out;
}

function safeJoin(base: string, rel: string): string | null {
    const normalised = rel.replace(/^\/+/, "");
    const abs = resolve(base, normalised);
    const baseResolved = resolve(base);
    if (abs !== baseResolved && !abs.startsWith(baseResolved + sep)) return null;
    return abs;
}

function send(res: ServerResponse, status: number, body: string): void {
    res.writeHead(status, { "content-type": "text/plain; charset=utf-8" });
    res.end(body);
}

function sendJSON(res: ServerResponse, value: unknown): void {
    res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(value));
}

async function sendFile(
    res: ServerResponse,
    path: string,
    mime: string,
): Promise<void> {
    const body = await readFile(path);
    res.writeHead(200, { "content-type": mime });
    res.end(body);
}

/**
 * Locate the bundled `assets/web/` directory. Walks up from this file
 * looking for the `@morphir/substrate` package root (same approach used
 * by ai-instructions.ts).
 */
async function locateWebAssetsRoot(): Promise<string> {
    const pkgRoot = await locatePackageRoot();
    if (!pkgRoot) throw new Error("dev: could not locate substrate package root");
    return join(pkgRoot, "assets", "web");
}

async function locatePackageRoot(): Promise<string | null> {
    const here = fileURLToPath(new URL(".", import.meta.url));
    let dir = resolve(here);
    while (true) {
        const candidate = join(dir, "package.json");
        try {
            const raw = await readFile(candidate, "utf8");
            const parsed = JSON.parse(raw) as { name?: string };
            if (parsed.name === "@morphir/substrate") return dir;
        } catch {
            // not present or unreadable — keep walking
        }
        const parent = dirname(dir);
        if (parent === dir) return null;
        dir = parent;
    }
}
