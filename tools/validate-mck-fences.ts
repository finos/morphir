// Validates every canonical and accepted JSON fence of the Morphir Compatibility
// Kit against the v4 JSON Schemas, so the kit and the schemas cannot drift.
//
//   bun run tools/validate-mck-fences.ts
//
// A case heading names the model type its fences decode to (`{node=Type}`); the
// node maps to a definition of morphir-ir-v4.json or, for document-tree files, of
// morphir-ir-v4-document-tree-files.json, and the fence body must validate against
// it. A fence carrying `warning=` is a legacy spelling of decision 0006: a reader
// normalizes it and reports the warning, but the schema describes only the
// canonical and expanded forms, so such a fence must be REJECTED here. The
// exception is the nested { "doc", "value" } wrapper of decision 0010, which the
// schema still describes for one release.
import { Glob } from "bun";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const kitDir = path.join(repositoryRoot, "spec", "ir", "mck");
const schemaDir = path.join(repositoryRoot, "website", "static", "schemas");
const irSchema = path.join(schemaDir, "morphir-ir-v4.json");
const treeSchema = path.join(schemaDir, "morphir-ir-v4-document-tree-files.json");

/** The IR version this checker knows how to validate. */
const SUPPORTED_VERSION = "4";

/** A schema file and the location inside it a node's fences must validate against. */
interface Target {
	/** Absolute path of the schema file. */
	readonly schema: string;
	/** JSON pointer into that schema; "" is the root schema. */
	readonly pointer: string;
}

/** Model type named by a case heading, mapped to where its fences are checked. */
const NODE_TARGETS: ReadonlyMap<string, Target> = new Map<string, Target>([
	["Distribution", { schema: irSchema, pointer: "" }],
	["FormatVersion", { schema: irSchema, pointer: "#/definitions/FormatVersion" }],
	["Name", { schema: irSchema, pointer: "#/definitions/Name" }],
	["Path", { schema: irSchema, pointer: "#/definitions/Path" }],
	["FQName", { schema: irSchema, pointer: "#/definitions/FQName" }],
	["Type", { schema: irSchema, pointer: "#/definitions/Type" }],
	["Value", { schema: irSchema, pointer: "#/definitions/Value" }],
	["Pattern", { schema: irSchema, pointer: "#/definitions/Pattern" }],
	["Literal", { schema: irSchema, pointer: "#/definitions/Literal" }],
	[
		"TypeSpecification",
		{ schema: irSchema, pointer: "#/definitions/TypeSpecification" },
	],
	[
		"TypeDefinition",
		{ schema: irSchema, pointer: "#/definitions/TypeDefinition" },
	],
	[
		"ValueSpecification",
		{ schema: irSchema, pointer: "#/definitions/ValueSpecification" },
	],
	[
		"ValueDefinition",
		{ schema: irSchema, pointer: "#/definitions/ValueDefinition" },
	],
	[
		"ModuleSpecification",
		{ schema: irSchema, pointer: "#/definitions/ModuleSpecification" },
	],
	[
		"ModuleDefinition",
		{ schema: irSchema, pointer: "#/definitions/ModuleDefinition" },
	],
	[
		"AccessControlledTypeDefinition",
		{ schema: irSchema, pointer: "#/definitions/AccessControlledTypeDefinition" },
	],
	[
		"AccessControlledValueDefinition",
		{ schema: irSchema, pointer: "#/definitions/AccessControlledValueDefinition" },
	],
	[
		"DistributionManifestFile",
		{ schema: treeSchema, pointer: "#/definitions/DistributionManifestFile" },
	],
	[
		"ModuleManifestFile",
		{ schema: treeSchema, pointer: "#/definitions/ModuleManifestFile" },
	],
	[
		"TypeDefinitionFile",
		{ schema: treeSchema, pointer: "#/definitions/TypeDefinitionFile" },
	],
	[
		"ValueDefinitionFile",
		{ schema: treeSchema, pointer: "#/definitions/ValueDefinitionFile" },
	],
]);

