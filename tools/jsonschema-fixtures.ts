// JSON Schema CLI 16.3.0 dereferences an invalid native pointer in `test`
// mode for nested Workbench provider schemas. Run the same fixture assertions
// through its exhaustive `validate` command. This carries no schema semantics.
import { mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

type Fixture = {
	target: string;
	tests: { description: string; data: unknown; valid: boolean }[];
};

function fixture(value: unknown): Fixture {
	if (typeof value !== "object" || value === null || Array.isArray(value)) {
		throw new Error("Fixture must be an object.");
	}
	const fields = value as Record<string, unknown>;
	if (
		typeof fields.target !== "string" ||
		!fields.target ||
		!Array.isArray(fields.tests) ||
		fields.tests.length === 0
	) {
		throw new Error("Fixture requires a target and nonempty tests.");
	}
	for (const test of fields.tests) {
		if (
			typeof test !== "object" || test === null ||
			typeof test.description !== "string" ||
			typeof test.valid !== "boolean" || !Object.hasOwn(test, "data")
		) {
			throw new Error("Malformed schema fixture assertion.");
		}
	}
	return value as Fixture;
}

export async function runFixtureSuite(
	directory: string,
	references: string[],
): Promise<number> {
	const files = (await readdir(directory))
		.filter(file => file.endsWith(".json"))
		.sort();
	if (files.length === 0) {
		throw new Error("Schema fixture suite must be nonempty.");
	}
	const scratch = await mkdtemp(path.join(tmpdir(), "morphir-jsonschema-"));
	let count = 0;
	try {
		for (const file of files) {
			const input = fixture(JSON.parse(
				await readFile(path.join(directory, file), "utf8"),
			));
			// A local reference keeps URI resolution in the official CLI.
			const target = path.join(scratch, "target.json");
			await writeFile(target, JSON.stringify({
				$schema: "https://json-schema.org/draft/2020-12/schema",
				$ref: input.target,
			}));
			for (const test of input.tests) {
				const instance = path.join(scratch, "instance.json");
				await writeFile(instance, JSON.stringify(test.data));
				const child = Bun.spawnSync(
					["jsonschema", "validate", target, instance, ...references],
					{ stdout: "pipe", stderr: "pipe", windowsHide: true },
				);
				const errors = new TextDecoder().decode(child.stderr);
				const instanceRejected = child.exitCode === 2 &&
					errors.includes("Schema validation failure");
				if (child.signalCode != null ||
					(child.exitCode !== 0 && !instanceRejected)) {
					throw new Error(`${file}: validator failed for ${test.description}: ${errors}`);
				}
				if ((child.exitCode === 0) !== test.valid) {
					throw new Error(`${file}: ${test.description} did not match expected valid=${test.valid}: ${errors}`);
				}
				++count;
			}
			console.log(`${path.join(directory, file)}: PASS ${input.tests.length}/${input.tests.length}`);
		}
	} finally {
		await rm(scratch, { recursive: true, force: true });
	}
	return count;
}

if (import.meta.main) {
	const repositoryRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
	process.chdir(repositoryRoot);
	const [directory, ...references] = process.argv.slice(2);
	if (!directory) {
		console.error("Usage: bun run tools/jsonschema-fixtures.ts <fixture-directory> [-r schema...]");
		process.exit(2);
	}
	try {
		await runFixtureSuite(directory, references);
	} catch (error) {
		console.error(error instanceof Error ? error.message : String(error));
		process.exit(1);
	}
}
