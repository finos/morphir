import { npmCli } from '../../../tests/npm.ts';
import type { PipelineReport, Warning, FrontendInventory } from '../../../tests/cli-contracts.ts';
import type { Json } from '../../../types/data.ts';
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, cpSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, existsSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const appDirectory = fileURLToPath(new URL("../", import.meta.url));
const workspaceDirectory = fileURLToPath(new URL("../../../", import.meta.url));
const runner = join(workspaceDirectory, "pkgs/morphir-host/runners/wasm.mjs");
const targets = ["native", "js", "wasm", "wasm-gc"];
const selected = process.argv[2] ? [process.argv[2]] : targets;
const headlessOnly = process.env.MORPHIR_HEADLESS_ONLY === '1';
let reference: unknown;

function checkHelp(output: string) {
  assert.match(output, /^Morphir CLI\r?\n/);
  assert.match(output, /^Usage: morphir/m);
  assert.match(output, /project/);
  assert.match(output, /toolchain/);
  assert.match(output, /--json-lines/);
}

function headlessAcceptance(target: string, binary: string, launcher?: string, installedRoot?: string) {
  const env = {
    ...process.env,
    MORPHIR_HEADLESS_BUILD: join(workspaceDirectory, '_build'),
    MORPHIR_HEADLESS_PROFILE: 'release',
    MORPHIR_HEADLESS_BINARY: binary,
    MORPHIR_GENERATION_VERIFIER: join(workspaceDirectory, '_build/js/release/build/finos/morphir-engine/acceptance/retained-generation/retained-generation.js'),
    MORPHIR_CONNECTED_PROVIDER_BUILD: join(workspaceDirectory, '_build'),
    MORPHIR_CONNECTED_HELPER: join(appDirectory, 'build-provider/connected.mjs'),
    MORPHIR_TRANSFER_HELPER: join(appDirectory, 'build-provider/transfers.mjs'),
    ...(launcher ? { MORPHIR_HEADLESS_LAUNCHER: launcher } : {}),
    ...(installedRoot ? {
      MORPHIR_GENERATION_HELPER: join(installedRoot, 'build-provider/library-build.mjs'),
      MORPHIR_CONNECTED_HELPER: join(installedRoot, 'build-provider/connected.mjs'),
      MORPHIR_TRANSFER_HELPER: join(installedRoot, 'build-provider/transfers.mjs'),
    } : {}),
  };
  for (const script of [
    ...(target === 'js' || target === 'native' ? ['test-headless-evaluation.ts', 'test-headless-models.ts'] : []),
    'test-headless-worksheet.ts',
    'test-model-inventory.ts',
    'test-generation.ts',
    ...(target === 'wasm' || target === 'wasm-gc' || process.platform === 'win32' || process.env.MORPHIR_WORKBENCH_LIVE_HOST ? ['test-headless-connected.ts'] : []),
    ...(target === 'wasm' || target === 'wasm-gc' || process.platform === 'win32' || process.env.MORPHIR_WORKBENCH_ARTIFACT_HOST ? ['test-headless-transfers.ts'] : []),
    ...(process.env.MORPHIR_MCK_BIN && (target === 'js' || target === 'native') ? ['test-headless-model-mck.ts'] : []),
  ]) {
    execFileSync(process.execPath, [join(appDirectory, 'scripts', script), target], {
      cwd: workspaceDirectory, env, stdio: 'inherit',
      // Twelve fresh host fixtures include two complete 64-MiB transfers.
      // Each scenario retains its acquisition and prompt-cancellation limits.
      timeout: script === 'test-headless-transfers.ts' ? 900000 : 180000,
    });
  }
}

