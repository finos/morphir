import { expect, test } from "bun:test";
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { runMckEngineTests } from "./test-mck-engine.ts";

type Call = { args: string[]; cwd: string; env: Record<string, string> };
type Scenario = { buildStatus?: number; testStatus?: number; messages?: string; missingFile?: boolean; testOutput?: string; testError?: string };

function withCargo(scenario: Scenario, action: (fixture: {
	root: string;
	peer: string;
	options: { cwd: string; env: Record<string, string | undefined>; cargo: [string, ...string[]] };
	calls: () => Call[];
}) => void): void {
	const root = realpathSync(mkdtempSync(path.join(tmpdir(), "mck engine runner ")));
	try {
		const peer = path.join(root, "reported peer executable");
		if (!scenario.missingFile) writeFileSync(peer, "trusted peer fixture");
		const trace = path.join(root, "calls.jsonl");
		const config = path.join(root, "scenario.json");
		writeFileSync(config, JSON.stringify({ ...scenario, peer }));
		const cargo = path.join(root, "cargo.ts");
		writeFileSync(cargo, `
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
const scenario = JSON.parse(readFileSync(process.env.MCK_TEST_SCENARIO!, "utf8"));
const args = process.argv.slice(2);
appendFileSync(process.env.MCK_TEST_TRACE!, JSON.stringify({ args, cwd: process.cwd(), env: process.env }) + "\\n");
if (args.includes("--no-run")) {
  writeFileSync(1, scenario.messages ?? JSON.stringify({ reason: "compiler-artifact", target: { name: "mep_transport", kind: ["test"] }, executable: scenario.peer }) + "\\n");
  process.exit(scenario.buildStatus ?? 0);
}
process.stdout.write(scenario.testOutput ?? "");
process.stderr.write(scenario.testError ?? "");
process.exit(scenario.testStatus ?? 0);
`);
		action({
			root, peer,
			options: {
				cwd: root,
				cargo: [process.execPath, cargo],
				env: {
					...process.env,
					MCK_TEST_TRACE: trace,
					MCK_TEST_SCENARIO: config,
					MORPHIR_MCK_REPORT_PEER_BIN: "/ambient stale peer",
					morphir_mck_report_peer_bin: "/ambient case variant",
					CARGO_TARGET_DIR: path.join(root, "custom target"),
					CARGO_PROFILE_TEST_DEBUG: "1",
					RUSTUP_TOOLCHAIN: "fixture-selected-toolchain",
				},
			},
			calls: () => {
				try { return readFileSync(trace, "utf8").trim().split("\n").map((line) => JSON.parse(line) as Call); }
				catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return []; throw error; }
			},
		});
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}

test("builds the reported peer once, then runs the full group with the same selected environment", () => {
	withCargo({}, ({ root, peer, options, calls }) => {
		expect(runMckEngineTests([], options)).toBe(0);
		const [build, tests] = calls();
		expect(build?.args).toEqual(["test", "--locked", "-p", "morphir-mck", "--test", "mep_transport", "--no-run", "--message-format=json-render-diagnostics"]);
		expect(tests?.args).toEqual(["test", "--locked", "-p", "morphir-mck"]);
		expect(calls()).toHaveLength(2);
		for (const call of [build!, tests!]) {
			expect(call.cwd).toBe(root);
			expect(call.env.CARGO_TARGET_DIR).toBe(path.join(root, "custom target"));
			expect(call.env.CARGO_PROFILE_TEST_DEBUG).toBe("1");
			expect(call.env.RUSTUP_TOOLCHAIN).toBe("fixture-selected-toolchain");
			expect(call.env.morphir_mck_report_peer_bin).toBeUndefined();
		}
		expect(build?.env.MORPHIR_MCK_REPORT_PEER_BIN).toBeUndefined();
		expect(tests?.env.MORPHIR_MCK_REPORT_PEER_BIN).toBe(peer);
	});
});

