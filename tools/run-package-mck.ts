// Runs the native MCK against one independent package adapter. No verdict logic.
import { mkdirSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { packageMckInvocation, packageProcessExitCode } from "./package-mck-command.ts";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
try {
	const { command, report } = packageMckInvocation(root, process.platform, process.argv.slice(2));
	mkdirSync(path.dirname(report), { recursive: true });
	rmSync(report, { force: true });
	const result = Bun.spawnSync(command, { cwd: root, stdio: ["inherit", "inherit", "inherit"] });
	process.exit(packageProcessExitCode(result));
} catch (error) {
	console.error(error instanceof Error ? error.message : String(error));
	process.exit(2);
}
