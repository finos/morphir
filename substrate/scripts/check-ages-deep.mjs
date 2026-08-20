#!/usr/bin/env node
// Audit every installed package (including transitive deps) across the
// root and web/ node_modules trees. Flags anything published less than
// 7 days ago.
//
// Cost: one `npm view <name> time --json` per unique package name (cached
// by name across versions). Slow first run; faster on warm npm cache.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readdir, readFile } from "node:fs/promises";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const exec = promisify(execFile);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const MS_PER_DAY = 86_400_000;
const CUTOFF_DAYS = 7;
const PARALLEL = 8;

async function walkNodeModules(dir, out = new Map()) {
    let entries;
    try {
        entries = await readdir(dir, { withFileTypes: true });
    } catch {
        return out;
    }
    for (const e of entries) {
        if (!e.isDirectory()) continue;
        if (e.name === ".bin" || e.name === ".cache") continue;
        const sub = join(dir, e.name);
        if (e.name.startsWith("@")) {
            // Scoped: recurse into scope, treat each child as a package.
            const scoped = await readdir(sub, { withFileTypes: true });
            for (const s of scoped) {
                if (s.isDirectory()) {
                    await collect(join(sub, s.name), out);
                }
            }
        } else {
            await collect(sub, out);
        }
    }
    return out;
}

async function collect(pkgDir, out) {
    try {
        const meta = JSON.parse(
            await readFile(join(pkgDir, "package.json"), "utf8"),
        );
        if (meta.name && meta.version) {
            const key = `${meta.name}@${meta.version}`;
            if (!out.has(key)) {
                out.set(key, { name: meta.name, version: meta.version });
            }
        }
    } catch {
        // empty / bad package — skip
    }
    // Nested node_modules (npm sometimes nests).
    await walkNodeModules(join(pkgDir, "node_modules"), out);
}

const timeCache = new Map();
async function getTimes(name) {
    if (timeCache.has(name)) return timeCache.get(name);
    const p = (async () => {
        const { stdout } = await exec(
            "npm",
            ["view", name, "time", "--json"],
            { shell: true, maxBuffer: 20 * 1024 * 1024 },
        );
        return JSON.parse(stdout);
    })();
    timeCache.set(name, p);
    return p;
}

async function withConcurrency(items, n, fn) {
    const results = [];
    let i = 0;
    const workers = Array.from({ length: n }, async () => {
        while (i < items.length) {
            const idx = i++;
            results[idx] = await fn(items[idx]);
        }
    });
    await Promise.all(workers);
    return results;
}

const trees = [
    join(root, "node_modules"),
    join(root, "web", "node_modules"),
];
const installed = new Map();
for (const t of trees) await walkNodeModules(t, installed);

const list = [...installed.values()];
const now = Date.now();
console.log(`Auditing ${list.length} installed packages…`);

const rows = await withConcurrency(list, PARALLEL, async (p) => {
    try {
        const times = await getTimes(p.name);
        const t = times[p.version];
        if (!t) return { ...p, ageDays: null, error: "no publish time" };
        const ageDays = Math.floor((now - new Date(t).getTime()) / MS_PER_DAY);
        return { ...p, ageDays, published: t };
    } catch (e) {
        return { ...p, error: e.message };
    }
});

const risky = rows.filter((r) => typeof r.ageDays === "number" && r.ageDays < CUTOFF_DAYS);
risky.sort((a, b) => a.ageDays - b.ageDays);

if (risky.length === 0) {
    console.log("OK — no installed package is younger than 7 days.");
    process.exit(0);
}

console.log(`\nFound ${risky.length} package(s) younger than ${CUTOFF_DAYS} days:\n`);
const w = (s, n) => String(s).padEnd(n);
console.log(w("package", 36), w("version", 14), w("age (days)", 12), "published");
for (const r of risky) {
    console.log(
        w(r.name, 36),
        w(r.version, 14),
        w(r.ageDays, 12),
        r.published,
    );
}
process.exit(1);
