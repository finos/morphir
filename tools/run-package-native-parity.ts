// Migration-only orchestration. The Rust MCK owns execution and verdicts.
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { assertPackageParity, nativePackageInvocations } from "./package-mck-parity.ts";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
try {
	for (const run of nativePackageInvocations(root, process.platform)) {
		// Missing baseline must fail before a native run can be mistaken for parity.
		const baseline: unknown = JSON.parse(readFileSync(run.baseline, "utf8"));
		const result = Bun.spawnSync(run.command, { cwd: root, stdio: ["inherit", "inherit", "inherit"] });
		if (result.exitCode !== 0) throw new Error(`native package run failed (${result.exitCode}): ${run.report}`);
		assertPackageParity(baseline, JSON.parse(readFileSync(run.report, "utf8")));
		console.log(`package migration parity: ${path.basename(run.report)} matches its TypeScript-runner baseline`);
	}
} catch (error) {
	console.error(String(error));
	process.exit(1);
}
