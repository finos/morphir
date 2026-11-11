// Orchestration only. Contract behavior is implemented and tested in finos/morphir-dotnet.
import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { checkCorpusMetadata } from "./check-toolchain-corpus";

interface Result { status: number; stdout: string; stderr: string }
interface Context { cwd: string; env: NodeJS.ProcessEnv }
export type Execute = (command: string, args: string[], context: Context) => Result;

const configPath = ".config/toolchain-contract-tests.json";
const fixturePath = "docs/spec/toolchain/fixtures/0.1.0-draft.1";
const project = "tests/Morphir.Toolchain.Tests/Morphir.Toolchain.Tests.fsproj";
const defaultRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export function sourceInfo(root: string): { repository: string; commit: string } {
	const value = JSON.parse(readFileSync(resolve(root, configPath), "utf8"));
	if (value.repository !== "finos/morphir-dotnet" ||
		Object.keys(value).some((key) => !["repository", "commit"].includes(key))) {
		throw new Error(`${configPath} must name finos/morphir-dotnet and one commit`);
	}
	if (typeof value.commit !== "string" || !/^[0-9a-f]{40}$/.test(value.commit)) {
		throw new Error(`${configPath} requires a full 40-character commit, never a floating ref`);
	}
	return { repository: value.repository, commit: value.commit };
}

const execute: Execute = (command, args, context) => {
	const result = spawnSync(command, args, {
		...context,
		encoding: "utf8",
		windowsHide: true,
		maxBuffer: 32 * 1024 * 1024,
	});
	if (result.error) throw result.error;
	if (result.status === null) throw new Error(`${command} ended without an exit code, signal ${result.signal}`);
	return { status: result.status, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
};

export function checkContracts(rootArgument: string, sourceArgument: string, run: Execute = execute): Result {
	// Resolve paths before any child changes its working directory.
	const root = resolve(rootArgument);
	const source = resolve(sourceArgument);
	const config = sourceInfo(root);
	for (const file of [`${fixturePath}/cases.json`, `${fixturePath}/signed/cases.json`, `${fixturePath}/contract-files.json`]) {
		if (!existsSync(resolve(root, file))) throw new Error(`Missing current parent corpus: ${file}`);
	}
	if (!existsSync(resolve(source, project))) throw new Error(`Missing .NET test project: ${resolve(source, project)}`);
	const context = {
		cwd: source,
		env: {
			...process.env,
			DOTNET_PROCESSOR_COUNT: "2",
			MORPHIR_TEST_MAX_PROCESSES: "2",
			MORPHIR_TOOLCHAIN_CONTRACT_ROOT: root,
		},
	};
	const git = process.env.MORPHIR_GIT ?? "git";
	const head = run(git, ["rev-parse", "HEAD"], context);
	if (head.status !== 0 || head.stdout.trim() !== config.commit) {
		throw new Error(`The .NET source commit must be ${config.commit}; observed ${head.stdout.trim() || head.stderr.trim()}`);
	}
	const dirty = run(git, ["status", "--porcelain", "--untracked-files=all"], context);
	if (dirty.status !== 0 || dirty.stdout.trim()) throw new Error("The .NET source has tracked changes, untracked files, or cannot be inspected");
	const dotnet = process.env.MORPHIR_DOTNET ?? "dotnet";
	const build = run(dotnet, ["build", project, "--configuration", "Release", "--maxcpucount:1", "-p:UseSharedCompilation=false", "-nodeReuse:false"], context);
	if (build.status !== 0) return build;
	const tests = run(dotnet, ["exec", "tests/Morphir.Toolchain.Tests/bin/Release/net10.0/Morphir.Toolchain.Tests.dll", "--sequenced", "--summary"], context);
	if (tests.status === 0 && tests.stdout.split(/\r?\n/)[0] !== `External toolchain corpus: ${root}`) {
		throw new Error("The .NET suite did not acknowledge the external corpus; refusing results from its default pinned fixtures");
	}
	return { status: tests.status, stdout: build.stdout + tests.stdout, stderr: build.stderr + tests.stderr };
}

if (import.meta.main) {
	try {
		const args = process.argv.slice(2);
		if (args[0] === "source" && (args.length === 1 || (args.length === 3 && args[1] === "--github-output"))) {
			const config = sourceInfo(defaultRoot);
			if (args[2]) appendFileSync(resolve(args[2]), `repository=${config.repository}\ncommit=${config.commit}\n`);
			console.log(JSON.stringify(config));
		} else if (args.length === 3 && args[0] === "check" && args[1] === "--source") {
			checkCorpusMetadata(defaultRoot);
			const result = checkContracts(defaultRoot, args[2]!);
			process.stdout.write(result.stdout);
			process.stderr.write(result.stderr);
			process.exitCode = result.status;
		} else {
			throw new Error("usage: check-toolchain-contracts source [--github-output <file>] | check --source <dotnet-checkout>");
		}
	} catch (error) {
		console.error(error instanceof Error ? error.message : String(error));
		process.exitCode = 1;
	}
}
