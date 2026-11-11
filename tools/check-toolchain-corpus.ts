// Metadata checks retained from the removed Rust reference crate. This reads no
// document through a contract reader and computes no implementation's expected result.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, posix, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { fences } from "./spec-mep-smithy";

const fixture = "docs/spec/toolchain/fixtures/0.1.0-draft.1";
const narrative = "docs/design/proposals/toolchain-acquisition.md";
interface Manifest {
	contractVersion: string;
	files: string[];
	trees: string[];
	references: { path: string; reason: string }[];
}
interface Case {
	name: string;
	rule?: string;
	document?: string;
	expected: string | { code: string; path: string };
}

const spans = (cell: string) => [...cell.matchAll(/`([^`]*)`/g)].map((match) => match[1]!);
const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Match only the path spelling used in the contract check tables. */
export function pathMatches(pattern: string, path: string): boolean {
	const expression = pattern.split(/(\[[a-z]\]|<id>|…)/).map((part) => {
		if (/^\[[a-z]\]$/.test(part)) return "\\[[0-9]+\\]";
		if (part === "<id>") return "[a-z0-9-]+";
		if (part === "…") return "[\\s\\S]*";
		return escape(part);
	}).join("");
	return new RegExp(`^(?:${expression})$`).test(path);
}

function repositoryPath(path: string): string {
	if (path.includes("\\") || path.startsWith("/") || /^[a-z]:/i.test(path)) throw new Error(`Not a repository-relative path: ${path}`);
	const normalized = posix.normalize(path);
	if (normalized === ".." || normalized.startsWith("../")) throw new Error(`Path leaves the repository: ${path}`);
	return normalized;
}

function outsideFences(markdown: string): string {
	let inside = false;
	return markdown.split(/\r?\n/).map((line) => {
		if (line.startsWith("```")) { inside = !inside; return ""; }
		return inside ? "" : line;
	}).join("\n");
}