function exercise(command: string, prefix: readonly string[], directory: string, target: string, buildHelper = join(appDirectory,"build-provider/library-build.mjs")) {
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith("MORPHIR_")));
  env.HOME = join(directory, "home");
  env.USERPROFILE = env.HOME;
  env.XDG_CONFIG_HOME = join(directory, "config");
  delete env.APPDATA;
  const run = (args: string[], expected = 0, cwd = directory) => {
    const result = spawnSync(command, [...prefix, ...args], {cwd, env, encoding: "utf8"});
    assert.equal(result.status, expected, `${target} ${args.join(" ")}:\n${result.stdout}\n${result.stderr}`);
    return result;
  };
  const put = (path: string, text: string | Uint8Array) => { mkdirSync(join(directory, path, ".."), {recursive: true}); writeFileSync(join(directory, path), text); };
  const lines = (args: string[], expected = 0) => run([...args, "--json-lines"], expected).stdout.trim().split(/\r?\n/).map(line => {
    const record = JSON.parse(line);
    assert.equal(typeof record.type, "string");
    assert.ok(Object.hasOwn(record, "data"));
    return record;
  });
  put("morphir.toml", '[workspace]\nmembers=["packages/*"]\nexclude=["packages/skip"]\ndefault_member="packages/core"\n');
  put("morphir.config.scm", '(pipeline (transform (lambda (file) file)))');
  put("packages/core/morphir.toml", '[project]\nname="Core"\nsource_directory="src"\n');
  put("packages/tools/morphir.toml", '[project]\nname="Tools"\nsource_directory="lib"\n');
  put("packages/skip/morphir.toml", '[project]\nname="Skip"\n');
  put("packages/core/src/Main.scm", '42');
  put("packages/core/src/nested/Other.scm", '41');
  put("packages/tools/lib/Main.scm", '"hello λ😀"');
  checkHelp(run([]).stdout);
  assert.deepEqual(JSON.parse(run(["--help", "--json"]).stdout).commands, ["run", "execute", "verify", "conform", "eval", "worksheet", "generate", "model inspect", "model export-original", "connected connect", "connected run", "connected artifacts", "workspace", "project list", "toolchain info", "toolchain setup", "toolchain build", "toolchain run", "toolchain exec"]);
  assert.equal(lines(["--help"])[0].type, "help");
  for (const args of [["run", "--help"], ["workspace", "--help"], ["project", "list", "--help"]]) {
    assert.ok(JSON.parse(run([...args, "--json"]).stdout).options.includes("--json-lines"));
    assert.equal(lines(args)[0].type, "help");
  }
  assert.equal(lines(["unknown"], 2)[0].type, "error");
  assert.match(JSON.parse(run(["--json", "toolchain", "run", "--help"]).stdout).usage, /^Usage: morphir toolchain run/m);
  assert.match(JSON.parse(run(["run", "--targte", "js", "--json"], 2).stdout).error, /--target/);
  assert.match(JSON.parse(run(["toolchain", "build", "--yes", "--json"], 2).stdout).error, /--yes/);
  assert.match(JSON.parse(run(["verify", "missing", "--suite=one", "--suite", "two", "--json"], 2).stdout).error, /Repeated option: --suite/);

  for (const args of [["run", "--help", "--unknown"], ["run", "--morphir-internal-help"],
    ["run", "--json=true"], ["run", "--target", "--help"],
    ["toolchain", "info", "--timeout", "1", "--timeout", "2"]]) {
    const error = JSON.parse(run([...args, "--json"], 2).stdout);
    assert.equal(error.successful, false);
    assert.equal(typeof error.error, "string");
    assert.equal(lines(args, 2)[0].type, "error");
  }
  assert.equal(lines(["workspace", "--json"], 2)[0].type, "error");
  const tooling = JSON.parse(run(["toolchain", "info", "--json"]).stdout);
  if (target === "wasm") {
    assert.equal(tooling.supported, false);
    assert.equal(lines(["toolchain", "setup", "--yes"], 2)[0].type, "error");
  } else {
    assert.equal(tooling.validated, true);
    assert.equal(lines(["toolchain", "info"])[0].type, "toolchain");
    const toolhome = tooling.home;
    put("moon-example/moon.mod", 'name="morphir/tooling-example"\nversion="0.0.0"\n');
    put("moon-example/moon.pkg", 'pkgtype(kind: "executable")\nimport {"moonbitlang/core/env"}\n');
    put("moon-example/main.mbt", 'fn main { for arg in @env.args()[1:] { println(arg) } }\n');
    const built = JSON.parse(run(["toolchain", "build", "moon-example", "--home", toolhome, "--target", "wasm", "--json"]).stdout);
    assert.equal(built.successful, true);
    const executed = JSON.parse(run(["toolchain", "run", "moon-example", "--home", toolhome, "--json", "--", "--help", "--json", "", "λ value", "--", "$(echo forbidden)"]).stdout);
    assert.equal(executed.process.stdout.trim(), '--help\n--json\n\nλ value\n--\n$(echo forbidden)');
    assert.equal(executed.successful, true);
    if (tooling.moonx) {
      put("tooling.mbtx", 'fn main { println(42) }\n');
      const script=JSON.parse(run(["toolchain","exec","tooling.mbtx","--home",toolhome,"--json"]).stdout);
      assert.equal(script.process.stdout.trim(),'42');
    }
    assert.equal(lines(["toolchain", "setup", "--home", toolhome])[0].data.validated, true);
    const invalid = JSON.parse(run(["toolchain", "info", "--home", "absent", "--json"],2).stdout);
    assert.match(invalid.error, /Missing moon/);
    put("moon-example/main.mbt", 'fn main { let n : Int = "bad"; println(n) }\n');
    const failed = JSON.parse(run(["toolchain", "build", "moon-example", "--home", toolhome, "--json"],255).stdout);
    assert.equal(failed.successful,false);
    assert.match(failed.process.stderr, /Mismatch/);
  }
  assert.equal(JSON.parse(run(["workspace", "--json"]).stdout).projects.length, 2);
  const workspaceLines = lines(["workspace"]);
  assert.equal(workspaceLines[0].type, "workspace");
  assert.equal(workspaceLines.filter(r => r.type === "project").length, 2);
  const defaultProjects: {name: string;frontend: string;target: string}[] = JSON.parse(run(["project", "list", "--json"]).stdout).projects;
  assert.deepEqual(defaultProjects.map(p => [p.name, p.frontend, p.target]),
    [["Core", "scheme", "ir-json"], ["Tools", "scheme", "ir-json"]]);
  assert.match(run(["project", "list"]).stdout, /^NAME\tPATH\tFRONTEND\tTARGET/m);
  const dryLines = lines(["run", "--dry-run"]);
  assert.equal(dryLines.filter(r => r.type === "source").length, 2);
  assert.equal(dryLines.at(-1).type, "plan");
  assert.equal(dryLines.at(-1).data.sourceCount, 2);
  assert.ok(!existsSync(join(directory, ".morphir/out")));
  const defaultPlan = JSON.parse(run(["run", "--dry-run"]).stdout);
  assert.equal(defaultPlan.sources.length, 2);
  assert.ok(defaultPlan.sources.every((p: string) => p.startsWith("packages/core/")));
  const selectedPlan = JSON.parse(run(["run", "--project", "Tools", "--dry-run"]).stdout);
  assert.deepEqual(selectedPlan.sources, ["packages/tools/lib/Main.scm"]);
  const filePlan = JSON.parse(run(["run", "packages/core/src/Main.scm", "--dry-run"]).stdout);
  assert.deepEqual(filePlan.sources, ["packages/core/src/Main.scm"]);
  const dirPlan = JSON.parse(run(["run", "packages/core/src/nested", "--dry-run"]).stdout);
  assert.deepEqual(dirPlan.sources, ["packages/core/src/nested/Other.scm"]);
  // WASI can only discover ancestors within its preopened development root.
  if (target !== "wasm") {
    assert.deepEqual(JSON.parse(run(["run", "--dry-run"], 0, join(directory, "packages/tools")).stdout).sources,
      ["packages/tools/lib/Main.scm"]);
  }
  const result = JSON.parse(run(["run", "--all", "--json"]).stdout);
  assert.equal(result.processed, 3);
  assert.equal(result.committed.length, 2);
  const artifact = join(directory, ".morphir/out/packages/core/compile.dest/Main.ir.json");
  const before = readFileSync(artifact, "utf8");
  if (reference) assert.deepEqual(JSON.parse(before), reference);
  else reference = JSON.parse(before);
  // Rerun replaces owned task directories and removes stale task outputs.
  put(".morphir/out/packages/core/compile.dest/stale", "old");
  run(["run", "--all"]);
  assert.ok(!existsSync(join(directory, ".morphir/out/packages/core/compile.dest/stale")));
  put("packages/tools/morphir.config.scm", '(pipeline (transform (lambda (file) 123)))');
  const failure = JSON.parse(run(["run", "--all", "--json"], 1).stdout);
  assert.equal(failure.successful, false);
  assert.deepEqual(failure.committed, []);
  assert.equal(readFileSync(artifact, "utf8"), before);
  const failureLines = lines(["run", "--all"], 1);
  assert.ok(failureLines.some(r => r.type === "diagnostic"));
  assert.equal(failureLines.at(-1).data.successful, false);
  assert.equal(failureLines.filter(r => r.type === "committed").length, 0);
  rmSync(join(directory, "packages/tools/morphir.config.scm"));
  const streamed = lines(["run", "--all"]);
  assert.equal(streamed.filter(r => r.type === "artifact").length, 3);
  assert.equal(streamed.filter(r => r.type === "committed").length, 2);
  assert.equal(streamed.at(-1).type, "result");
  assert.equal(streamed.at(-1).data.successful, true);
  assert.equal(streamed.at(-1).data.processed, 3);
  put("morphir.yaml", "workspace: {}");
  assert.match(run(["run"], 2).stderr, /Ambiguous/);
  rmSync(join(directory, "morphir.yaml"));
  run(["run", "--all", "--project", "Core"], 2);
  run(["run", "--output", "../outside"], 2);
  // A busy publisher fails without changing the previous outputs.
  mkdirSync(join(directory, ".morphir/out/.morphir-publish.lock"));
  run(["run"], 1);
  rmSync(join(directory, ".morphir/out/.morphir-publish.lock"), {recursive:true});
  assert.equal(readFileSync(artifact, "utf8"), before);
  if (process.platform !== "win32") {
    symlinkSync("Main.scm", join(directory, "packages/core/src/alias.scm"));
    assert.match(run(["run"], 2).stderr, /link/);
    rmSync(join(directory, "packages/core/src/alias.scm"));
  }
  writeFileSync(join(directory,"packages/core/src/Invalid.scm"), Buffer.from([0xff]));
  assert.equal(JSON.parse(run(["run","packages/core/src/Invalid.scm","--json"],1).stdout).successful,false);
  rmSync(join(directory,"packages/core/src/Invalid.scm"));
  if (target !== "wasm") {
    // An explicit Morphir home works without OS home/config variables.
    put("config-home/morphir.toml", '[frontend]\nlanguage="missing-from-registry"');
    const saved = {...env};
    for (const key of ["HOME","USERPROFILE","APPDATA","XDG_CONFIG_HOME"]) delete env[key];
    env.MORPHIR_HOME = join(directory,"config-home");
    assert.match(run(["run","--dry-run"],2).stderr,/Unknown frontend: missing-from-registry/);
    delete env.MORPHIR_HOME;
    Object.assign(env,saved);
    rmSync(join(directory,"config-home"),{recursive:true});
  }
  // Listing resolves layered languages without requiring their compiler plugins.
  put("catalog/morphir.toml", '[workspace]\nmembers=["a","b","c"]\n[frontend]\nlanguage="elm"\n[pipeline]\nbackend="scala"\n');
  put("catalog/a/morphir.toml", '[project]\nname="A"\n');
  put("catalog/b/morphir.toml", '[project]\nname="B"\n[frontend]\nlanguage="scheme"\n[pipeline]\nbackend="ir-json"\n');
  put("catalog/c/morphir.toml", '[project]\nname="C"\n[frontend]\nlanguage="moonbit"\n[pipeline]\nbackend="javascript"\n');
  put("catalog/morphir.config.scm", '(pipeline (transform (lambda (file) file)))');
  put("catalog/b/morphir.config.scm", '(pipeline (backend "scheme"))');
  writeFileSync(join(directory, "catalog/a/Invalid.elm"), Buffer.from([0xff]));
  const list = (...filters: string[]): { projects: {name: string;frontend: string;target: string}[] } => JSON.parse(run(["project", "list", "catalog", ...filters, "--json"]).stdout);
  assert.deepEqual(list().projects.map((p: {name: string;frontend: string;target: string}) => [p.name, p.frontend, p.target]),
    [["A", "elm", "scala"], ["B", "scheme", "scheme"], ["C", "moonbit", "javascript"]]);
  assert.deepEqual(list("--frontend", "elm").projects.map((p: {name: string;frontend: string;target: string}) => p.name), ["A"]);
  assert.deepEqual(list("--target", "scheme").projects.map((p: {name: string;frontend: string;target: string}) => p.name), ["B"]);
  assert.deepEqual(list("--frontend", "elm", "--frontend", "scheme").projects.map((p: {name: string;frontend: string;target: string}) => p.name), ["A", "B"]);
  assert.deepEqual(list("--target", "scala", "--target", "javascript").projects.map((p: {name: string;frontend: string;target: string}) => p.name), ["A", "C"]);
  assert.deepEqual(list("--frontend", "scheme", "--target", "scheme").projects.map((p: {name: string;frontend: string;target: string}) => p.name), ["B"]);
  assert.deepEqual(list("--frontend", "scheme", "--target", "scala").projects, []);
  assert.deepEqual(list("--frontend", "missing").projects, []);
  assert.ok(!existsSync(join(directory, "catalog/.morphir/out")));
  assert.deepEqual(lines(["project", "list", "catalog", "--target", "scheme"]).map(r => r.type), ["project", "result"]);
  const emptyList = lines(["project", "list", "catalog", "--frontend", "missing"]);
  assert.equal(emptyList.length, 1);
  assert.equal(emptyList[0].data.projectCount, 0);
  for (const args of [["project"], ["project", "bad"], ["project", "list", "--target"],
      ["project", "list", "--frontend", ""], ["project", "list", "--all"]]) {
    assert.equal(lines(args, 2)[0].type, "error");
    assert.equal(JSON.parse(run([...args, "--json"], 2).stdout).successful, false);
  }
  put("select.scm", '(pipeline (backend "rust"))');
  assert.equal(list("--config", "select.scm", "--target", "rust").projects.length, 3);
  put("catalog/b/morphir.config.scm", '(pipeline (frontend 42))');
  const invalidList = JSON.parse(run(["project", "list", "catalog", "--frontend", "elm", "--json"], 2).stdout);
  assert.deepEqual(invalidList.projects.map((p: {name: string;frontend: string;target: string}) => p.name), ["A"]);
  assert.equal(invalidList.successful, false);
  assert.equal(invalidList.diagnostics.length, 1);
  const invalidLines = lines(["project", "list", "catalog", "--frontend", "missing"], 2);
  assert.deepEqual(invalidLines.map(r => r.type), ["diagnostic", "result"]);
  assert.equal(invalidLines.at(-1).data.successful, false);
  put("catalog/b/morphir.config.scm", '(pipeline (backend "scheme"))');
  put("catalog/b/morphir.toml", '[project]\nname="B"\n[ir]\nformat_version=5\n');
  const invalidIr = JSON.parse(run(["project", "list", "catalog", "--json"], 2).stdout);
  assert.equal(invalidIr.successful, false);
  assert.match(invalidIr.diagnostics[0].message, /versions are integers 1 through 4/);
  assert.equal(lines(["project", "list", "catalog"], 2).at(-1).data.successful, false);
  // Source frontends carry native Ion metadata into the typed pipeline.
  put("moon-model/morphir.toml", '[project]\nname="BooleanModel"\nmodule_prefix="App"\n[frontend]\nlanguage="moonbit"\n[pipeline]\nbackend="checkpoint"\ncomponents=["json-identity"]\n');
  put("moon-model/src/Main.mbt", 'pub fn broken(');
  put("moon-model/src/ignored.json", 'not a model');
  const modelArgs = ["run", "moon-model"];
  const sourceDryLog = join(directory, "source-dry.ionb");
  const modelPlan = JSON.parse(run([...modelArgs, "--dry-run", "--log", "--log-file", sourceDryLog, "--json"]).stdout);
  assert.ok(!existsSync(sourceDryLog));
  assert.ok(!existsSync(join(directory,"moon-model/.morphir/logs")));
  assert.deepEqual(modelPlan.sources, ["src/Main.mbt"]);
  assert.deepEqual(modelPlan.frontends.map((f: FrontendInventory) => Object.fromEntries(['source','unitId','frontend','profile','dependencies','outputContract'].map(k => [k,f[k]]))), [{source: "src/Main.mbt", unitId: "Main", frontend: "moonbit", profile: "moonbit-model-bool-v1", dependencies: {"moonbitlang/parser": "0.4.5", "moonbitlang/lexer": "0.4.3"}, outputContract: "ir-unit"}]);
  assert.equal(modelPlan.frontends[0].language,'moonbit');
  assert.equal(modelPlan.frontends[0].provider,'finos/morphir-moonbit-frontend');
  assert.equal(modelPlan.frontends[0].defaultProfile,true);
  assert.equal(modelPlan.frontends[0].evidence,'local-acceptance');
  assert.deepEqual(new Set(modelPlan.frontends[0].availableProfiles),new Set(['moonbit-model-bool-v1','moonbit-model-bool-library-v1','moonbit-model-typed-library-foundation-v1','moonbit-model-int32-library-v1','moonbit-model-integer-library-v1','moonbit-model-float-library-v1','moonbit-model-string-library-v1','moonbit-model-library-v1','moonbit-model-library-v2','moonbit-model-library-2026-10-17','moonbit-model-library-2026-10-19','moonbit-model-pinned-sdk-library-v1']));
  assert.equal(modelPlan.frontends[0].capabilities.maxDocuments,1);
  assert.equal(modelPlan.frontends[0].capabilities.incremental,false);
  assert.equal(modelPlan.frontends[0].capabilities.limits.functions,1);
  assert.equal(modelPlan.boundaries[0].outputFormat, "ion-binary");
  assert.equal(lines([...modelArgs, "--dry-run"]).find(r => r.type === "frontend").data.profile, "moonbit-model-bool-v1");
  assert.ok(!existsSync(join(directory, "moon-model/.morphir/out")));
  const modelSource = '// λ😀\npub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }';
  put("moon-model/src/Main.mbt", modelSource);
  const modelResult = JSON.parse(run([...modelArgs, "--json"]).stdout);
  assert.equal(modelResult.successful, true);
  assert.equal(modelResult.frontends[0].profile, "moonbit-model-bool-v1");
  const modelOutput = join(directory, "moon-model/.morphir/out/compile.dest");
  const modelBinary = readFileSync(join(modelOutput, "Main.ionb"));
  assert.deepEqual([...modelBinary.subarray(0, 4)], [0xe0, 0x01, 0x00, 0xea]);
  if (target === "wasm" || target === "wasm-gc") {
    assert.match(run([...modelArgs, "--log-file", "source.ionb", "--json"], 2).stderr, /observability.clock_capability_required/);
  } else {
    const defaultLog = join(directory,"moon-model/.morphir/logs/frontend.ionb");
    assert.ok(!existsSync(defaultLog));
    assert.deepEqual(JSON.parse(run([...modelArgs,"--log","--json"]).stdout), modelResult);
    assert.deepEqual([...readFileSync(defaultLog).subarray(0,4)],[224,1,0,234]);
    run([...modelArgs,"--log","--json"]);
    assert.ok(existsSync(defaultLog + ".1"));
    const explicitLog = join(directory,"explicit-frontend.ionb");
    const savedDefault = readFileSync(defaultLog);
    run([...modelArgs,"--log","--log-file",explicitLog,"--json"]);
    assert.deepEqual([...readFileSync(explicitLog).subarray(0,4)],[224,1,0,234]);
    assert.deepEqual(readFileSync(defaultLog),savedDefault);
  for (const format of ["ion-binary", "ion-text", "json-lines", "text"]) {
    const extension = {"ion-binary":"ionb","ion-text":"ion","json-lines":"jsonl",text:"log"}[format];
    const log = join(directory,"moon-model/.morphir/logs/frontend." + extension);
    const observed = JSON.parse(run([...modelArgs, "--log", "--log-format", format, "--json"]).stdout);
    assert.deepEqual(observed, modelResult);
    assert.deepEqual(readFileSync(join(modelOutput, "Main.ionb")), modelBinary);
    const contents = readFileSync(log);
    if (format === "ion-binary") assert.deepEqual([...contents.subarray(0, 4)], [224, 1, 0, 234]);
    else {
      assert.match(contents.toString(), /profile-check/);
      assert.ok(!contents.toString().includes("eligible"));
    }
    if (format === "json-lines") {
      const records = contents.toString().trim().split("\n").map(line => JSON.parse(line));
      assert.deepEqual(records.filter(r => r.signal === "succeeded").map(r => r.stage), ["parse", "profile-check", "lower", "frontend"]);
      assert.equal(records.length, 8);
      for (const record of records) {
        assert.equal(record.profile, "morphir-observation-v1");
        assert.equal(record.details, null);
        if (record.stage !== "frontend") assert.equal(record.parent_id, records[0].span_id);
      }
    }
  }
  const sourceSinkFailure = run([...modelArgs, "--log-file", directory, "--json"]);
  assert.match(sourceSinkFailure.stderr, /observability sink unavailable/);
  assert.deepEqual(JSON.parse(sourceSinkFailure.stdout), modelResult);
  assert.deepEqual(readFileSync(join(modelOutput, "Main.ionb")), modelBinary);
  }
  const modelText = JSON.parse(run([...modelArgs, "--checkpoint-format", "ion-text", "--json"]).stdout);
  assert.equal(modelText.successful, true);
  const modelIon = readFileSync(join(modelOutput, "Main.ion"), "utf8");
  assert.match(modelIon, /morphir_moonbit_frontend/);
  assert.match(modelIon, /moonbit-model-bool-v1/);
  assert.match(modelIon, /moonbit-parser-position-v1/);
  // An explicit JSON component projection retains the native metadata sidecar.
  const modelLibrary = JSON.parse(run([...modelArgs, "--backend", "moonbit", "--validation", "source-only", "--json"]).stdout);
  assert.equal(modelLibrary.projects.length, 1);
  const modelSymbols = readFileSync(join(modelOutput, "Main/symbols.10n"));
  assert.deepEqual([...modelSymbols.subarray(0, 4)], [0xe0, 0x01, 0x00, 0xea]);
  assert.match(readFileSync(join(modelOutput, "Main/library.mbt"), "utf8"), /pub fn/);
  // Failed source compilation cannot replace the previously published library.
  put("moon-model/src/Main.mbt", 'pub fn bad(x : @other.Bool) -> Bool { true }');
  const modelFailure = JSON.parse(run([...modelArgs, "--json"], 1).stdout);
  assert.deepEqual(modelFailure.committed, []);
  assert.equal(modelFailure.diagnostics[0].stage, "frontend");
  assert.match(modelFailure.diagnostics[0].message, /^moonbit_frontend\.unsupported_type:.* at 1:/);
  const rejected = JSON.parse(run([...modelArgs, "--json"], 1).stdout).diagnostics[0];
  assert.equal(rejected.code, "moonbit_frontend.unsupported_type");
  assert.equal(typeof rejected.location.startLine, "number");
  assert.deepEqual(readFileSync(join(modelOutput, "Main/symbols.10n")), modelSymbols);
  if (target !== "wasm" && target !== "wasm-gc") {
  const rejectedLog = join(directory, "rejected-source.jsonl");
  assert.deepEqual(JSON.parse(run([...modelArgs, "--log-file", rejectedLog, "--log-format", "json-lines", "--json"], 1).stdout), modelFailure);
  const rejectedRecords = readFileSync(rejectedLog, "utf8").trim().split("\n").map(line => JSON.parse(line));
  assert.deepEqual(rejectedRecords.filter(r => r.signal === "failed").map(r => r.stage), ["profile-check", "frontend"]);
  assert.ok(!readFileSync(rejectedLog, "utf8").includes("@other.Bool"));
  }
  const modelFailureLines = lines(modelArgs, 1);
  assert.equal(modelFailureLines.find(r => r.type === "diagnostic").data.message, modelFailure.diagnostics[0].message);
  assert.match(run(modelArgs, 1).stderr, /moonbit_frontend\.unsupported_type/);
  put("moon-model/src/Main.mbt", modelSource);
  const lossyModel = JSON.parse(run([...modelArgs, "--checkpoint-format", "morphir-json", "--json"], 1).stdout);
  assert.match(lossyModel.diagnostics[0].message, /data\.lossy_conversion/);
  put("moon-model/morphir.toml", readFileSync(join(directory, "moon-model/morphir.toml"), "utf8").replace('components=["json-identity"]', ''));
  assert.match(run([...modelArgs, "--backend", "ir-json", "--json"], 2).stdout, /frontend\.typed_backend_required/);
  const schemeFromMoonBit = JSON.parse(run([...modelArgs, "--backend", "scheme", "--json"]).stdout);
  assert.equal(schemeFromMoonBit.successful, true);
  // Scheme from a rich unit keeps the metadata in a sidecar and comments each define (morphir-ukvn.5.40).
  assert.ok(!schemeFromMoonBit.warnings.some((w: {message: string}) => w.message.startsWith("backend.metadata_dropped")));
  const schemeSymbols = readFileSync(join(modelOutput, "Main.symbols.10n"));
  assert.deepEqual([...schemeSymbols.subarray(0, 4)], [0xe0, 0x01, 0x00, 0xea]);
  assert.match(readFileSync(join(modelOutput, "Main.scm"), "utf8"), /^;; \S+ \(\S*Main\.mbt:\d+:\d+\)$/m);
  // Language identity stays MoonBit while profile selection changes its supported source.
  const libraryProfile = "moonbit-model-bool-library-v1";
  const sourceProvider = "finos/morphir-moonbit-frontend";
  put("moon-library/morphir.toml", '[project]\nname="LibraryModel"\nmodule_prefix="App"\n[frontend]\nlanguage="moonbit"\nprofile="' + libraryProfile + '"\n[pipeline]\nbackend="checkpoint"\ncomponents=["json-identity"]\n');
  put("moon-library/src/Main.mbt", 'pub fn broken(');
  const librarySourceArgs = ["run", "moon-library"];
  const librarySourcePlan = JSON.parse(run([...librarySourceArgs,"--dry-run","--log","--json"]).stdout);
  assert.equal(librarySourcePlan.frontends[0].language,"moonbit");
  assert.equal(librarySourcePlan.frontends[0].profile,libraryProfile);
  assert.equal(librarySourcePlan.frontends[0].defaultProfile,false);
  assert.equal(librarySourcePlan.frontends[0].capabilities.limits.functions,64);
  assert.equal(librarySourcePlan.frontends[0].evidence,"local-acceptance");
  assert.ok(!existsSync(join(directory,"moon-library/.morphir")));
  const humanSourcePlan = run([...librarySourceArgs,"--dry-run"]).stdout;
  assert.match(humanSourcePlan,/Language: moonbit; provider: finos\/morphir-moonbit-frontend/);
  assert.match(humanSourcePlan,/Boolean library; documents per unit: 1; incremental: false/);
  assert.match(humanSourcePlan,/Direct same-file calls/);
  assert.equal(lines([...librarySourceArgs,"--dry-run"]).find(r=>r.type==='frontend').data.provider,sourceProvider);
  for (const [flags,code] of [
    [["--frontend-provider","absent"],"frontend.unknown_provider"],
    [["--frontend-profile","absent"],"frontend.unknown_profile"],
    [["--frontend","moonbit-library"],"Unknown frontend: moonbit-library"],
    [["--frontend","ion-text"],"frontend.source_constraint_on_data_format"],
    [["--frontend-profile="],"Missing value for --frontend-profile"],
  ] as const) assert.ok(JSON.parse(run([...librarySourceArgs,...flags,"--dry-run","--json"],2).stdout).error.includes(code),code + ": " + run([...librarySourceArgs,...flags,"--dry-run","--json"],2).stdout);
  put("library-choice.scm", '(pipeline (frontend-profile "moonbit-model-bool-v1"))');
  assert.equal(JSON.parse(run([...librarySourceArgs,"--config","library-choice.scm","--dry-run","--json"]).stdout).frontends[0].defaultProfile,true);
  assert.equal(JSON.parse(run([...librarySourceArgs,"--config","library-choice.scm","--frontend-profile",libraryProfile,"--frontend-provider",sourceProvider,"--dry-run","--json"]).stdout).frontends[0].profile,libraryProfile);
  const sourceLibrary = 'fn helper(x : Bool) -> Bool { !x }\npub fn eligible(x : Bool) -> Bool { let y = helper(x); y }\npub fn zero() -> Bool { eligible(false) }';
  put("moon-library/src/Main.mbt",sourceLibrary);
  const librarySourceResult = JSON.parse(run([...librarySourceArgs,"--json"]).stdout);
  assert.equal(librarySourceResult.successful,true);
  const librarySourceRoot = join(directory,"moon-library/.morphir/out/compile.dest");
  const savedLibrarySource = readFileSync(join(librarySourceRoot,"Main.ionb"));
  assert.deepEqual([...savedLibrarySource.subarray(0,4)],[224,1,0,234]);
  assert.ok(!existsSync(join(directory,"moon-library/.morphir/logs")));
  const loss = JSON.parse(run([...librarySourceArgs,"--checkpoint-format","morphir-json","--json"],1).stdout);
  assert.match(loss.diagnostics[0].message,/data.lossy_conversion/);
  assert.deepEqual(loss.committed,[]);
  assert.deepEqual(readFileSync(join(librarySourceRoot,"Main.ionb")),savedLibrarySource);
  run([...librarySourceArgs,"--checkpoint-format","ion-text","--json"]);
  const librarySourceIon = readFileSync(join(librarySourceRoot,"Main.ion"),"utf8");
  assert.match(librarySourceIon,/moonbit-model-bool-library-v1/);
  assert.match(librarySourceIon,/binding/);
  assert.match(librarySourceIon,/call/);
  const libraryCalls = [
    {id:"eligible",entry:"library-model:app/main#eligible",arguments:[{type:"bool",value:false}]},
    {id:"zero",entry:"library-model:app/main#zero",arguments:[]},
  ];
  put("library-calls.json",JSON.stringify({profile:"morphir-invocations-v1",calls:libraryCalls}));
  const executableEntries = JSON.parse(run(["execute","moon-library/.morphir/out/compile.dest/Main.ion","--unit-id","Main","--suite","library-calls.json","--dry-run","--json"]).stdout);
  assert.deepEqual(executableEntries.entries,libraryCalls.map(c=>c.entry));
  put("library-private.json",JSON.stringify({profile:"morphir-invocations-v1",calls:[{id:"hidden",entry:"library-model:app/main#helper",arguments:[{type:"bool",value:false}]}]}));
  const privateEntry = JSON.parse(run(["execute","moon-library/.morphir/out/compile.dest/Main.ion","--unit-id","Main","--suite","library-private.json","--dry-run","--json"],2).stdout);
  assert.match(privateEntry.error,/execution.entry_not_public_or_supported/);
  if (target !== "wasm") {
    const compiledSourceLibrary = JSON.parse(run([...librarySourceArgs,"--backend","moonbit","--validation","required","--build-provider","process","--build-helper",buildHelper,"--build-node",process.execPath,"--home",tooling.home,"--sdk",join(workspaceDirectory,"pkgs/morphir-sdk"),"--target","wasm","--json"]).stdout);
    assert.equal(compiledSourceLibrary.validated.length,1);
  }
  run([...librarySourceArgs,"--backend","moonbit","--validation","source-only","--json"]);
  const libraryGenerated = readFileSync(join(librarySourceRoot,"Main/library.mbt"),"utf8");
  assert.equal((libraryGenerated.match(/pub fn/g)||[]).length,2);
  assert.equal((libraryGenerated.match(/^fn /gm)||[]).length,1);
  put("moon-library/src/Main.mbt", 'pub fn bad(x : Bool) -> Bool { bad(x) }');
  const libraryRejected = JSON.parse(run([...librarySourceArgs,"--json"],1).stdout);
  assert.match(libraryRejected.diagnostics[0].message,/^moonbit_frontend\.recursive_call:.*provider finos\/morphir-moonbit-frontend; profile moonbit-model-bool-library-v1.* at 1:/);
  assert.equal(readFileSync(join(librarySourceRoot,"Main/library.mbt"),"utf8"),libraryGenerated);
  put("moon-library/src/Main.mbt", 'fn hidden() -> Bool { true }');
  run([...librarySourceArgs,"--backend","moonbit","--validation","source-only","--json"]);
  assert.ok(!readFileSync(join(librarySourceRoot,"Main/library.mbt"),"utf8").includes('pub fn'));
  const languageList=JSON.parse(run(["project","list","moon-library","--frontend","moonbit","--json"]).stdout);
  assert.equal(languageList.projects[0].frontend,"moonbit");
  assert.deepEqual(JSON.parse(run(["project","list","moon-library","--frontend","moonbit-library","--json"]).stdout).projects,[]);
  for (const [name,profile,source,marker] of [
    ['typed-foundation','moonbit-model-typed-library-foundation-v1','pub fn choose(flag : Bool, a : Int32, b : Int) -> Int32 { let value : Int = if flag { a } else { b }; identity(value) }\nfn identity(value : Int32) -> Int { value }','signed-32'],
    ['numeric-int32','moonbit-model-int32-library-v1','pub fn wrap() -> Int32 { 2147483647 + 1 }','moonbit-source-number-v1'],
    ['string-basics','moonbit-model-string-library-v1','fn prefix() -> String { "Hello, " }\npub fn greet(name : String) -> String { let greeting : String = prefix(); greeting + name }\npub fn welcome(name : String, enabled : Bool) -> String { if enabled { greet(name) } else { "" } }','well-formed-utf16'],
    ['supported-library','moonbit-model-library-v1',"pub fn choose_for(name : String, enabled : Bool, first : Int32, second : Int) -> Int32 { let greeting : String = if enabled { \"Hello, \" + name } else { \"\" }; if greeting == \"Hello, Morphir\" { first } else { second } }",'signed-32'],
    ['ordered-library','moonbit-model-library-v2','pub fn choose(a : String, b : String, x : Int32, y : Int) -> Int32 { if a < b && a <= b && !(a > b) && !(a >= b) { x } else { y } }','utf16-shortlex'],
    ['dated-library','moonbit-model-library-2026-10-17','/// Choose by shortlex name order.\n///\n/// Preserve the exact signed value. λ😀\npub fn choose(a : String, b : String, x : Int32, y : Int) -> Int32 { if a < b { x } else { y } }','utf16-shortlex'],
    ['indexed-library','moonbit-model-library-2026-10-19','pub fn cut(s : String, start : Int32, end : Int32) -> String { s[start:end].to_owned() }\npub fn count(s : String) -> Int32 { s.length() }\npub fn count_cut(s : String, start : Int32, end : Int32) -> Int32 { cut(s, start, end).length() + start }','moonbit-source-string-index-v1'],
  ] as const) {
    put(name+'/morphir.toml','[project]\nname="'+name+'"\n[frontend]\nlanguage="moonbit"\nprofile="'+profile+'"\n[pipeline]\nbackend="checkpoint"\n');
    put(name+'/src/Main.mbt',source);
    const args=['run',name];
    const checkpoint=JSON.parse(run([...args,'--checkpoint-format','ion-text','--json']).stdout);
    assert.equal(checkpoint.successful,true);
    const out=join(directory,name,'.morphir/out/compile.dest');
    const ion=readFileSync(join(out,'Main.ion'),'utf8');
    assert.ok(ion.includes(profile));assert.ok(ion.includes(marker));
    const loss=JSON.parse(run([...args,'--checkpoint-format','morphir-json','--json'],1).stdout);
    assert.match(loss.diagnostics[0].message,/data.lossy_conversion/);
    assert.deepEqual(loss.committed,[]);
    assert.equal(JSON.parse(run([...args,'--backend','scheme','--validation','source-only','--json']).stdout).successful,true);
    assert.equal(JSON.parse(run([...args,'--backend','moonbit','--validation','source-only','--json']).stdout).successful,true);
    const generated=readFileSync(join(out,'Main/library.mbt'),'utf8');
    if(name==='dated-library') { assert.ok(ion.includes('Choose by shortlex name order.')); assert.ok(generated.includes('/// Choose by shortlex name order.\n///\n/// Preserve the exact signed value. λ😀')); }
    if(name==='indexed-library') { assert.ok(ion.includes('moonbit-source-number-v1')); assert.ok(generated.includes('@source_int32.normalize')); assert.ok(generated.includes('@source_string.slice_owned')); }
    if(name==='supported-library'||name==='ordered-library'||name==='dated-library')assert.ok(ion.includes('well-formed-utf16'));
    if(name==='string-basics'||name==='supported-library'||name==='ordered-library'||name==='dated-library'||name==='indexed-library')assert.ok(generated.includes('@source_string.require_valid'));
    if(target!=='wasm') {
      const built=JSON.parse(run([...args,'--backend','moonbit','--validation','required','--build-provider','process','--build-helper',buildHelper,'--build-node',process.execPath,'--home',tooling.home,'--sdk',join(workspaceDirectory,'pkgs/morphir-sdk'),'--target','wasm','--json']).stdout);
      assert.equal(built.validated.length,1);
    }
  }
  // An unchanged morphir-elm project compiles with the Elm provider that the CLI registers.
  const elmCorpus = join(workspaceDirectory, "pkgs/morphir-elm/conformance/projects/modules");
  mkdirSync(join(directory, "elm-modules"), {recursive: true});
  cpSync(join(elmCorpus, "morphir.json"), join(directory, "elm-modules/morphir.json"));
  cpSync(join(elmCorpus, "src"), join(directory, "elm-modules/src"), {recursive: true});
  const elmPlan = JSON.parse(run(["run", "elm-modules", "--dry-run", "--json"]).stdout);
  const elmFrontend = elmPlan.frontends[0];
  assert.equal(elmFrontend.language, "elm");
  assert.equal(elmFrontend.provider, "finos/morphir-elm");
  assert.equal(elmFrontend.profile, "library");
  assert.equal(elmFrontend.capabilities.maxDocuments, null);
  assert.ok(!existsSync(join(directory, "elm-modules/.morphir")));
  assert.equal(JSON.parse(run(["run", "elm-modules", "--json"]).stdout).successful, true);
  const elmIr = JSON.parse(readFileSync(join(directory, "elm-modules/.morphir/out/compile.dest/parity/modules.json"), "utf8"));
  assert.equal(typeof elmIr, "object");
  const generated = (backend: string, suffix: string) => {
    assert.equal(JSON.parse(run(["run", "elm-modules", "--backend", backend, "--validation", "source-only", "--json"]).stdout).successful, true);
    return readdirSync(join(directory, "elm-modules/.morphir/out"), {recursive: true}).filter(p => String(p).endsWith(suffix));
  };
  assert.ok(generated("elm", ".elm").length > 0);
  assert.ok(generated("moonbit", "library.mbt").length > 0);
  assert.match(run(["run", "elm-modules", "--backend", "ir-json", "--json"], 2).stdout, /frontend\.typed_backend_required/);
  assert.deepEqual(JSON.parse(run(["project", "list", "elm-modules", "--json"]).stdout).projects.map((p: {name: string;frontend: string;target: string}) => [p.name, p.frontend]), [["Parity.Modules", "elm"]]);
  const namingManifest='[project]\nname="Naming"\nmodule_prefix="App"\n[frontend]\nlanguage="moonbit"\nprofile="'+libraryProfile+'"\n[pipeline]\nbackend="checkpoint"\n';
  put("naming/morphir.toml",namingManifest);
  put("naming/src/Main.mbt",'pub fn is_ready() -> Bool { true }\npub fn isReady() -> Bool { false }');
  const namingResult=run(["run","naming","--json"]);
  const namingJson: PipelineReport=JSON.parse(namingResult.stdout);
  assert.equal(namingJson.successful,true);
  assert.equal(namingJson.warnings.length,1);
  const namingWarning=namingJson.warnings[0];
  assert.equal(namingWarning!.code,"moonbit_frontend.name_normalization_collision");
  assert.deepEqual(namingWarning!.locations.map(l=>l.original),["isReady","is_ready"]);
  assert.deepEqual(namingWarning!.locations.map(l=>l.allocated),["is-ready-source-69735265","is-ready"]);
  assert.deepEqual(namingWarning!.locations.map(l=>l.source.startLine),[2,1]);
  assert.ok(namingWarning!.fix.includes("is_ready_renamed_1"));
  assert.match(namingResult.stderr,/warning:.*name_normalization_collision/);
  assert.match(namingResult.stderr,/fix:/);
  assert.ok(!existsSync(join(directory,"naming/.morphir/logs")));
  const warningLines=lines(["run","naming"]);
  assert.equal(warningLines.filter(r=>r.type==="warning").length,1);
  assert.equal(warningLines.find(r=>r.type==="result").data.successful,true);
  const namingCheckpoint=join(directory,"naming/.morphir/out/compile.dest/Main.ionb");
  const namingSaved=readFileSync(namingCheckpoint);
  put("naming/morphir.toml",namingManifest+'strict_naming=true\n');
  const namingStrict=JSON.parse(run(["run","naming","--json"],1).stdout);
  assert.equal(namingStrict.warnings.length,1);
  assert.equal(namingStrict.successful,false);
  assert.match(namingStrict.diagnostics[0].message,/naming.strict/);
  assert.deepEqual(namingStrict.committed,[]);
  assert.deepEqual(readFileSync(namingCheckpoint),namingSaved);
  put("naming/src/Main.mbt",'pub fn readyλ() -> Bool { true }');
  const lexicalRejected=JSON.parse(run(["run","naming","--json"],1).stdout);
  assert.match(lexicalRejected.diagnostics[0].message,/moonbit_frontend\.syntax: Lexing error/);
  assert.deepEqual(lexicalRejected.committed,[]);
  assert.deepEqual(readFileSync(namingCheckpoint),namingSaved);
  // Checkpoints use the same source selection and private publication lifecycle.
  // No toolchain home is configured, and generation does not invoke acquisition.
  put("checkpoints/morphir.toml", '[project]\nname="Pricing"\n[frontend]\nlanguage="ir-json"\n[pipeline]\nbackend="checkpoint"\n');
  put("checkpoints/src/Main.json", '{"formatVersion":3,"distribution":["Library",[["pricing"]],[],{"modules":[]}]}');
  const checkpointArgs = ["run", "checkpoints"];
  const checkpointPlan = JSON.parse(run([...checkpointArgs, "--dry-run", "--json"]).stdout);
  assert.deepEqual(checkpointPlan.sources, ["src/Main.json"]);
  assert.equal(checkpointPlan.boundaries[0].inputFormat, "morphir-json");
  assert.equal(checkpointPlan.boundaries[0].outputFormat, "ion-binary");
  assert.equal(checkpointPlan.boundaries[0].profile, "morphir-pipeline-v1");
  assert.equal(checkpointPlan.boundaries[0].readBytes, false);
  assert.equal(checkpointPlan.boundaries[0].writeBytes, true);
  assert.ok(!existsSync(join(directory, "checkpoints/.morphir/out")));
  const binaryResult = JSON.parse(run([...checkpointArgs, "--json"]).stdout);
  assert.equal(binaryResult.successful, true);
  assert.equal(binaryResult.artifactDetails[0].encoding, "binary");
  assert.equal(binaryResult.artifactDetails[0].status, "accepted");
  assert.equal(binaryResult.committed.length, 1);
  const checkpointRoot = join(directory, "checkpoints/.morphir/out/compile.dest");
  const binary = readFileSync(join(checkpointRoot, "Main.ionb"));
  assert.deepEqual([...binary.subarray(0,4)], [0xe0, 0x01, 0x00, 0xea]);
  // Read the real binary file without interpreting it as UTF-8.
  put("checkpoints/src/Main.ionb", binary);
  rmSync(join(directory, "checkpoints/src/Main.json"));
  const textResult = JSON.parse(run([...checkpointArgs, "--frontend", "ion-binary", "--backend", "checkpoint", "--checkpoint-format", "ion-text", "--json"]).stdout);
  assert.equal(textResult.boundaries[0].readBytes, true);
  assert.equal(textResult.boundaries[0].writeBytes, false);
  assert.equal(textResult.artifactDetails[0].encoding, "text");
  const ionText = readFileSync(join(checkpointRoot, "Main.ion"), "utf8");
  assert.match(ionText, /morphir_pipeline::/);
  assert.match(ionText, /formatVersion: 4/);
  assert.ok(!existsSync(join(checkpointRoot, "Main.ionb")));
  put("checkpoints/src/Main.ion", ionText);
  rmSync(join(directory, "checkpoints/src/Main.ionb"));
  const checkpointRecords = lines([...checkpointArgs, "--frontend", "ion-text"]);
  assert.equal(checkpointRecords.find(r => r.type === "boundary").data.inputFormat, "ion-text");
  assert.equal(checkpointRecords.find(r => r.type === "accepted").data.format, "ion-binary");
  assert.equal(checkpointRecords.filter(r => r.type === "committed").length, 1);
  assert.deepEqual(readFileSync(join(checkpointRoot, "Main.ionb")), binary);
  const humanCheckpoint = run([...checkpointArgs, "--frontend", "ion-text"]).stdout;
  assert.match(humanCheckpoint, /ion-text -> ion-binary/);
  assert.match(humanCheckpoint, /Accepted .*Main\.ionb/);
  assert.match(humanCheckpoint, /Published .*compile\.dest/);
  // JSON remains a supported explicit export format.
  const jsonCheckpoint = JSON.parse(run([...checkpointArgs, "--frontend", "ion-text", "--checkpoint-format", "morphir-json", "--json"]).stdout);
  assert.equal(jsonCheckpoint.artifactDetails[0].format, "morphir-json");
  assert.equal(JSON.parse(readFileSync(join(checkpointRoot,"Main.json"),"utf8")).formatVersion,4);
  // Rich annotations remain intact through real text/binary files.
  const richIon = ionText.replace("morphir_pipeline::", "morphir_pipeline::audit::")
    .replace("metadata: []", 'metadata: [{node_id:"node:1",data:tag::tag::unknown::{price:12.340d0,blob:{{/wCA}},nothing:null.int}}]');
  put("checkpoints/src/Main.ion", richIon);
  run([...checkpointArgs,"--frontend","ion-text"]);
  const richBinary = readFileSync(join(checkpointRoot,"Main.ionb"));
  put("checkpoints/src/Main.ionb",richBinary);
  rmSync(join(directory,"checkpoints/src/Main.ion"));
  run([...checkpointArgs,"--frontend","ion-binary","--checkpoint-format","ion-text"]);
  const richText = readFileSync(join(checkpointRoot,"Main.ion"),"utf8");
  assert.match(richText,/morphir_pipeline::audit::/);
  assert.match(richText,/tag::tag::unknown::/);
  assert.match(richText,/price: 12\.340(?:d0)?,/);
  assert.match(richText,/null.int/);
  const lossy = JSON.parse(run([...checkpointArgs,"--frontend","ion-binary","--checkpoint-format","morphir-json","--json"],1).stdout);
  assert.equal(lossy.successful,false);
  assert.deepEqual(lossy.committed,[]);
  assert.match(lossy.diagnostics[0].message,/data.lossy_conversion/);
  assert.equal(readFileSync(join(checkpointRoot,"Main.ion"),"utf8"),richText);
  put("checkpoints/src/Main.ionb",Buffer.from([0xe0,0x01,0x00,0xea,0xff]));
  const malformed = JSON.parse(run([...checkpointArgs,"--frontend","ion-binary","--json"],1).stdout);
  assert.equal(malformed.successful,false);
  assert.deepEqual(malformed.committed,[]);
  assert.equal(readFileSync(join(checkpointRoot,"Main.ion"),"utf8"),richText);
  put("checkpoints/src/Main.ionb",richBinary);
  put("checkpoints/src/Main.10n",richBinary);
  assert.match(run([...checkpointArgs,"--frontend","ion-binary","--dry-run"],2).stderr,/Duplicate output path/);
  rmSync(join(directory,"checkpoints/src/Main.10n"));
  // A held publisher lock prevents binary replacement and preserves previous files.
  mkdirSync(join(directory,"checkpoints/.morphir/out/.morphir-publish.lock"));
  const busy = JSON.parse(run([...checkpointArgs,"--frontend","ion-binary","--json"],1).stdout);
  assert.equal(busy.artifactDetails.length,1);
  assert.deepEqual(busy.committed,[]);
  assert.ok(busy.publicationError);
  assert.equal(readFileSync(join(checkpointRoot,"Main.ion"),"utf8"),richText);
  rmSync(join(directory,"checkpoints/.morphir/out/.morphir-publish.lock"),{recursive:true});
  assert.match(run([...checkpointArgs,"--checkpoint-format","bogus"],2).stderr,/data.unknown_codec/);
  // A file/directory collision is rejected during planning, preserving the old task.
  const simpleJson = '{"formatVersion":3,"distribution":["Library",[["pricing"]],[],{"modules":[]}]}';
  put("checkpoints/src/Main.json",simpleJson);
  rmSync(join(directory,"checkpoints/src/Main.ionb"));
  put("checkpoints/src/Main.ionb/Nested.json",simpleJson);
  const stagingFailure = JSON.parse(run([...checkpointArgs,"--frontend","ir-json","--json"],2).stdout);
  assert.match(stagingFailure.error,/Duplicate output path/);
  assert.deepEqual(stagingFailure.committed,[]);

  assert.equal(readFileSync(join(checkpointRoot,"Main.ion"),"utf8"),richText);
  assert.ok(!existsSync(join(directory,"checkpoints/.morphir/out/.morphir-publish.lock")));

  // Complete library generation uses the same byte, component and publication lifecycle.
  put("libraries/morphir.toml", "[project]\nname='Pricing'\n[frontend]\nlanguage='ir-json'\n[pipeline]\nbackend='moonbit'\nvalidation='source-only'\n");
  put("libraries/src/Main.json",simpleJson);
  const libraryArgs=["run","libraries","--backend","moonbit","--validation","source-only","--component","json-identity"];
  const libraryPlan=JSON.parse(run([...libraryArgs,"--dry-run","--json"]).stdout);
  assert.equal(libraryPlan.components[0].transport,"morphir-json");
  assert.equal(libraryPlan.boundaries[0].outputFormat,"moonbit");
  const library=JSON.parse(run([...libraryArgs,"--json"]).stdout);
  assert.equal(library.successful,true);assert.equal(library.projects.length,1);assert.equal(library.artifacts.length,4);
  assert.equal(library.validated.length,0);assert.equal(library.publicationDetails[0].status,"published");
  const libraryRoot=join(directory,"libraries/.morphir/out/compile.dest/Main");
  assert.deepEqual(readdirSync(libraryRoot).sort(),["library.mbt","moon.mod","moon.pkg","symbols.10n"]);
  put("libraries/.morphir/out/compile.dest/Main/stale.mbt","stale");
  put("libraries/.morphir/out/compile.dest/Main/build-receipt.ionb","stale receipt");
  const libraryLines=lines(libraryArgs);
  assert.equal(libraryLines.filter(r=>r.type==="generated").length,1);
  assert.equal(libraryLines.filter(r=>r.type==="validated").length,0);
  assert.equal(libraryLines.filter(r=>r.type==="published").length,1);
  assert.ok(!existsSync(join(libraryRoot,"stale.mbt")));assert.ok(!existsSync(join(libraryRoot,"build-receipt.ionb")));
  const libraryBefore=readFileSync(join(libraryRoot,"symbols.10n"));
  put("libraries/src/Bad.json","malformed");
  const failedLibrary=JSON.parse(run([...libraryArgs,"--json"],1).stdout);
  assert.equal(failedLibrary.successful,false);assert.deepEqual(failedLibrary.committed,[]);
  assert.deepEqual(readFileSync(join(libraryRoot,"symbols.10n")),libraryBefore);
  rmSync(join(directory,"libraries/src/Bad.json"));
  // Current JSON and historical JSON both enter Ion checkpoints and buildable source.
  const checkpointLibrary=["run","libraries","--backend","checkpoint","--checkpoint-format","ion-text"];
  run(checkpointLibrary);
  const libraryIonPath=join(directory,"libraries/.morphir/out/compile.dest/Main.ion");
  const libraryIon=readFileSync(libraryIonPath,"utf8").replace("metadata: []",'metadata: [{node_id:"unit:Main",data:tag::tag::{amount:12.340d0,blob:{{/wCA}},nil:null.int}}]');
  put("libraries/src/Main.ion",libraryIon);rmSync(join(directory,"libraries/src/Main.json"));
  run([...libraryArgs,"--frontend","ion-text"]);
  const richSymbols=readFileSync(join(libraryRoot,"symbols.10n"));
  run([...checkpointLibrary,"--frontend","ion-text","--checkpoint-format","ion-binary"]);
  put("libraries/src/Main.ionb",readFileSync(join(directory,"libraries/.morphir/out/compile.dest/Main.ionb")));
  rmSync(join(directory,"libraries/src/Main.ion"));
  run([...libraryArgs,"--frontend","ion-binary"]);
  assert.deepEqual(readFileSync(join(libraryRoot,"symbols.10n")),richSymbols);
  const required=[...libraryArgs,"--frontend","ion-binary","--validation","required"];
  const unsupported=JSON.parse(run([...required,"--json"],1).stdout);
  assert.match(unsupported.publicationError,/build.provider_required/);assert.deepEqual(unsupported.committed,[]);
  assert.deepEqual(readFileSync(join(libraryRoot,"symbols.10n")),richSymbols);
  if(target!=="wasm") {
    const provider=["--build-provider","process","--build-helper",buildHelper,"--build-node",process.execPath,"--home",tooling.home,"--sdk",join(workspaceDirectory,"pkgs/morphir-sdk"),"--target","wasm"];
    const builtLibrary=JSON.parse(run([...required,...provider,"--json"]).stdout);
    assert.equal(builtLibrary.successful,true);assert.equal(builtLibrary.validated.length,1);
    assert.equal(builtLibrary.artifacts.length,5);assert.ok(existsSync(join(libraryRoot,"build-receipt.ionb")));
    const builtBefore=readFileSync(join(libraryRoot,"build-receipt.ionb"));
    const compilerFailure=JSON.parse(run([...required,...provider,"--sdk",join(directory,"absent-sdk"),"--json"],1).stdout);
    assert.equal(compilerFailure.successful,false);assert.deepEqual(compilerFailure.committed,[]);
    assert.deepEqual(readFileSync(join(libraryRoot,"build-receipt.ionb")),builtBefore);
    const timedOut=JSON.parse(run([...required,...provider,"--timeout","20","--json"],1).stdout);
    assert.equal(timedOut.successful,false);assert.deepEqual(timedOut.committed,[]);
    assert.deepEqual(readFileSync(join(libraryRoot,"build-receipt.ionb")),builtBefore);
    run([...libraryArgs,"--frontend","ion-binary"]);
    assert.ok(!existsSync(join(libraryRoot,"build-receipt.ionb")));
  }

  // A morphir-elm morphir.json still passes through the new CLI.
  const legacy = join(directory, "legacy");
  put("legacy/morphir.json", '{"name":"Legacy","sourceDirectory":"src","exposedModules":["Main"]}');
  put("legacy/src/Legacy/Main.elm", 'module Legacy.Main exposing (answer)\n\n\nanswer : Int\nanswer =\n    42\n');
  // Keep the legacy project independent of its enclosing test workspace.
  run(["run", "--dry-run"], 0, legacy);
  assert.equal(JSON.parse(run(["project", "list", "--json"], 0, legacy).stdout).projects[0].name, "Legacy");
  assert.equal(JSON.parse(run(["project", "list", "--json"], 0, legacy).stdout).projects[0].frontend, "elm");
  // A morphir.json is always a morphir-elm project, and morphir-elm requires exposedModules.
  const legacyElm = join(directory, "legacy-elm");
  put("legacy-elm/morphir.json", '{"name":"Legacy","sourceDirectory":"src"}');
  assert.match(run(["run", "--dry-run", "--json"], 2, legacyElm).stdout, /exposedModules must be a list of module names/);
  console.log(`CLI workspace integration passed: ${target}`);
}