/**
 * Cases whose `warning=` fence is the nested { "doc", "value" } wrapper. Decision
 * 0010 keeps that shape valid in the schema for one release even though a reader
 * reports legacy_spelling for it, so these fences must validate rather than fail.
 * An explicit list, because nothing in the fence itself distinguishes them.
 */
const DOC_WRAPPER_CASES: ReadonlySet<string> = new Set([
	"definitions-0006",
	"definitions-0010",
]);

// ---------------------------------------------------------------- the kit

interface Fence {
	readonly caseId: string;
	readonly node: string;
	readonly index: number;
	readonly role: string;
	/** The legacy-spelling code this fence carries, if any. */
	readonly warning: string | null;
	readonly body: string;
	readonly sourceFile: string;
	readonly line: number;
}

type Outcome = "ok" | "rejected" | "fail" | "skip";

interface Result {
	readonly fence: Fence;
	/** Whether the schema is expected to accept this fence. */
	readonly expectValid: boolean;
	outcome: Outcome;
	message: string;
}

const CASE_HEADING = /^##\s+([a-z][a-z-]*-\d{4}):\s*(.*)$/;
const FENCE_OPEN = /^```(\S+)((?:\s+\S+)*)\s*$/;

/** Reads `key=value` pairs out of a `{ .. }` suffix on a case heading. */
function headingKeys(title: string): Record<string, string> {
	const keys: Record<string, string> = {};
	const braces = title.match(/\{([^}]*)\}\s*$/);
	const inner = braces?.[1];
	if (inner === undefined) return keys;
	for (const pair of inner.split(/\s+/)) {
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

interface OpenFence {
	readonly language: string;
	readonly role: string;
	readonly keys: Record<string, string>;
	readonly line: number;
}

function collectFences(file: string, text: string): Fence[] {
	const fences: Fence[] = [];
	const lines = text.split(/\r?\n/);
	let current: ActiveCase | null = null;
	let open: OpenFence | null = null;
	let body: string[] = [];

	for (const [offset, line] of lines.entries()) {
		if (open !== null) {
			if (line.trimEnd() === "```") {
				const isData =
					open.language === "json" &&
					(open.role === "canonical" || open.role === "accepted");
				if (current !== null && isData) {
					current.count += 1;
					fences.push({
						caseId: current.id,
						node: current.node,
						index: current.count,
						role: open.role,
						warning: open.keys.warning ?? null,
						body: body.join("\n"),
						sourceFile: file,
						line: open.line,
					});
				}
				open = null;
				body = [];
			} else {
				body.push(line);
			}
			continue;
		}

		const fenceOpen = line.match(FENCE_OPEN);
		const language = fenceOpen?.[1];
		if (fenceOpen !== null && language !== undefined) {
			const info = fenceInfo(fenceOpen[2] ?? "");
			open = {
				language,
				role: info.role,
				keys: info.keys,
				line: offset + 1,
			};
			body = [];
			continue;
		}

		if (line.startsWith("## ")) {
			current = null;
			const heading = line.match(CASE_HEADING);
			const id = heading?.[1];
			if (heading === null || id === undefined) continue;
			const keys = headingKeys(heading[2] ?? "");
			if (keys.status === "pending") continue;
			if (keys.version !== undefined && keys.version !== SUPPORTED_VERSION) {
				continue;
			}
			current = { id, node: keys.node ?? "", count: 0 };
		}
	}

	return fences;
}

// ---------------------------------------------------------------- validation

