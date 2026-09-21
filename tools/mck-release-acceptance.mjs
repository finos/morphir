// Prepare published CLI acceptance before the OS denies network access.
// The native Rust harness remains the only runner/checker under test.
import { createHash } from "node:crypto";
import { appendFile, mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { createConnection } from "node:net";
import { verifyReleaseVersion } from "./mck-release-version.mjs";
import { sourceQualificationTargets } from "./mck-release-qualification.mjs";

const tag = process.env.RELEASE_TAG;
const target = process.env.RELEASE_TARGET;
const targets = new Map([
  ["x86_64-unknown-linux-gnu", "linux-x64"],
  ["aarch64-unknown-linux-gnu", "linux-arm64"],
  ["x86_64-apple-darwin", "darwin-x64"],
  ["aarch64-apple-darwin", "darwin-arm64"],
  ["x86_64-pc-windows-msvc", "win32-x64"],
  ["aarch64-pc-windows-msvc", "win32-arm64"],
]);
if (!/^v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$/.test(tag ?? "")) throw new Error("RELEASE_TAG must be an existing version tag");
if (targets.get(target) !== `${process.platform}-${process.arch}`) throw new Error("acceptance requires the target's native runner");
const root = process.cwd();
const run = (program, args, options = {}) => {
  const result = spawnSync(program, args, { cwd: root, encoding: "utf8", timeout: 1_200_000, maxBuffer: 64 * 1024 * 1024, ...options });
  if (result.error || result.status !== 0) throw new Error(`${program} ${args.join(" ")}: ${result.error ?? result.status}\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  return result.stdout.trim();
};
const commit = run("git", ["rev-parse", "HEAD"]);
if (!/^[a-f0-9]{40}$/.test(commit) || run("git", ["rev-parse", `${tag}^{commit}`]) !== commit) throw new Error("checkout must match the requested full tag commit");
const version = tag.slice(1);
const base = await mkdtemp(path.join(process.env.RUNNER_TEMP ?? tmpdir(), "mck-release-acceptance-"));
const evidence = path.join(root, ".dev/out/mck-release-acceptance");
await mkdir(evidence, { recursive: true });
const archive = `morphir-${version}-${target}.${process.platform === "win32" ? "zip" : "tgz"}`;
const url = `https://github.com/finos/morphir/releases/download/${encodeURIComponent(tag)}/${archive}`;
async function download(address, limit) {
  const response = await fetch(address, { signal: AbortSignal.timeout(180_000) });
  if (!response.ok) throw new Error(`${address}: HTTP ${response.status}`);
  const chunks = [];
  let total = 0;
  for await (const chunk of response.body) {
    total += chunk.length;
    if (total > limit) throw new Error(`${address}: release asset exceeds ${limit} bytes`);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
const checksum = (await download(`${url}.sha256`, 4096)).toString("utf8").replace(/^\uFEFF/, "").trim();
const [expected, filename, ...extra] = checksum.split(/\s+/);
if (!/^[a-fA-F0-9]{64}$/.test(expected) || filename?.replace(/^\*/, "") !== archive || extra.length) throw new Error("invalid release checksum file");
const bytes = await download(url, 512 * 1024 * 1024);
const actual = createHash("sha256").update(bytes).digest("hex");
if (actual !== expected.toLowerCase()) throw new Error("published CLI archive checksum mismatch");
const asset = path.join(base, archive);
await writeFile(asset, bytes);
const install = path.join(base, "installed");
await mkdir(install);
const executable = process.platform === "win32" ? "morphir.exe" : "morphir";
if (process.platform === "win32") {
  run("pwsh", ["-NoProfile", "-NonInteractive", "-Command", "Expand-Archive -LiteralPath $env:MCK_ARCHIVE -DestinationPath $env:MCK_INSTALL"], { env: { ...process.env, MCK_ARCHIVE: asset, MCK_INSTALL: install } });
} else {
  if (run("tar", ["-tzf", asset]) !== executable) throw new Error("unexpected release archive members");
  run("tar", ["-xzf", asset, "-C", install]);
}
if (JSON.stringify(await readdir(install)) !== JSON.stringify([executable])) throw new Error("unexpected extracted release files");
const cli = path.join(install, executable);
const reportedVersion = verifyReleaseVersion(run(cli, ["--version"], { env: { ...process.env, MORPHIR_LOG_FILE: "false" } }), version);
await writeFile(path.join(evidence, "release.json"), `${JSON.stringify({ tag, commit, target, archive, sha256: actual, reportedVersion }, null, 2)}\n`);

// Compile while network and Cargo are available; execute this exact artifact later.
const build = run("cargo", ["test", "--locked", "--package", "morphir", "--target", target, "--test", "mck_run", "--no-run", "--message-format=json-render-diagnostics"]);
const artifacts = build.split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line))
  .filter((entry) => entry.reason === "compiler-artifact" && entry.target.name === "mck_run" && entry.executable);
if (artifacts.length !== 1) throw new Error("expected one native mck_run test executable");

// The tagged source defines available suites. Keep old IR-only releases
// qualifiable, and require the complete package test set once it exists.
const metadata = JSON.parse(run("cargo", ["metadata", "--locked", "--no-deps", "--format-version", "1"]));
const qualificationTargets = sourceQualificationTargets(metadata);
const qualification = spawnSync("cargo", ["test", "--locked", "--package", "morphir-mck", "--target", target, ...qualificationTargets.flatMap(name => ["--test", name])], {
  cwd: root, encoding: "utf8", timeout: 600_000, maxBuffer: 16 * 1024 * 1024,
});
await writeFile(path.join(evidence, "source-transport.log"), `Source qualification tests: ${qualificationTargets.join(", ")}\n${qualification.stdout ?? ""}\n${qualification.stderr ?? ""}`);
if (qualification.error || qualification.status !== 0) throw new Error(`source transport qualification failed: ${qualification.error ?? qualification.status}\n${qualification.stdout}\n${qualification.stderr}`);

// Prove the exact direct TCP probe works before applying network denial.
const probe = "1.1.1.1:443";
await new Promise((resolve, reject) => {
  const socket = createConnection({ host: "1.1.1.1", port: 443 });
  socket.setTimeout(5000);
  socket.once("connect", () => { socket.destroy(); resolve(); });
  socket.once("error", reject);
  socket.once("timeout", () => { socket.destroy(); reject(new Error("network probe unavailable before isolation")); });
});

const acquisition = path.join(base, "acquisition");
const home = path.join(acquisition, "home");
const temporary = path.join(acquisition, "tmp");
await mkdir(home, { recursive: true });
await mkdir(temporary);
const repository = path.join(base, "consumer");
await mkdir(repository);
const hooks = path.join(base, "empty-hooks");
await mkdir(hooks);
const kit = path.join(repository, "kit");
const acquisitionEnv = { ...process.env, HOME: home, USERPROFILE: home, LOCALAPPDATA: home, APPDATA: home, XDG_CACHE_HOME: home, TMPDIR: temporary, TMP: temporary, TEMP: temporary, MORPHIR_LOG_FILE: "false" };
try {
  run(cli, ["mck", "kit", "vendor", "--source", "github:finos/morphir", "--revision", commit, "--dest", kit], { cwd: repository, env: acquisitionEnv });
  run("git", ["init"], { cwd: repository });
  run("git", ["config", "core.autocrlf", "false"], { cwd: repository });
  await writeFile(path.join(repository, ".gitattributes"), "kit/** -text\n");
  run("git", ["add", "--force", "kit", ".gitattributes"], { cwd: repository });
  run("git", ["-c", "user.name=MCK release acceptance", "-c", "user.email=mck-acceptance@localhost", "-c", `core.hooksPath=${hooks}`, "-c", "commit.gpgsign=false", "commit", "-m", "Record exact-commit acquired kit"], { cwd: repository });
  if (run("git", ["status", "--porcelain"], { cwd: repository })) throw new Error("acquired kit repository is not clean");
} finally {
  await rm(acquisition, { recursive: true, force: true });
}
await rm(asset);
await writeFile(path.join(evidence, "acquisition.json"), `${JSON.stringify({ tag, commit, target, archive, sha256: actual, reportedVersion, probe, snapshotCommit: run("git", ["rev-parse", "HEAD"], { cwd: repository }), acquisitionStateRemoved: true }, null, 2)}\n`);
const environment = {
  MCK_TEST_EXE: artifacts[0].executable,
  MORPHIR_MCK_INSTALLED_CLI: cli,
  MORPHIR_MCK_PREACQUIRED_KIT: kit,
  MORPHIR_MCK_REQUIRE_NETWORK_DENIAL: probe,
  MORPHIR_MCK_ACCEPTANCE_EVIDENCE: evidence,
};
if (!process.env.GITHUB_ENV) throw new Error("GITHUB_ENV is required to hand off prepared inputs");
for (const [key, value] of Object.entries(environment)) {
  if (/[\r\n]/.test(value)) throw new Error(`unsafe environment value for ${key}`);
  await appendFile(process.env.GITHUB_ENV, `${key}=${value}\n`);
}
console.log(`Verified ${archive}; acquired ${commit}; compiled ${artifacts[0].executable}. Ready for network-denied native acceptance.`);
