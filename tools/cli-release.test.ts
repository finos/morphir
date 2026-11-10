// The official CLI delivery: the source pin, the release workflow's routing and
// what qualification launches. See tools/cli-release.ts.
import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import {
	type CliReleaseConfig,
	type LaunchMetadata,
	changelogReleaseVersion,
	expectedLaunches,
	extractCommand,
	gitlinkCommit,
	gitmodulesUrl,
	launchPlan,
	legacyAliasNames,
	legacyPlatforms,
	offeringMatrix,
	type Qualification,
	parseReleaseTag,
	prepareRelease,
	pinnedSourceOfferings,
	readConfig,
	readKitStatus,
	releaseManifest,
	releaseMatrix,
	releaseBlocker,
	releaseTag,
	scenarioStatus,
	verifySource,
	versionReported,
} from "./cli-release";

const root = path.resolve(import.meta.dir, "..");
const config = readConfig(root);
const read = (file: string) => readFileSync(path.join(root, file), "utf8");

type Step = { name?: string; run?: string; uses?: string; if?: string; with?: Record<string, unknown>; shell?: string };
type Job = { needs?: string | string[]; if?: string; uses?: string; with?: Record<string, unknown>; "runs-on"?: string; strategy?: { matrix?: unknown }; steps: Step[]; permissions?: Record<string, string> };
type Workflow = { on: Record<string, unknown>; jobs: Record<string, Job>; permissions?: Record<string, string> };
const release = Bun.YAML.parse(read(".github/workflows/release.yml")) as Workflow;
const ci = Bun.YAML.parse(read(".github/workflows/ci.yml")) as Workflow;
const runs = (job: Job | undefined) => (job?.steps ?? []).map(step => step.run ?? "").join("\n");

describe("source pin", () => {
	test("the CLI source is finos/morphir-dotnet at the recorded commit", () => {
		expect(config.source.repository).toBe("https://github.com/finos/morphir-dotnet");
		expect(config.source.submodule).toBe("ecosystem/morphir-dotnet");
		expect(config.source.commit).toMatch(/^[0-9a-f]{40}$/);
		expect(gitmodulesUrl(read(".gitmodules"), config.source.submodule)).toBe("https://github.com/finos/morphir-dotnet.git");
		expect(gitlinkCommit(root, config.source.submodule)).toBe(config.source.commit);
		expect(verifySource(root, config)).toEqual([]);
	});

	test("a moved gitlink, another repository or a short commit is refused", () => {
		const moved: CliReleaseConfig = { ...config, source: { ...config.source, commit: "0".repeat(40) } };
		expect(verifySource(root, moved).join("\n")).toContain("is pinned at");
		const elsewhere: CliReleaseConfig = { ...config, source: { ...config.source, repository: "https://github.com/example/morphir-dotnet" } };
		expect(verifySource(root, elsewhere).join("\n")).toContain("not the recorded source");
		const short: CliReleaseConfig = { ...config, source: { ...config.source, commit: "7c26348" } };
		expect(verifySource(root, short).join("\n")).toContain("full 40-character commit");
	});

	test("the expected offerings are the ones the pinned build defines", () => {
		const pinned = pinnedSourceOfferings(read(`${config.source.submodule}/build/Helpers/ReleaseProfiles.cs`));
		expect(config.deployments.map(d => d.id)).toEqual(pinned.deployments);
		expect(config.platforms.map(p => p.rid)).toEqual(pinned.platforms);
		expect(config.deployments.find(d => d.id === "dotnet-tool")).toMatchObject({
			portable: true,
			package: "Morphir.Tool",
			invocations: ["dotnet-morphir", "dotnet morphir"],
		});
	});
});

