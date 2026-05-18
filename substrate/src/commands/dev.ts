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

export interface DevOptions {
    readonly dir?: string;
    readonly port?: number;
    readonly host?: string;
    readonly open?: boolean;
}

export interface DevServer {
    readonly url: string;
    readonly root: string;
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
    const root = resolve(opts.dir ?? process.cwd());
    const rootStat = await stat(root).catch(() => null);
    if (!rootStat || !rootStat.isDirectory()) {
        throw new Error(`dev: ${root} is not a directory`);
    }

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
        async close() {
            await watcher.close();
            wss.close();
            await new Promise<void>((res2) => server.close(() => res2()));
        },
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
            const raw = await readFile(safe, "utf8");
            const html = marked.parse(raw, { async: false }) as string;
            return sendJSON(res, {
                path: rel,
                html,
                raw,
            });
        } catch {
            return send(res, 404, "Not found");
        }
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
