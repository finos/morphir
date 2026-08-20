#!/usr/bin/env node
// For each direct dep, find the latest version satisfying its declared
// range and report its publish age. Flags ranges that would resolve to
// a release younger than the 7-day cutoff on a fresh install.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import semver from "semver";

const exec = promisify(execFile);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const cutoffMs = 7 * 86_400_000;

function direct(pkgPath) {
    const pkg = JSON.parse(readFileSync(resolve(root, pkgPath), "utf8"));
    return { ...pkg.dependencies, ...pkg.devDependencies };
}

async function meta(name) {
    const { stdout } = await exec(
        "npm",
        ["view", name, "versions", "time", "--json"],
        { shell: true, maxBuffer: 10 * 1024 * 1024 },
    );
    return JSON.parse(stdout);
}

async function check(file) {
    const deps = direct(file);
    const now = Date.now();
    const rows = await Promise.all(
        Object.entries(deps).map(async ([name, range]) => {
            try {
                const m = await meta(name);
                const candidates = m.versions
                    .filter((v) => !semver.prerelease(v))
                    .filter((v) => semver.satisfies(v, range));
                const latest = semver.maxSatisfying(candidates, range);
                const t = m.time[latest];
                const ageDays = Math.floor(
                    (now - new Date(t).getTime()) / 86_400_000,
                );
                return {
                    name,
                    range,
                    latestMatch: latest,
                    ageDays,
                    risky: ageDays < 7,
                };
            } catch (e) {
                return { name, range, error: e.message };
            }
        }),
    );
    rows.sort((a, b) => (a.ageDays ?? 1e9) - (b.ageDays ?? 1e9));
    console.log(`\n# ${file}`);
    const w = (s, n) => String(s).padEnd(n);
    console.log(
        w("package", 26),
        w("range", 14),
        w("latest match", 14),
        w("age", 5),
        "risky?",
    );
    for (const r of rows) {
        console.log(
            w(r.name, 26),
            w(r.range, 14),
            w(r.latestMatch ?? "?", 14),
            w(r.ageDays ?? "?", 5),
            r.risky ? "YES" : "no",
        );
    }
}

await check("package.json");
await check("web/package.json");
