import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { metadataFindings, pathMatches } from "./check-toolchain-corpus";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const fixture = "docs/spec/toolchain/fixtures/0.1.0-draft.1";
const narrative = "docs/design/proposals/toolchain-acquisition.md";
const read = (path: string) => readFileSync(resolve(root, path), "utf8");

test("all retained contract metadata gates pass against the current parent", () => {
	expect(metadataFindings(root)).toEqual([]);
});

test("an unpinned repository file linked by a contract is refused", () => {
	const result = metadataFindings(root, (path) => read(path) + (path === "docs/spec/toolchain/index.md" ? "\n[code](../../../Cargo.toml)\n" : ""));
	expect(result.some((finding) => finding.includes("Cargo.toml") && finding.includes("not pinned"))).toBe(true);
});

test("a manifest reference needs a real file and a reason", () => {
	const result = metadataFindings(root, (path) => {
		if (path !== `${fixture}/contract-files.json`) return read(path);
		const value = JSON.parse(read(path));
		value.references.push({ path: "missing-reference.md", reason: "" });
		return JSON.stringify(value);
	});
	expect(result.some((finding) => finding.includes("missing-reference.md"))).toBe(true);
	expect(result.some((finding) => finding.includes("reason"))).toBe(true);
});

test("a check-table rule cannot silently lose its diagnostic expectation", () => {
	const result = metadataFindings(root, (path) => {
		if (path !== `${fixture}/cases.json`) return read(path);
		const value = JSON.parse(read(path));
		value.bindings.find((row: { rule?: string }) => row.rule).expected.code = "invented_code";
		return JSON.stringify(value);
	});
	expect(result.some((finding) => finding.includes("invented_code"))).toBe(true);
});

test("a changed narrative example cannot replace its fixed expected bytes", () => {
	const result = metadataFindings(root, (path) => path === narrative ? read(path).replace('[host]', '[invented-host]') : read(path));
	expect(result.some((finding) => finding.includes("example differs"))).toBe(true);
});

test("missing anchors and inaccessible diagrams are found", () => {
	const result = metadataFindings(root, (path) => {
		const text = read(path);
		if (path === narrative) return `${text}\n[missing](#missing-anchor)\n`;
		return path.endsWith(".svg") ? text.replace('role="img"', "") : text;
	});
	expect(result.some((finding) => finding.includes("missing-anchor"))).toBe(true);
	expect(result.some((finding) => finding.includes("role, title or description"))).toBe(true);
});

test("the proposed interface warning cannot disappear", () => {
	const result = metadataFindings(root, (path) => path === narrative ? read(path).replace(":::caution Proposed interface, not implemented", "") : read(path));
	expect(result.some((finding) => finding.includes("proposal warning"))).toBe(true);
});

test("check-table paths match indexes, portable keys, and suffixes exactly", () => {
	expect(pathMatches("hosts[i].platforms.<id>.target", "hosts[12].platforms.win-x64.target")).toBe(true);
	expect(pathMatches("hosts[i].source", "hosts.source")).toBe(false);
	expect(pathMatches("hosts[i].source", "hosts[].source")).toBe(false);
	expect(pathMatches("platforms.<id>.target", "platforms.WinX64.target")).toBe(false);
	expect(pathMatches("…artifactTarget", "providers[0].platforms.win-x64.artifactTarget")).toBe(true);
	expect(pathMatches("", "")).toBe(true);
	expect(pathMatches("", "hosts")).toBe(false);
});
