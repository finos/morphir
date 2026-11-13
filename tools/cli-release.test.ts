// The official CLI delivery: the source pin, the release workflow's routing and
// what qualification launches. See tools/cli-release.ts.
import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import os from "node:os";
import { crc32 } from "node:zlib";
import path from "node:path";

import {
	type BuildContents,
	type CliReleaseConfig,
	type LaunchMetadata,
	buildOriginProblems,
	changelogReleaseVersion,
	expectedLaunches,
	extractCommand,
	gitlinkCommit,
	gitmodulesUrl,
	type HelperResult,
	applyEnvironment,
	helperCommand,
	helperResultProblems,
	helperToolInstall,
	installHelperPath,
	toolLaunchStep,
	launchPlan,
	legacyAliasNames,
	legacyPlatforms,
	offeringMatrix,
	type Qualification,
	parseReleaseTag,
	prepareRelease,
	publicationBlockers,
	pinnedSourceOfferings,
	readConfig,
	readKitStatus,
	releaseManifest,
	releaseMatrix,
	releaseBlocker,
	releaseTag,
	scenarioStatus,
	unreleasedEntries,
	verifySource,
	versionCollisionBlockers,
	versionReported,
	workflowBindingProblems,
} from "./cli-release";

const root = path.resolve(import.meta.dir, "..");
const config = readConfig(root);
const read = (file: string) => readFileSync(path.join(root, file), "utf8");
/** The platforms the pinned source publishes legacy names for; the fixtures pack one Native AOT archive for each. */
const legacyRids = legacyPlatforms(read(`${config.source.submodule}/build/Helpers/ReleaseProfiles.cs`));

type Step = { id?: string; name?: string; run?: string; uses?: string; if?: string; with?: Record<string, unknown>; shell?: string };
type Job = { needs?: string | string[]; if?: string; uses?: string; with?: Record<string, unknown>; "runs-on"?: string; strategy?: { matrix?: unknown }; steps: Step[]; permissions?: Record<string, string> };
type Workflow = { on: Record<string, unknown>; jobs: Record<string, Job>; permissions?: Record<string, string> };
const release = Bun.YAML.parse(read(".github/workflows/release.yml")) as Workflow;
const ci = Bun.YAML.parse(read(".github/workflows/ci.yml")) as Workflow;
const runs = (job: Job | undefined) => (job?.steps ?? []).map(step => step.run ?? "").join("\n");
/** The build contents the source writes beside an artifact, packed from the pinned commit. */
const contentsOf = (launch: LaunchMetadata, origin: { commit: string; workingTreeClean: boolean } = { commit: config.source.commit, workingTreeClean: true }): BuildContents => ({ artifact: launch.artifact, release: launch.release, deployment: launch.deployment, platform: launch.platform, sha256: launch.sha256, origin: { ...origin, packedAt: "2026-11-10T00:00:00Z" } });
const passingQualification = (launch: LaunchMetadata, runnerPlatform: string): Qualification => ({ release: launch.release, deployment: launch.deployment, platform: launch.platform, runnerPlatform, artifact: launch.artifact, sha256: launch.sha256, invocations: [{ invocation: "morphir", reportedVersion: `${launch.release}+${config.source.commit.slice(0, 7)}`, scenarios: [{ scenario: "launch", status: "passed", exitCode: 0 }] }], qualified: true, pending: [] });
/** `base` with the macOS packaged input recorded as pending triage, for the tests of that mechanism. */
const withPendingTriage = (base: CliReleaseConfig): CliReleaseConfig => ({
	...base,
	pendingTriage: [{ scenario: "packaged-input", platforms: ["osx-x64", "osx-arm64"], reason: "Test fixture.", evidence: ["https://example.invalid/evidence"] }],
});
/** A throwaway git repository in `dir` with one commit; returns that commit. */
function gitCommit(dir: string): string {
	const git = (args: string[]) => Bun.spawnSync(["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=", ...args], { cwd: dir, stdout: "pipe", stderr: "pipe", windowsHide: true });
	git(["init", "-q"]);
	writeFileSync(path.join(dir, ".keep"), "");
	git(["add", ".keep"]);
	expect(git(["commit", "-q", "-m", "fixture"]).exitCode).toBe(0);
	return git(["rev-parse", "HEAD"]).stdout.toString().trim();
}

