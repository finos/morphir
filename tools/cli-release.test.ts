// The official CLI delivery: the source pin, the release workflow's routing and
// what qualification launches. See tools/cli-release.ts.
import { describe, expect, test } from "bun:test";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
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
	hostArchiveName,
	type MorphirupAsset,
	type MorphirupEvidence,
	type MorphirupQualification,
	morphirupAssetNames,
	morphirupAssets,
	morphirupEvidenceProblems,
	morphirupManagerNames,
	morphirupMatrix,
	parseChecksums,
	pinnedMorphirupPlatforms,
	pinnedToolchainPlatforms,
	qualifyMorphirup,
	SOURCE_WORKFLOWS,
	sourceInterfaceProblems,
	toolchainBundleBlockers,
	toolchainFamily,
	MIN_TOOLCHAIN_FAMILY,
	versionNamesPin,
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
/** The SHA-256 of a file, as lowercase hex. */
const fileSha = (file: string) => new Bun.CryptoHasher("sha256").update(readFileSync(file)).digest("hex");
/**
 * Writes the flattened morphirup assets of `version` into `dir`, as FlattenReleaseAssets and the two checksum targets
 * leave them: each host archive is a copy of its platform's self-contained offering (`hosts`), each
 * `morphir-toolchain-<rid>.json` a 0.1.0-preview.5 bundle whose URLs name the release `tag`, every other file holds
 * placeholder bytes, `morphirup-v<version>.sha256` lists the morphirup files and SHA256SUMS the toolchain files.
 * Returns the SHA-256 of each manager by platform.
 */
function writeMorphirupAssets(dir: string, version: string, hosts: Map<string, string>, tag = `v${version}`): Map<string, string> {
	mkdirSync(dir, { recursive: true });
	const names = morphirupAssetNames(config.morphirup, version).filter(n => n.role !== "checksums" && n.role !== "toolchain-checksums");
	const isBundle = (asset: string) => /^morphir-toolchain-.+\.json$/.test(asset);
	for (const n of names.filter(n => !isBundle(n.asset))) {
		if (n.role === "host-archive") copyFileSync(hosts.get(n.platform!)!, path.join(dir, n.asset));
		else writeFileSync(path.join(dir, n.asset), `placeholder ${n.asset}`);
	}
	for (const rid of config.morphirup.toolchainPlatforms) writeFileSync(path.join(dir, `morphir-toolchain-${rid}.json`), JSON.stringify(toolchainBundle(dir, version, rid, tag)));
	const line = (asset: string) => `${fileSha(path.join(dir, asset))}  ${asset}`;
	writeFileSync(path.join(dir, `morphirup-v${version}.sha256`), `${names.filter(n => ["manager", "manager-archive", "notices"].includes(n.role)).map(n => line(n.asset)).join("\n")}\n`);
	writeFileSync(path.join(dir, "SHA256SUMS"), `${names.filter(n => n.role === "host-archive" || n.role === "toolchain").map(n => line(n.asset)).join("\n")}\n`);
	return new Map(names.filter(n => n.role === "manager").map(n => [n.platform!, fileSha(path.join(dir, n.asset))]));
}
/** The role a bundle gives each of a toolchain platform's nine files. */
const bundleRole = (asset: string): string =>
	asset.startsWith("morphir-host-candidate-") ? "host-candidate"
	: asset.startsWith("morphir-dotnet-") ? "host-archive"
	: asset.startsWith("morphir-extensions-") ? "selection"
	: `${asset.includes("-frontend-") ? "frontend" : "backend"}-${asset.endsWith(".release.json") ? "release" : asset.endsWith(".manifest") ? "manifest" : "archive"}`;
