/**
 * Compute an integrity hash for an installed package tree.
 *
 * The hash is a SHA-256 over the sorted list of (relative-path,
 * file-contents) pairs, encoded as a single stream. This gives a
 * stable digest that detects any content change or re-ordering.
 */
import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { join, relative, sep } from "node:path";

/**
 * Compute `sha256-<base64>` over every file under `root`, excluding
 * the `.git` directory.
 */
export async function computeIntegrity(root: string): Promise<string> {
    const files = await listFiles(root);
    files.sort((a, b) => a.localeCompare(b));

    const hash = createHash("sha256");
    for (const file of files) {
        const rel = relative(root, file).split(sep).join("/");
        hash.update(rel);
        hash.update("\0");
        const content = await readFile(file);
        hash.update(content);
        hash.update("\0");
    }
    return `sha256-${hash.digest("base64")}`;
}

async function listFiles(root: string): Promise<string[]> {
    const out: string[] = [];
    async function walk(dir: string): Promise<void> {
        const entries = await readdir(dir, { withFileTypes: true });
        for (const entry of entries) {
            if (entry.name === ".git") continue;
            const full = join(dir, entry.name);
            if (entry.isDirectory()) {
                await walk(full);
            } else if (entry.isFile()) {
                out.push(full);
            }
        }
    }
    await walk(root);
    return out;
}