describe("release identity", () => {
	test("official CLI releases carry their own tag namespace", () => {
		expect(releaseTag(config, "0.4.0-alpha.4")).toBe("cli/v0.4.0-alpha.4");
		expect(parseReleaseTag(config, "cli/v0.4.0-alpha.4")).toBe("0.4.0-alpha.4");
		expect(parseReleaseTag(config, "cli/v1.2.3")).toBe("1.2.3");
	});

	test("Rust CLI tags, partial versions, leading zeros and build metadata are refused", () => {
		for (const tag of ["v0.4.0-beta.12", "cli/0.4.0", "cli/v1", "cli/v01.0.0", "cli/v1.0.0+build.1", "cli/vlatest", "cli/v1.0.0 "]) {
			expect(() => parseReleaseTag(config, tag)).toThrow();
		}
	});

	test("the release version is the latest released version in the pinned CHANGELOG", () => {
		const changelog = "# Changelog\n\n## [Unreleased]\n\n### Added\n\n## [0.4.0-alpha.4] - 2026-11-10\n\n## [0.4.0-alpha.3] - 2026-11-09\n";
		expect(changelogReleaseVersion(changelog)).toBe("0.4.0-alpha.4");
		expect(() => changelogReleaseVersion("## [Unreleased]\n")).toThrow();
		expect(() => changelogReleaseVersion("## [v1.0] - 2026-01-01\n")).toThrow();
		expect(changelogReleaseVersion(read(`${config.source.submodule}/CHANGELOG.md`))).toMatch(/^\d+\.\d+\.\d+/);
	});
});

