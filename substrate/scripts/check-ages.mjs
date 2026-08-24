#!/usr/bin/env node
// One-off helper. Resolves the actual installed version of each direct dep
// and prints its publish date plus age in days.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const exec = promisify(execFile);

const root = resolve(import.meta.dirname, "..");

function direct(pkgPath, scope) {
    const pkg = JSON.parse(readFileSync(resolve(root, pkgPath), "utf8"));
    const all = { ...pkg.dependencies, ...pkg.devDependencies };
    return Object.keys(all).map((name) => ({ name, scope }));
}

function resolveVersion({ name, scope }) {
    const base = scope === "root" ? "node_modules" : "web/node_modules";
    const p = resolve(root, base, name, "package.json");
    return JSON.parse(readFileSync(p, "utf8")).version;
}

async function publishedAt(name, version) {
    const { stdout } = await exec(
        "npm",
        ["view", name, "time", "--json"],
        { shell: true, maxBuffer: 10 * 1024 * 1024 },
    );
    const times = JSON.parse(stdout);
    return times[version] ?? null;
}

const pkgs = [
    ...direct("package.json", "root"),
    ...direct("web/package.json", "web"),
];

const now = Date.now();
const results = await Promise.all(
    pkgs.map(async (p) => {
        const version = resolveVersion(p);
        try {
            const t = await publishedAt(p.name, version);
            const ageDays = t
                ? Math.floor((now - new Date(t).getTime()) / 86_400_000)
                : null;
            return { ...p, version, published: t, ageDays };
        } catch (e) {
            return { ...p, version, error: e.message };
        }
    }),
);

results.sort((a, b) => (a.ageDays ?? 1e9) - (b.ageDays ?? 1e9));
const w = (s, n) => String(s).padEnd(n);
console.log(w("package", 30), w("version", 12), w("published", 22), "age (days)");
for (const r of results) {
    console.log(
        w(r.name, 30),
        w(r.version, 12),
        w(r.published ?? "?", 22),
        r.ageDays ?? r.error ?? "?",
    );
}