function headings(markdown: string): Set<string> {
	return new Set(outsideFences(markdown).split("\n").filter((line) => line.startsWith("#"))
		.map((line) => line.replace(/^#+\s*/, "").trim().toLowerCase().replace(/[^\p{L}\p{N} _-]/gu, "").replaceAll(" ", "-")));
}

function links(markdown: string) {
	return [...outsideFences(markdown).matchAll(/(!?)\[([^\]]*)\]\(([^)]*)\)/g)]
		.map((match) => ({ image: match[1] === "!", alt: match[2]!, target: match[3]!.trim() }));
}

function linkedFile(page: string, path: string): string {
	if (path.startsWith("/") && !path.startsWith("/schemas/")) throw new Error(`${page}: link the repository file instead of the site route ${path}`);
	return path.startsWith("/schemas/")
		? repositoryPath(`website/static/schemas/${path.slice("/schemas/".length)}`)
		: path ? repositoryPath(posix.join(posix.dirname(page), path)) : page;
}

export function metadataFindings(root: string, readText = (path: string) => readFileSync(resolve(root, repositoryPath(path)), "utf8")): string[] {
	const failures: string[] = [];
	const json = (path: string) => JSON.parse(readText(path));
	const manifest: Manifest = json(`${fixture}/contract-files.json`);
	if (manifest.contractVersion !== "0.1.0-draft.1") failures.push("contract-files.json has a different contractVersion");
	const files = new Set(manifest.files);
	const references = new Set(manifest.references.map((reference) => reference.path));
	const exists = (path: string, directory: boolean) => {
		const absolute = resolve(root, repositoryPath(path));
		return existsSync(absolute) && (directory ? statSync(absolute).isDirectory() : statSync(absolute).isFile());
	};
	for (const path of manifest.trees) if (!exists(path, true)) failures.push(`Missing manifest tree: ${path}`);
	for (const path of files) if (!exists(path, false)) failures.push(`Missing manifest file: ${path}`);
	for (const reference of manifest.references) {
		if (!exists(reference.path, false)) failures.push(`Missing manifest reference: ${reference.path}`);
		if (typeof reference.reason !== "string" || !reference.reason.trim()) failures.push(`${reference.path}: reference needs a reason`);
	}
	const pages = readdirSync(resolve(root, "docs/spec/toolchain")).filter((file) => file.endsWith(".md")).map((file) => `docs/spec/toolchain/${file}`);
	const schemas = readdirSync(resolve(root, "website/static/schemas"))
		.filter((file) => file.endsWith("-0.1.0-draft.1.schema.json") && ["toolset-recipe-", "toolchain-", "morphirup-"].some((prefix) => file.startsWith(prefix)))
		.map((file) => `website/static/schemas/${file}`);
	if (pages.length + schemas.length !== 13) failures.push("Expected seven contract pages and six schemas");
	for (const path of [...pages, ...schemas]) if (!files.has(path)) failures.push(`${path}: not pinned in contract-files.json`);
	for (const page of [...files].filter((path) => path.endsWith(".md"))) {
		for (const { target } of links(readText(page))) {
			if (/^[a-z][a-z0-9+.-]*:/i.test(target)) continue;
			const path = target.split("#")[0]!;
			if (!path) continue;
			const file = linkedFile(page, path);
			if (!files.has(file) && !references.has(file) && !manifest.trees.some((tree) => file === tree || file.startsWith(`${tree}/`))) {
				failures.push(`${page}: ${file} is not pinned or referenced`);
			}
		}
	}

	const unsigned = json(`${fixture}/cases.json`);
	const signed = json(`${fixture}/signed/cases.json`);
	const byRule = new Map<string, Case[]>();
	for (const section of [unsigned.bindings, signed.selection, signed.recipeChecks, signed.trust, signed.lockRecipe, signed.channelSelection]) {
		for (const row of section as Case[]) {
			if (!row.rule) continue;
			if (typeof row.expected === "string" || typeof row.expected.code !== "string" || typeof row.expected.path !== "string") {
				failures.push(`${row.rule}: a rule's cases must name a refusal code and path`);
				continue;
			}
			byRule.set(row.rule, [...(byRule.get(row.rule) ?? []), row]);
		}
	}
	const named = new Set<string>();
	let rowCount = 0;
	for (const page of ["toolset-recipe", "toolchain-lock", "installation-receipt"]) {
		let header: string[] | undefined;
		for (const line of readText(`docs/spec/toolchain/${page}.md`).split(/\r?\n/)) {
			if (!line.startsWith("|")) { header = undefined; continue; }
			const cells = line.trim().replace(/^\||\|$/g, "").split(" | ").map((cell) => cell.trim());
			if (!header) { header = cells; continue; }
			if (cells.every((cell) => /^-+$/.test(cell))) continue;
			const indexes = ["Cases", "Code", "Path"].map((column) => header!.indexOf(column));
			if (indexes.some((index) => index < 0)) continue;
			rowCount++;
			if (cells.length !== header.length) { failures.push(`${page}: malformed check table row`); continue; }
			const [caseCell, codeCell, pathCell] = indexes.map((index) => cells[index]!);
			const label = `${page}: ${cells[0]}`;
			if (caseCell!.startsWith("No fixture:")) {
				if (!caseCell!.slice("No fixture:".length).trim()) failures.push(`${label}: No fixture needs a reason`);
				continue;
			}
			const rules = spans(caseCell!);
			if (!rules.length) failures.push(`${label}: names no case`);
			const codes = spans(codeCell!).filter((code) => /^[a-z][a-z0-9_]*$/.test(code));
			const patterns = pathCell === "empty" ? [""] : pathCell!.includes("`") ? spans(pathCell!) : undefined;
			const covered = new Set<string>();
			for (const rule of rules) {
				named.add(rule);
				const cases = byRule.get(rule);
				if (!cases) { failures.push(`${label}: no case has rule ${rule}`); continue; }
				for (const row of cases) {
					if (typeof row.expected === "string") continue;
					const expected = row.expected;
					if (codes.length && !codes.includes(expected.code)) failures.push(`${label}: ${row.name} reports ${expected.code}`);
					if (patterns && !patterns.some((pattern) => pathMatches(pattern, expected.path))) failures.push(`${label}: ${row.name} reports path ${expected.path}`);
					covered.add(expected.code);
				}
			}
			for (const code of codes) if (!covered.has(code)) failures.push(`${label}: no case reports ${code}`);
		}
	}
	if (rowCount < 40) failures.push("Contract check tables were not found");
	for (const rule of byRule.keys()) if (!named.has(rule)) failures.push(`rule ${rule} appears in no check table`);

	const markdown = readText(narrative);
	let examples = 0;
	const validDocuments = new Set((unsigned.documents as Case[]).filter((row) => row.expected === "valid").map((row) => `${fixture}/${row.document}`));
	for (const fence of fences(markdown)) {
		if (!/^(json|toml)(\s|$)/.test(fence.info)) continue;
		examples++;
		const title = /title="([^"]+)"/.exec(fence.info)?.[1];
		if (!title || !validDocuments.has(title)) { failures.push(`Narrative line ${fence.line}: example must name a listed valid fixture`); continue; }
		const expected = readText(title);
		if (`${fence.body}\n` !== (expected.endsWith("\n") ? expected : `${expected}\n`)) failures.push(`Narrative line ${fence.line}: example differs from ${title}`);
	}
	if (examples < 5) failures.push("Narrative document examples were not found");
	let diagrams = 0;
	for (const page of new Set([narrative, "docs/design/proposals/index.md", ...[...files].filter((path) => path.endsWith(".md"))])) {
		for (const { image, alt, target } of links(readText(page))) {
			if (/^[a-z][a-z0-9+.-]*:/i.test(target)) continue;
			const [path, anchor] = target.split("#");
			const file = linkedFile(page, path!);
			if (!exists(file, false)) { failures.push(`${page}: ${target} does not exist`); continue; }
			if (anchor && !headings(readText(file)).has(anchor)) failures.push(`${page}: ${target} names a missing heading`);
			if (image) {
				if (page === narrative) diagrams++;
				const svg = readText(file);
				if (!alt.trim()) failures.push(`${page}: ${target} has no alternative text`);
				if (!svg.includes('role="img"') || !svg.includes("<title") || !svg.includes("<desc")) failures.push(`${page}: ${target} lacks role, title or description`);
			}
		}
	}
	if (diagrams !== 7) failures.push("The narrative must carry seven diagrams");
	const body = markdown.split("---")[2] ?? "";
	if (!body.trimStart().startsWith("# Toolchain acquisition") || !body.includes(":::caution Proposed interface, not implemented")) failures.push("The narrative must retain its proposal warning");
	for (const decision of ["DEP-1", "UP-1", "UP-2", "FS-1", "LOCK-1", "PATH-1", "QUAL-1"]) if (!markdown.includes(decision)) failures.push(`Narrative is missing ${decision}`);
	if (markdown.includes("morphir mck")) failures.push("The narrative must not present the retired Rust command as its runner");
	return failures;
}

export function checkCorpusMetadata(root: string): void {
	const failures = metadataFindings(root);
	if (failures.length) throw new Error(failures.join("\n"));
}

if (import.meta.main) {
	try {
		checkCorpusMetadata(resolve(dirname(fileURLToPath(import.meta.url)), ".."));
		console.log("Toolchain corpus metadata checks passed");
	} catch (error) {
		console.error(error instanceof Error ? error.message : String(error));
		process.exitCode = 1;
	}
}