/** Runs the jsonschema CLI over a directory of instances at one entry point. */
function validateDirectory(
	directory: string,
	target: Target,
): Map<string, boolean> {
	const args = [
		"validate",
		target.schema,
		directory,
		"--verbose",
		"--continue",
	];
	if (target.pointer !== "") args.push("--entrypoint", target.pointer);
	const run = Bun.spawnSync(["jsonschema", ...args], { cwd: repositoryRoot });
	const output = `${run.stdout.toString()}\n${run.stderr.toString()}`;
	const verdicts = new Map<string, boolean>();
	for (const line of output.split(/\r?\n/)) {
		const match = line.match(/^(ok|fail):\s+(.*)$/);
		const verdict = match?.[1];
		const file = match?.[2];
		if (verdict === undefined || file === undefined) continue;
		verdicts.set(path.basename(file.trim()), verdict === "ok");
	}
	return verdicts;
}

/**
 * Re-runs one instance to get a short reason for its failure. The CLI reports
 * every branch of every union it tried, so the most informative single line is
 * the one about the deepest place in the instance it got to.
 */
function failureMessage(instance: string, target: Target): string {
	const args = ["validate", target.schema, instance];
	if (target.pointer !== "") args.push("--entrypoint", target.pointer);
	const run = Bun.spawnSync(["jsonschema", ...args], { cwd: repositoryRoot });
	const output = `${run.stdout.toString()}\n${run.stderr.toString()}`;
	const lines = output.split(/\r?\n/).map((line) => line.trim());
	let best = "";
	let bestDepth = -1;
	for (const [offset, line] of lines.entries()) {
		if (!line.startsWith("The ")) continue;
		const at = lines[offset + 1]?.match(/^at instance location "([^"]*)"/);
		const location = at?.[1];
		if (location === undefined) continue;
		if (location.length > bestDepth) {
			bestDepth = location.length;
			best = location === "" ? line : `${line} at ${location}`;
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
	expectValid: fence.warning === null || DOC_WRAPPER_CASES.has(fence.caseId),
	outcome: "skip",
	message: "",
}));

const workspace = mkdtempSync(path.join(os.tmpdir(), "mck-fences-"));
try {
	const byNode = new Map<string, { target: Target; group: Result[] }>();
	for (const result of results) {
		const target = NODE_TARGETS.get(result.fence.node);
		if (target === undefined) {
			result.message = `skipped (node=${result.fence.node || "unset"})`;
			continue;
		}
		const entry = byNode.get(result.fence.node) ?? { target, group: [] };
		entry.group.push(result);
		byNode.set(result.fence.node, entry);
	}

	for (const [node, { target, group }] of byNode) {
		const directory = path.join(workspace, node);
		mkdirSync(directory, { recursive: true });
		const instances = new Map<string, Result>();
		for (const result of group) {
			const name = `${result.fence.caseId}__${result.fence.index}.json`;
			writeFileSync(path.join(directory, name), result.fence.body);
			instances.set(name, result);
		}
		const verdicts = validateDirectory(directory, target);
		for (const [name, result] of instances) {
			const accepted = verdicts.get(name);
			if (accepted === undefined) {
				result.outcome = "fail";
				result.message = "the validator reported no verdict for this instance";
			} else if (accepted === result.expectValid) {
				result.outcome = accepted ? "ok" : "rejected";
			} else if (accepted) {
				result.outcome = "fail";
				result.message =
					"the schema accepted a window spelling it must reject (decision 0006)";
			} else {
				result.outcome = "fail";
				result.message = failureMessage(path.join(directory, name), target);
			}
		}
	}
} finally {
	rmSync(workspace, { recursive: true, force: true });
}

let ok = 0;
let rejected = 0;
let failed = 0;
let skipped = 0;
for (const { fence, outcome, message } of results) {
	const label = `${fence.caseId} fence-${fence.index}`;
	if (outcome === "ok") {
		ok += 1;
		console.log(`${label}: ok`);
	} else if (outcome === "rejected") {
		rejected += 1;
		console.log(`${label}: ok (rejected as expected)`);
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

console.log(
	`\n${ok} ok, ${rejected} rejected as expected, ${failed} failed, ${skipped} skipped`,
);
if (failed > 0) process.exit(1);
