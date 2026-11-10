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
//   bun run tools/cli-release.ts release-info --tag cli/v0.4.0-alpha.4 [--kit-status <file>]
//   bun run tools/cli-release.ts qualify --release-dir <dir> --deployment <id> [--rid <rid>] --version <v> --out <file>
//   bun run tools/cli-release.ts legacy-aliases --assets <dir> --version <v> --out <dir>
//   bun run tools/cli-release.ts manifest --tag <tag> --version <v> --assets <dir> --kit-status <file> [--legacy <file>] --out <dir>
//
// The expectations live in .config/cli-release.json.
import { format, parse } from "@std/semver";
import { createHash } from "node:crypto";
import { appendFileSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

export type Deployment = { id: string; portable: boolean; package?: string; invocations: string[] };
export type Platform = { rid: string; runner: string };
export type PendingTriage = { scenario: string; platforms: string[]; reason: string; evidence: string[] };
export type CliReleaseConfig = {
	source: { repository: string; submodule: string; commit: string };
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

/** The version an official CLI tag names. Rust CLI tags (`v*`) and anything else are refused. */
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

export type LaunchStep = { invocation: string; command: string[] };

/**
 * How each invocation of an offering is started. Archives run their extracted executable or apphost itself,
 * never `dotnet exec`: launching the produced file is what users do, and the file's own loader behaviour is
 * part of what ships. The tool package runs as the `dotnet-morphir` shim the SDK installed and as
 * `dotnet morphir` from a local tool manifest.
 */
export function launchPlan(launch: LaunchMetadata, extracted: string, toolPath: string): LaunchStep[] {
	if (launch.layout === "tool-package") {
		const shim = process.platform === "win32" ? `${launch.launchPath}.exe` : launch.launchPath;
		return [
			{ invocation: "dotnet-morphir", command: [path.join(toolPath, shim)] },
			{ invocation: "dotnet morphir", command: ["dotnet", "morphir"] },
		];
	}
	return [{ invocation: "morphir", command: [path.join(extracted, launch.launchPath)] }];
}

/**
 * Whether `--version` output names the release. The executable prints the release, optionally with the source
 * commit it was built from as SemVer build metadata (`0.4.0-alpha.4+<sha>`); the launch metadata carries the release
 * alone. Metadata counts only when it is at least 7 hex digits of the pinned commit: any other commit or text fails.
 */
export function versionReported(output: string, version: string, commit: string): boolean {
	const text = output.trim();
	if (text === version) return true;
	if (!text.startsWith(`${version}+`)) return false;
	const metadata = text.slice(version.length + 1);
	return /^[0-9a-f]{7,40}$/.test(metadata) && commit.startsWith(metadata);
}

/** A scenario's status. A result under a recorded pending triage is kept but never counted as qualified. */
export function scenarioStatus(config: CliReleaseConfig, rid: string, scenario: string, exitCode: number): ScenarioStatus {
	if (config.pendingTriage.some(entry => entry.scenario === scenario && entry.platforms.includes(rid))) return "pending-triage";
	return exitCode === 0 ? "passed" : "failed";
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
	invocations: { invocation: string; scenarios: { scenario: string; status: ScenarioStatus; exitCode: number }[] }[];
	qualified: boolean;
	pending: string[];
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

	const work = mkdtempSync(path.join(process.env.RUNNER_TEMP ?? os.tmpdir(), `cli-${deployment}-`));
	const extracted = path.join(work, "extracted");
	const toolPath = path.join(work, "tools");
	mkdirSync(extracted);
	let env: Record<string, string | undefined> = { ...process.env };
	if (launch.layout === "tool-package") {
		const feed = path.join(work, "feed");
		mkdirSync(feed);
		copyFileSync(artifact, path.join(feed, launch.artifact));
		const pkg = config.deployments.find(d => d.id === deployment)?.package ?? "Morphir.Tool";
		check(run(["dotnet", "tool", "install", pkg, "--version", version, "--add-source", feed, "--tool-path", toolPath], { cwd: work }), "dotnet tool install --tool-path");
		check(run(["dotnet", "new", "tool-manifest"], { cwd: work }), "dotnet new tool-manifest");
		check(run(["dotnet", "tool", "install", pkg, "--version", version, "--add-source", feed, "--local"], { cwd: work }), "dotnet tool install --local");
	} else {
		// bsdtar (Windows, macOS) reads zip and tar.gz; Linux archives are tar.gz.
		check(run(["tar", "-xf", artifact, "-C", extracted], { cwd: work }), `extract ${launch.artifact}`);
		if (deployment !== "framework-dependent") env = withoutDotnet();
	}

	const input = path.join(work, "input");
	mkdirSync(input);
	const example = path.join(input, "greeting-example.json");
	copyFileSync(path.join(root, "website/static/ir/examples/v3/greeting-example.json"), example);

	const invocations = launchPlan(launch, extracted, toolPath).map(step => {
		if (!existsSync(step.command[0]!) && step.command[0] !== "dotnet") throw new Error(`${launch.artifact} has no ${step.command[0]}`);
		const scenarios: Qualification["invocations"][number]["scenarios"] = [];
		const version_ = run([...step.command, "--version"], { cwd: work, env });
		const versionMatches = version_.exitCode === 0 && versionReported(version_.stdout, version, config.source.commit);
		scenarios.push({ scenario: "launch", status: scenarioStatus(config, launch.platform === "any" ? platform : launch.platform, "launch", versionMatches ? 0 : 1), exitCode: version_.exitCode });
		const help = run([...step.command, "--help"], { cwd: work, env });
		scenarios.push({ scenario: "help", status: help.exitCode === 0 ? "passed" : "failed", exitCode: help.exitCode });
		const verify = run([...step.command, "ir", "verify", example], { cwd: work, env });
		scenarios.push({ scenario: "packaged-input", status: scenarioStatus(config, platform, "packaged-input", verify.exitCode), exitCode: verify.exitCode });
		for (const [name, result] of [["--version", version_], ["--help", help], ["ir verify", verify]] as const) {
			console.error(`${step.invocation} ${name}: exit ${result.exitCode}\n${result.stdout}${result.stderr}`);
		}
		return { invocation: step.invocation, scenarios };
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
	};
}

// ---- Release manifest ----------------------------------------------------

/** The kit identity `morphir-mck kit status --json` reports, as the manifest records it. */
export type KitStatus = { path: string; algorithm: string; corpusHash: string; revision: string };

/** The release manifest: release evidence that names the exact source, kit and artifact digests. Not a contract. */
export function releaseManifest(config: CliReleaseConfig, tag: string, version: string, commit: string, kit: KitStatus, launches: LaunchMetadata[], qualifications: Qualification[], legacy: LegacyAlias[] = []) {
	if (parseReleaseTag(config, tag) !== version) throw new Error(`${tag} does not name release ${version}`);
	const failed = qualifications.filter(q => q.invocations.some(i => i.scenarios.some(s => s.status === "failed")));
	if (failed.length > 0) throw new Error(`qualification failed: ${failed.map(q => `${q.deployment} ${q.runnerPlatform}`).join(", ")}`);
	for (const deployment of config.deployments) {
		for (const platform of config.platforms) {
			const found = qualifications.some(q => q.deployment === deployment.id && q.runnerPlatform === platform.rid);
			if (!found) throw new Error(`no qualification of ${deployment.id} on ${platform.rid}`);
		}
	}
	return {
		note: "Release evidence of finos/morphir, not a contract.",
		tag,
		release: version,
		finosMorphirCommit: commit,
		source: config.source,
		kit,
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
			output("tag", tag);
			output("version", version);
			output("prerelease", (parse(version).prerelease ?? []).length > 0 ? "true" : "false");
			output("matrix", JSON.stringify(releaseMatrix(config)));
			return 0;
		}
		case "qualify": {
			const deployment = required(rest, "--deployment");
			const platform = required(rest, "--platform");
			const result = qualify(root, config, required(rest, "--release-dir"), deployment, option(rest, "--rid"), required(rest, "--version"), platform);
			const out = required(rest, "--out");
			mkdirSync(path.dirname(out), { recursive: true });
			writeFileSync(out, `${JSON.stringify(result, null, 2)}\n`);
			const failed = result.invocations.flatMap(i => i.scenarios.filter(s => s.status === "failed").map(s => `${i.invocation} ${s.scenario}`));
			for (const failure of failed) console.error(`error: ${result.artifact} on ${platform}: ${failure} failed`);
			return failed.length === 0 ? 0 : 1;
		}
		case "legacy-aliases": {
			const assets = required(rest, "--assets");
			const version = required(rest, "--version");
			const out = required(rest, "--out");
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
				check(run(["tar", "-xf", archive, "-C", staging], { cwd: staging }), `extract ${launch.artifact}`);
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
			const assets = required(rest, "--assets");
			const launches = files(assets, ".build-launch.json").map(file => JSON.parse(readFileSync(file, "utf8")) as LaunchMetadata);
			const unique = [...new Map(launches.map(launch => [launch.artifact, launch])).values()];
			for (const launch of unique) {
				const [artifact] = files(assets, launch.artifact).filter(file => path.basename(file) === launch.artifact);
				if (artifact === undefined) throw new Error(`${launch.artifact} is missing from ${assets}`);
				if (sha256(artifact) !== launch.sha256) throw new Error(`${launch.artifact} does not match its recorded SHA-256`);
			}
			const qualifications = files(assets, ".qualification.json").map(file => JSON.parse(readFileSync(file, "utf8")) as Qualification);
			const kit = readKitStatus(readFileSync(required(rest, "--kit-status"), "utf8"), config.kit);
			const legacyFile = option(rest, "--legacy");
			const legacy = legacyFile === undefined ? [] : (JSON.parse(readFileSync(legacyFile, "utf8")) as LegacyAlias[]);
			const manifest = releaseManifest(config, required(rest, "--tag"), required(rest, "--version"), process.env.GITHUB_SHA ?? "unknown", kit, unique, qualifications, legacy);
			const out = required(rest, "--out");
			mkdirSync(out, { recursive: true });
			writeFileSync(path.join(out, "release-manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
			writeFileSync(path.join(out, "release-notes.md"), releaseNotes(manifest));
			return 0;
		}
		default:
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