describe("source pin", () => {
	test("the CLI source is finos/morphir-dotnet at the recorded commit", () => {
		expect(config.source.repository).toBe("https://github.com/finos/morphir-dotnet");
		expect(config.source.submodule).toBe("ecosystem/morphir-dotnet");
		expect(config.source.commit).toMatch(/^[0-9a-f]{40}$/);
		expect(gitmodulesUrl(read(".gitmodules"), config.source.submodule)).toBe("https://github.com/finos/morphir-dotnet.git");
		expect(gitlinkCommit(root, config.source.submodule)).toBe(config.source.commit);
		expect(verifySource(root, config)).toEqual([]);
	});

	test("contract-test source and CLI delivery are independently pinned", () => {
		const contracts = JSON.parse(read(".config/toolchain-contract-tests.json")) as { repository: string; commit: string };
		expect(contracts.repository).toBe("finos/morphir-dotnet");
		expect(contracts.commit).toMatch(/^[0-9a-f]{40}$/);
		expect(contracts.commit).not.toBe(config.source.commit);
		const corpus = runs(ci.jobs["toolchain-contracts"]);
		expect(corpus).toContain("tools/check-toolchain-contracts.ts source");
		expect(corpus).toContain("tools/check-toolchain-contracts.ts check --source .dev/toolchain-contract-source");
		expect(corpus).not.toContain("tools/cli-release.ts");
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
	test("official CLI releases use v<version> (maintainer decision, 10 November 2026)", () => {
		expect(config.tagPrefix).toBe("v");
		expect(releaseTag(config, "0.4.0-beta.13")).toBe("v0.4.0-beta.13");
		expect(parseReleaseTag(config, "v0.4.0-beta.13")).toBe("0.4.0-beta.13");
		expect(parseReleaseTag(config, "v1.2.3")).toBe("1.2.3");
	});

	test("other namespaces, partial versions, leading zeros and build metadata are refused", () => {
		for (const tag of ["cli/v0.4.0", "0.4.0", "v1", "v01.0.0", "v1.0.0+build.1", "vlatest", "v1.0.0 ", "extension/python/v0.4.0"]) {
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
		expect(push.tags).toEqual(["v*"]);
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
		expect(config.source.candidate?.pullRequest).toBe("https://github.com/finos/morphir-dotnet/pull/637");
		expect(releaseBlocker(config)).toContain("marked candidate");
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
		const plan = launchPlan(archive, "/work/extract");
		expect(plan).toEqual([{ invocation: "morphir", command: [path.join("/work/extract", "morphir.exe")] }]);
		const apphost = launchPlan({ ...archive, deployment: "framework-dependent", layout: "folder", launchPath: "morphir" }, "/x");
		expect(apphost[0]?.command).toEqual([path.join("/x", "morphir")]);
		for (const step of [...plan, ...apphost]) expect(step.command[0]).not.toBe("dotnet");
	});

	test("the tool package starts from the helper's result: the installed command, and dotnet morphir from the manifest", () => {
		expect(() => launchPlan({ ...archive, deployment: "dotnet-tool", platform: "any", artifact: "Morphir.Tool.0.4.0-alpha.4.nupkg", launchPath: "dotnet-morphir", layout: "tool-package" }, "/unused")).toThrow("install helper");
		const command = path.resolve("/q/tool-path-tool", process.platform === "win32" ? "dotnet-morphir.exe" : "dotnet-morphir");
		const global = toolLaunchStep({ mode: "tool-path", invocation: { file: command, arguments: [], workingDirectory: null, environment: {} } } as unknown as HelperResult);
		expect(global).toEqual({ invocation: "dotnet-morphir", command: [command], env: {} });
		const manifest = path.resolve("/q/local-tool");
		const env = { NUGET_PACKAGES: path.resolve("/q/local-nuget/packages"), DOTNET_CLI_HOME: path.resolve("/q/local-nuget/cli-home") };
		const local = toolLaunchStep({ mode: "local", invocation: { file: "dotnet", arguments: ["morphir"], workingDirectory: manifest, environment: env } } as unknown as HelperResult);
		expect(local).toEqual({ invocation: "dotnet morphir", command: ["dotnet", "morphir"], cwd: manifest, env });
	});

	test("an invocation's environment is applied as given; null removes a variable", () => {
		const applied = applyEnvironment({ PATH: "p", NUGET_FALLBACK_PACKAGES: "ambient", NUGET_PACKAGES: "ambient" }, { NUGET_PACKAGES: "isolated", NUGET_FALLBACK_PACKAGES: null });
		expect(applied).toEqual({ PATH: "p", NUGET_PACKAGES: "isolated" });
	});
	test("every platform qualifies every scenario: nothing is pending triage", () => {
		expect(config.pendingTriage).toEqual([]);
		for (const { rid } of config.platforms) {
			for (const scenario of ["launch", "help", "packaged-input"]) {
				expect(scenarioStatus(config, rid, scenario, 0)).toBe("passed");
				expect(scenarioStatus(config, rid, scenario, 1)).toBe("failed");
			}
		}
	});

	test("a result under a recorded pending triage is kept but never counted as qualified", () => {
		const triaged = withPendingTriage(config);
		expect(scenarioStatus(triaged, "osx-arm64", "packaged-input", 0)).toBe("pending-triage");
		expect(scenarioStatus(triaged, "osx-x64", "packaged-input", 1)).toBe("pending-triage");
		expect(scenarioStatus(triaged, "linux-x64", "packaged-input", 0)).toBe("passed");
		expect(scenarioStatus(triaged, "osx-arm64", "launch", 0)).toBe("passed");
		expect(scenarioStatus(triaged, "win-x64", "launch", 1)).toBe("failed");
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
			"cargo run --locked --manifest-path ecosystem/morphir-rust/umbrella-tools/Cargo.toml -p morphir-mck-cli -- check spec/ir/mck",
			"cargo run --locked --manifest-path ecosystem/morphir-rust/umbrella-tools/Cargo.toml -p morphir-mck-cli -- schema check --kit spec/ir/mck",
		]);
		expect(ci.jobs["release-workflow"]?.steps.some(step => step.run === "bun test tools/cli-release.test.ts")).toBe(true);
	});
});

describe("release manifest", () => {
	const publishable: CliReleaseConfig = { ...config, source: { ...config.source, candidate: undefined } };
	const kitText = (overrides: Record<string, unknown> = {}) =>
		JSON.stringify({ mode: "local", revision: "a".repeat(40), modified: false, algorithm: "mck-file-map-sha256/1", corpusHash: `sha256-${"b".repeat(64)}`, errors: 0, ...overrides });
	const kit = readKitStatus(kitText(), "spec/ir/mck");
	const launchOf = (deployment: string, platform: string): LaunchMetadata => ({ release: "0.4.0-alpha.4", deployment, platform, artifact: `${deployment}-${platform}.zip`, sha256: `${deployment}-${platform}`.padEnd(64, "0"), launchPath: "morphir", layout: "folder" });
	const launches = config.deployments.flatMap(d => (d.portable ? [launchOf(d.id, "any")] : config.platforms.map(p => launchOf(d.id, p.rid))));
	const passing = (deployment: string, rid: string, pending: string[] = []): Qualification => {
		const launch = launches.find(l => l.deployment === deployment && l.platform === (deployment === "dotnet-tool" ? "any" : rid))!;
		return {
			...passingQualification(launch, rid),
			invocations: [{ invocation: "morphir", reportedVersion: "0.4.0-alpha.4", scenarios: [{ scenario: "launch", status: "passed", exitCode: 0 }, ...pending.map(scenario => ({ scenario, status: "pending-triage" as const, exitCode: 1 }))] }],
			qualified: pending.length === 0,
			pending,
		};
	};
	const all = () => config.deployments.flatMap(d => config.platforms.map(p => passing(d.id, p.rid)));
	/** The qualifications of a configuration that records the macOS packaged input as pending triage. */
	const allTriaged = () => config.deployments.flatMap(d => config.platforms.map(p => passing(d.id, p.rid, p.rid.startsWith("osx") ? ["packaged-input"] : [])));
	const commit = "d".repeat(40);

	test("the kit identity is the runner's own, from a clean kit", () => {
		expect(kit).toEqual({ path: "spec/ir/mck", algorithm: "mck-file-map-sha256/1", corpusHash: `sha256-${"b".repeat(64)}`, revision: "a".repeat(40) });
		expect(() => readKitStatus(kitText({ modified: true }), "spec/ir/mck")).toThrow("uncommitted");
		expect(() => readKitStatus(kitText({ errors: 2 }), "spec/ir/mck")).toThrow("errors");
		expect(() => readKitStatus(kitText({ corpusHash: "abc" }), "spec/ir/mck")).toThrow("corpus hash");
	});

	test("it names the source, kit and every artifact digest, and keeps pending triage visible", () => {
		const manifest = releaseManifest(publishable, "v0.4.0-alpha.4", "0.4.0-alpha.4", commit, kit, launches, all());
		expect(manifest.source).toEqual(publishable.source);
		expect(manifest.kit).toEqual(kit);
		expect(manifest.publication).toEqual({ dryRun: false, publishable: true, blockers: [] });
		const mac = manifest.qualification.find(q => q.deployment === "native-aot" && q.platform === "osx-arm64");
		expect(mac).toMatchObject({ qualified: true, pending: [] });
		expect(manifest.pendingTriage).toEqual([]);
		// A recorded pending triage stays visible in the manifest and its notes, and is never counted as qualified.
		const triaged = withPendingTriage(publishable);
		const visible = releaseManifest(triaged, "v0.4.0-alpha.4", "0.4.0-alpha.4", commit, kit, launches, allTriaged());
		expect(visible.qualification.find(q => q.deployment === "native-aot" && q.platform === "osx-arm64")).toMatchObject({ qualified: false, pending: ["packaged-input"] });
		expect(visible.pendingTriage).toEqual(triaged.pendingTriage);
		const blocked = releaseManifest(config, "v0.4.0-alpha.4", "0.4.0-alpha.4", commit, kit, launches, all(), [], { dryRun: true, blockers: ["candidate"] });
		expect(blocked.publication).toEqual({ dryRun: true, publishable: false, blockers: ["candidate"] });
	});

	test("a missing, failed, repeated, extra or mismatched qualification, or a mismatched tag or commit, is refused", () => {
		const refuse = (qualifications: Qualification[], expected: string, tag = "v0.4.0-alpha.4", at = commit) =>
			expect(() => releaseManifest(publishable, tag, "0.4.0-alpha.4", at, kit, launches, qualifications)).toThrow(expected);
		refuse(all().slice(1), "no qualification of native-aot on win-x64");
		const failed = all();
		failed[0] = { ...failed[0]!, invocations: [{ invocation: "morphir", reportedVersion: "0.4.0-alpha.3", scenarios: [{ scenario: "launch", status: "failed", exitCode: 1 }] }], qualified: false };
		refuse(failed, "qualification failed");
		refuse([...all(), all()[0]!], "repeated qualification native-aot win-x64");
		refuse([...all(), { ...all()[0]!, runnerPlatform: "freebsd-x64" }], "unexpected qualification");
		refuse(all().map((q, i) => (i === 0 ? { ...q, sha256: "f".repeat(64) } : q)), "launched bytes");
		refuse(all().map((q, i) => (i === 0 ? { ...q, artifact: "other.zip" } : q)), "launched other.zip");
		refuse(all().map((q, i) => (i === 0 ? { ...q, release: "0.4.0-alpha.3" } : q)), "is of release 0.4.0-alpha.3");
		refuse(all(), "does not name", "v0.4.0-alpha.5");
		refuse(all(), "commit is unknown", "v0.4.0-alpha.4", "unknown");
	});
});

describe("publication gate", () => {
	const publishable: CliReleaseConfig = { ...config, source: { ...config.source, candidate: undefined } };
	const released = "## [Unreleased]\n\n### Added\n\n## [0.4.0-alpha.4] - 2026-11-10\n\n- Shipped.\n";
	const unreleased = "## [Unreleased]\n\n### Added\n\n- The MCK dispatch.\n\n## [0.4.0-alpha.4] - 2026-11-10\n";

	test("only a non-candidate pin that is the source's own release tag commit, with nothing unreleased, publishes", () => {
		expect(publicationBlockers(publishable, "0.4.0-alpha.4", released, config.source.commit, [])).toEqual([]);
		expect(unreleasedEntries(released)).toEqual([]);
		expect(unreleasedEntries(unreleased)).toEqual(["- The MCK dispatch."]);
	});

	test("the candidate marker, unreleased source changes, or a source tag elsewhere each block publication", () => {
		expect(publicationBlockers(config, "0.4.0-alpha.4", released, config.source.commit, []).join()).toContain("marked candidate");
		expect(publicationBlockers(publishable, "0.4.0-alpha.4", unreleased, config.source.commit, []).join()).toContain("1 unreleased entry");
		expect(publicationBlockers(publishable, "0.4.0-alpha.4", released, undefined, []).join()).toContain("has no tag v0.4.0-alpha.4");
		// The source's v0.4.0-alpha.4 is bec7df3; publishing the pinned 8c15df5 under that version would ship other bytes.
		expect(publicationBlockers(publishable, "0.4.0-alpha.4", released, "bec7df31eb813396e0e119c557e0a319adbe1ebb", []).join()).toContain("is not the source's release 0.4.0-alpha.4");
	});

	test("the pinned source today is blocked on every count", () => {
		const blockers = publicationBlockers(config, changelogReleaseVersion(read(`${config.source.submodule}/CHANGELOG.md`)), read(`${config.source.submodule}/CHANGELOG.md`), "bec7df31eb813396e0e119c557e0a319adbe1ebb", ["v0.4.0-alpha.4", "v0.4.0-beta.12"]);
		expect(blockers.join()).toContain("is not newer than");
		expect(blockers.length).toBeGreaterThanOrEqual(2);
		expect(blockers.join()).toContain("marked candidate");
	});
});

describe("the shared v* namespace", () => {
	// finos/morphir's v* tags so far: the Rust CLI's releases, up to v0.4.0-beta.12.
	const rust = ["v0.4.0-alpha.1", "v0.4.0-alpha.4", "v0.4.0-alpha.7", "v0.4.0-beta.11", "v0.4.0-beta.12", "extension/python/v0.4.0", "mill-plugins/v0.5.0-M05"];

	test("a version newer than every existing v* release can be published", () => {
		expect(versionCollisionBlockers(config, "0.4.0-beta.13", rust)).toEqual([]);
		expect(versionCollisionBlockers(config, "0.4.0", rust)).toEqual([]);
		// The release's own tag exists while it runs, and is left out.
		expect(versionCollisionBlockers(config, "0.4.0", [...rust, "v0.4.0"])).toEqual([]);
	});

	test("a version below the Rust CLI's releases, or one already published, is blocked", () => {
		expect(versionCollisionBlockers(config, "0.4.0-alpha.4", rust).join()).toContain("is not newer than");
		expect(versionCollisionBlockers(config, "0.4.0-beta.11", ["v0.4.0-beta.12", "v0.4.0-alpha.7"]).join()).toContain("is not newer than v0.4.0-beta.12");
		// Reusing an existing tag itself (v0.4.0-beta.12 again) is refused by the existing-release step and by the
		// binding check: that tag's commit is the Rust release, never the checkout of a new run.
		expect(versionCollisionBlockers(config, "0.3.9", rust).join()).toContain("existing tags");
		expect(publicationBlockers({ ...config, source: { ...config.source, candidate: undefined } }, "0.4.0-alpha.4", "## [Unreleased]\n", config.source.commit, rust).join()).toContain("is not newer than");
	});

	test("the workflow runs for v* tags and keeps a dispatch a dry run by default", () => {
		const push = release.on.push as { tags: string[] };
		expect(push.tags).toEqual(["v*"]);
		expect(read(".github/workflows/release.yml")).not.toContain("cli/v");
	});
});

describe("the run is bound to the tag, its commit and the pin", () => {
	const workflow = read(".github/workflows/release.yml");
	const good = { tag: "v0.4.0-alpha.4", githubRef: "refs/tags/v0.4.0-alpha.4", githubSha: "e".repeat(40), head: "e".repeat(40), tagCommit: "e".repeat(40), workflow };

	test("a run from the tag, checked out at the tag's commit, with the workflow's literal pin", () => {
		expect(workflowBindingProblems(config, good)).toEqual([]);
	});

	test("a moved tag cannot substitute another checkout for the immutable triggering commit", () => {
		expect(workflowBindingProblems(config, { ...good, githubSha: "f".repeat(40) }).join()).toContain("triggering commit");
		expect(workflowBindingProblems(config, { ...good, githubSha: undefined }).join()).toContain("triggering commit is unknown");
		expect(workflowBindingProblems(config, { ...good, githubSha: "unknown" }).join()).toContain("triggering commit is unknown");
	});

	test("a dispatch from another ref, another checkout, an unknown commit or another literal pin is refused", () => {
		expect(workflowBindingProblems(config, { ...good, githubRef: "refs/heads/main" }).join()).toContain("dispatch it from the tag");
		expect(workflowBindingProblems(config, { ...good, tagCommit: "f".repeat(40) }).join()).toContain("but the checkout is");
		expect(workflowBindingProblems(config, { ...good, head: "unknown", tagCommit: undefined }).join()).toContain("checked-out commit is unknown");
		const other = workflow.replaceAll(config.source.commit, "0".repeat(40));
		expect(workflowBindingProblems(config, { ...good, workflow: other }).join()).toContain("not the pinned");
	});

	test("a dry run may rehearse a release from a branch, bound to the branch's commit; a publication may not", () => {
		const branch = { ...good, githubRef: "refs/heads/feat/dotnet-cli-release-pin", tagCommit: undefined, dryRun: true };
		expect(workflowBindingProblems(config, branch)).toEqual([]);
		// A tag that already exists elsewhere does not matter to a rehearsal from a branch.
		expect(workflowBindingProblems(config, { ...branch, tagCommit: "f".repeat(40) })).toEqual([]);
		expect(workflowBindingProblems(config, { ...branch, dryRun: false }).join()).toContain("dispatch it from the tag");
		expect(workflowBindingProblems(config, { ...branch, githubSha: "f".repeat(40) }).join()).toContain("triggering commit");
		expect(workflowBindingProblems(config, { ...branch, githubRef: "refs/pull/1/merge" }).join()).toContain("dispatch it from the tag");
		const other = workflow.replaceAll(config.source.commit, "0".repeat(40));
		expect(workflowBindingProblems(config, { ...branch, workflow: other }).join()).toContain("not the pinned");
		// From a tag, a dry run is bound to the tag exactly as a publication is.
		expect(workflowBindingProblems(config, { ...good, dryRun: true, tagCommit: "f".repeat(40) }).join()).toContain("but the checkout is");
	});

	test("a branch rehearsal never shares a concurrency group with the tag's release, and nothing is cancelled", () => {
		const concurrency = (release as Workflow & { concurrency?: { group?: string; "cancel-in-progress"?: boolean } }).concurrency;
		// The ref is part of the group: a tag push and a dispatch from the tag share refs/tags/<tag>, so real releases of
		// one tag still queue one at a time, while a rehearsal from a branch queues in a group of its own and cannot
		// replace a pending release of that tag.
		expect(concurrency?.group).toBe("${{ github.workflow }}-${{ github.ref }}-${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}");
		expect(concurrency?.["cancel-in-progress"]).toBe(false);
	});

	test("release-info checks out the tag, or the triggering commit of a branch dry run, and knows whether the run is dry", () => {
		const info = release.jobs["release-info"]!;
		const checkout = info.steps.find(step => step.uses?.startsWith("actions/checkout@"));
		expect(checkout?.with?.ref).toBe("${{ startsWith(github.ref, 'refs/tags/') && env.RELEASE_TAG || github.sha }}");
		const step = info.steps.find(s => s.id === "release");
		expect(step?.run).toContain("tools/cli-release.ts release-info");
		expect(read(".github/workflows/release.yml")).toContain("DRY_RUN: ${{ github.event_name == 'workflow_dispatch' && inputs.dry-run && 'true' || 'false' }}");
	});

	test("an artifact is bound to the pin by the pack origin its build recorded", () => {
		const launch: LaunchMetadata = { release: "0.4.0-alpha.4", deployment: "native-aot", platform: "linux-x64", artifact: "a.tar.gz", sha256: "1".repeat(64), launchPath: "morphir", layout: "single-file" };
		expect(buildOriginProblems(config, launch, contentsOf(launch))).toEqual([]);
		expect(buildOriginProblems(config, launch, undefined).join()).toContain("source commit is unknown");
		expect(buildOriginProblems(config, launch, contentsOf(launch, { commit: "bec7df31eb813396e0e119c557e0a319adbe1ebb", workingTreeClean: true })).join()).toContain("not the pinned");
		expect(buildOriginProblems(config, launch, contentsOf(launch, { commit: config.source.commit, workingTreeClean: false })).join()).toContain("uncommitted changes");
		expect(buildOriginProblems(config, launch, { ...contentsOf(launch), sha256: "2".repeat(64) }).join()).toContain("build contents sha256");
	});

	test("release creation needs a tag push or an explicit non-dry dispatch, and a publishable pin", () => {
		const dispatch = release.on.workflow_dispatch as { inputs: Record<string, { default?: unknown; type?: string }> };
		expect(dispatch.inputs["dry-run"]).toMatchObject({ type: "boolean", default: true });
		const publish = release.jobs["publish-release"]!;
		const create = publish.steps.find(step => step.name === "Create the release");
		expect(create?.if).toBe("env.DRY_RUN != 'true' && needs.release-info.outputs.publishable == 'true'");
		const manifestStep = publish.steps.find(step => step.name === "Write the release manifest");
		expect(manifestStep?.run).toContain('--commit "$COMMIT"');
		expect(manifestStep?.run).toContain("DRY=(--dry-run)");
		const evidence = publish.steps.find(step => step.name === "Upload the release evidence");
		expect(evidence?.if).toBe("always()");
		for (const job of ["pack-tool", "qualify-platform", "publish-release"].filter(name => release.jobs[name] !== undefined)) {
			const checkout = release.jobs[job]!.steps.find(step => step.uses?.startsWith("actions/checkout@"));
			expect(checkout?.with?.ref).toBe("${{ needs.release-info.outputs.commit }}");
		}
	});
});
describe("legacy release names", () => {
	test("future legacy names alias the Native AOT executable on the platforms that shipped them", () => {
		expect(config.legacyAliases.of).toBe("native-aot");
		const pinned = legacyPlatforms(read(`${config.source.submodule}/build/Helpers/ReleaseProfiles.cs`));
		expect(pinned).toEqual(["win-x64", "win-arm64", "osx-arm64", "linux-x64", "linux-arm64"]);
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
	for (const rid of legacyRids) {
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
	expect(recorded).toHaveLength(legacyRids.length * 2);
	expect(recorded.find(a => a.asset === "morphir-win-x64.exe")?.aliasOf).toBe("morphir-dotnet-1.0.0-native-aot-win-x64.tar.gz");
});
describe("reported version", () => {
	const pin = config.source.commit;
	test("the release from the launch metadata, alone or with build metadata that prefixes the pinned commit", () => {
		expect(versionReported("0.4.0-alpha.4\n", "0.4.0-alpha.4", pin)).toBe(true);
		expect(versionReported(`0.4.0-alpha.4+${pin}\n`, "0.4.0-alpha.4", pin)).toBe(true);
		expect(versionReported(`0.4.0-alpha.4+${pin.slice(0, 7)}`, "0.4.0-alpha.4", pin)).toBe(true);
		// Build metadata naming another commit, too short a prefix or anything but hex fails: wrong provenance.
		expect(versionReported("0.4.0-alpha.4+7c26348", "0.4.0-alpha.4", pin)).toBe(false);
		expect(versionReported(`0.4.0-alpha.4+${pin.slice(0, 6)}`, "0.4.0-alpha.4", pin)).toBe(false);
		expect(versionReported("0.4.0-alpha.4+build.1", "0.4.0-alpha.4", pin)).toBe(false);
	});

	test("another release, an empty suffix or other output is refused", () => {
		expect(versionReported("0.4.0-alpha.3+8c15df5", "0.4.0-alpha.4", pin)).toBe(false);
		expect(versionReported("0.4.0-alpha.4.1", "0.4.0-alpha.4", pin)).toBe(false);
		expect(versionReported("0.4.0-alpha.4+", "0.4.0-alpha.4", pin)).toBe(false);
		expect(versionReported("morphir 0.4.0-alpha.4", "0.4.0-alpha.4", pin)).toBe(false);
		expect(versionReported("0.4.0-alpha.4\nextra", "0.4.0-alpha.4", pin)).toBe(false);
		expect(versionReported("", "0.4.0-alpha.4", pin)).toBe(false);
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
				writeFileSync(path.join(dir, `${artifact}.build-contents.json`), JSON.stringify(contentsOf(launch)));
				launches.push(launch);
			}
		}
		const qualificationDir = path.join(assets, "cli-qualification-all");
		mkdirSync(qualificationDir);
		for (const d of config.deployments) for (const p of config.platforms) {
			const launch = launches.find(l => l.deployment === d.id && l.platform === (d.portable ? "any" : p.rid))!;
			writeFileSync(path.join(qualificationDir, `${d.id}-${p.rid}.qualification.json`), JSON.stringify(passingQualification(launch, p.rid)));
		}
		const kit = path.join(work, "kit.json");
		writeFileSync(kit, JSON.stringify({ revision: "a".repeat(40), modified: false, algorithm: "mck-file-map-sha256/1", corpusHash: `sha256-${"b".repeat(64)}`, errors: 0 }));
		const tool = path.join(root, "tools/cli-release.ts");
		const runTool = (args: string[], cwd: string) => Bun.spawnSync(["bun", "run", tool, ...args], { cwd, stdout: "pipe", stderr: "pipe", windowsHide: true });
		const head = gitCommit(work);

		// Every path is relative to `work`, and every command runs from there.
		const legacy = runTool(["legacy-aliases", "--assets", "assets", "--version", "1.0.0", "--out", "legacy"], work);
		expect(legacy.exitCode, legacy.stderr.toString()).toBe(0);
		expect(readFileSync(path.join(work, "legacy/morphir-win-x64.exe"), "utf8")).toContain("echo 1.0.0+abc1234");

		const inputs = { tag: "v1.0.0", version: "1.0.0", assets: "assets", kitStatus: "kit.json", legacy: "legacy/legacy-aliases.json", commit: head, changelog: "## [Unreleased]\n\n## [1.0.0] - 2026-11-10\n", sourceTagCommit: config.source.commit, existingTags: ["v0.4.0-beta.12", "v0.4.0-alpha.4", "extension/python/v0.4.0"] };
		// The candidate pin: a dry run validates everything and writes the evidence and the list it would attach...
		const dry = prepareRelease(config, work, { ...inputs, out: "dry", dryRun: true });
		const dryManifest = JSON.parse(readFileSync(path.join(work, "dry/release-manifest.json"), "utf8"));
		expect(dryManifest.publication).toEqual({ dryRun: true, publishable: false, blockers: [expect.stringContaining("marked candidate")] });
		expect(readFileSync(path.join(work, "dry/dry-run-assets.txt"), "utf8").trim().split("\n")).toEqual(dry);
		expect(existsSync(path.join(work, "dry/release-assets.txt"))).toBe(false);
		// ...and a publication refuses it, leaving no release asset list.
		expect(() => prepareRelease(config, work, { ...inputs, out: "refused", dryRun: false })).toThrow("publication refused");
		expect(existsSync(path.join(work, "refused/release-assets.txt"))).toBe(false);
		// A run bound to another commit than the checkout validates nothing.
		expect(() => prepareRelease(config, work, { ...inputs, out: "other", dryRun: true, commit: "d".repeat(40) })).toThrow("not the bound commit");

		// The same inputs publish once the pin is the source's released, non-candidate commit.
		const publishable = { ...config, source: { ...config.source, candidate: undefined } };
		const listed = prepareRelease(publishable, work, { ...inputs, out: "publish", dryRun: false });
		expect(readFileSync(path.join(work, "publish/release-assets.txt"), "utf8").trim().split("\n")).toEqual(listed);
		const names = listed.map(file => path.basename(file)).sort();
		expect(names).toHaveLength(launches.length + legacyRids.length * 2 + 1);
		for (const launch of launches) expect(names).toContain(launch.artifact);
		expect(names).toContain("morphir-linux-arm64-v1.0.0.tar.gz");
		expect(names).toContain("release-manifest.json");		for (const file of listed) expect(path.isAbsolute(file)).toBe(true);

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
		const realLaunch: LaunchMetadata = { release: Bun.version, deployment: "native-aot", platform: rid, artifact: archive, sha256: sha(path.join(real, archive)), launchPath: exe, layout: "single-file" };
		writeFileSync(path.join(real, `${archive}.build-launch.json`), JSON.stringify(realLaunch));
		writeFileSync(path.join(real, `${archive}.build-contents.json`), JSON.stringify(contentsOf(realLaunch)));
		runTool(["qualify", "--release-dir", "real", "--deployment", "native-aot", "--rid", rid, "--platform", rid, "--version", Bun.version, "--out", "q/native.json"], work);
		const result = JSON.parse(readFileSync(path.join(work, "q/native.json"), "utf8")) as Qualification;
		expect(result.invocations[0]?.reportedVersion).toBe(Bun.version);
		expect(result.invocations[0]?.scenarios.find(s => s.scenario === "launch")?.status).toBe("passed");
		expect(result.sha256).toBe(sha(path.join(real, archive)));	}, 180_000);

	test("a repeated or missing artifact fails instead of being merged or dropped", () => {
		const launch = (deployment: string, platform: string, artifact = `${deployment}-${platform}`): LaunchMetadata => ({ release: "1.0.0", deployment, platform, artifact, sha256: "0", launchPath: "morphir", layout: "folder" });
		const all = config.deployments.flatMap(d => (d.portable ? [launch(d.id, "any")] : config.platforms.map(p => launch(d.id, p.rid))));
		expect(expectedLaunches(config, all)).toHaveLength(all.length);
		expect(() => expectedLaunches(config, all.slice(1))).toThrow("no artifact for native-aot win-x64");
		expect(() => expectedLaunches(config, [...all, launch("native-aot", "win-x64", "other.zip")])).toThrow("2 artifacts for native-aot win-x64");
		expect(() => expectedLaunches(config, [...all, launch("native-aot", "freebsd-x64")])).toThrow("unexpected artifact");
	});
});
describe("nothing maintained runs the deleted CLI", () => {
	// Released Rust tags are re-qualified from their own tagged source, so that acceptance keeps naming the old
	// package; nothing else may.
	const historical = new Set([".github/workflows/mck-release-acceptance.yml", "tools/mck-release-acceptance.mjs", "tools/cli-release.test.ts"]);
	const walk = (dir: string): string[] =>
		readdirSync(path.join(root, dir)).flatMap(name => {
			const relative = `${dir}/${name}`;
			return statSync(path.join(root, relative)).isDirectory() ? walk(relative) : [relative];
		});
	const maintained = () =>
		[".config/mise/config.toml", ...walk(".config/mise/tasks"), ...walk(".github/workflows"), ...walk(".github/actions"), ...walk("tools").filter(f => !f.includes("/node_modules/"))]
			.filter(file => /\.(toml|py|ts|mjs|yml|yaml|sh)$/.test(file) || file.startsWith(".config/mise/tasks/"))
			.filter(file => !historical.has(file));
	const deletedCli = [
		/(?:^|[\s"'`,[(])(?:-p|--package)["'`]?\s*,?\s*["'`]?morphir(?![-\w])/m,
		/target[\\/](?:debug|release)[\\/]morphir(?![-\w.])/,
		/CARGO_BIN_EXE_morphir(?![-\w])/,
		/crates\/morphir\//,
	];

	test("tasks, the scripts they call, workflows, actions and tools", () => {
		const offenders = maintained().flatMap(file => {
			const text = readFileSync(path.join(root, file), "utf8");
			return deletedCli.filter(pattern => pattern.test(text)).map(pattern => `${file}: ${pattern}`);
		});
		expect(offenders).toEqual([]);
	});

	test("the guard sees a Python argument list across lines", () => {
		expect(deletedCli[0]!.test('[\n  "cargo", "run",\n  "--package",\n  "morphir",\n  "--example", "x"]')).toBe(true);
		expect(deletedCli[0]!.test('"--package", "morphir-dev-tools"')).toBe(false);
	});
});
/** A stored (uncompressed) zip, enough for a NuGet package or a Windows release archive in a test. */
function storedZip(entries: [string, Uint8Array][]): Buffer {
	const local: Buffer[] = [];
	const central: Buffer[] = [];
	let offset = 0;
	for (const [name, bytes] of entries) {
		const data = Buffer.from(bytes);
		const fileName = Buffer.from(name);
		const crc = crc32(data);
		const header = Buffer.alloc(30);
		header.writeUInt32LE(0x04034b50, 0);
		header.writeUInt16LE(20, 4);
		header.writeUInt32LE(crc, 14);
		header.writeUInt32LE(data.length, 18);
		header.writeUInt32LE(data.length, 22);
		header.writeUInt16LE(fileName.length, 26);
		local.push(header, fileName, data);
		const entry = Buffer.alloc(46);
		entry.writeUInt32LE(0x02014b50, 0);
		entry.writeUInt16LE(20, 4);
		entry.writeUInt16LE(20, 6);
		entry.writeUInt32LE(crc, 16);
		entry.writeUInt32LE(data.length, 20);
		entry.writeUInt32LE(data.length, 24);
		entry.writeUInt16LE(fileName.length, 28);
		entry.writeUInt32LE((0o100755 * 0x10000) >>> 0, 38);
		entry.writeUInt32LE(offset, 42);
		central.push(entry, fileName);
		offset += 30 + fileName.length + data.length;
	}
	const directory = Buffer.concat(central);
	const end = Buffer.alloc(22);
	end.writeUInt32LE(0x06054b50, 0);
	end.writeUInt16LE(entries.length, 8);
	end.writeUInt16LE(entries.length, 10);
	end.writeUInt32LE(directory.length, 12);
	end.writeUInt32LE(offset, 16);
	return Buffer.concat([...local, directory, end]);
}

/** A managed assembly to stand in for the tool's entry point: the SDK's own dotnet.dll, when an SDK is installed. */
function sdkAssembly(): string | undefined {
	const listed = Bun.spawnSync(["dotnet", "--list-sdks"], { stdout: "pipe", stderr: "pipe", windowsHide: true });
	if (listed.exitCode !== 0) return undefined;
	const line = listed.stdout.toString().trim().split(/\r?\n/).filter(l => l.trim().length > 0).at(-1);
	const match = line === undefined ? null : /^(\S+) \[(.+)\]$/.exec(line.trim());
	const dll = match === null ? undefined : path.join(match[2]!, match[1]!, "dotnet.dll");
	return dll !== undefined && Bun.file(dll).size > 0 ? dll : undefined;
}

describe("the tool package installs through the source's helper, and only its own bytes", () => {
	const assembly = sdkAssembly();
	const pwsh = Bun.spawnSync(["pwsh", "-NoLogo", "-NoProfile", "-Command", "$PSVersionTable.PSVersion.Major"], { stdout: "pipe", stderr: "ignore", windowsHide: true });
	const pwshAvailable = pwsh.exitCode === 0 && Number(pwsh.stdout.toString().trim()) >= 7;
	const helper = installHelperPath(root, config);
	const toolPackage = (marker: string) =>
		storedZip([
			["Morphir.Tool.nuspec", Buffer.from(`<?xml version="1.0"?><package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd"><metadata><id>Morphir.Tool</id><version>9.9.9-isolation</version><authors>test</authors><description>${marker}</description><packageTypes><packageType name="DotnetTool" /></packageTypes></metadata></package>`)],
			["tools/net10.0/any/DotnetToolSettings.xml", Buffer.from('<?xml version="1.0" encoding="utf-8"?><DotNetCliTool Version="1"><Commands><Command Name="dotnet-morphir" EntryPoint="dotnet-morphir.dll" Runner="dotnet" /></Commands></DotNetCliTool>')],
			["tools/net10.0/any/dotnet-morphir.dll", Buffer.concat([readFileSync(assembly ?? process.execPath), Buffer.from(marker)])],
		]);
	const sha = (file: string) => new Bun.CryptoHasher("sha256").update(readFileSync(file)).digest("hex");

	test("the pinned source carries the helper, and the command runs it in each mode with new folders and a result file", () => {
		expect(existsSync(helper)).toBe(true);
		const tool = helperCommand(helper, "pkg/a.nupkg", "q/tool", "q/nuget", "tool-path", "q/r.json");
		expect(tool.slice(0, 6)).toEqual(["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File", helper]);
		expect(tool).not.toContain("-Local");
		for (const [flag, value] of [["-Package", "pkg/a.nupkg"], ["-ToolPath", "q/tool"], ["-WorkDir", "q/nuget"], ["-ResultFile", "q/r.json"]] as const) {
			expect(tool[tool.indexOf(flag) + 1]).toBe(path.resolve(value));
		}
		expect(helperCommand(helper, "a.nupkg", "t", "w", "local", "r.json")).toContain("-Local");
	});

	// Runs the real helper against a same-id, same-version package in the working directory's NuGet configuration
	// and in a warm packages folder. Needs PowerShell 7 and a .NET SDK, which every release runner has.
	test.skipIf(assembly === undefined || !pwshAvailable)("a conflicting feed and a warm cache never win, in either mode, and a tampered copy is refused", () => {
		const work = mkdtempSync(path.join(os.tmpdir(), "cli-helper-isolation-"));
		const produced = path.join(work, "produced", "Morphir.Tool.9.9.9-isolation.nupkg");
		const external = path.join(work, "external", "Morphir.Tool.9.9.9-isolation.nupkg");
		mkdirSync(path.dirname(produced), { recursive: true });
		mkdirSync(path.dirname(external), { recursive: true });
		writeFileSync(produced, toolPackage("PRODUCED"));
		writeFileSync(external, toolPackage("EXTERNAL"));
		const qualifyWork = path.join(work, "qualify");
		mkdirSync(qualifyWork);
		writeFileSync(path.join(qualifyWork, "nuget.config"), `<?xml version="1.0" encoding="utf-8"?><configuration><packageSources><add key="external" value="${path.dirname(external)}" /></packageSources></configuration>`);
		const warm = path.join(work, "warm-packages");
		const seed = path.join(work, "seed");
		mkdirSync(seed);
		writeFileSync(path.join(seed, "nuget.config"), `<?xml version="1.0" encoding="utf-8"?><configuration><packageSources><clear /><add key="external" value="${path.dirname(external)}" /></packageSources></configuration>`);
		const seedEnv = { ...process.env, NUGET_PACKAGES: warm, DOTNET_NOLOGO: "1", DOTNET_CLI_TELEMETRY_OPTOUT: "1" };
		expect(Bun.spawnSync(["dotnet", "new", "tool-manifest"], { cwd: seed, env: seedEnv, windowsHide: true }).exitCode).toBe(0);
		expect(Bun.spawnSync(["dotnet", "tool", "install", "Morphir.Tool", "--version", "9.9.9-isolation", "--local"], { cwd: seed, env: seedEnv, windowsHide: true }).exitCode).toBe(0);

		const saved = process.env.NUGET_PACKAGES;
		process.env.NUGET_PACKAGES = warm;
		try {
			const { steps, evidence } = helperToolInstall(root, config, produced, sha(produced), qualifyWork);
			expect(evidence.map(e => e.mode)).toEqual(["tool-path", "local"]);
			for (const { result } of evidence) {
				expect(result.package.sha256).toBe(sha(produced));
				expect(result.caches.packagesFolder).not.toBe(warm);
				for (const copy of result.stored) {
					expect(sha(copy.path)).toBe(sha(produced));
					expect(sha(copy.path)).not.toBe(sha(external));
				}
			}
			expect(steps.map(step => step.invocation)).toEqual(["dotnet-morphir", "dotnet morphir"]);
			expect(steps[1]).toMatchObject({ command: ["dotnet", "morphir"], cwd: evidence[1]!.result.toolPath });

			// The parent's own hashing refuses a copy that changes after the helper checked it, in either mode.
			for (const { result, mode } of evidence) {
				writeFileSync(result.stored[0]!.path, readFileSync(external));
				expect(helperResultProblems(result, mode, sha(produced)).join()).toContain("parent's own hashing");
			}
		} finally {
			if (saved === undefined) delete process.env.NUGET_PACKAGES;
			else process.env.NUGET_PACKAGES = saved;
		}
	}, 600_000);

	test("a result of another mode, another package, relative paths or a shell-like invocation is refused", () => {
		const work = mkdtempSync(path.join(os.tmpdir(), "cli-helper-result-"));
		const store = path.join(work, "tool", ".store", "morphir.tool", "1.0.0", "morphir.tool", "1.0.0");
		mkdirSync(store, { recursive: true });
		const copy = path.join(store, "morphir.tool.1.0.0.nupkg");
		writeFileSync(copy, "package");
		const command = path.join(work, "tool", process.platform === "win32" ? "dotnet-morphir.exe" : "dotnet-morphir");
		writeFileSync(command, "shim");
		const good: HelperResult = {
			mode: "tool-path",
			package: { id: "Morphir.Tool", version: "1.0.0", command: "dotnet-morphir", path: copy, sha256: sha(copy) },
			caches: { packagesFolder: path.join(work, "nuget", "packages"), httpCache: path.join(work, "nuget", "http-cache"), pluginsCache: path.join(work, "nuget", "plugins-cache"), cliHome: null },
			toolPath: path.join(work, "tool"),
			packageFolder: store,
			stored: [{ path: copy, sha256: sha(copy) }],
			invocation: { file: command, arguments: [], workingDirectory: null, environment: {} },
		};
		expect(helperResultProblems(good, "tool-path", sha(copy))).toEqual([]);
		expect(helperResultProblems(good, "local", sha(copy)).join()).toContain("not local");
		expect(helperResultProblems(good, "tool-path", "0".repeat(64)).join()).toContain("not the artifact's");
		expect(helperResultProblems({ ...good, toolPath: "tool" }, "tool-path", sha(copy)).join()).toContain("not absolute");
		expect(helperResultProblems({ ...good, stored: [] }, "tool-path", sha(copy)).join()).toContain("no stored package");
		expect(helperResultProblems({ ...good, invocation: { ...good.invocation, arguments: "--version" as unknown as string[] } }, "tool-path", sha(copy)).join()).toContain("argument array");
		expect(helperResultProblems({ ...good, mode: "local", invocation: { file: path.join(store, "dotnet-morphir.dll"), arguments: [], workingDirectory: work, environment: {} } }, "local", sha(copy)).join()).toContain("not `dotnet <command>`");
		const siblingCommand = path.join(work, "tool-sibling", path.basename(command));
		mkdirSync(path.dirname(siblingCommand));
		writeFileSync(siblingCommand, "another shim");
		expect(helperResultProblems({ ...good, invocation: { ...good.invocation, file: siblingCommand } }, "tool-path", sha(copy)).join()).toContain("not the installed command");
		const local: HelperResult = {
			...good,
			mode: "local",
			caches: { ...good.caches, packagesFolder: path.join(work, "tool", ".store"), cliHome: path.join(work, "cli-home") },
			invocation: {
				file: "dotnet", arguments: ["morphir"], workingDirectory: good.toolPath,
				environment: { NUGET_PACKAGES: path.join(work, "tool", ".store"), DOTNET_CLI_HOME: path.join(work, "cli-home") },
			},
		};
		expect(helperResultProblems(local, "local", sha(copy))).toEqual([]);
		expect(helperResultProblems({ ...local, invocation: { ...local.invocation, arguments: ["other-tool"] } }, "local", sha(copy)).join()).toContain("not `dotnet <command>`");
		expect(helperResultProblems({ ...local, invocation: { ...local.invocation, workingDirectory: work } }, "local", sha(copy)).join()).toContain("not `dotnet <command>`");
		expect(helperResultProblems({ ...local, invocation: { ...local.invocation, environment: { ...local.invocation.environment, NUGET_PACKAGES: work } } }, "local", sha(copy)).join()).toContain("isolated caches");
		expect(helperResultProblems({ ...local, invocation: { ...local.invocation, environment: { ...local.invocation.environment, DOTNET_CLI_HOME: work } } }, "local", sha(copy)).join()).toContain("isolated caches");
	});
});
describe("real zip archives", () => {
	const unzipAvailable = process.platform === "win32" || Bun.spawnSync(["unzip", "-v"], { stdout: "ignore", stderr: "ignore" }).exitCode === 0;
	const sha = (file: string) => new Bun.CryptoHasher("sha256").update(readFileSync(file)).digest("hex");

	// Runs where this machine has the reader extractCommand picks: Windows' own tar.exe, or unzip elsewhere. A
	// Linux or macOS runner without unzip skips it; the release runners have it.
	test.skipIf(!unzipAvailable)("extractCommand reads a real zip on this platform, from relative paths", () => {
		const work = mkdtempSync(path.join(os.tmpdir(), "cli-zip-"));
		writeFileSync(path.join(work, "a.zip"), storedZip([["morphir.exe", Buffer.from("zip executable")], ["lib/b.dll", Buffer.from("library")]]));
		mkdirSync(path.join(work, "out"));
		const command = extractCommand(path.join(work, "a.zip"), path.join(work, "out"));
		const result = Bun.spawnSync(command, { cwd: os.tmpdir(), stderr: "pipe", windowsHide: true });
		expect(result.exitCode, result.stderr.toString()).toBe(0);
		expect(readFileSync(path.join(work, "out/morphir.exe"), "utf8")).toBe("zip executable");
		expect(readFileSync(path.join(work, "out/lib/b.dll"), "utf8")).toBe("library");
	});

	test.skipIf(!unzipAvailable)("legacy-aliases takes the Windows executable out of its zip archive", () => {
		const work = mkdtempSync(path.join(os.tmpdir(), "cli-legacy-zip-"));
		const assets = path.join(work, "assets");
		mkdirSync(assets);
		for (const rid of legacyRids) {
			const exe = rid.startsWith("win-") ? "morphir.exe" : "morphir";
			const artifact = `morphir-dotnet-1.0.0-native-aot-${rid}.${rid.startsWith("win-") ? "zip" : "tar.gz"}`;
			if (rid.startsWith("win-")) writeFileSync(path.join(assets, artifact), storedZip([[exe, Buffer.from(`native ${rid}`)]]));
			else {
				const folder = path.join(work, `publish-${rid}`);
				mkdirSync(folder);
				writeFileSync(path.join(folder, exe), `native ${rid}`);
				expect(Bun.spawnSync(["tar", "-czf", path.join(assets, artifact), "-C", folder, exe], { windowsHide: true }).exitCode).toBe(0);
			}
			const launch: LaunchMetadata = { release: "1.0.0", deployment: "native-aot", platform: rid, artifact, sha256: sha(path.join(assets, artifact)), launchPath: exe, layout: "single-file" };
			writeFileSync(path.join(assets, `${artifact}.build-launch.json`), JSON.stringify(launch));
		}
		const result = Bun.spawnSync(["bun", "run", path.join(root, "tools/cli-release.ts"), "legacy-aliases", "--assets", "assets", "--version", "1.0.0", "--out", "legacy"], { cwd: work, stderr: "pipe", windowsHide: true });
		expect(result.exitCode, result.stderr.toString()).toBe(0);
		expect(readFileSync(path.join(work, "legacy/morphir-win-x64.exe"), "utf8")).toBe("native win-x64");
		const listing = Bun.spawnSync(["tar", "-tzf", path.join(work, "legacy/morphir-win-x64-v1.0.0.tar.gz")], { stdout: "pipe", windowsHide: true });
		expect(listing.stdout.toString().trim().split(/\r?\n/)).toContain("win-x64/morphir.exe");
	}, 60_000);
});