describe("release workflow routing", () => {
	test("only an official CLI tag or an explicit existing tag starts a release", () => {
		const push = release.on.push as { tags: string[] };
		expect(push.tags).toEqual(["cli/v*"]);
		const dispatch = release.on.workflow_dispatch as { inputs: Record<string, { required: boolean }> };
		expect(dispatch.inputs.tag?.required).toBe(true);
		expect(release.permissions).toEqual({ contents: "read" });
	});

	test("no job builds or packages the deleted Rust CLI", () => {
		const text = read(".github/workflows/release.yml");
		expect(text).not.toMatch(/cargo (build|test)[^\n]*--package morphir\b/);
		expect(text).not.toContain("dtolnay/rust-toolchain");
		expect(text).not.toContain("select_release_assets");
	});

	test("every offering is built by the source's reusable workflow at exactly the pinned commit", () => {
		const offering = release.jobs.offering as Job & { uses?: string; with?: Record<string, string> };
		expect(offering.uses).toBe(`finos/morphir-dotnet/.github/workflows/cli-offering.yml@${config.source.commit}`);
		expect(offering.with).toEqual({
			repository: "finos/morphir-dotnet",
			ref: config.source.commit,
			deployment: "${{ matrix.deployment }}",
			rid: "${{ matrix.rid }}",
			os: "${{ matrix.runner }}",
			configuration: "Release",
		});
		expect(offering.strategy?.matrix).toBe("${{ fromJSON(needs.release-info.outputs.offerings) }}");
		const matrix = offeringMatrix(config).include;
		expect(matrix).toHaveLength(3 * config.platforms.length + 1);
		expect(matrix).toContainEqual({ deployment: "dotnet-tool", rid: "", runner: "ubuntu-24.04" });
		expect(matrix).toContainEqual({ deployment: "native-aot", rid: "win-arm64", runner: "windows-11-arm" });
		expect(read(".github/workflows/release.yml")).not.toContain("PackRelease");
	});

	test("each platform qualifies its own and the tool's artifacts, and uploads only the reports", () => {
		const qualifyJob = release.jobs["qualify-platform"];
		expect(qualifyJob?.needs).toEqual(["release-info", "offering"]);
		expect(qualifyJob?.["runs-on"]).toBe("${{ matrix.runner }}");
		expect(qualifyJob?.strategy?.matrix).toBe("${{ fromJSON(needs.release-info.outputs.matrix) }}");
		const steps = runs(qualifyJob);
		expect(steps).toContain("bun run tools/cli-release.ts verify-source");
		expect(steps).toMatch(/qualify --release-dir \.dev\/out\/cli-release\/offerings --deployment "\$deployment"/);
		expect(steps).toMatch(/qualify --release-dir \.dev\/out\/cli-release\/tool --deployment dotnet-tool/);
		const downloads = qualifyJob!.steps.filter(step => step.uses?.startsWith("actions/download-artifact@"));
		expect(downloads.map(step => step.with)).toEqual([
			{ pattern: "morphir-dotnet-*-${{ matrix.rid }}", path: ".dev/out/cli-release/offerings", "merge-multiple": true },
			{ name: "morphir-dotnet-dotnet-tool-any", path: ".dev/out/cli-release/tool" },
		]);
		// upload-artifact leaves out hidden folders such as .dev unless told; the glob names only the reports.
		const upload = qualifyJob!.steps.find(step => step.uses?.startsWith("actions/upload-artifact@"));
		expect(upload?.with).toMatchObject({ path: ".dev/out/cli-release/qualification/*.qualification.json", "include-hidden-files": true, "if-no-files-found": "error" });
		const setup = qualifyJob!.steps.find(step => step.uses?.startsWith("actions/setup-dotnet@"));
		expect(setup?.with?.["global-json-file"]).toBe("ecosystem/morphir-dotnet/global.json");
		expect(releaseMatrix(config)).toEqual({ include: config.platforms.map(p => ({ rid: p.rid, runner: p.runner })) });
	});

	test("publishing needs every qualification, attaches the listed assets and never replaces a release", () => {
		const publish = release.jobs["publish-release"];
		expect(publish?.needs).toEqual(["release-info", "offering", "qualify-platform"]);
		expect(publish?.permissions).toEqual({ contents: "write" });
		const steps = runs(publish);
		expect(steps).not.toContain("--clobber");
		expect(steps).not.toContain("gh release upload");
		expect(steps).not.toContain("gh release edit");
		expect(steps).not.toContain("nullglob");
		expect(steps).not.toMatch(/assets\/\*\//);
		expect(steps).toContain("already exists");
		expect(steps).toContain("bun run tools/cli-release.ts manifest");
		expect(steps).toContain("mapfile -t ASSETS < .dev/out/cli-release/publish/release-assets.txt");
		expect(steps).toMatch(/gh release create "\$TAG"[^\n]*--verify-tag[^\n]*"\$\{ASSETS\[@\]\}"/);
	});

	test("a candidate pin builds and qualifies but cannot publish", () => {
		expect(config.source.candidate?.pullRequest).toBe("https://github.com/finos/morphir-dotnet/pull/590");
		expect(releaseBlocker(config)).toContain("unmerged candidate");
		expect(releaseBlocker({ ...config, source: { ...config.source, candidate: undefined } })).toBeUndefined();
	});
});
describe("qualification launches what ships", () => {
	const archive: LaunchMetadata = {
		release: "0.4.0-alpha.4",
		deployment: "native-aot",
		platform: "win-x64",
		artifact: "morphir-dotnet-0.4.0-alpha.4-native-aot-win-x64.zip",
		sha256: "0".repeat(64),
		launchPath: "morphir.exe",
		layout: "single-file",
	};

	test("an archive offering runs its extracted executable or apphost directly", () => {
		const plan = launchPlan(archive, "/work/extract", "/work/tools");
		expect(plan).toEqual([{ invocation: "morphir", command: [path.join("/work/extract", "morphir.exe")] }]);
		const apphost = launchPlan({ ...archive, deployment: "framework-dependent", layout: "folder", launchPath: "morphir" }, "/x", "/t");
		expect(apphost[0]?.command).toEqual([path.join("/x", "morphir")]);
		for (const step of [...plan, ...apphost]) expect(step.command[0]).not.toBe("dotnet");
	});

	test("the tool package runs as dotnet-morphir and as dotnet morphir", () => {
		const plan = launchPlan(
			{ ...archive, deployment: "dotnet-tool", platform: "any", artifact: "Morphir.Tool.0.4.0-alpha.4.nupkg", launchPath: "dotnet-morphir", layout: "tool-package" },
			"/unused",
			"/work/tools",
		);
		expect(plan.map(step => step.invocation)).toEqual(["dotnet-morphir", "dotnet morphir"]);
		expect(plan[0]?.command[0]).toBe(path.join("/work/tools", process.platform === "win32" ? "dotnet-morphir.exe" : "dotnet-morphir"));
		expect(plan[1]?.command).toEqual(["dotnet", "morphir"]);
	});

	test("a macOS packaged input result is never counted as qualified until triaged", () => {
		expect(scenarioStatus(config, "osx-arm64", "packaged-input", 0)).toBe("pending-triage");
		expect(scenarioStatus(config, "osx-x64", "packaged-input", 1)).toBe("pending-triage");
		expect(scenarioStatus(config, "linux-x64", "packaged-input", 0)).toBe("passed");
		expect(scenarioStatus(config, "osx-arm64", "launch", 0)).toBe("passed");
		expect(scenarioStatus(config, "win-x64", "launch", 1)).toBe("failed");
	});
});

describe("CI after the Rust CLI", () => {
	test("compatibility gates run the standalone runner and no job runs the deleted CLI", () => {
		const text = read(".github/workflows/ci.yml");
		expect(text).not.toMatch(/--package morphir\b(?!-)/);
		expect(text).not.toContain("target/release/morphir ");
		const tasks = Bun.TOML.parse(read(".config/mise/config.toml")) as { tasks: Record<string, { run?: string | string[] }> };
		const commands = Object.values(tasks.tasks).flatMap(task => (Array.isArray(task.run) ? task.run : [task.run ?? ""]));
		for (const command of commands) expect(command).not.toMatch(/-p morphir\b(?!-)|--package morphir\b(?!-)/);
		expect(tasks.tasks["mck:check"]?.run).toEqual([
			"cargo run --locked -p morphir-mck-cli -- check spec/ir/mck",
			"cargo run --locked -p morphir-mck-cli -- schema check --kit spec/ir/mck",
		]);
		expect(ci.jobs["release-workflow"]?.steps.some(step => step.run === "bun test tools/cli-release.test.ts")).toBe(true);
	});
});

describe("release manifest", () => {
	const publishable: CliReleaseConfig = { ...config, source: { ...config.source, candidate: undefined } };
	const kitText = (overrides: Record<string, unknown> = {}) =>
		JSON.stringify({ mode: "local", revision: "a".repeat(40), modified: false, algorithm: "mck-file-map-sha256/1", corpusHash: `sha256-${"b".repeat(64)}`, errors: 0, ...overrides });
	const kit = readKitStatus(kitText(), "spec/ir/mck");
	const passing = (deployment: string, rid: string, pending: string[] = []): Qualification => ({
		release: "0.4.0-alpha.4",
		deployment,
		platform: deployment === "dotnet-tool" ? "any" : rid,
		runnerPlatform: rid,
		artifact: `${deployment}-${rid}`,
		sha256: "c".repeat(64),
		invocations: [{ invocation: "morphir", reportedVersion: "0.4.0-alpha.4", scenarios: [{ scenario: "launch", status: "passed", exitCode: 0 }, ...pending.map(scenario => ({ scenario, status: "pending-triage" as const, exitCode: 1 }))] }],
		qualified: pending.length === 0,
		pending,
	});
	const all = () => config.deployments.flatMap(d => config.platforms.map(p => passing(d.id, p.rid, p.rid.startsWith("osx") ? ["packaged-input"] : [])));

	test("the kit identity is the runner's own, from a clean kit", () => {
		expect(kit).toEqual({ path: "spec/ir/mck", algorithm: "mck-file-map-sha256/1", corpusHash: `sha256-${"b".repeat(64)}`, revision: "a".repeat(40) });
		expect(() => readKitStatus(kitText({ modified: true }), "spec/ir/mck")).toThrow("uncommitted");
		expect(() => readKitStatus(kitText({ errors: 2 }), "spec/ir/mck")).toThrow("errors");
		expect(() => readKitStatus(kitText({ corpusHash: "abc" }), "spec/ir/mck")).toThrow("corpus hash");
	});

	test("it names the source, kit and every artifact digest, and keeps pending triage visible", () => {
		const manifest = releaseManifest(publishable, "cli/v0.4.0-alpha.4", "0.4.0-alpha.4", "d".repeat(40), kit, [], all());
		expect(manifest.source).toEqual(publishable.source);
		expect(() => releaseManifest(config, "cli/v0.4.0-alpha.4", "0.4.0-alpha.4", "d", kit, [], all())).toThrow("unmerged candidate");
		expect(manifest.kit).toEqual(kit);
		const mac = manifest.qualification.find(q => q.deployment === "native-aot" && q.platform === "osx-arm64");
		expect(mac).toMatchObject({ qualified: false, pending: ["packaged-input"] });
		expect(manifest.pendingTriage).toEqual(config.pendingTriage);
	});

	test("a missing or failed qualification, or a mismatched tag, publishes nothing", () => {
		expect(() => releaseManifest(publishable, "cli/v0.4.0-alpha.4", "0.4.0-alpha.4", "d", kit, [], all().slice(1))).toThrow("no qualification");
		const failed = all();
		failed[0] = { ...failed[0]!, invocations: [{ invocation: "morphir", reportedVersion: "0.4.0-alpha.3", scenarios: [{ scenario: "launch", status: "failed", exitCode: 1 }] }], qualified: false };
		expect(() => releaseManifest(publishable, "cli/v0.4.0-alpha.4", "0.4.0-alpha.4", "d", kit, [], failed)).toThrow("qualification failed");
		expect(() => releaseManifest(publishable, "cli/v0.4.0-alpha.5", "0.4.0-alpha.4", "d", kit, [], all())).toThrow("does not name");
	});
});
describe("legacy release names", () => {
	test("future legacy names alias the Native AOT executable on the platforms that shipped them", () => {
		expect(config.legacyAliases.of).toBe("native-aot");
		const pinned = legacyPlatforms(read(`${config.source.submodule}/build/Helpers/ReleaseProfiles.cs`));
		expect(pinned).toEqual(["win-x64", "osx-arm64", "linux-x64", "linux-arm64"]);
		expect(legacyAliasNames("win-x64", "0.4.0-alpha.4")).toEqual({ executable: "morphir-win-x64.exe", tarball: "morphir-win-x64-v0.4.0-alpha.4.tar.gz", entry: "win-x64/morphir.exe" });
		expect(legacyAliasNames("linux-arm64", "1.0.0")).toEqual({ executable: "morphir-linux-arm64", tarball: "morphir-linux-arm64-v1.0.0.tar.gz", entry: "linux-arm64/morphir" });
	});

	test("the release derives the aliases from packed bytes and never builds a fifth offering", () => {
		const text = read(".github/workflows/release.yml");
		expect(text).not.toContain("PublishSingleFile");
		expect(config.deployments).toHaveLength(4);
		const steps = runs(release.jobs["publish-release"]);
		expect(steps).toContain("bun run tools/cli-release.ts legacy-aliases");
		expect(steps.indexOf("legacy-aliases")).toBeLessThan(steps.indexOf("cli-release.ts manifest"));
		expect(steps).toContain("--legacy .dev/out/cli-release/legacy/legacy-aliases.json");
	});
});
test("legacy-aliases copies each packed Native AOT executable byte for byte", () => {
	const work = mkdtempSync(path.join(os.tmpdir(), "cli-legacy-"));
	const assets = path.join(work, "assets");
	const out = path.join(work, "legacy");
	mkdirSync(assets);
	const sha = (file: string) => new Bun.CryptoHasher("sha256").update(readFileSync(file)).digest("hex");
	for (const rid of ["win-x64", "osx-arm64", "linux-x64", "linux-arm64"]) {
		const exe = rid.startsWith("win-") ? "morphir.exe" : "morphir";
		const folder = path.join(work, `publish-${rid}`);
		mkdirSync(folder);
		writeFileSync(path.join(folder, exe), `native ${rid}`);
		const artifact = `morphir-dotnet-1.0.0-native-aot-${rid}.tar.gz`;
		expect(Bun.spawnSync(["tar", "-czf", path.join(assets, artifact), "-C", folder, exe], { windowsHide: true }).exitCode).toBe(0);
		const launch: LaunchMetadata = { release: "1.0.0", deployment: "native-aot", platform: rid, artifact, sha256: sha(path.join(assets, artifact)), launchPath: exe, layout: "single-file" };
		writeFileSync(path.join(assets, `${artifact}.build-launch.json`), JSON.stringify(launch));
	}
	const result = Bun.spawnSync(["bun", "run", path.join(root, "tools/cli-release.ts"), "legacy-aliases", "--assets", assets, "--version", "1.0.0", "--out", out], { cwd: root, stderr: "pipe", windowsHide: true });
	expect(result.exitCode, result.stderr.toString()).toBe(0);
	expect(readFileSync(path.join(out, "morphir-win-x64.exe"), "utf8")).toBe("native win-x64");
	expect(readFileSync(path.join(out, "morphir-linux-arm64"), "utf8")).toBe("native linux-arm64");
	const listing = Bun.spawnSync(["tar", "-tzf", path.join(out, "morphir-osx-arm64-v1.0.0.tar.gz")], { stdout: "pipe", windowsHide: true });
	expect(listing.stdout.toString().trim().split(/\r?\n/)).toContain("osx-arm64/morphir");
	const recorded = JSON.parse(readFileSync(path.join(out, "legacy-aliases.json"), "utf8")) as { asset: string; aliasOf: string }[];
	expect(recorded).toHaveLength(8);
	expect(recorded.find(a => a.asset === "morphir-win-x64.exe")?.aliasOf).toBe("morphir-dotnet-1.0.0-native-aot-win-x64.tar.gz");
});
describe("reported version", () => {
	test("the part before + is the release from the launch metadata; build metadata is evidence", () => {
		expect(versionReported("0.4.0-alpha.4\n", "0.4.0-alpha.4")).toBe(true);
		expect(versionReported("0.4.0-alpha.4+8c15df59ce902c3ec06bb2df0c8ab4a88445a39d\n", "0.4.0-alpha.4")).toBe(true);
		expect(versionReported("0.4.0-alpha.4+7c26348", "0.4.0-alpha.4")).toBe(true);
	});

	test("another release, an empty suffix or other output is refused", () => {
		expect(versionReported("0.4.0-alpha.3+8c15df5", "0.4.0-alpha.4")).toBe(false);
		expect(versionReported("0.4.0-alpha.4.1", "0.4.0-alpha.4")).toBe(false);
		expect(versionReported("0.4.0-alpha.4+", "0.4.0-alpha.4")).toBe(false);
		expect(versionReported("morphir 0.4.0-alpha.4", "0.4.0-alpha.4")).toBe(false);
		expect(versionReported("0.4.0-alpha.4\nextra", "0.4.0-alpha.4")).toBe(false);
		expect(versionReported("", "0.4.0-alpha.4")).toBe(false);
	});
});

describe("archives are read wherever the command runs", () => {
	test("extraction uses absolute paths and a program that reads the archive's format", () => {
		const windows = extractCommand("rel/a.zip", "out", "win32", "C:\\Windows");
		expect(windows[0]).toBe("C:\\Windows\\System32\\tar.exe");
		expect(path.isAbsolute(windows[2]!)).toBe(true);
		expect(extractCommand("rel/a.zip", "out", "linux")).toEqual(["unzip", "-q", path.resolve("rel/a.zip"), "-d", path.resolve("out")]);
		expect(extractCommand("rel/a.tar.gz", "out", "darwin")).toEqual(["tar", "-xzf", path.resolve("rel/a.tar.gz"), "-C", path.resolve("out")]);
	});

	test("qualify, legacy-aliases and manifest take relative paths from an unrelated working directory", () => {
		const work = mkdtempSync(path.join(os.tmpdir(), "cli-relative-"));
		const assets = path.join(work, "assets");
		mkdirSync(assets);
		const sha = (file: string) => new Bun.CryptoHasher("sha256").update(readFileSync(file)).digest("hex");
		const launches: LaunchMetadata[] = [];
		// A tiny controlled "executable": a script that prints the release with build metadata. It is the only
		// program qualification starts here, and only on platforms where a script runs directly.
		for (const d of config.deployments) {
			for (const rid of d.portable ? ["any"] : config.platforms.map(p => p.rid)) {
				const folder = path.join(work, `publish-${d.id}-${rid}`);
				mkdirSync(folder);
				const exe = rid.startsWith("win-") ? "morphir.exe" : "morphir";
				writeFileSync(path.join(folder, exe), "#!/bin/sh\necho 1.0.0+abc1234\n", { mode: 0o755 });
				const artifact = d.portable ? "Morphir.Tool.1.0.0.nupkg" : `morphir-dotnet-1.0.0-${d.id}-${rid}.tar.gz`;
				const dir = path.join(assets, `morphir-dotnet-${d.id}-${rid}`);
				mkdirSync(dir);
				expect(Bun.spawnSync(["tar", "-czf", path.join(dir, artifact), "-C", folder, exe], { windowsHide: true }).exitCode).toBe(0);
				const launch: LaunchMetadata = { release: "1.0.0", deployment: d.id, platform: rid, artifact, sha256: sha(path.join(dir, artifact)), launchPath: d.portable ? "dotnet-morphir" : exe, layout: d.portable ? "tool-package" : d.id === "native-aot" ? "single-file" : "folder" };
				writeFileSync(path.join(dir, `${artifact}.build-launch.json`), JSON.stringify(launch));
				launches.push(launch);
			}
		}
		const qualificationDir = path.join(assets, "cli-qualification-all");
		mkdirSync(qualificationDir);
		for (const d of config.deployments) for (const p of config.platforms) {
			writeFileSync(path.join(qualificationDir, `${d.id}-${p.rid}.qualification.json`), JSON.stringify({ release: "1.0.0", deployment: d.id, platform: p.rid, runnerPlatform: p.rid, artifact: "x", sha256: "y", invocations: [{ invocation: "morphir", reportedVersion: "1.0.0+abc1234", scenarios: [{ scenario: "launch", status: "passed", exitCode: 0 }] }], qualified: true, pending: [] }));
		}
		const kit = path.join(work, "kit.json");
		writeFileSync(kit, JSON.stringify({ revision: "a".repeat(40), modified: false, algorithm: "mck-file-map-sha256/1", corpusHash: `sha256-${"b".repeat(64)}`, errors: 0 }));
		const tool = path.join(root, "tools/cli-release.ts");
		const runTool = (args: string[], cwd: string) => Bun.spawnSync(["bun", "run", tool, ...args], { cwd, stdout: "pipe", stderr: "pipe", windowsHide: true });

		// Every path is relative to `work`, and every command runs from there.
		const legacy = runTool(["legacy-aliases", "--assets", "assets", "--version", "1.0.0", "--out", "legacy"], work);
		expect(legacy.exitCode, legacy.stderr.toString()).toBe(0);
		expect(readFileSync(path.join(work, "legacy/morphir-win-x64.exe"), "utf8")).toContain("echo 1.0.0+abc1234");

		// The candidate pin refuses the manifest; the same inputs pass once the pin is a main commit.
		const refused = runTool(["manifest", "--tag", "cli/v1.0.0", "--version", "1.0.0", "--assets", "assets", "--kit-status", "kit.json", "--legacy", "legacy/legacy-aliases.json", "--out", "publish"], work);
		expect(refused.exitCode).toBe(1);
		expect(refused.stderr.toString()).toContain("unmerged candidate");
		const listed = prepareRelease({ ...config, source: { ...config.source, candidate: undefined } }, work, { tag: "cli/v1.0.0", version: "1.0.0", assets: "assets", kitStatus: "kit.json", legacy: "legacy/legacy-aliases.json", out: "publish", commit: "c".repeat(40) });
		expect(readFileSync(path.join(work, "publish/release-assets.txt"), "utf8").trim().split("\n")).toEqual(listed);
		const names = listed.map(file => path.basename(file)).sort();
		expect(names).toHaveLength(launches.length + 8 + 1);
		for (const launch of launches) expect(names).toContain(launch.artifact);
		expect(names).toContain("morphir-linux-arm64-v1.0.0.tar.gz");
		expect(names).toContain("release-manifest.json");
		for (const file of listed) expect(path.isAbsolute(file)).toBe(true);

		// qualify from the same unrelated directory, with a relative release dir. The launched program is this
		// test's own Bun executable under the name morphir: a real binary that prints a bare version.
		const rid = process.platform === "win32" ? "win-x64" : process.platform === "darwin" ? "osx-arm64" : "linux-x64";
		const exe = process.platform === "win32" ? "morphir.exe" : "morphir";
		const packed = path.join(work, "packed");
		mkdirSync(packed);
		Bun.spawnSync([process.platform === "win32" ? "cmd" : "cp", ...(process.platform === "win32" ? ["/c", "copy", "/b", process.execPath, path.join(packed, exe)] : [process.execPath, path.join(packed, exe)])], { windowsHide: true });
		const real = path.join(work, "real");
		mkdirSync(real);
		const archive = `morphir-dotnet-${Bun.version}-native-aot-${rid}.tar.gz`;
		expect(Bun.spawnSync(["tar", "-czf", path.join(real, archive), "-C", packed, exe], { windowsHide: true }).exitCode).toBe(0);
		writeFileSync(path.join(real, `${archive}.build-launch.json`), JSON.stringify({ release: Bun.version, deployment: "native-aot", platform: rid, artifact: archive, sha256: sha(path.join(real, archive)), launchPath: exe, layout: "single-file" }));
		runTool(["qualify", "--release-dir", "real", "--deployment", "native-aot", "--rid", rid, "--platform", rid, "--version", Bun.version, "--out", "q/native.json"], work);
		const result = JSON.parse(readFileSync(path.join(work, "q/native.json"), "utf8")) as Qualification;
		expect(result.invocations[0]?.reportedVersion).toBe(Bun.version);
		expect(result.invocations[0]?.scenarios.find(s => s.scenario === "launch")?.status).toBe("passed");
		expect(result.sha256).toBe(sha(path.join(real, archive)));	});

	test("a repeated or missing artifact fails instead of being merged or dropped", () => {
		const launch = (deployment: string, platform: string, artifact = `${deployment}-${platform}`): LaunchMetadata => ({ release: "1.0.0", deployment, platform, artifact, sha256: "0", launchPath: "morphir", layout: "folder" });
		const all = config.deployments.flatMap(d => (d.portable ? [launch(d.id, "any")] : config.platforms.map(p => launch(d.id, p.rid))));
		expect(expectedLaunches(config, all)).toHaveLength(all.length);
		expect(() => expectedLaunches(config, all.slice(1))).toThrow("no artifact for native-aot win-x64");
		expect(() => expectedLaunches(config, [...all, launch("native-aot", "win-x64", "other.zip")])).toThrow("2 artifacts for native-aot win-x64");
		expect(() => expectedLaunches(config, [...all, launch("native-aot", "freebsd-x64")])).toThrow("unexpected artifact");
	});
});