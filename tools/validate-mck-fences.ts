// Validates every canonical and accepted JSON fence of the Morphir Compatibility
// Kit against the v4 JSON Schema, so the kit and the schema cannot drift.
//
//   bun run tools/validate-mck-fences.ts
//
// A case heading names the model type its fences decode to (`{node=Type}`); the
// node maps to a definition of website/static/schemas/morphir-ir-v4.json, and the
// fence body must validate against it. Fences carrying `warning=` are the legacy
// spellings of decision 0006: a reader normalizes them and reports the warning,
// but the schema deliberately does not describe them, so they are skipped here.
import { Glob } from "bun";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const kitDir = path.join(repositoryRoot, "spec", "ir", "mck");
const schemaPath = path.join(
	repositoryRoot,
	"website",
	"static",
	"schemas",
	"morphir-ir-v4.json",
);

/** The IR version this checker knows how to validate. */
const SUPPORTED_VERSION = "4";

/**
 * Model type named by a case heading, mapped to the schema location its fences
 * must validate against. `""` is the root schema rather than a definition.
 */
const NODE_ENTRYPOINTS: Readonly<Record<string, string>> = {
	Distribution: "",
	FormatVersion: "#/definitions/FormatVersion",
	Name: "#/definitions/Name",
	Path: "#/definitions/Path",
	FQName: "#/definitions/FQName",
	Type: "#/definitions/Type",
	Value: "#/definitions/Value",
	Pattern: "#/definitions/Pattern",
	Literal: "#/definitions/Literal",
	TypeSpecification: "#/definitions/TypeSpecification",
	TypeDefinition: "#/definitions/TypeDefinition",
	ValueSpecification: "#/definitions/ValueSpecification",
	ValueDefinition: "#/definitions/ValueDefinition",
	ModuleSpecification: "#/definitions/ModuleSpecification",
	ModuleDefinition: "#/definitions/ModuleDefinition",
	AccessControlledTypeDefinition:
		"#/definitions/AccessControlledTypeDefinition",
	AccessControlledValueDefinition:
		"#/definitions/AccessControlledValueDefinition",
};

// ---------------------------------------------------------------- the kit

interface Fence {
	readonly caseId: string;
	readonly node: string;
	readonly index: number;
	readonly role: string;
	readonly body: string;
	readonly sourceFile: string;
	readonly line: number;
}

type Outcome = "ok" | "fail" | "skip";

interface Result {
	readonly fence: Fence;
	outcome: Outcome;
	message: string;
}

const CASE_HEADING = /^##\s+([a-z][a-z-]*-\d{4}):\s*(.*)$/;
const FENCE_OPEN = /^```(\S+)((?:\s+\S+)*)\s*$/;

/** Reads `key=value` pairs out of a `{ .. }` suffix on a case heading. */
function headingKeys(title: string): Record<string, string> {
	const braces = title.match(/\{([^}]*)\}\s*$/);
	const keys: Record<string, string> = {};
	if (!braces) return keys;
	for (const pair of braces[1].split(/\s+/)) {
		const [name, value] = pair.split("=");
		if (name && value !== undefined) keys[name] = value;
	}
	return keys;
}

/**
 * Splits a fence info string tail into its role and its `key=value` pairs. The
 * info string is `<language> <role> [key=value ...]`.
 */
function fenceInfo(tail: string): {
	role: string;
	keys: Record<string, string>;
} {
	const tokens = tail.trim().split(/\s+/).filter(Boolean);
	const keys: Record<string, string> = {};
	for (const pair of tokens.slice(1)) {
		const [name, value] = pair.split("=");
		if (name && value !== undefined) keys[name] = value;
	}
	return { role: tokens[0] ?? "", keys };
}

interface ActiveCase {
	readonly id: string;
	readonly node: string;
	count: number;
}

function collectFences(file: string, text: string): Fence[] {
	const fences: Fence[] = [];
	const lines = text.split(/\r?\n/);
	let current: ActiveCase | null = null;
	let open: {
		language: string;
		role: string;
		keys: Record<string, string>;
	} | null = null;
	let body: string[] = [];
	let openLine = 0;

	for (const [offset, line] of lines.entries()) {
		if (open) {
			if (line.trimEnd() === "```") {
				if (
					current &&
					open.language === "json" &&
					(open.role === "canonical" || open.role === "accepted")
				) {
					current.count += 1;
					if (open.keys.warning === undefined) {
						fences.push({
							caseId: current.id,
							node: current.node,
							index: current.count,
							role: open.role,
							body: body.join("\n"),
							sourceFile: file,
							line: openLine,
						});
					} else {
						fences.push({
							caseId: current.id,
							node: "",
							index: current.count,
							role: "window",
							body: "",
							sourceFile: file,
							line: openLine,
						});
					}
				}
				open = null;
				body = [];
			} else {
				body.push(line);
			}
			continue;
		}

		const fenceOpen = line.match(FENCE_OPEN);
		if (fenceOpen) {
			const info = fenceInfo(fenceOpen[2] ?? "");
			open = { language: fenceOpen[1], role: info.role, keys: info.keys };
			body = [];
			openLine = offset + 1;
			continue;
		}

		if (line.startsWith("## ")) {
			const heading = line.match(CASE_HEADING);
			current = null;
			if (!heading) continue;
			const keys = headingKeys(heading[2]);
			if (keys.status === "pending") continue;
			if (keys.version !== undefined && keys.version !== SUPPORTED_VERSION) {
				continue;
			}
			current = { id: heading[1], node: keys.node ?? "", count: 0 };
		}
	}

	return fences;
}