if (selected.some(target => target === 'js' || target === 'native')) {
  execFileSync(process.execPath, ['--experimental-transform-types', '--test',
    join(appDirectory, 'scripts/test-connected-session.ts')], {
    cwd: workspaceDirectory, stdio: 'inherit', timeout: 30000,
  });
}

// The sidecar verifier is pure and runs separately from the selected CLI host.
execFileSync('moon', ['build', 'pkgs/morphir-engine/acceptance/retained-generation', 'pkgs/morphir-host/connected-core', '--target', 'js', '--release'], {
  cwd: workspaceDirectory, stdio: 'inherit',
});
mkdirSync(join(appDirectory, 'dist'), { recursive: true });
copyFileSync(join(workspaceDirectory, '_build/js/release/build/finos/morphir-host/connected-core/connected-core.js'), join(appDirectory, 'dist/connected-core.js'));
if (process.env.MORPHIR_WORKBENCH_LIVE_HOST && selected.some(target => target === 'js' || target === 'native')) {
  execFileSync('moon', ['build', 'apps/morphir-workbench/execution-host', 'apps/morphir-workbench/worker', '--target', 'js', '--release'], {
    cwd: workspaceDirectory, stdio: 'inherit',
  });
}
for (const target of selected) {
  assert.ok(targets.includes(target), `Unknown target: ${target}`);
  let admittedNative;
  if (target === "native" && process.env.MORPHIR_CI_NATIVE) {
    const artifact = JSON.parse(execFileSync("moon", ["run", "scripts/ci-artifact.mbtx", "verify", "native-cli", process.env.MORPHIR_CI_NATIVE], {cwd: workspaceDirectory, encoding: "utf8"}));
    assert.equal(artifact.metadata.buildMode, "release");
    admittedNative = join(artifact.directory, "morphir-native");
  } else {
    // Moon's Windows native backend uses an MSVC-compatible driver. The generated
    // CLI exceeds the standard COFF section limit; CL preserves Moon's default flags.
    const env = target === "native" && process.platform === "win32"
      ? { ...process.env, CL: `/bigobj ${process.env.CL ?? ""}`.trim() }
      : process.env;
    execFileSync("moon", ["build", ".", "--target", target, "--release"], {cwd: appDirectory, stdio:"inherit", env});
  }
  const artifactDirectory = join(workspaceDirectory, "_build", target, "release/build/morphir/morphir");
  const directory = mkdtempSync(join(tmpdir(), "morphir-cli-"));
  try {
    if (!headlessOnly && target === "native") exercise(admittedNative || join(artifactDirectory,"morphir.exe"), [], directory, target);
    else if (!headlessOnly && target === "js") exercise(process.execPath, [join(artifactDirectory,"morphir.js")], directory, target);
    else if (!headlessOnly) {
      const artifact = join(artifactDirectory,"morphir.wasm");
      if (target === "wasm") {
        const module = await WebAssembly.compile(readFileSync(artifact));
        assert.ok(WebAssembly.Module.imports(module).every(i => i.module === "wasi_snapshot_preview1"));
      }
      exercise(process.execPath, [runner,artifact], directory, target);
    }
    const binary = admittedNative || join(artifactDirectory, target === 'native' ? 'morphir.exe' : target === 'js' ? 'morphir.js' : 'morphir.wasm');
    let headlessLauncher;
    if (target === 'js') {
      // Use the production effect adapter with this run's selected artifact.
      // The packed-package lane below uses the actual installed launcher.
      headlessLauncher = join(directory, 'headless-launcher.mjs');
      const workerHost = pathToFileURL(join(workspaceDirectory, 'pkgs/morphir-host/runners/terminal-worker.mjs')).href;
      writeFileSync(headlessLauncher, `import {terminalWorker} from ${JSON.stringify(workerHost)};\nif (!terminalWorker(new URL(import.meta.url),process.argv.slice(2))) await import(${JSON.stringify(pathToFileURL(binary).href)});\n`);
    }
    headlessAcceptance(target, binary, headlessLauncher);
  } finally { rmSync(directory, {recursive:true,force:true}); }
}