/** A 0.1.0-preview.5 bundle of `rid` over the files in `dir`, with URLs of the release `tag`, as the source writes it. */
function toolchainBundle(dir: string, version: string, rid: string, tag: string, family = "0.1.0-preview.5", host = "finos/morphir") {
	const files = morphirupAssetNames(config.morphirup, version).filter(n => n.platform === rid && (n.role === "host-archive" || n.role === "toolchain") && !n.asset.startsWith("morphir-toolchain-"));
	return {
		$schema: `https://morphir.finos.org/schemas/local-toolchains/${family}/bundle.schema.json`,
		version,
		sourceCommit: config.source.commit,
		platform: rid,
		assets: files.map(f => ({ name: f.asset, role: bundleRole(f.asset), bytes: statSync(path.join(dir, f.asset)).size, sha256: fileSha(path.join(dir, f.asset)), url: `https://github.com/${host}/releases/download/${tag}/${f.asset}` })),
	};
}
/** A passing morphirup qualification of `rid`'s manager with the bytes `sha256`. */
const passingMorphirup = (rid: string, version: string, sha256: string): MorphirupQualification => ({
	kind: "morphirup", release: version, platform: rid, asset: morphirupManagerNames(rid, version).executable, sha256, reportedVersion: `${version}+${config.source.commit.slice(0, 7)}`,
	scenarios: [{ scenario: "launch", status: "passed", exitCode: 0 }, { scenario: "archive", status: "passed", exitCode: 0 }], qualified: true,
});
/** Morphirup evidence of `version` in which every manager passed, for manifests built in memory. */
function morphirupEvidence(version: string): MorphirupEvidence {
	const assets: MorphirupAsset[] = morphirupAssetNames(config.morphirup, version).map((n, i) => ({ ...n, sha256: i.toString(16).padStart(64, "0") }));
	return { assets, qualifications: config.morphirup.platforms.map(rid => passingMorphirup(rid, version, assets.find(a => a.role === "manager" && a.platform === rid)!.sha256)) };
}
/** `base` marked as a delivery candidate, for the tests of the candidate gate; the real pin is a source release. */
const asCandidate = (base: CliReleaseConfig): CliReleaseConfig => ({
	...base,
	source: { ...base.source, candidate: { pullRequest: "https://github.com/finos/morphir-dotnet/pull/637", reason: "Test fixture." } },
});
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
		// The self-contained offering of a toolchain platform is the toolchain job's host archive, not built here.
		expect(matrix).toHaveLength(3 * config.platforms.length + 1 - config.morphirup.toolchainPlatforms.length);
		expect(matrix).toContainEqual({ deployment: "dotnet-tool", rid: "", runner: "ubuntu-24.04" });
		expect(matrix).toContainEqual({ deployment: "native-aot", rid: "win-arm64", runner: "windows-11-arm" });
		expect(matrix).toContainEqual({ deployment: "self-contained", rid: "osx-x64", runner: "macos-15-intel" });
		for (const rid of config.morphirup.toolchainPlatforms) expect(matrix).not.toContainEqual(expect.objectContaining({ deployment: "self-contained", rid }));
		expect(read(".github/workflows/release.yml")).not.toContain("PackRelease");
	});

	test("each platform qualifies its own and the tool's artifacts, and uploads only the reports", () => {
		const qualifyJob = release.jobs["qualify-platform"];
		expect(qualifyJob?.needs).toEqual(["release-info", "offering", "morphirup"]);
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
			{ name: "morphirup-${{ matrix.rid }}", path: ".dev/out/cli-release/morphirup" },
		]);
		const morphirupDownload = qualifyJob!.steps.find(step => step.with?.name === "morphirup-${{ matrix.rid }}");
		expect(morphirupDownload?.if).toBe("matrix.morphirup");
		const morphirupQualify = qualifyJob!.steps.find(step => step.name === "Qualify morphirup");
		expect(morphirupQualify?.if).toBe("matrix.morphirup");
		expect(morphirupQualify?.run).toContain("bun run tools/cli-release.ts qualify-morphirup --dir .dev/out/cli-release/morphirup");
		expect(morphirupQualify?.run).toContain('".dev/out/cli-release/qualification/$RID.morphirup-qualification.json"');
		// upload-artifact leaves out hidden folders such as .dev unless told; the glob names only the reports.
		const upload = qualifyJob!.steps.find(step => step.uses?.startsWith("actions/upload-artifact@"));
		expect(upload?.with).toMatchObject({ path: ".dev/out/cli-release/qualification/*qualification.json", "include-hidden-files": true, "if-no-files-found": "error" });
		const setup = qualifyJob!.steps.find(step => step.uses?.startsWith("actions/setup-dotnet@"));
		expect(setup?.with?.["global-json-file"]).toBe("ecosystem/morphir-dotnet/global.json");
		expect(releaseMatrix(config)).toEqual({ include: config.platforms.map(p => ({ rid: p.rid, runner: p.runner, morphirup: config.morphirup.platforms.includes(p.rid) })) });
	});

	test("publishing needs every qualification, attaches the listed assets and never replaces a release", () => {
		const publish = release.jobs["publish-release"];
		expect(publish?.needs).toEqual(["release-info", "offering", "morphirup", "qualify-platform", "assemble-morphirup"]);
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

	test("a pin that release.yml cannot run at is marked a candidate; a candidate pin cannot publish", () => {
		// The marker may stay on a compatible pin, until its source tag exists and a dry run of it passes.
		const incompatible = sourceInterfaceProblems(root, config, read(".github/workflows/release.yml")).length > 0;
		if (incompatible) expect(config.source.candidate).toBeDefined();
		expect(releaseBlocker(asCandidate(config))).toContain("marked candidate");
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
		const manifest = releaseManifest(publishable, "v0.4.0-alpha.4", "0.4.0-alpha.4", commit, kit, launches, all(), [], undefined, morphirupEvidence("0.4.0-alpha.4"));
		expect(manifest.source).toEqual(publishable.source);
		expect(manifest.kit).toEqual(kit);
		expect(manifest.publication).toEqual({ dryRun: false, publishable: true, blockers: [] });
		const mac = manifest.qualification.find(q => q.deployment === "native-aot" && q.platform === "osx-arm64");
		expect(mac).toMatchObject({ qualified: true, pending: [] });
		expect(manifest.pendingTriage).toEqual([]);
		// A recorded pending triage stays visible in the manifest and its notes, and is never counted as qualified.
		const triaged = withPendingTriage(publishable);
		const visible = releaseManifest(triaged, "v0.4.0-alpha.4", "0.4.0-alpha.4", commit, kit, launches, allTriaged(), [], undefined, morphirupEvidence("0.4.0-alpha.4"));
		expect(visible.qualification.find(q => q.deployment === "native-aot" && q.platform === "osx-arm64")).toMatchObject({ qualified: false, pending: ["packaged-input"] });
		expect(visible.pendingTriage).toEqual(triaged.pendingTriage);
		const blocked = releaseManifest(config, "v0.4.0-alpha.4", "0.4.0-alpha.4", commit, kit, launches, all(), [], { dryRun: true, blockers: ["candidate"] }, morphirupEvidence("0.4.0-alpha.4"));
		expect(blocked.publication).toEqual({ dryRun: true, publishable: false, blockers: ["candidate"] });
	});

	test("a missing, failed, repeated, extra or mismatched qualification, or a mismatched tag or commit, is refused", () => {
		const refuse = (qualifications: Qualification[], expected: string, tag = "v0.4.0-alpha.4", at = commit) =>
			expect(() => releaseManifest(publishable, tag, "0.4.0-alpha.4", at, kit, launches, qualifications, [], undefined, morphirupEvidence("0.4.0-alpha.4"))).toThrow(expected);
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
		expect(publicationBlockers(asCandidate(config), "0.4.0-alpha.4", released, config.source.commit, []).join()).toContain("marked candidate");
		expect(publicationBlockers(publishable, "0.4.0-alpha.4", unreleased, config.source.commit, []).join()).toContain("1 unreleased entry");
		expect(publicationBlockers(publishable, "0.4.0-alpha.4", released, undefined, []).join()).toContain("has no tag v0.4.0-alpha.4");
		// The source's v0.4.0-alpha.4 is bec7df3; publishing the pinned 8c15df5 under that version would ship other bytes.
		expect(publicationBlockers(publishable, "0.4.0-alpha.4", released, "bec7df31eb813396e0e119c557e0a319adbe1ebb", []).join()).toContain("is not the source's release 0.4.0-alpha.4");
	});

	test("the pinned source is its own release: newer than every v* tag, nothing unreleased", () => {
		const changelog = read(`${config.source.submodule}/CHANGELOG.md`);
		const version = changelogReleaseVersion(changelog);
		expect(version).toBe("0.5.0-alpha.2");
		const tags = ["v0.4.0-alpha.4", "v0.4.0-alpha.7", "v0.4.0-beta.12"];
		const released = { ...config, source: { ...config.source, candidate: undefined } };
		// With the source's tag v<version> on the pinned commit, nothing blocks publication.
		expect(publicationBlockers(released, version, changelog, config.source.commit, tags)).toEqual([]);
		// A source tag on another commit still blocks, and so does a marked candidate.
		expect(publicationBlockers(released, version, changelog, "bec7df31eb813396e0e119c557e0a319adbe1ebb", tags).join()).toContain("not the pinned");
		expect(publicationBlockers(asCandidate(config), version, changelog, config.source.commit, tags).join()).toContain("marked candidate");
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
describe("morphirup and the setup toolchain", () => {
	const morphirupJob = release.jobs.morphirup as Job & { uses?: string; with?: Record<string, unknown> };

	test("are built by the source's own morphirup-build.yml at the pin, with the toolchain and its host offering", () => {
		expect(morphirupJob.uses).toBe(`finos/morphir-dotnet/.github/workflows/morphirup-build.yml@${config.source.commit}`);
		expect(morphirupJob.with).toEqual({
			repository: "finos/morphir-dotnet",
			ref: config.source.commit,
			rid: "${{ matrix.rid }}",
			os: "${{ matrix.runner }}",
			configuration: "Release",
			toolchain: true,
			"upload-host-offering": true,
			"retention-days": 7,
		});
		expect(morphirupJob.needs).toBe("release-info");
		expect(morphirupJob.strategy?.matrix).toBe("${{ fromJSON(needs.release-info.outputs.morphirup) }}");
		expect(morphirupMatrix(config).include).toEqual([
			{ rid: "linux-x64", runner: "ubuntu-24.04" },
			{ rid: "linux-arm64", runner: "ubuntu-24.04-arm" },
			{ rid: "win-x64", runner: "windows-2025" },
			{ rid: "win-arm64", runner: "windows-11-arm" },
			{ rid: "osx-arm64", runner: "macos-15" },
		]);
		expect(SOURCE_WORKFLOWS).toEqual(["cli-offering.yml", "morphirup-build.yml"]);
	});

	test("the platforms, the toolchain platforms and the setup journey are the pinned source's", () => {
		expect(config.morphirup.platforms).toEqual(pinnedMorphirupPlatforms(read(`${config.source.submodule}/build/Helpers/MorphirupRelease.cs`)));
		expect(config.morphirup.toolchainPlatforms).toEqual(pinnedToolchainPlatforms(read(`${config.source.submodule}/build/Helpers/ReleaseAssets.cs`)));
		const build = read(`${config.source.submodule}/.github/workflows/morphirup-build.yml`);
		expect(build).toContain(`--filter-test-list ${config.morphirup.setupJourney}`);
		// The source's own release passes toolchain: true; so does release.yml.
		expect(read(`${config.source.submodule}/.github/workflows/deployment.yml`)).toMatch(/uses: \.\/\.github\/workflows\/morphirup-build\.yml[\s\S]*?toolchain: true/);
		for (const rid of config.morphirup.platforms) expect(config.platforms.map(p => p.rid)).toContain(rid);
	});

	test("the asset names are exactly the finos/morphir-dotnet v0.5.0-alpha.1 release's, without its legacy CLI names", () => {
		// Read from the published finos/morphir-dotnet v0.5.0-alpha.1 release: every asset but morphir-<rid>[-v<v>.tar.gz].
		const published = [
			"SHA256SUMS",
			"morphir-dotnet-0.5.0-alpha.1-self-contained-osx-arm64.tar.gz", "morphir-dotnet-0.5.0-alpha.1-self-contained-win-arm64.zip", "morphir-dotnet-0.5.0-alpha.1-self-contained-win-x64.zip",
			"morphir-extensions-osx-arm64.json", "morphir-extensions-win-arm64.json", "morphir-extensions-win-x64.json",
			...["osx-arm64", "win-arm64", "win-x64"].flatMap(rid => ["backend", "frontend"].flatMap(role => [`morphir-fsharp-${role}-0.5.0-alpha.1-${rid}.manifest`, `morphir-fsharp-${role}-0.5.0-alpha.1-${rid}.release.json`, `morphir-fsharp-${role}-0.5.0-alpha.1-${rid}.${rid === "osx-arm64" ? "tar.gz" : "zip"}`])),
			"morphir-host-candidate-osx-arm64.json", "morphir-host-candidate-win-arm64.json", "morphir-host-candidate-win-x64.json",
			"morphir-toolchain-osx-arm64.json", "morphir-toolchain-win-arm64.json", "morphir-toolchain-win-x64.json",
			"morphirup-linux-arm64", "morphirup-linux-arm64-v0.5.0-alpha.1.tar.gz", "morphirup-linux-x64", "morphirup-linux-x64-v0.5.0-alpha.1.tar.gz",
			"morphirup-osx-arm64", "morphirup-osx-arm64-v0.5.0-alpha.1.tar.gz", "morphirup-v0.5.0-alpha.1-THIRD-PARTY-NOTICES.txt", "morphirup-v0.5.0-alpha.1.sha256",
			"morphirup-win-arm64-v0.5.0-alpha.1.tar.gz", "morphirup-win-arm64.exe", "morphirup-win-x64-v0.5.0-alpha.1.tar.gz", "morphirup-win-x64.exe",
		];
		expect(published).toHaveLength(43);
		expect(morphirupAssetNames(config.morphirup, "0.5.0-alpha.1").map(n => n.asset).sort()).toEqual([...published].sort());
		// A host archive is the self-contained offering's name on its platform, so the release attaches it once.
		for (const rid of config.morphirup.toolchainPlatforms) expect(published).toContain(hostArchiveName(rid, "0.5.0-alpha.1"));
		expect(morphirupManagerNames("win-arm64", "0.5.0-alpha.1")).toEqual({ executable: "morphirup-win-arm64.exe", tarball: "morphirup-win-arm64-v0.5.0-alpha.1.tar.gz", entry: "win-arm64/morphirup.exe" });
	});

	test("the flattened assets must be exactly the contract's, listed with their bytes, with host archives that are the offerings", () => {
		const work = mkdtempSync(path.join(os.tmpdir(), "cli-morphirup-assets-"));
		const hosts = new Map<string, string>();
		for (const rid of config.morphirup.toolchainPlatforms) {
			const file = path.join(work, `host-${rid}`);
			writeFileSync(file, `host ${rid}`);
			hosts.set(rid, file);
		}
		const offerings = new Map([...hosts].map(([rid, file]) => [rid, fileSha(file)]));
		const fresh = (name: string) => {
			const dir = path.join(work, name);
			writeMorphirupAssets(dir, "1.0.0", hosts);
			return dir;
		};
		const ok = morphirupAssets(config.morphirup, "1.0.0", fresh("ok"), offerings);
		expect(ok).toHaveLength(43);
		expect(ok.find(a => a.asset === "morphirup-win-x64.exe")).toMatchObject({ role: "manager", platform: "win-x64" });

		const extra = fresh("extra");
		writeFileSync(path.join(extra, "morphir-extensions-linux-x64.json"), "{}");
		expect(() => morphirupAssets(config.morphirup, "1.0.0", extra, offerings)).toThrow("unexpected morphirup asset morphir-extensions-linux-x64.json");
		const missing = fresh("missing");
		rmSync(path.join(missing, "morphir-toolchain-win-arm64.json"));
		expect(() => morphirupAssets(config.morphirup, "1.0.0", missing, offerings)).toThrow("missing morphirup asset morphir-toolchain-win-arm64.json");
		const changed = fresh("changed");
		writeFileSync(path.join(changed, "morphir-host-candidate-win-x64.json"), "other bytes");
		expect(() => morphirupAssets(config.morphirup, "1.0.0", changed, offerings)).toThrow("SHA256SUMS lists morphir-host-candidate-win-x64.json with SHA-256");
		const unlisted = fresh("unlisted");
		writeFileSync(path.join(unlisted, "morphirup-v1.0.0.sha256"), readFileSync(path.join(unlisted, "morphirup-v1.0.0.sha256"), "utf8").split("\n").filter(l => !l.endsWith("morphirup-linux-x64")).join("\n"));
		expect(() => morphirupAssets(config.morphirup, "1.0.0", unlisted, offerings)).toThrow("morphirup-v1.0.0.sha256 does not list morphirup-linux-x64");
		const otherHost = new Map(offerings);
		otherHost.set("win-x64", "f".repeat(64));
		expect(() => morphirupAssets(config.morphirup, "1.0.0", fresh("other-host"), otherHost)).toThrow("one name, two builds");
		expect(() => parseChecksums(`${"a".repeat(64)}  x\n${"b".repeat(64)}  x\n`)).toThrow("x is listed twice");
		expect(() => parseChecksums("not a checksum line\n")).toThrow("is not a sha256sum line");
	});

	test("--version must be the release with the full pinned commit; a bare version or another commit fails", () => {
		const pin = config.source.commit;
		expect(versionNamesPin(`0.5.0-alpha.2+${pin}\n`, "0.5.0-alpha.2", pin)).toBe(true);
		expect(versionNamesPin("0.5.0-alpha.2", "0.5.0-alpha.2", pin)).toBe(false);
		expect(versionNamesPin(`0.5.0-alpha.2+${pin.slice(0, 7)}`, "0.5.0-alpha.2", pin)).toBe(false);
		expect(versionNamesPin(`0.5.0-alpha.2+${"0".repeat(40)}`, "0.5.0-alpha.2", pin)).toBe(false);
		expect(versionNamesPin(`0.5.0-alpha.1+${pin}`, "0.5.0-alpha.2", pin)).toBe(false);
	});

	test("a manager qualifies when it reports the release and the pin and its archive holds the same bytes", () => {
		const rid = process.platform === "win32" ? "win-x64" : process.platform === "darwin" ? "osx-arm64" : "linux-x64";
		const names = morphirupManagerNames(rid, "1.0.0");
		// A real native executable that prints what a manager built from the pin prints, compiled by this test's Bun.
		const build = mkdtempSync(path.join(os.tmpdir(), "cli-morphirup-build-"));
		writeFileSync(path.join(build, "manager.ts"), `console.log(${JSON.stringify(`1.0.0+${config.source.commit}`)});\n`);
		const compiled = path.join(build, names.executable);
		const compile = Bun.spawnSync([process.execPath, "build", "--compile", path.join(build, "manager.ts"), "--outfile", compiled], { stdout: "pipe", stderr: "pipe", windowsHide: true });
		expect(compile.exitCode, compile.stderr.toString()).toBe(0);
		const make = (name: string, executable: string, tamper: boolean) => {
			const dir = mkdtempSync(path.join(os.tmpdir(), `cli-morphirup-${name}-`));
			copyFileSync(executable, path.join(dir, names.executable));
			const tree = path.join(dir, "tree");
			mkdirSync(path.join(tree, rid), { recursive: true });
			if (tamper) writeFileSync(path.join(tree, names.entry), "other bytes");
			else copyFileSync(executable, path.join(tree, names.entry));
			expect(Bun.spawnSync(["tar", "-czf", path.join(dir, names.tarball), "-C", tree, rid], { windowsHide: true }).exitCode).toBe(0);
			return dir;
		};
		const passed = qualifyMorphirup(config, make("ok", compiled, false), rid, "1.0.0");
		expect(passed).toMatchObject({ kind: "morphirup", platform: rid, asset: names.executable, reportedVersion: `1.0.0+${config.source.commit}`, qualified: true });
		expect(passed.scenarios.map(s => `${s.scenario}=${s.status}`)).toEqual(["launch=passed", "archive=passed"]);
		const tampered = qualifyMorphirup(config, make("tampered", compiled, true), rid, "1.0.0");
		expect(tampered.scenarios.find(s => s.scenario === "archive")?.status).toBe("failed");
		expect(tampered.qualified).toBe(false);
		// Bun itself prints a bare version: the release, but no commit, so it is not this release's manager.
		const bare = morphirupManagerNames(rid, Bun.version);
		const bareDir = mkdtempSync(path.join(os.tmpdir(), "cli-morphirup-bare-"));
		copyFileSync(process.execPath, path.join(bareDir, bare.executable));
		mkdirSync(path.join(bareDir, "tree", rid), { recursive: true });
		copyFileSync(process.execPath, path.join(bareDir, "tree", bare.entry));
		expect(Bun.spawnSync(["tar", "-czf", path.join(bareDir, bare.tarball), "-C", path.join(bareDir, "tree"), rid], { windowsHide: true }).exitCode).toBe(0);
		const unpinned = qualifyMorphirup(config, bareDir, rid, Bun.version);
		expect(unpinned.scenarios.map(s => `${s.scenario}=${s.status}`)).toEqual(["launch=failed", "archive=passed"]);
		expect(() => qualifyMorphirup(config, bareDir, "osx-x64", Bun.version)).toThrow("morphirup is not released for osx-x64");
	}, 180_000);

	test("a release needs one passing qualification of every manager, of the bytes it attaches", () => {
		const evidence = morphirupEvidence("1.0.0");
		expect(morphirupEvidenceProblems(config, "1.0.0", evidence)).toEqual([]);
		expect(morphirupEvidenceProblems(config, "1.0.0", undefined)).toEqual(["no morphirup assets or qualification"]);
		const without = { ...evidence, qualifications: evidence.qualifications.filter(q => q.platform !== "linux-arm64") };
		expect(morphirupEvidenceProblems(config, "1.0.0", without).join()).toContain("no qualification of morphirup on linux-arm64");
		const failed = { ...evidence, qualifications: evidence.qualifications.map(q => (q.platform === "win-x64" ? { ...q, qualified: false } : q)) };
		expect(morphirupEvidenceProblems(config, "1.0.0", failed).join()).toContain("morphirup qualification failed: win-x64");
		const other = { ...evidence, qualifications: evidence.qualifications.map(q => (q.platform === "osx-arm64" ? { ...q, sha256: "e".repeat(64) } : q)) };
		expect(morphirupEvidenceProblems(config, "1.0.0", other).join()).toContain("morphirup qualification on osx-arm64 launched bytes");
		const repeated = { ...evidence, qualifications: [...evidence.qualifications, evidence.qualifications[0]!] };
		expect(morphirupEvidenceProblems(config, "1.0.0", repeated).join()).toContain("repeated morphirup qualification");
		const stray = { ...evidence, qualifications: [...evidence.qualifications, { ...evidence.qualifications[0]!, platform: "osx-x64" }] };
		expect(morphirupEvidenceProblems(config, "1.0.0", stray).join()).toContain("unexpected morphirup qualification on osx-x64");
		expect(morphirupEvidenceProblems(config, "2.0.0", evidence).join()).toContain("is of release 1.0.0");
	});

	test("a read-only job assembles the assets with the source's own targets; only the two gh steps hold the token", () => {
		const assemble = release.jobs["assemble-morphirup"]! as Job & { env?: Record<string, string> };
		expect(assemble.needs).toEqual(["release-info", "morphirup"]);
		expect(assemble.permissions).toEqual({ contents: "read" });
		const assembly = runs(assemble);
		expect(assembly).toContain("cd ecosystem/morphir-dotnet");
		expect(assembly).toMatch(/\.\/build\.sh --target FlattenReleaseAssets MorphirupChecksums WindowsToolchainChecksums/);
		expect(assembly).toContain("(cd \"$dir\" && sha256sum -c SHA256SUMS)");
		expect(assembly).toContain('sha256sum -c "morphirup-v${VERSION}.sha256"');
		expect(assembly).not.toMatch(/sha256sum [^-]/);
		expect(assemble.steps.filter(s => s.uses?.startsWith("actions/download-artifact@")).map(s => s.with?.pattern)).toEqual(["morphirup-*", "windows-release-toolchain-*"]);
		expect(assemble.steps.find(s => s.uses?.startsWith("actions/setup-dotnet@"))?.with?.["global-json-file"]).toBe("ecosystem/morphir-dotnet/global.json");
		expect(assemble.steps.find(s => s.uses?.startsWith("actions/upload-artifact@"))?.with).toMatchObject({ name: "cli-morphirup-release-assets", "if-no-files-found": "error" });
		expect(JSON.stringify(assemble)).not.toContain("GH_TOKEN");
		expect(JSON.stringify(assemble)).not.toContain("github.token");

		const publish = release.jobs["publish-release"]! as Job & { env?: Record<string, string> };
		expect(publish.needs).toContain("assemble-morphirup");
		expect(publish.env?.GH_TOKEN).toBeUndefined();
		const tokened = publish.steps.filter(s => JSON.stringify(s).includes("GH_TOKEN"));
		expect(tokened.map(s => s.name)).toEqual(["Refuse a release that already exists", "Create the release"]);
		for (const step of tokened) expect((step as { env?: Record<string, string> }).env?.GH_TOKEN).toBe("${{ github.token }}");
		const downloads = publish.steps.filter(step => step.uses?.startsWith("actions/download-artifact@")).map(step => step.with?.pattern ?? step.with?.name);
		expect(downloads).toEqual(["morphir-dotnet-*", "cli-qualification-*", "cli-morphirup-release-assets"]);
		expect(runs(publish)).toContain("--morphirup .dev/out/cli-release/morphirup-assets");
		expect(runs(publish)).not.toContain("build.sh");
	});

	// Fails at the pin 318b1bfd (0.5.0-alpha.1), whose morphirup-build.yml predates the cross-repository inputs; it
	// passes once the pin is the 0.5.0-alpha.2 release commit, and .config/cli-release.json marks the pin a candidate
	// until then. GitHub refuses a run whose call passes an input the called workflow does not declare.
	test("every input release.yml passes to a source workflow is declared by that workflow at the pin", () => {
		expect(sourceInterfaceProblems(root, config, read(".github/workflows/release.yml")).filter(p => p.includes("does not declare"))).toEqual([]);
	});

	// Fails at the pin 318b1bfd for the same reason, until the pin moves.
	test("the pinned morphirup-build.yml uploads the host offering for exactly the toolchain platforms", () => {
		expect(sourceInterfaceProblems(root, config, read(".github/workflows/release.yml")).filter(p => !p.includes("does not declare"))).toEqual([]);
	});

	test("the interface check reads the pinned workflows' declared inputs and the host-offering upload", () => {
		const fake = mkdtempSync(path.join(os.tmpdir(), "cli-interface-"));
		const workflows = path.join(fake, config.source.submodule, ".github/workflows");
		mkdirSync(workflows, { recursive: true });
		const offering = "on:\n  workflow_call:\n    inputs:\n      repository: { type: string }\n      ref: { type: string }\n      deployment: { type: string }\n      rid: { type: string }\n      os: { type: string }\n      configuration: { type: string }\njobs: {}\n";
		const upload = (condition: string, files = "a.build-launch.json\n            a.build-contents.json") =>
			`on:\n  workflow_call:\n    inputs:\n      repository: { type: string }\n      ref: { type: string }\n      rid: { type: string }\n      os: { type: string }\n      configuration: { type: string }\n      toolchain: { type: boolean }\n      upload-host-offering: { type: boolean }\n      retention-days: { type: number }\njobs:\n  build:\n    steps:\n      - uses: actions/upload-artifact@v6\n        if: ${condition}\n        with:\n          name: morphir-dotnet-self-contained-\${{ inputs.rid }}\n          path: |\n            ${files}\n`;
		writeFileSync(path.join(workflows, "cli-offering.yml"), offering);
		const releaseText = read(".github/workflows/release.yml");
		writeFileSync(path.join(workflows, "morphirup-build.yml"), upload("inputs.upload-host-offering && (inputs.rid == 'win-x64' || inputs.rid == 'win-arm64' || (inputs.rid == 'osx-arm64' && inputs.toolchain))"));
		expect(sourceInterfaceProblems(fake, config, releaseText)).toEqual([]);
		// As the pinned source writes it: the condition on a describing step, the upload on that step's outcome.
		const referenced = upload("steps.host-offering.outcome == 'success'").replace("    steps:\n", "    steps:\n      - id: host-offering\n        if: inputs.upload-host-offering && (inputs.rid == 'win-x64' || inputs.rid == 'win-arm64' || (inputs.rid == 'osx-arm64' && inputs.toolchain))\n        run: echo\n");
		writeFileSync(path.join(workflows, "morphirup-build.yml"), referenced);
		expect(sourceInterfaceProblems(fake, config, releaseText)).toEqual([]);
		writeFileSync(path.join(workflows, "morphirup-build.yml"), upload("inputs.upload-host-offering && (inputs.rid == 'win-x64' || inputs.rid == 'osx-arm64')"));
		expect(sourceInterfaceProblems(fake, config, releaseText).join()).toContain("not exactly win-x64, win-arm64, osx-arm64");
		writeFileSync(path.join(workflows, "morphirup-build.yml"), upload("inputs.rid == 'win-x64' || inputs.rid == 'win-arm64' || inputs.rid == 'osx-arm64'"));
		expect(sourceInterfaceProblems(fake, config, releaseText).join()).toContain("without depending on upload-host-offering");
		writeFileSync(path.join(workflows, "morphirup-build.yml"), upload("inputs.upload-host-offering && (inputs.rid == 'win-x64' || inputs.rid == 'win-arm64' || inputs.rid == 'osx-arm64')", "a.zip"));
		expect(sourceInterfaceProblems(fake, config, releaseText).join()).toContain("carries no .build-launch.json");
		writeFileSync(path.join(workflows, "morphirup-build.yml"), "on:\n  workflow_call:\n    inputs:\n      rid: { type: string }\njobs: {}\n");
		const problems = sourceInterfaceProblems(fake, config, releaseText).join("\n");
		expect(problems).toContain("passes 'repository' to morphirup-build.yml");
		expect(problems).toContain("uploads morphir-dotnet-self-contained-<rid> 0 times");
	});

	test("a toolchain bundle must be of preview.5 or later and download every file from this release", () => {
		const work = mkdtempSync(path.join(os.tmpdir(), "cli-bundles-"));
		const hosts = new Map(config.morphirup.toolchainPlatforms.map(rid => {
			const file = path.join(work, `host-${rid}`);
			writeFileSync(file, `host ${rid}`);
			return [rid, file] as const;
		}));
		const dir = path.join(work, "assets");
		writeMorphirupAssets(dir, "1.0.0", hosts, "v1.0.0");
		const attached = new Map(readdirSync(dir).map(name => [name, fileSha(path.join(dir, name))]));
		expect(toolchainBundleBlockers(config, "v1.0.0", "1.0.0", dir, attached)).toEqual([]);
		expect(toolchainFamily("https://morphir.finos.org/schemas/local-toolchains/0.1.0-preview.5/bundle.schema.json")).toBe("0.1.0-preview.5");
		expect(MIN_TOOLCHAIN_FAMILY).toBe("0.1.0-preview.5");
		const rewrite = (rid: string, bundle: object) => writeFileSync(path.join(dir, `morphir-toolchain-${rid}.json`), JSON.stringify(bundle));
		// The bundles of the pin 318b1bfd: local-toolchains 0.1.0-preview.4, downloading from finos/morphir-dotnet.
		rewrite("win-arm64", toolchainBundle(dir, "1.0.0", "win-arm64", "v1.0.0", "0.1.0-preview.4", "finos/morphir-dotnet"));
		const old = toolchainBundleBlockers(config, "v1.0.0", "1.0.0", dir, attached).join("\n");
		expect(old).toContain("morphir-toolchain-win-arm64.json is of local-toolchains family 0.1.0-preview.4, not 0.1.0-preview.5 or later");
		expect(old).toContain("from https://github.com/finos/morphir-dotnet/releases/download/v1.0.0/");
		rewrite("win-arm64", toolchainBundle(dir, "1.0.0", "win-arm64", "v1.0.0"));
		// Another tag, a later family, a file that is not attached, other bytes, another commit.
		rewrite("osx-arm64", toolchainBundle(dir, "1.0.0", "osx-arm64", "v0.9.0"));
		expect(toolchainBundleBlockers(config, "v1.0.0", "1.0.0", dir, attached).join()).toContain("not https://github.com/finos/morphir/releases/download/v1.0.0/");
		rewrite("osx-arm64", toolchainBundle(dir, "1.0.0", "osx-arm64", "v1.0.0", "0.1.0-preview.6"));
		expect(toolchainBundleBlockers(config, "v1.0.0", "1.0.0", dir, attached)).toEqual([]);
		const fewer = new Map(attached);
		fewer.delete(hostArchiveName("win-x64", "1.0.0"));
		expect(toolchainBundleBlockers(config, "v1.0.0", "1.0.0", dir, fewer).join()).toContain(`names ${hostArchiveName("win-x64", "1.0.0")}, which is not an asset of v1.0.0`);
		const other = new Map(attached);
		other.set("morphir-extensions-win-x64.json", "f".repeat(64));
		expect(toolchainBundleBlockers(config, "v1.0.0", "1.0.0", dir, other).join()).toContain("gives morphir-extensions-win-x64.json SHA-256");
		const moved = { ...config, source: { ...config.source, commit: "0".repeat(40) } };
		expect(toolchainBundleBlockers(moved, "v1.0.0", "1.0.0", dir, attached).join()).toContain("not the pinned");
	});
	test("a workflow that calls a source workflow at another commit, or another source workflow, is refused", () => {
		const workflow = read(".github/workflows/release.yml");
		const good = { tag: "v0.4.0-alpha.4", githubRef: "refs/tags/v0.4.0-alpha.4", githubSha: "e".repeat(40), head: "e".repeat(40), tagCommit: "e".repeat(40), workflow };
		expect(workflowBindingProblems(config, good)).toEqual([]);
		const moved = workflow.replace(`morphirup-build.yml@${config.source.commit}`, `morphirup-build.yml@${"0".repeat(40)}`);
		expect(workflowBindingProblems(config, { ...good, workflow: moved }).join()).toContain("morphirup-build.yml@");
		const extra = `${workflow}\n  other:\n    uses: finos/morphir-dotnet/.github/workflows/deployment.yml@${config.source.commit}\n`;
		expect(workflowBindingProblems(config, { ...good, workflow: extra }).join()).toContain("deployment.yml of the source, which is not a delivery workflow");
		const oneRef = workflow.replace(`      ref: ${config.source.commit}\n      rid: \${{ matrix.rid }}\n      os: \${{ matrix.runner }}\n      configuration: Release\n      toolchain`, "      rid: ${{ matrix.rid }}\n      os: ${{ matrix.runner }}\n      configuration: Release\n      toolchain");
		expect(oneRef).not.toBe(workflow);
		expect(workflowBindingProblems(config, { ...good, workflow: oneRef }).join()).toContain("once to each source workflow");
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
				// A toolchain platform's self-contained offering carries the host archive's name (zip on Windows); the bytes are a tar.gz either way.
				const artifact = d.portable ? "Morphir.Tool.1.0.0.nupkg" : d.id === "self-contained" && config.morphirup.toolchainPlatforms.includes(rid) ? hostArchiveName(rid, "1.0.0") : `morphir-dotnet-1.0.0-${d.id}-${rid}.tar.gz`;
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
		const hostFiles = new Map(config.morphirup.toolchainPlatforms.map(rid => [rid, path.join(assets, `morphir-dotnet-self-contained-${rid}`, hostArchiveName(rid, "1.0.0"))]));
		const managers = writeMorphirupAssets(path.join(work, "morphirup-assets"), "1.0.0", hostFiles);
		for (const [rid, digest] of managers) writeFileSync(path.join(qualificationDir, `${rid}.morphirup-qualification.json`), JSON.stringify(passingMorphirup(rid, "1.0.0", digest)));
		const kit = path.join(work, "kit.json");
		writeFileSync(kit, JSON.stringify({ revision: "a".repeat(40), modified: false, algorithm: "mck-file-map-sha256/1", corpusHash: `sha256-${"b".repeat(64)}`, errors: 0 }));
		const tool = path.join(root, "tools/cli-release.ts");
		const runTool = (args: string[], cwd: string) => Bun.spawnSync(["bun", "run", tool, ...args], { cwd, stdout: "pipe", stderr: "pipe", windowsHide: true });
		const head = gitCommit(work);

		// Every path is relative to `work`, and every command runs from there.
		const legacy = runTool(["legacy-aliases", "--assets", "assets", "--version", "1.0.0", "--out", "legacy"], work);
		expect(legacy.exitCode, legacy.stderr.toString()).toBe(0);
		expect(readFileSync(path.join(work, "legacy/morphir-win-x64.exe"), "utf8")).toContain("echo 1.0.0+abc1234");

		const inputs = { tag: "v1.0.0", version: "1.0.0", assets: "assets", kitStatus: "kit.json", legacy: "legacy/legacy-aliases.json", morphirup: "morphirup-assets", commit: head, changelog: "## [Unreleased]\n\n## [1.0.0] - 2026-11-10\n", sourceTagCommit: config.source.commit, existingTags: ["v0.4.0-beta.12", "v0.4.0-alpha.4", "extension/python/v0.4.0"] };
		// A candidate pin: a dry run validates everything and writes the evidence and the list it would attach...
		const candidate = asCandidate(config);
		const dry = prepareRelease(candidate, work, { ...inputs, out: "dry", dryRun: true });
		const dryManifest = JSON.parse(readFileSync(path.join(work, "dry/release-manifest.json"), "utf8"));
		expect(dryManifest.publication).toEqual({ dryRun: true, publishable: false, blockers: [expect.stringContaining("marked candidate")] });
		expect(readFileSync(path.join(work, "dry/dry-run-assets.txt"), "utf8").trim().split("\n")).toEqual(dry);
		expect(existsSync(path.join(work, "dry/release-assets.txt"))).toBe(false);
		// ...and a publication refuses it, leaving no release asset list.
		expect(() => prepareRelease(candidate, work, { ...inputs, out: "refused", dryRun: false })).toThrow("publication refused");
		expect(existsSync(path.join(work, "refused/release-assets.txt"))).toBe(false);
		// A run bound to another commit than the checkout validates nothing.
		expect(() => prepareRelease(candidate, work, { ...inputs, out: "other", dryRun: true, commit: "d".repeat(40) })).toThrow("not the bound commit");

		// The same inputs publish once the pin is the source's released, non-candidate commit.
		const publishable = { ...config, source: { ...config.source, candidate: undefined } };
		const listed = prepareRelease(publishable, work, { ...inputs, out: "publish", dryRun: false });
		expect(readFileSync(path.join(work, "publish/release-assets.txt"), "utf8").trim().split("\n")).toEqual(listed);
		const names = listed.map(file => path.basename(file)).sort();
		// The morphirup and toolchain assets join the offerings; each host archive is attached once, as its offering.
		expect(names).toHaveLength(launches.length + legacyRids.length * 2 + 1 + morphirupAssetNames(config.morphirup, "1.0.0").length - config.morphirup.toolchainPlatforms.length);
		for (const name of ["SHA256SUMS", "morphirup-v1.0.0.sha256", "morphirup-win-arm64.exe", "morphirup-linux-x64-v1.0.0.tar.gz", "morphir-toolchain-osx-arm64.json"]) expect(names).toContain(name);
		expect(names.filter(name => name === hostArchiveName("win-x64", "1.0.0"))).toHaveLength(1);
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