test("forwards only the closed library selection and one literal test-name substring", () => {
	withCargo({}, ({ options, calls }) => {
		const filter = "a name; $(do-not-expand)";
		expect(runMckEngineTests([filter, "--lib"], options)).toBe(0);
		expect(calls()[0]?.args).not.toContain(filter);
		expect(calls()[1]?.args).toEqual(["test", "--locked", "-p", "morphir-mck", "--lib", filter]);
	});
});

test("rejects unsupported selectors before building or executing anything", () => {
	withCargo({}, ({ options, calls }) => {
		for (const args of [["--release"], ["--lib", "--lib"], ["one", "two"], ["--", "--ignored"], ["--test-threads=1"], ["--target", "other"], ["--features=other"], ["--package=other"], [""]]) {
			expect(() => runMckEngineTests(args, options)).toThrow("usage:");
		}
		expect(calls()).toEqual([]);
	});
});

test("a failed peer build prevents tests and preserves its status", () => {
	withCargo({ buildStatus: 23, messages: "peer build diagnostic\n" }, ({ options, calls }) => {
		expect(runMckEngineTests([], options)).toBe(23);
		expect(calls()).toHaveLength(1);
	});
});

test("successful Cargo without the requested artifact cannot launch tests", () => {
	withCargo({ messages: JSON.stringify({ reason: "compiler-artifact", target: { name: "other", kind: ["test"] }, executable: "/stale/other" }) }, ({ options, calls }) => {
		expect(() => runMckEngineTests([], options)).toThrow("no mep_transport test executable");
		expect(calls()).toHaveLength(1);
	});
});

test("a reported but missing executable cannot launch tests or use the ambient peer", () => {
	withCargo({ missingFile: true }, ({ options, calls }) => {
		expect(() => runMckEngineTests([], options)).toThrow("ENOENT");
		expect(calls()).toHaveLength(1);
	});
});

test("test failure status and ordinary output pass through the actual subprocess boundary", () => {
	withCargo({ testStatus: 37, testOutput: "ordinary test output\n", testError: "ordinary test error\n" }, ({ options, calls }) => {
		const moduleUrl = pathToFileURL(path.join(import.meta.dir, "test-mck-engine.ts")).href;
		const launcher = `import { runMckEngineTests } from ${JSON.stringify(moduleUrl)};
process.exitCode = runMckEngineTests([], { cwd: process.cwd(), env: process.env, cargo: ${JSON.stringify(options.cargo)} });`;
		const result = Bun.spawnSync([process.execPath, "--eval", launcher], { cwd: options.cwd, env: options.env, stdout: "pipe", stderr: "pipe" });
		expect(result.exitCode).toBe(37);
		expect(result.stdout.toString()).toBe("ordinary test output\n");
		expect(result.stderr.toString()).toBe("ordinary test error\n");
		expect(calls()).toHaveLength(2);
	});
});

test("failure to start Cargo refuses before any test process", () => {
	withCargo({}, ({ root, options, calls }) => {
		expect(() => runMckEngineTests([], { ...options, cargo: [path.join(root, "missing-cargo")] })).toThrow("ENOENT");
		expect(calls()).toEqual([]);
	});
});

test("retains the reported peer after a Cargo message stream larger than the default capture buffer", () => {
	withCargo({}, ({ peer, options, calls }) => {
		const messages = JSON.stringify({ reason: "compiler-message", message: "x".repeat(2 * 1024 * 1024) }) + "\n"
			+ JSON.stringify({ reason: "compiler-artifact", target: { name: "mep_transport", kind: ["test"] }, executable: peer });
		writeFileSync(options.env.MCK_TEST_SCENARIO!, JSON.stringify({ peer, messages }));
		expect(runMckEngineTests([], options)).toBe(0);
		expect(calls()).toHaveLength(2);
		expect(calls()[1]?.env.MORPHIR_MCK_REPORT_PEER_BIN).toBe(peer);
	});
});