if (selected.includes("js")) {
  assert.ok(npmCli, "Run this script with npm test");
  const directory = mkdtempSync(join(tmpdir(), "morphir-npm-"));
  const npm = (args: string[], cwd: string) => execFileSync(process.execPath,
    [npmCli,"--cache",join(directory,"cache"),...args], {cwd,encoding:"utf8"});
  try {
    npm(["pack","--pack-destination",directory], appDirectory);
    const tarball = readdirSync(directory).find(p => p.endsWith(".tgz"));
    assert.ok(tarball);
    npm(["install","--prefix",directory,"--ignore-scripts","--no-audit","--no-fund","--offline",join(directory,tarball)],directory);
    checkHelp(npm(["exec","--prefix",directory,"--offline","--","morphir","--help"], directory));
    assert.ok(existsSync(join(directory,"node_modules/@morphir/morphir/build-provider/library-build.mjs")));
    const installed = join(directory,"node_modules/@morphir/morphir/bin/morphir.js");
    const fixture = join(directory,"fixture");
    mkdirSync(fixture);
    if (!headlessOnly) exercise(process.execPath,[installed],fixture,"npm",join(directory,"node_modules/@morphir/morphir/build-provider/library-build.mjs"));
    const installedRoot = join(directory, 'node_modules/@morphir/morphir');
    headlessAcceptance('js', join(installedRoot, 'dist/morphir.js'), installed, installedRoot);
    console.log("Installed npm package integration passed");
  } finally { rmSync(directory,{recursive:true,force:true}); }
}