// ---------------------------------------------------------------- validation

/** Runs the jsonschema CLI over a directory of instances at one entry point. */
function validateDirectory(
	directory: string,
	entrypoint: string,
): Map<string, boolean> {
	const args = ["validate", schemaPath, directory, "--verbose", "--continue"];
	if (entrypoint !== "") args.push("--entrypoint", entrypoint);
	const run = Bun.spawnSync(["jsonschema", ...args], { cwd: repositoryRoot });
	const output = `${run.stdout.toString()}\n${run.stderr.toString()}`;
	const verdicts = new Map<string, boolean>();
	for (const line of output.split(/\r?\n/)) {
		const match = line.match(/^(ok|fail):\s+(.*)$/);
		if (!match) continue;
		verdicts.set(path.basename(match[2].trim()), match[1] === "ok");
	}
	return verdicts;
}

/**
 * Re-runs one instance to get a short reason for its failure. The CLI reports
 * every branch of every union it tried, so the most informative single line is
 * the one about the deepest place in the instance it got to.
 */
function failureMessage(instance: string, entrypoint: string): string {
	const args = ["validate", schemaPath, instance];
	if (entrypoint !== "") args.push("--entrypoint", entrypoint);
	const run = Bun.spawnSync(["jsonschema", ...args], { cwd: repositoryRoot });
	const output = `${run.stdout.toString()}\n${run.stderr.toString()}`;
	const lines = output.split(/\r?\n/).map((line) => line.trim());
	let best = "";
	let bestDepth = -1;
	for (const [offset, line] of lines.entries()) {
		if (!line.startsWith("The ")) continue;
		const at = lines[offset + 1]?.match(/^at instance location "([^"]*)"/);
		if (!at) continue;
		const depth = at[1].length;
		if (depth > bestDepth) {
			bestDepth = depth;
			best = at[1] === "" ? line : `${line} at ${at[1]}`;
		}
	}
	return best === "" ? "schema validation failed" : best;
}

// ---------------------------------------------------------------- entry point

const glob = new Glob("*.md");
const kitFiles = (await Array.fromAsync(glob.scan({ cwd: kitDir }))).sort();
if (kitFiles.length === 0) {
	console.error(`error: no kit case files found in ${kitDir}`);
	process.exit(1);
}

const fences: Fence[] = [];
for (const name of kitFiles) {
	const file = path.join(kitDir, name);
	fences.push(...collectFences(name, await Bun.file(file).text()));
}

const results: Result[] = fences.map((fence) => ({
	fence,
	outcome: "skip",
	message: "",
}));

const workspace = mkdtempSync(path.join(os.tmpdir(), "mck-fences-"));
try {
	const byNode = new Map<string, Result[]>();
	for (const result of results) {
		const { fence } = result;
		if (fence.role === "window") {
			result.message = "skipped (window)";
			continue;
		}
		const entrypoint = NODE_ENTRYPOINTS[fence.node];
		if (entrypoint === undefined) {
			result.message = `skipped (node=${fence.node || "unset"})`;
			continue;
		}
		const group = byNode.get(fence.node) ?? [];
		group.push(result);
		byNode.set(fence.node, group);
	}

	for (const [node, group] of byNode) {
		const entrypoint = NODE_ENTRYPOINTS[node];
		const directory = path.join(workspace, node);
		mkdirSync(directory, { recursive: true });
		const instances = new Map<string, Result>();
		for (const result of group) {
			const name = `${result.fence.caseId}__${result.fence.index}.json`;
			writeFileSync(path.join(directory, name), result.fence.body);
			instances.set(name, result);
		}
		const verdicts = validateDirectory(directory, entrypoint);
		for (const [name, result] of instances) {
			const passed = verdicts.get(name);
			if (passed === true) {
				result.outcome = "ok";
			} else {
				result.outcome = "fail";
				result.message =
					passed === undefined
						? "the validator reported no verdict for this instance"
						: failureMessage(path.join(directory, name), entrypoint);
			}
		}
	}
} finally {
	rmSync(workspace, { recursive: true, force: true });
}

let ok = 0;
let failed = 0;
let skipped = 0;
for (const { fence, outcome, message } of results) {
	const label = `${fence.caseId} fence-${fence.index}`;
	if (outcome === "ok") {
		ok += 1;
		console.log(`${label}: ok`);
	} else if (outcome === "skip") {
		skipped += 1;
		console.log(`${label}: ${message}`);
	} else {
		failed += 1;
		console.log(
			`${label}: FAIL ${message} (${fence.sourceFile}:${fence.line})`,
		);
	}
}

console.log(`\n${ok} ok, ${failed} failed, ${skipped} skipped`);
if (failed > 0) process.exit(1);
