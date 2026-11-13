// Official Morphir CLI delivery from finos/morphir.
//
// The CLI source is finos/morphir-dotnet, pinned as the ecosystem/morphir-dotnet
// submodule, and its own build produces every artifact
// (build/Build.ReleaseProfiles.cs, `--target PackRelease`). This tool never
// packages anything. It checks the pin, derives the release identity, launches
// what the build produced exactly as a user would, and writes the release
// manifest that ties a tag to its source, kit and artifact digests.
//
//   bun run tools/cli-release.ts verify-source
//   bun run tools/cli-release.ts release-info --tag v<version>
//   bun run tools/cli-release.ts qualify --release-dir <dir> --deployment <id> [--rid <rid>] --version <v> --out <file>
//   bun run tools/cli-release.ts legacy-aliases --assets <dir> --version <v> --out <dir>
//   bun run tools/cli-release.ts manifest --tag <tag> --version <v> --commit <sha> --assets <dir> --kit-status <file> [--legacy <file>] --out <dir> [--dry-run]
//
// The expectations live in .config/cli-release.json.
import { format, greaterOrEqual, parse } from "@std/semver";
import { createHash } from "node:crypto";
import { appendFileSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

export type Deployment = { id: string; portable: boolean; package?: string; invocations: string[] };
export type Platform = { rid: string; runner: string };
export type PendingTriage = { scenario: string; platforms: string[]; reason: string; evidence: string[] };
export type CliReleaseConfig = {
	source: { repository: string; submodule: string; commit: string; candidate?: { pullRequest: string; reason: string } };
	tagPrefix: string;
	kit: string;
	deployments: Deployment[];
	platforms: Platform[];
	legacyAliases: { of: string; decision: string };
	pendingTriage: PendingTriage[];
};

/** The build-side launch metadata the .NET build writes beside each artifact (`<artifact>.build-launch.json`). */
export type LaunchMetadata = {
	release: string;
	deployment: string;
	platform: string;
	artifact: string;
	sha256: string;
	launchPath: string;
	layout: string;
};

export type ScenarioStatus = "passed" | "failed" | "pending-triage";

export function readConfig(root: string): CliReleaseConfig {
	return JSON.parse(readFileSync(path.join(root, ".config/cli-release.json"), "utf8")) as CliReleaseConfig;
}

// ---- Source pin ----------------------------------------------------------

/** The URL `.gitmodules` records for the submodule at `submodulePath`, or undefined. */
export function gitmodulesUrl(gitmodules: string, submodulePath: string): string | undefined {
	let current: { path?: string; url?: string } = {};
	const sections: { path?: string; url?: string }[] = [];
	for (const raw of gitmodules.split(/\r?\n/)) {
		const line = raw.trim();
		if (line.startsWith("[submodule ")) {
			current = {};
			sections.push(current);
			continue;
		}
		const match = /^(path|url)\s*=\s*(.+)$/.exec(line);
		if (match) current[match[1] as "path" | "url"] = match[2]!.trim();
	}
	return sections.find(section => section.path === submodulePath)?.url;
}

/** The commit the index records for a submodule (its gitlink), read without the submodule checked out. */
export function gitlinkCommit(root: string, submodulePath: string): string | undefined {
	const result = Bun.spawnSync(["git", "ls-files", "--stage", "--", submodulePath], { cwd: root, stdout: "pipe", stderr: "pipe", windowsHide: true });
	if (result.exitCode !== 0) return undefined;
	const match = /^160000 ([0-9a-f]{40}) 0\t/.exec(result.stdout.toString());
	return match?.[1];
}

/** Every way the checkout disagrees with the recorded CLI source; empty when the pin holds. */
export function verifySource(root: string, config: CliReleaseConfig): string[] {
	const { repository, submodule, commit } = config.source;
	const problems: string[] = [];
	if (!/^[0-9a-f]{40}$/.test(commit)) problems.push(`source.commit must be a full 40-character commit, not '${commit}'`);
	const url = gitmodulesUrl(readFileSync(path.join(root, ".gitmodules"), "utf8"), submodule);
	if (url === undefined) problems.push(`.gitmodules declares no submodule at ${submodule}`);
	else if (url.replace(/\.git$/, "") !== repository) problems.push(`${submodule} comes from ${url}, not the recorded source ${repository}`);
	const pinned = gitlinkCommit(root, submodule);
	if (pinned === undefined) problems.push(`${submodule} is not a submodule gitlink in the index`);
	else if (pinned !== commit) problems.push(`${submodule} is pinned at ${pinned}, but .config/cli-release.json records ${commit}`);
	return problems;
}

/**
 * The deployment ids and platform RIDs the pinned build defines, read from its profile model
 * (build/Helpers/ReleaseProfiles.cs). Used only to detect drift between the parent's expectations and the
 * pinned source; the build itself stays the one packaging implementation.
 */
export function pinnedSourceOfferings(releaseProfiles: string): { deployments: string[]; platforms: string[] } {
	const all = (pattern: RegExp) => [...releaseProfiles.matchAll(pattern)].map(match => match[1]!);
	return {
		deployments: all(/public static readonly Deployment \w+ = new\(\s*"([a-z-]+)"/g),
		platforms: all(/public static readonly TargetPlatform \w+ = new\("([a-z0-9-]+)"/g),
	};
}

/**
 * The platforms the pinned source's legacy release assets were published for (`LegacyAsset.TrimmedSingleFile`'s
 * released platforms). The names stay for those platforms; their bytes are now the Native AOT executable.
 */
export function legacyPlatforms(releaseProfiles: string): string[] {
	const rids = new Map([...releaseProfiles.matchAll(/public static readonly TargetPlatform (\w+) = new\("([a-z0-9-]+)"/g)].map(m => [m[1]!, m[2]!]));
	const legacy = /TrimmedSingleFile = new\([\s\S]*?\[(TargetPlatform\.\w+(?:,\s*TargetPlatform\.\w+)*)\]\);/.exec(releaseProfiles);
	if (!legacy) throw new Error("the pinned source defines no legacy release platforms");
	return legacy[1]!.split(",").map(item => {
		const rid = rids.get(item.trim().replace("TargetPlatform.", ""));
		if (rid === undefined) throw new Error(`unknown platform ${item.trim()}`);
		return rid;
	});
}

/** The legacy asset names of one platform, as the pinned source's `LegacyAsset` spells them. */
export function legacyAliasNames(rid: string, version: string): { executable: string; tarball: string; entry: string } {
	const executable = rid.startsWith("win-") ? "morphir.exe" : "morphir";
	return {
		executable: rid.startsWith("win-") ? `morphir-${rid}.exe` : `morphir-${rid}`,
		tarball: `morphir-${rid}-v${exactRelease(version)}.tar.gz`,
		// The proto plugin strips the `{rid}/` prefix, so the executable sits under it.
		entry: `${rid}/${executable}`,
	};
}

export type LegacyAlias = { asset: string; sha256: string; aliasOf: string; executableSha256: string };

// ---- Release identity ----------------------------------------------------

/** Parses an exact SemVer release in canonical spelling, without build metadata. */
function exactRelease(version: string): string {
	let parsed;
	try {
		parsed = parse(version);
	} catch {
		throw new Error(`'${version}' is not a SemVer version`);
	}
	if (format(parsed) !== version) throw new Error(`'${version}' is not in canonical SemVer spelling`);
	if ((parsed.build ?? []).length > 0) throw new Error(`'${version}' has build metadata; a release identity has none`);
	return version;
}

export function releaseTag(config: CliReleaseConfig, version: string): string {
	return `${config.tagPrefix}${exactRelease(version)}`;
}

/**
 * The version an official CLI tag names: `v<version>` (maintainer decision, 10 November 2026), the same namespace
 * the deleted Rust CLI's releases used. Partial, non-canonical and build-metadata versions are refused; whether the
 * version is new is `versionCollisionBlockers`.
 */
export function parseReleaseTag(config: CliReleaseConfig, tag: string): string {
	if (!tag.startsWith(config.tagPrefix)) throw new Error(`'${tag}' is not an official CLI tag (${config.tagPrefix}<version>)`);
	return exactRelease(tag.slice(config.tagPrefix.length));
}

/** The latest released version in a Keep a Changelog file: the first `## [x.y.z] - date` heading. */
export function changelogReleaseVersion(changelog: string): string {
	for (const match of changelog.matchAll(/^## \[([^\]]+)\](.*)$/gm)) {
		if (match[1] === "Unreleased") continue;
		if (!/^\s*-\s*\d{4}-\d{2}-\d{2}\s*$/.test(match[2]!)) throw new Error(`release heading '${match[0]}' has no date`);
		return exactRelease(match[1]!);
	}
	throw new Error("the CHANGELOG has no released version");
}

/** The GitHub Actions matrix of platform jobs: one runner of the platform's own operating system each. */
export function releaseMatrix(config: CliReleaseConfig): { include: Platform[] } {
	return { include: config.platforms.map(({ rid, runner }) => ({ rid, runner })) };
}

// ---- Qualification -------------------------------------------------------

/** One way to start an offering: the command, and for an installed tool the folder and environment it needs. */
export type LaunchStep = { invocation: string; command: string[]; cwd?: string; env?: Record<string, string | null> };

/**
 * How an archive offering is started: its extracted executable or apphost itself, never `dotnet exec`. Launching
 * the produced file is what users do, and the file's own loader behaviour is part of what ships. The tool package is
 * started from what the source's install helper reports (`toolLaunchPlan`).
 */
export function launchPlan(launch: LaunchMetadata, extracted: string): LaunchStep[] {
	if (launch.layout === "tool-package") throw new Error(`${launch.artifact} is a tool package; it is started from the install helper's result`);
	return [{ invocation: "morphir", command: [path.join(extracted, launch.launchPath)] }];
}
/**
 * Whether `--version` output names the release built from the pinned commit. The executable prints the release,
 * normally followed by `+` and the commit it was built from (`0.4.0-alpha.4+<sha>`); the launch metadata's `release`
 * carries the release alone and is the authority for the part before `+`. This repository owns the provenance, so it
 * is stricter than the source's own start check: build metadata, when printed, must be at least 7 hex digits that
 * prefix the pinned commit, and anything else after `+` fails. The pack origin in the build contents binds the bytes
 * to the commit either way (`buildOriginProblems`).
 */
export function versionReported(output: string, release: string, commit: string): boolean {
	const text = output.trim();
	if (text.length === 0 || /\s/.test(text)) return false;
	const plus = text.indexOf("+");
	if (plus < 0) return text === release;
	const metadata = text.slice(plus + 1);
	return text.slice(0, plus) === release && /^[0-9a-f]{7,40}$/.test(metadata) && commit.startsWith(metadata);
}
/** A scenario's status. A result under a recorded pending triage is kept but never counted as qualified. */
export function scenarioStatus(config: CliReleaseConfig, rid: string, scenario: string, exitCode: number): ScenarioStatus {
	if (config.pendingTriage.some(entry => entry.scenario === scenario && entry.platforms.includes(rid))) return "pending-triage";
	return exitCode === 0 ? "passed" : "failed";
}

/**
 * The command that extracts an archive into a folder on this machine. A zip needs a reader of zip: Windows'
 * own bsdtar (Git for Windows puts GNU tar first on PATH, which reads no zip), and `unzip` elsewhere. A tar.gz uses
 * the system tar. Both paths are absolute so the command does not depend on the working directory.
 */
export function extractCommand(archive: string, destination: string, platform: NodeJS.Platform = process.platform, systemRoot = process.env.SystemRoot ?? "C:\\Windows"): string[] {
	const source = path.resolve(archive);
	const target = path.resolve(destination);
	if (platform === "win32") return [path.win32.join(systemRoot, "System32", "tar.exe"), "-xf", source, "-C", target];
	if (source.endsWith(".zip")) return ["unzip", "-q", source, "-d", target];
	return ["tar", "-xzf", source, "-C", target];
}

/** The reusable-workflow matrix: every deployment on every platform, and the portable tool once. */
export function offeringMatrix(config: CliReleaseConfig): { include: { deployment: string; rid: string; runner: string }[] } {
	const include = config.deployments.flatMap(deployment =>
		deployment.portable
			? [{ deployment: deployment.id, rid: "", runner: "ubuntu-24.04" }]
			: config.platforms.map(platform => ({ deployment: deployment.id, rid: platform.rid, runner: platform.runner })),
	);
	return { include };
}

/** Why a release cannot run from this pin, or undefined when it can. */
export function releaseBlocker(config: CliReleaseConfig): string | undefined {
	const candidate = config.source.candidate;
	return candidate === undefined ? undefined : `the CLI source pin is a marked candidate (${candidate.pullRequest}); ${candidate.reason}`;
}

/** The package copies NuGet keeps for an installed package: files named `<id>.<version>.nupkg`, any case, under `roots`. */
export function installedPackageCopies(roots: string[], id: string, version: string): string[] {
	const wanted = `${id}.${version}.nupkg`.toLowerCase();
	const walk = (dir: string): string[] =>
		existsSync(dir)
			? readdirSync(dir).flatMap(name => {
					const full = path.join(dir, name);
					return statSync(full).isDirectory() ? walk(full) : name.toLowerCase() === wanted ? [full] : [];
				})
			: [];
	return roots.flatMap(walk);
}

/** The source's install helper, as the pinned commit carries it. */
export function installHelperPath(root: string, config: CliReleaseConfig): string {
	return path.join(root, config.source.submodule, ".github", "scripts", "install-tool-package.ps1");
}

export type HelperMode = "tool-path" | "local";

/**
 * The result file of the source's install helper (`-ResultFile`): internal evidence of finos/morphir-dotnet, not a
 * contract. Only the members the parent reads are typed.
 */
export type HelperResult = {
	mode: HelperMode;
	package: { id: string; version: string; command: string; path: string; sha256: string };
	caches: { packagesFolder: string; httpCache: string; pluginsCache: string; cliHome: string | null };
	toolPath: string;
	packageFolder: string;
	stored: { path: string; sha256: string }[];
	invocation: { file: string; arguments: string[]; workingDirectory: string | null; environment: Record<string, string | null> };
};

/**
 * The command that runs the source's install helper: one isolated install of the produced package, into new folders,
 * writing its result file. `-Local` installs into a new tool manifest instead of a tool path. PowerShell 7 runs it on
 * every release runner.
 */
export function helperCommand(helper: string, artifact: string, toolPath: string, workDir: string, mode: HelperMode, resultFile: string): string[] {
	return ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File", helper, "-Package", path.resolve(artifact), "-ToolPath", path.resolve(toolPath), "-WorkDir", path.resolve(workDir), ...(mode === "local" ? ["-Local"] : []), "-ResultFile", path.resolve(resultFile)];
}

/**
 * The parent's own check of a helper run, independent of the helper's: the mode and package are the produced ones,
 * every reported copy and every `<id>.<version>.nupkg` the parent itself finds where that mode installs (the tool
 * store, or the packages folder of a local install) has the artifact's SHA-256 by the parent's own hashing, every
 * path is absolute, and the invocation is a direct command with an argument array, never a shell string or an
 * entry assembly. Returns the problems.
 */
export function helperResultProblems(result: HelperResult, mode: HelperMode, artifactSha256: string): string[] {
	const problems: string[] = [];
	if (result.mode !== mode) problems.push(`the helper ran in ${result.mode} mode, not ${mode}`);
	if (result.package?.sha256 !== artifactSha256) problems.push(`the helper installed a package with SHA-256 ${result.package?.sha256}, not the artifact's ${artifactSha256}`);
	const absolute = [result.toolPath, result.packageFolder, result.caches?.packagesFolder, ...(result.stored ?? []).map(copy => copy.path)];
	if (absolute.some(value => typeof value !== "string" || !path.isAbsolute(value))) problems.push("the helper reported a path that is not absolute");
	if (!Array.isArray(result.stored) || result.stored.length === 0) problems.push("the helper reported no stored package");
	for (const copy of result.stored ?? []) {
		if (!existsSync(copy.path)) problems.push(`the reported copy ${copy.path} does not exist`);
		else if (sha256(copy.path) !== artifactSha256) problems.push(`the reported copy ${copy.path} does not have the artifact's SHA-256 by the parent's own hashing`);
	}
	if (problems.length === 0) {
		const root = mode === "tool-path" ? path.join(result.toolPath, ".store") : result.caches.packagesFolder;
		const found = installedPackageCopies([root], result.package.id, result.package.version);
		if (found.length === 0) problems.push(`the parent finds no ${result.package.id}.${result.package.version}.nupkg under ${root}`);
		for (const copy of found) if (sha256(copy) !== artifactSha256) problems.push(`${copy} does not have the artifact's SHA-256`);
	}
	const invocation = result.invocation;
	if (invocation === undefined || typeof invocation.file !== "string" || !Array.isArray(invocation.arguments) || typeof invocation.environment !== "object" || invocation.environment === null) problems.push("the helper's invocation is not a command, an argument array and an environment object");
	else if (mode === "tool-path") {
		const expectedCommand = path.join(path.resolve(result.toolPath), process.platform === "win32" ? "dotnet-morphir.exe" : "dotnet-morphir");
		if (!path.isAbsolute(invocation.file) || !existsSync(invocation.file) || invocation.arguments.length !== 0 || path.resolve(invocation.file) !== expectedCommand) problems.push(`the tool-path invocation is not the installed command itself: ${invocation.file}`);
	} else if (invocation.file !== "dotnet" || invocation.arguments.length !== 1 || invocation.arguments[0] !== "morphir" || typeof invocation.workingDirectory !== "string" || !path.isAbsolute(invocation.workingDirectory) || path.resolve(invocation.workingDirectory) !== path.resolve(result.toolPath)) {
		problems.push(`the local invocation is not \`dotnet <command>\` from the manifest folder: ${invocation.file} ${invocation.arguments.join(" ")}`);
	} else if (invocation.environment.NUGET_PACKAGES !== result.caches.packagesFolder || typeof result.caches.cliHome !== "string" || !path.isAbsolute(result.caches.cliHome) || invocation.environment.DOTNET_CLI_HOME !== result.caches.cliHome) {
		problems.push("the local invocation does not use the helper's isolated caches");
	}
	return problems;
}

/** How a verified helper result starts the tool: its command, folder and environment, applied as they are. */
export function toolLaunchStep(result: HelperResult): LaunchStep {
	const { file, arguments: args, workingDirectory, environment } = result.invocation;
	return {
		invocation: result.mode === "tool-path" ? path.basename(file).replace(/\.exe$/i, "") : `dotnet ${args.join(" ")}`,
		command: [file, ...args],
		...(workingDirectory === null ? {} : { cwd: workingDirectory }),
		env: environment,
	};
}

export type ToolInstallEvidence = { mode: HelperMode; resultFile: string; result: HelperResult };

/**
 * Installs the produced tool package through the source's helper, once into a tool path and once as a local tool,
 * each into its own new folders, and checks each result with `helperResultProblems`. The helper owns the isolation
 * (finos/morphir-dotnet's single implementation); the parent owns the independent byte check.
 */
export function helperToolInstall(root: string, config: CliReleaseConfig, artifact: string, artifactSha256: string, work: string): { steps: LaunchStep[]; evidence: ToolInstallEvidence[] } {
	const helper = installHelperPath(root, config);
	if (!existsSync(helper)) throw new Error(`the pinned source has no install helper at ${helper}`);
	const steps: LaunchStep[] = [];
	const evidence: ToolInstallEvidence[] = [];
	for (const mode of ["tool-path", "local"] as const) {
		const resultFile = path.join(work, `install-${mode}.json`);
		check(run(helperCommand(helper, artifact, path.join(work, `${mode}-tool`), path.join(work, `${mode}-nuget`), mode, resultFile), { cwd: work }), `install-tool-package.ps1 (${mode})`);
		if (!existsSync(resultFile)) throw new Error(`the install helper wrote no result file in ${mode} mode`);
		const result = JSON.parse(readFileSync(resultFile, "utf8")) as HelperResult;
		const problems = helperResultProblems(result, mode, artifactSha256);
		if (problems.length > 0) throw new Error(problems.join("; "));
		steps.push(toolLaunchStep(result));
		evidence.push({ mode, resultFile, result });
	}
	return { steps, evidence };
}

/** Applies an invocation's environment to a base environment: a null value removes the variable. */
export function applyEnvironment(base: Record<string, string | undefined>, overrides: Record<string, string | null> | undefined): Record<string, string | undefined> {
	const env = { ...base };
	for (const [name, value] of Object.entries(overrides ?? {})) {
		for (const key of Object.keys(env)) if (key.toUpperCase() === name.toUpperCase()) delete env[key];
		if (value !== null) env[name] = value;
	}
	return env;
}
function sha256(file: string): string {
	return createHash("sha256").update(readFileSync(file)).digest("hex");
}

type Run = { exitCode: number; stdout: string; stderr: string };

function run(command: string[], options: { cwd: string; env?: Record<string, string | undefined> }): Run {
	const result = Bun.spawnSync(command, {
		cwd: options.cwd,
		env: options.env,
		stdout: "pipe",
		stderr: "pipe",
		stdin: "ignore",
		timeout: 180_000,
		windowsHide: true,
	});
	return { exitCode: result.exitCode ?? -1, stdout: result.stdout.toString(), stderr: result.stderr.toString() };
}

function check(result: Run, what: string): void {
	if (result.exitCode !== 0) throw new Error(`${what} exited ${result.exitCode}\n${result.stdout}\n${result.stderr}`);
}

/** An environment without any .NET installation on the search path, for offerings that carry their runtime. */
function withoutDotnet(): Record<string, string | undefined> {
	const env: Record<string, string | undefined> = { ...process.env };
	const separator = process.platform === "win32" ? ";" : ":";
	const pathKey = Object.keys(env).find(key => key.toUpperCase() === "PATH") ?? "PATH";
	env[pathKey] = (env[pathKey] ?? "")
		.split(separator)
		.filter(entry => !/dotnet/i.test(entry))
		.join(separator);
	for (const key of Object.keys(env)) if (/^DOTNET_ROOT/i.test(key)) delete env[key];
	env.DOTNET_MULTILEVEL_LOOKUP = "0";
	return env;
}

export type Qualification = {
	release: string;
	deployment: string;
	platform: string;
	runnerPlatform: string;
	artifact: string;
	sha256: string;
	invocations: { invocation: string; reportedVersion: string; scenarios: { scenario: string; status: ScenarioStatus; exitCode: number }[] }[];
	qualified: boolean;
	pending: string[];
	toolInstall?: ToolInstallEvidence[];
};

function readLaunch(releaseDir: string, deployment: string, rid: string | undefined): LaunchMetadata {
	const matches = readdirSync(releaseDir)
		.filter(name => name.endsWith(".build-launch.json"))
		.map(name => JSON.parse(readFileSync(path.join(releaseDir, name), "utf8")) as LaunchMetadata)
		.filter(launch => launch.deployment === deployment && (rid === undefined || launch.platform === rid));
	if (matches.length !== 1) throw new Error(`expected one ${deployment} ${rid ?? "portable"} artifact in ${releaseDir}, found ${matches.length}`);
	return matches[0]!;
}

/** Launches one produced offering on this machine and records what each invocation did. */
export function qualify(root: string, config: CliReleaseConfig, releaseDir: string, deployment: string, rid: string | undefined, version: string, platform: string): Qualification {
	const launch = readLaunch(releaseDir, deployment, rid);
	if (launch.release !== version) throw new Error(`${launch.artifact} is release ${launch.release}, not ${version}`);
	const artifact = path.join(releaseDir, launch.artifact);
	const digest = sha256(artifact);
	if (digest !== launch.sha256) throw new Error(`${launch.artifact} has SHA-256 ${digest}, but its launch metadata records ${launch.sha256}`);
	const contentsFile = path.join(releaseDir, `${launch.artifact}.build-contents.json`);
	const origin = buildOriginProblems(config, launch, existsSync(contentsFile) ? (JSON.parse(readFileSync(contentsFile, "utf8")) as BuildContents) : undefined);
	if (origin.length > 0) throw new Error(origin.join("; "));

	const work = mkdtempSync(path.join(process.env.RUNNER_TEMP ?? os.tmpdir(), `cli-${deployment}-`));
	const extracted = path.join(work, "extracted");
	mkdirSync(extracted);
	let env: Record<string, string | undefined> = { ...process.env };
	let toolEvidence: ToolInstallEvidence[] | undefined;
	let steps: LaunchStep[];
	if (launch.layout === "tool-package") {
		const installed = helperToolInstall(root, config, artifact, digest, work);
		steps = installed.steps;
		toolEvidence = installed.evidence;
	} else {
		// bsdtar (Windows, macOS) reads zip and tar.gz; Linux archives are tar.gz.
		check(run(extractCommand(artifact, extracted), { cwd: work }), `extract ${launch.artifact}`);
		if (deployment !== "framework-dependent") env = withoutDotnet();
		steps = launchPlan(launch, extracted);
	}

	const input = path.join(work, "input");
	mkdirSync(input);
	const example = path.join(input, "greeting-example.json");
	copyFileSync(path.join(root, "website/static/ir/examples/v3/greeting-example.json"), example);

	const invocations = steps.map(step => {
		if (!existsSync(step.command[0]!) && step.command[0] !== "dotnet") throw new Error(`${launch.artifact} has no ${step.command[0]}`);
		const scenarios: Qualification["invocations"][number]["scenarios"] = [];
		const stepEnv = applyEnvironment(env, step.env);
		const cwd = step.cwd ?? work;
		const version_ = run([...step.command, "--version"], { cwd, env: stepEnv });
		const versionMatches = version_.exitCode === 0 && versionReported(version_.stdout, launch.release, config.source.commit);
		scenarios.push({ scenario: "launch", status: scenarioStatus(config, launch.platform === "any" ? platform : launch.platform, "launch", versionMatches ? 0 : 1), exitCode: version_.exitCode });
		const help = run([...step.command, "--help"], { cwd, env: stepEnv });
		scenarios.push({ scenario: "help", status: help.exitCode === 0 ? "passed" : "failed", exitCode: help.exitCode });
		const verify = run([...step.command, "ir", "verify", example], { cwd, env: stepEnv });
		scenarios.push({ scenario: "packaged-input", status: scenarioStatus(config, platform, "packaged-input", verify.exitCode), exitCode: verify.exitCode });
		for (const [name, result] of [["--version", version_], ["--help", help], ["ir verify", verify]] as const) {
			console.error(`${step.invocation} ${name}: exit ${result.exitCode}\n${result.stdout}${result.stderr}`);
		}
		return { invocation: step.invocation, reportedVersion: version_.stdout.trim(), scenarios };
	});
	const all = invocations.flatMap(i => i.scenarios);
	return {
		release: version,
		deployment,
		platform: launch.platform,
		runnerPlatform: platform,
		artifact: launch.artifact,
		sha256: digest,
		invocations,
		qualified: all.every(s => s.status === "passed"),
		pending: all.filter(s => s.status === "pending-triage").map(s => s.scenario),
		...(toolEvidence === undefined ? {} : { toolInstall: toolEvidence }),
	};
}

// ---- Release manifest ----------------------------------------------------

/**
 * The launch metadata of exactly the expected artifacts: one per deployment and platform, and one for each portable
 * deployment. A missing, repeated or unexpected artifact is an error, never dropped or merged silently.
 */
export function expectedLaunches(config: CliReleaseConfig, launches: LaunchMetadata[]): LaunchMetadata[] {
	const key = (deployment: string, platform: string) => `${deployment} ${platform}`;
	const expected = config.deployments.flatMap(d => (d.portable ? [key(d.id, "any")] : config.platforms.map(p => key(d.id, p.rid))));
	const byKey = new Map<string, LaunchMetadata[]>();
	for (const launch of launches) byKey.set(key(launch.deployment, launch.platform), [...(byKey.get(key(launch.deployment, launch.platform)) ?? []), launch]);
	const problems: string[] = [];
	for (const wanted of expected) {
		const found = byKey.get(wanted) ?? [];
		if (found.length === 0) problems.push(`no artifact for ${wanted}`);
		if (new Set(found.map(l => l.artifact)).size > 1 || found.length > 1) problems.push(`${found.length} artifacts for ${wanted}`);
	}
	for (const extra of byKey.keys()) if (!expected.includes(extra)) problems.push(`unexpected artifact for ${extra}`);
	if (problems.length > 0) throw new Error(problems.join("; "));
	return expected.map(wanted => byKey.get(wanted)![0]!);
}

/** The kit identity `morphir-mck kit status --json` reports, as the manifest records it. */
export type KitStatus = { path: string; algorithm: string; corpusHash: string; revision: string };

/** The release manifest: release evidence that names the exact source, kit and artifact digests. Not a contract. */
/** The pack origin and identity the source's build writes beside an artifact (`<artifact>.build-contents.json`). */
export type BuildContents = {
	artifact: string;
	release: string;
	deployment: string;
	platform: string;
	sha256: string;
	origin?: { commit: string; workingTreeClean: boolean; packedAt?: string } | null;
};

/**
 * Ties an artifact to the pinned source: its build contents must name the same artifact, release, deployment,
 * platform and SHA-256 as its launch metadata, and it must have been packed from the pinned commit with a clean
 * working tree. Returns the problems; none means the binding holds.
 */
export function buildOriginProblems(config: CliReleaseConfig, launch: LaunchMetadata, contents: BuildContents | undefined): string[] {
	if (contents === undefined) return [`${launch.artifact} has no build contents (.build-contents.json), so its source commit is unknown`];
	const problems: string[] = [];
	for (const key of ["artifact", "release", "deployment", "platform", "sha256"] as const) {
		if (contents[key] !== launch[key]) problems.push(`${launch.artifact}: build contents ${key} is ${contents[key]}, launch metadata says ${launch[key]}`);
	}
	if (contents.origin == null) problems.push(`${launch.artifact}: build contents record no pack origin`);
	else {
		if (contents.origin.commit !== config.source.commit) problems.push(`${launch.artifact} was packed from ${contents.origin.commit}, not the pinned ${config.source.commit}`);
		if (contents.origin.workingTreeClean !== true) problems.push(`${launch.artifact} was packed from a working tree with uncommitted changes`);
	}
	return problems;
}

/** The entries under `## [Unreleased]` in a Keep a Changelog file: every line that is not blank and not a heading. */
export function unreleasedEntries(changelog: string): string[] {
	const start = changelog.search(/^## \[Unreleased\]/m);
	if (start < 0) return [];
	const rest = changelog.slice(start).split(/\r?\n/).slice(1);
	const end = rest.findIndex(line => /^## \[/.test(line));
	return (end < 0 ? rest : rest.slice(0, end)).filter(line => line.trim().length > 0 && !/^#{3,}\s/.test(line) && !/^\[[^\]]+\]:\s/.test(line));
}

/**
 * Why the pinned source must not be published as `version`. A dry run records these and stops before creating a
 * release; a publication refuses them. The pin is publishable only when it is not a marked candidate, its CHANGELOG
 * has nothing unreleased, and the source's own release tag `v<version>` names exactly the pinned commit: otherwise
 * the bytes would differ from the release the source already published under that version.
 */
export function publicationBlockers(config: CliReleaseConfig, version: string, changelog: string, sourceTagCommit: string | undefined, existingTags: string[]): string[] {
	const blockers: string[] = [];
	const candidate = releaseBlocker(config);
	if (candidate !== undefined) blockers.push(candidate);
	const unreleased = unreleasedEntries(changelog);
	if (unreleased.length > 0) blockers.push(`the pinned CHANGELOG has ${unreleased.length} unreleased entr${unreleased.length === 1 ? "y" : "ies"}, so the pin is not the source's release ${version}`);
	if (sourceTagCommit === undefined) blockers.push(`${config.source.repository} has no tag v${version}`);
	else if (sourceTagCommit !== config.source.commit) blockers.push(`${config.source.repository} tag v${version} is ${sourceTagCommit}, not the pinned ${config.source.commit}: the pin is not the source's release ${version}`);
	blockers.push(...versionCollisionBlockers(config, version, existingTags));
	return blockers;
}

/**
 * Why `v<version>` cannot be a new official release of this repository. The tag namespace is shared with the
 * deleted Rust CLI's releases, which stay as they are. So the version must be newer than every other `v<semver>`
 * tag already in finos/morphir (for example `v0.4.0-beta.12`), and must not reuse one: a lower version would put the
 * new CLI behind the old one and could reuse a published identity such as `v0.4.0-alpha.4`. `tags` are the tag
 * names of this repository; the release's own tag is left out. This repository never picks the version.
 */
export function versionCollisionBlockers(config: CliReleaseConfig, version: string, tags: string[]): string[] {
	const own = releaseTag(config, version);
	const others = tags
		.filter(tag => tag !== own && tag.startsWith(config.tagPrefix))
		.flatMap(tag => {
			try {
				return [{ tag, version: parse(exactRelease(tag.slice(config.tagPrefix.length))) }];
			} catch {
				return [];
			}
		});
	const wanted = parse(version);
	const notOlder = others.filter(other => greaterOrEqual(other.version, wanted)).map(other => other.tag);
	return notOlder.length === 0
		? []
		: [`${own} is not newer than ${notOlder.length === 1 ? notOlder[0] : `${notOlder.length} existing tags (${notOlder.slice(0, 3).join(", ")}${notOlder.length > 3 ? ", ..." : ""})`} in finos/morphir; an official release must be newer than every existing v* release and never reuse one`];
}

/** The tag names of a git repository's remote, read with `git ls-remote`. */
export function remoteTags(cwd: string, remote = "origin"): string[] {
	const result = Bun.spawnSync(["git", "ls-remote", "--tags", "--refs", remote], { cwd, stdout: "pipe", stderr: "pipe", windowsHide: true, timeout: 60_000 });
	if (result.exitCode !== 0) throw new Error(`git ls-remote --tags ${remote} failed: ${result.stderr.toString()}`);
	return result.stdout.toString().trim().split(/\r?\n/).filter(Boolean).map(line => line.split("\t")[1]!.replace(/^refs\/tags\//, ""));
}

/** The commit a tag of the source repository names (peeled), or undefined when there is no such tag. */
export function sourceTagCommit(repository: string, tag: string): string | undefined {
	const result = Bun.spawnSync(["git", "ls-remote", "--tags", `${repository}.git`, `refs/tags/${tag}`, `refs/tags/${tag}^{}`], { stdout: "pipe", stderr: "pipe", windowsHide: true, timeout: 60_000 });
	if (result.exitCode !== 0) throw new Error(`git ls-remote ${repository} failed: ${result.stderr.toString()}`);
	const refs = new Map(result.stdout.toString().trim().split(/\r?\n/).filter(Boolean).map(line => { const [sha, ref] = line.split("\t"); return [ref!, sha!] as const; }));
	return refs.get(`refs/tags/${tag}^{}`) ?? refs.get(`refs/tags/${tag}`);
}

/**
 * Binds the run to what it releases: the workflow must run from the tag's own ref (so its definition, and the literal
 * `uses`/`ref` commit, are the tag's), the checkout must match both the triggering commit and the tag, and the workflow's literal
 * source commit must equal the pinned one. Returns the problems; a release with any problem builds nothing.
 *
 * A dry run may instead rehearse a release from a branch (`refs/heads/...`), so the release can be exercised before
 * its tag exists. It is then bound to the branch's triggering commit, and the tag only names the version; whether the
 * tag exists, or where it points, does not matter to the rehearsal. A publication is never dispatched from a branch.
 */
export function workflowBindingProblems(config: CliReleaseConfig, run: { tag: string; githubRef: string | undefined; githubSha: string | undefined; head: string; tagCommit: string | undefined; workflow: string; dryRun?: boolean }): string[] {
	const problems: string[] = [];
	const rehearsal = run.dryRun === true && run.githubRef?.startsWith("refs/heads/") === true;
	if (!rehearsal && run.githubRef !== `refs/tags/${run.tag}`) problems.push(`the workflow runs from ${run.githubRef ?? "an unknown ref"}, not refs/tags/${run.tag}; dispatch it from the tag${run.dryRun === true ? " or, for a dry run, from a branch" : ""}`);
	if (!/^[0-9a-f]{40}$/.test(run.head)) problems.push(`the checked-out commit is unknown (${run.head})`);
	if (run.githubSha === undefined || !/^[0-9a-f]{40}$/.test(run.githubSha)) problems.push(`the triggering commit is unknown (${run.githubSha ?? "missing GITHUB_SHA"})`);
	else if (run.githubSha !== run.head) problems.push(`the triggering commit is ${run.githubSha}, but the checkout is ${run.head}; the tag may have moved after this run started`);
	if (!rehearsal && run.tagCommit !== run.head) problems.push(`${run.tag} is ${run.tagCommit ?? "missing"}, but the checkout is ${run.head}`);
	const uses = [...run.workflow.matchAll(/uses:\s*finos\/morphir-dotnet\/\.github\/workflows\/cli-offering\.yml@([0-9a-f]+)/g)].map(m => m[1]);
	const refs = [...run.workflow.matchAll(/^\s+ref:\s*([0-9a-f]{40})\s*$/gm)].map(m => m[1]);
	if (uses.length !== 1 || uses[0] !== config.source.commit) problems.push(`release.yml builds with cli-offering.yml@${uses.join(",") || "nothing"}, not the pinned ${config.source.commit}`);
	if (refs.length !== 1 || refs[0] !== config.source.commit) problems.push(`release.yml passes ref ${refs.join(",") || "nothing"}, not the pinned ${config.source.commit}`);
	return problems;
}

/**
 * Validates the release evidence and returns the manifest. Every qualification must be the one expected record for
 * its deployment and platform and match that artifact's launch metadata; a missing, failed, wrong, extra or repeated
 * record, an artifact of another release, or a tag that does not name the release, is an error in a dry run too.
 * Publication readiness is recorded separately (`publication`) and decided by the caller.
 */
export function releaseManifest(config: CliReleaseConfig, tag: string, version: string, commit: string, kit: KitStatus, launches: LaunchMetadata[], qualifications: Qualification[], legacy: LegacyAlias[] = [], publication: { dryRun: boolean; blockers: string[] } = { dryRun: false, blockers: [] }) {
	if (parseReleaseTag(config, tag) !== version) throw new Error(`${tag} does not name release ${version}`);
	if (!/^[0-9a-f]{40}$/.test(commit)) throw new Error(`the finos/morphir commit is unknown (${commit})`);
	const stray = launches.filter(launch => launch.release !== version);
	if (stray.length > 0) throw new Error(`artifacts of another release: ${stray.map(launch => `${launch.artifact} (${launch.release})`).join(", ")}`);
	const problems: string[] = [];
	const seen = new Set<string>();
	for (const q of qualifications) {
		const key = `${q.deployment} ${q.runnerPlatform}`;
		const deployment = config.deployments.find(d => d.id === q.deployment);
		if (deployment === undefined || !config.platforms.some(p => p.rid === q.runnerPlatform)) {
			problems.push(`unexpected qualification ${key}`);
			continue;
		}
		if (seen.has(key)) problems.push(`repeated qualification ${key}`);
		seen.add(key);
		const launch = launches.find(l => l.deployment === q.deployment && l.platform === (deployment.portable ? "any" : q.runnerPlatform));
		if (launch === undefined) problems.push(`qualification ${key} has no artifact`);
		else {
			if (q.release !== version) problems.push(`qualification ${key} is of release ${q.release}`);
			if (q.artifact !== launch.artifact) problems.push(`qualification ${key} launched ${q.artifact}, not ${launch.artifact}`);
			if (q.sha256 !== launch.sha256) problems.push(`qualification ${key} launched bytes ${q.sha256}, not ${launch.artifact}'s ${launch.sha256}`);
		}
		if (q.invocations.some(i => i.scenarios.some(s => s.status === "failed"))) problems.push(`qualification failed: ${key}`);
	}
	for (const deployment of config.deployments) {
		for (const platform of config.platforms) {
			if (!seen.has(`${deployment.id} ${platform.rid}`)) problems.push(`no qualification of ${deployment.id} on ${platform.rid}`);
		}
	}
	if (problems.length > 0) throw new Error(problems.join("; "));
	return {
		note: "Release evidence of finos/morphir, not a contract.",
		tag,
		release: version,
		finosMorphirCommit: commit,
		source: config.source,
		kit,
		publication: { dryRun: publication.dryRun, publishable: publication.blockers.length === 0 && !publication.dryRun, blockers: publication.blockers },
		artifacts: launches
			.map(launch => ({ artifact: launch.artifact, sha256: launch.sha256, deployment: launch.deployment, platform: launch.platform }))
			.sort((a, b) => a.artifact.localeCompare(b.artifact)),
		legacyAliases: { decision: config.legacyAliases.decision, assets: [...legacy].sort((a, b) => a.asset.localeCompare(b.asset)) },
		qualification: qualifications
			.map(q => ({ deployment: q.deployment, platform: q.runnerPlatform, artifact: q.artifact, qualified: q.qualified, pending: q.pending }))
			.sort((a, b) => `${a.deployment} ${a.platform}`.localeCompare(`${b.deployment} ${b.platform}`)),
		pendingTriage: config.pendingTriage,
	};
}
function releaseNotes(manifest: ReturnType<typeof releaseManifest>): string {
	const lines = [
		...(manifest.publication.publishable ? [] : [`**Not a release.** Dry run or blocked publication: ${manifest.publication.blockers.join("; ") || "dry run"}.`, ""]),
		`Morphir CLI ${manifest.release}, built from [${manifest.source.repository}](${manifest.source.repository}) at \`${manifest.source.commit}\` by finos/morphir \`${manifest.finosMorphirCommit}\`.`,
		"",
		`Compatibility kit \`${manifest.kit.path}\` at \`${manifest.kit.revision}\`, ${manifest.kit.algorithm} \`${manifest.kit.corpusHash}\`.`,
		"",
		"| Artifact | Deployment | Platform | SHA-256 |",
		"| --- | --- | --- | --- |",
		...manifest.artifacts.map(a => `| \`${a.artifact}\` | ${a.deployment} | ${a.platform} | \`${a.sha256}\` |`),
		"",
		"Legacy names, the Native AOT executable under its earlier names:",
		"",
		...manifest.legacyAliases.assets.map(a => `- \`${a.asset}\` = \`${a.aliasOf}\` executable, SHA-256 \`${a.sha256}\``),
		"",
		"| Deployment | Platform | Qualified | Pending triage |",
		"| --- | --- | --- | --- |",
		...manifest.qualification.map(q => `| ${q.deployment} | ${q.platform} | ${q.qualified ? "yes" : "no"} | ${q.pending.join(", ") || "none"} |`),
	];
	for (const entry of manifest.pendingTriage) lines.push("", `Pending triage, ${entry.scenario} on ${entry.platforms.join(", ")}: ${entry.reason} Evidence: ${entry.evidence.join("; ")}.`);
	return `${lines.join("\n")}\n`;
}

export type ReleaseInputs = {
	tag: string;
	version: string;
	assets: string;
	kitStatus: string;
	legacy?: string;
	out: string;
	/** The finos/morphir commit release-info bound the run to; the checkout in `cwd` must be it. */
	commit: string;
	/** Write the evidence and the asset list, and refuse nothing on publication grounds; never a release. */
	dryRun: boolean;
	/** The pinned source's CHANGELOG, the commit of its tag `v<version>` and this repository's tags, for the publication gate. */
	changelog: string;
	sourceTagCommit: string | undefined;
	existingTags: string[];
};

/**
 * Verifies the downloaded artifacts and writes the release manifest, the notes and `release-assets.txt`: the exact
 * files the release attaches, one absolute path per line. Relative paths resolve against `cwd`. Every validation
 * failure throws, in a dry run too. Publication blockers (`publicationBlockers`) are recorded in the manifest; outside a
 * dry run they throw after the evidence is written, so no asset list for a blocked release can be used. Returns the list.
 */
export function prepareRelease(config: CliReleaseConfig, cwd: string, inputs: ReleaseInputs): string[] {
	const head = Bun.spawnSync(["git", "rev-parse", "HEAD"], { cwd, stdout: "pipe", stderr: "pipe", windowsHide: true });
	const checkedOut = head.exitCode === 0 ? head.stdout.toString().trim() : "unknown";
	if (checkedOut !== inputs.commit) throw new Error(`the checkout is ${checkedOut}, not the bound commit ${inputs.commit}`);
	const assets = path.resolve(cwd, inputs.assets);
	const launches = files(assets, ".build-launch.json").map(file => JSON.parse(readFileSync(file, "utf8")) as LaunchMetadata);
	const expected = expectedLaunches(config, launches);
	const releaseFiles: string[] = [];
	const problems: string[] = [];
	for (const launch of expected) {
		const found = files(assets, launch.artifact).filter(file => path.basename(file) === launch.artifact);
		if (found.length === 0) throw new Error(`${launch.artifact} is missing from ${assets}`);
		if (found.length > 1) throw new Error(`${launch.artifact} appears ${found.length} times under ${assets}`);
		const artifact = found[0]!;
		if (sha256(artifact) !== launch.sha256) throw new Error(`${launch.artifact} does not match its recorded SHA-256`);
		const contents = files(assets, `${launch.artifact}.build-contents.json`).filter(file => path.basename(file) === `${launch.artifact}.build-contents.json`);
		if (contents.length > 1) problems.push(`${launch.artifact} has ${contents.length} build contents files`);
		problems.push(...buildOriginProblems(config, launch, contents.length === 1 ? (JSON.parse(readFileSync(contents[0]!, "utf8")) as BuildContents) : undefined));
		releaseFiles.push(artifact);
	}
	if (problems.length > 0) throw new Error(problems.join("; "));
	const qualifications = files(assets, ".qualification.json").map(file => JSON.parse(readFileSync(file, "utf8")) as Qualification);
	const kit = readKitStatus(readFileSync(path.resolve(cwd, inputs.kitStatus), "utf8"), config.kit);
	const legacyFile = inputs.legacy === undefined ? undefined : path.resolve(cwd, inputs.legacy);
	const legacy = legacyFile === undefined ? [] : (JSON.parse(readFileSync(legacyFile, "utf8")) as LegacyAlias[]);
	for (const alias of legacy) {
		const file = path.join(path.dirname(legacyFile!), alias.asset);
		if (!existsSync(file) || sha256(file) !== alias.sha256) throw new Error(`${alias.asset} is missing or does not match its recorded SHA-256`);
		releaseFiles.push(file);
	}
	const blockers = publicationBlockers(config, inputs.version, inputs.changelog, inputs.sourceTagCommit, inputs.existingTags);
	const manifest = releaseManifest(config, inputs.tag, inputs.version, inputs.commit, kit, expected, qualifications, legacy, { dryRun: inputs.dryRun, blockers });
	const out = path.resolve(cwd, inputs.out);
	mkdirSync(out, { recursive: true });
	writeFileSync(path.join(out, "release-manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
	writeFileSync(path.join(out, "release-notes.md"), releaseNotes(manifest));
	releaseFiles.push(path.join(out, "release-manifest.json"));
	const names = releaseFiles.map(file => path.basename(file));
	const repeated = names.filter((name, index) => names.indexOf(name) !== index);
	if (repeated.length > 0) throw new Error(`release asset names repeat: ${[...new Set(repeated)].join(", ")}`);
	if (!inputs.dryRun && blockers.length > 0) throw new Error(`publication refused: ${blockers.join("; ")}`);
	writeFileSync(path.join(out, inputs.dryRun ? "dry-run-assets.txt" : "release-assets.txt"), `${releaseFiles.join("\n")}\n`);
	return releaseFiles;
}
// ---- Command line --------------------------------------------------------

function option(args: string[], name: string): string | undefined {
	const index = args.indexOf(name);
	return index >= 0 ? args[index + 1] : undefined;
}

function required(args: string[], name: string): string {
	const value = option(args, name);
	if (value === undefined) throw new Error(`${name} is required`);
	return value;
}

function output(name: string, value: string): void {
	if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`);
	console.log(`${name}=${value}`);
}

/** Reads `morphir-mck kit status --json`. A kit with uncommitted changes or errors identifies nothing. */
export function readKitStatus(text: string, kitPath: string): KitStatus {
	const status = JSON.parse(text) as Record<string, unknown>;
	const { algorithm, corpusHash, revision, modified, errors } = status;
	if (typeof algorithm !== "string" || typeof corpusHash !== "string" || !/^sha256-[0-9a-f]{64}$/.test(corpusHash)) throw new Error("the kit status names no corpus hash");
	if (typeof revision !== "string" || !/^[0-9a-f]{40}$/.test(revision)) throw new Error("the kit status names no commit");
	if (modified !== false) throw new Error("the kit has uncommitted changes");
	if (errors !== 0) throw new Error(`the kit has ${String(errors)} errors`);
	return { path: kitPath, algorithm, corpusHash, revision };
}

function files(directory: string, suffix: string): string[] {
	const found: string[] = [];
	for (const entry of readdirSync(directory)) {
		const full = path.join(directory, entry);
		if (statSync(full).isDirectory()) found.push(...files(full, suffix));
		else if (entry.endsWith(suffix)) found.push(full);
	}
	return found;
}

function main(args: string[]): number {
	const root = path.resolve(import.meta.dir, "..");
	const config = readConfig(root);
	const [command, ...rest] = args;
	switch (command) {
		case "verify-source": {
			const problems = verifySource(root, config);
			for (const problem of problems) console.error(`error: ${problem}`);
			if (problems.length === 0) console.log(`${config.source.submodule} is ${config.source.repository} at ${config.source.commit}`);
			return problems.length === 0 ? 0 : 1;
		}
		case "release-info": {
			const problems = verifySource(root, config);
			if (problems.length > 0) throw new Error(problems.join("\n"));
			const tag = required(rest, "--tag");
			const version = parseReleaseTag(config, tag);
			const changelog = changelogReleaseVersion(readFileSync(path.join(root, config.source.submodule, "CHANGELOG.md"), "utf8"));
			if (changelog !== version) throw new Error(`${tag} names ${version}, but the pinned source releases ${changelog} (its CHANGELOG.md)`);
			const git = (args: string[]) => {
				const result = Bun.spawnSync(["git", ...args], { cwd: root, stdout: "pipe", stderr: "pipe", windowsHide: true });
				return result.exitCode === 0 ? result.stdout.toString().trim() : undefined;
			};
			const head = git(["rev-parse", "HEAD"]) ?? "unknown";
			const binding = workflowBindingProblems(config, {
				tag,
				githubRef: process.env.GITHUB_REF,
				githubSha: process.env.GITHUB_SHA,
				head,
				tagCommit: git(["rev-parse", `refs/tags/${tag}^{commit}`]),
				workflow: readFileSync(path.join(root, ".github/workflows/release.yml"), "utf8"),
				dryRun: process.env.DRY_RUN === "true",
			});
			if (binding.length > 0) throw new Error(binding.join("\n"));
			output("tag", tag);
			output("version", version);
			output("commit", head);
			output("prerelease", (parse(version).prerelease ?? []).length > 0 ? "true" : "false");
			output("matrix", JSON.stringify(releaseMatrix(config)));
			output("offerings", JSON.stringify(offeringMatrix(config)));
			// Building and qualifying may run while publication is blocked, so the interface can be exercised in a
			// dry run; the manifest step refuses a blocked publication on its own as well.
			const blockers = publicationBlockers(config, version, readFileSync(path.join(root, config.source.submodule, "CHANGELOG.md"), "utf8"), sourceTagCommit(config.source.repository, `v${version}`), remoteTags(root));
			for (const blocker of blockers) console.error(`::warning::publication blocked: ${blocker}`);
			output("publishable", blockers.length === 0 ? "true" : "false");
			return 0;
		}
		case "qualify": {
			const deployment = required(rest, "--deployment");
			const platform = required(rest, "--platform");
			const result = qualify(root, config, path.resolve(required(rest, "--release-dir")), deployment, option(rest, "--rid"), required(rest, "--version"), platform);
			const out = path.resolve(required(rest, "--out"));
			mkdirSync(path.dirname(out), { recursive: true });
			writeFileSync(out, `${JSON.stringify(result, null, 2)}\n`);
			const failed = result.invocations.flatMap(i => i.scenarios.filter(s => s.status === "failed").map(s => `${i.invocation} ${s.scenario}`));
			for (const failure of failed) console.error(`error: ${result.artifact} on ${platform}: ${failure} failed`);
			return failed.length === 0 ? 0 : 1;
		}
		case "legacy-aliases": {
			const assets = path.resolve(required(rest, "--assets"));
			const version = required(rest, "--version");
			const out = path.resolve(required(rest, "--out"));
			mkdirSync(out, { recursive: true });
			const platforms = legacyPlatforms(readFileSync(path.join(root, config.source.submodule, "build/Helpers/ReleaseProfiles.cs"), "utf8"));
			const launches = files(assets, ".build-launch.json").map(file => JSON.parse(readFileSync(file, "utf8")) as LaunchMetadata);
			const aliases: LegacyAlias[] = [];
			for (const rid of platforms) {
				const launch = launches.find(l => l.deployment === config.legacyAliases.of && l.platform === rid);
				if (launch === undefined) throw new Error(`no ${config.legacyAliases.of} artifact for legacy platform ${rid}`);
				const [archive] = files(assets, launch.artifact).filter(file => path.basename(file) === launch.artifact);
				if (archive === undefined || sha256(archive) !== launch.sha256) throw new Error(`${launch.artifact} is missing or does not match its SHA-256`);
				const names = legacyAliasNames(rid, version);
				const staging = mkdtempSync(path.join(process.env.RUNNER_TEMP ?? os.tmpdir(), `legacy-${rid}-`));
				check(run(extractCommand(archive, staging), { cwd: staging }), `extract ${launch.artifact}`);
				const executable = path.join(staging, launch.launchPath);
				const digest = sha256(executable);
				copyFileSync(executable, path.join(out, names.executable));
				const tree = path.join(staging, "tree");
				mkdirSync(path.join(tree, rid), { recursive: true });
				copyFileSync(executable, path.join(tree, names.entry));
				check(run(["tar", "-czf", path.join(out, names.tarball), "-C", tree, rid], { cwd: tree }), `pack ${names.tarball}`);
				for (const asset of [names.executable, names.tarball]) {
					aliases.push({ asset, sha256: sha256(path.join(out, asset)), aliasOf: launch.artifact, executableSha256: digest });
				}
				if (sha256(path.join(out, names.executable)) !== digest) throw new Error(`${names.executable} differs from the ${launch.artifact} executable`);
			}
			writeFileSync(path.join(out, "legacy-aliases.json"), `${JSON.stringify(aliases, null, 2)}\n`);
			return 0;
		}
		case "manifest": {
			const version = required(rest, "--version");
			prepareRelease(config, process.cwd(), {
				tag: required(rest, "--tag"),
				version,
				assets: required(rest, "--assets"),
				kitStatus: required(rest, "--kit-status"),
				legacy: option(rest, "--legacy"),
				out: required(rest, "--out"),
				commit: required(rest, "--commit"),
				dryRun: rest.includes("--dry-run"),
				changelog: readFileSync(path.join(root, config.source.submodule, "CHANGELOG.md"), "utf8"),
				sourceTagCommit: sourceTagCommit(config.source.repository, `v${version}`),
				existingTags: remoteTags(root),
			});
			return 0;
		}		default:
			console.error("usage: cli-release.ts verify-source | release-info | qualify | manifest (see the header of tools/cli-release.ts)");
			return 2;
	}
}

if (import.meta.main) {
	try {
		process.exit(main(Bun.argv.slice(2)));
	} catch (error) {
		console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
		process.exit(1);
	}
}
