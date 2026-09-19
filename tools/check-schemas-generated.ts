// Fails when a JSON schema under website/static/schemas differs from what
// `mise run website:build-schemas` generates from the YAML sources.
//
// Usage (from the parent repository root):
//
//   bun run tools/check-schemas-generated.ts
//
// The YAML files are the source; the JSON files are generated and formatted
// from them, then committed. `schema:validate` only validates the JSON and
// `check:config-schema-sync` only compares it with morphir-rust's copy, so
// without this a YAML-only change passes and the next regeneration rewrites
// the JSON unannounced.
//
// This snapshots every JSON schema, runs the generator in place, and compares.
// In CI the snapshot is the committed state. Locally it is the working tree,
// so in-progress edits are compared rather than HEAD. Either way the files are
// left regenerated, which is the fix to commit when the check fails.
import { spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export type Drift = { file: string; change: "changed" | "added" | "removed" };

const normalise = (text: string) => text.replace(/\r\n/g, "\n");

/** Files whose content differs between two snapshots, sorted by name. */
export function schemaDrift(before: Map<string, string>, after: Map<string, string>): Drift[] {
	const names = [...new Set([...before.keys(), ...after.keys()])].sort();
	return names.flatMap((file): Drift[] => {
		const was = before.get(file);
		const now = after.get(file);
		if (was === undefined) return [{ file, change: "added" }];
		if (now === undefined) return [{ file, change: "removed" }];
		return normalise(was) === normalise(now) ? [] : [{ file, change: "changed" }];
	});
}

function snapshot(directory: string): Map<string, string> {
	return new Map(
		readdirSync(directory)
			.filter((name) => name.endsWith(".json"))
			.map((name) => [name, readFileSync(path.join(directory, name), "utf8")]),
	);
}

if (import.meta.main) {
	const repositoryRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
	const schemas = path.join(repositoryRoot, "website", "static", "schemas");
	const relativeSchemas = path.relative(repositoryRoot, schemas).split(path.sep).join("/");

	const before = snapshot(schemas);
	const build = spawnSync("mise", ["run", "website:build-schemas"], {
		cwd: repositoryRoot,
		stdio: "inherit",
		windowsHide: true,
		shell: process.platform === "win32",
	});
	if (build.status !== 0) {
		console.error(`mise run website:build-schemas failed (exit ${build.status ?? build.signal})`);
		process.exit(1);
	}
	const after = snapshot(schemas);

	const drift = schemaDrift(before, after);
	if (drift.length === 0) {
		console.log(`Every JSON schema in ${relativeSchemas} matches its YAML source.`);
		process.exit(0);
	}

	const previous = mkdtempSync(path.join(tmpdir(), "schemas-generated-"));
	for (const { file, change } of drift) {
		console.error(`${relativeSchemas}/${file}: ${change} by regeneration`);
		if (change !== "changed") continue;
		const was = path.join(previous, file);
		writeFileSync(was, normalise(before.get(file) ?? ""));
		spawnSync("git", ["--no-pager", "diff", "--no-index", "--", was, path.join(schemas, file)], {
			stdio: "inherit",
			windowsHide: true,
		});
	}
	console.error(
		"The committed JSON schemas are out of date with their YAML sources. " +
			"They have been regenerated in place: review and commit them.",
	);
	process.exit(1);
}
