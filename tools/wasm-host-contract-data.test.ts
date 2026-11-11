// Parent-owned documentation/data integrity only; host behavior is checked by the .NET runner.
import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const contract = JSON.parse(readFileSync("spec/mep/wasm-execution-profiles.json", "utf8"));
const pagePath = "docs/spec/extensions/wasm-hosts.md";

test("published WASM profile tables retain every contract import, result and refusal", () => {
	const page = readFileSync(pagePath, "utf8");
	for (const [name, profile] of Object.entries<any>(contract.profiles)) {
		expect(page, name).toContain(`### ${name}`);
		for (const entry of profile.imports) {
			const signature = "(" + entry.params.join(", ") + ") -> " + (entry.results.length ? entry.results.join(", ") : "()");
			const quote = (value: string) => String.fromCharCode(96) + value + String.fromCharCode(96);
			expect(page).toContain("| " + quote(entry.module + "." + entry.name) + " | " + quote(signature) + " |");
			expect(page, `${name}: ${entry.module}.${entry.name}`).toContain(`\`${entry.module}.${entry.name}\``);
		}
		for (const result of profile.handleResults) {
			expect(page, `${name}: ${result.result}`).toContain(result.detail);
		}
	}
	for (const refusal of contract.refusals) expect(page).toContain(`\`${refusal.code}\``);
	for (const fault of contract.faults) expect(page).toContain(`\`${fault.kind}\``);
	for (const bound of contract.bounds.requiredForQualification) expect(page).toContain(`\`${bound}\``);
	for (const deviation of contract.knownDeviations) expect(page).toContain(deviation.tracking);
});

test("published WASM documentation distinguishes implemented observations from qualification", () => {
	const page = readFileSync(pagePath, "utf8");
	expect(page).toContain("No .NET offering/platform is declared qualified by this page.");
	expect(page).toContain("not_enforced");
	expect(page).toContain("notificationDelivery");
	expect(page).toContain("Unknown or absent values mean `none`");
	expect(page).toContain("guest-output");
	expect(page).toContain("268435456");
	expect(page).toContain("1048576");
	expect(page).toContain("16777216");
	expect(page).toContain("1024");
	expect(page).toContain("MORPHIR_EXTENSION_OVERLAY");
});

test("every sandbox policy leaf keeps its exact published value", () => {
	const page = readFileSync(pagePath, "utf8");
	const quote = (value: string) => String.fromCharCode(96) + value + String.fromCharCode(96);
	const visit = (value: Record<string, unknown>, prefix = "") => {
		for (const [name, child] of Object.entries(value)) {
			const key = prefix ? prefix + "." + name : name;
			if (child && typeof child === "object" && !Array.isArray(child)) {
				visit(child as Record<string, unknown>, key);
			} else {
				const text = typeof child === "string" ? child : JSON.stringify(child);
				expect(page, key).toContain("| " + quote(key) + " | " + quote(text) + " |");
			}
		}
	};
	visit(contract.policy);
});
