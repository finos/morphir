import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../../../', import.meta.url));
const binary = resolve(process.env.MORPHIR_HEADLESS_BINARY ?? join(repository, '_build/native/debug/build/morphir/morphir/morphir.exe'));
const guest = resolve(process.env.MORPHIR_NATIVE_GUEST ?? join(repository, '_build/native/release/build/finos/morphir-extension/morphir-extension.exe'));
const adapter = resolve(process.env.MORPHIR_NATIVE_SERVICES ?? join(repository, '.dev/native-services/target/debug/morphir-moonbit-native-services'));
const nextGuest = resolve(join(adapter, '../native-catalog-v2'));
const helper = join(repository, 'apps/morphir/build-provider/native-services.mjs');
const sha256 = (file: string) => createHash('sha256').update(readFileSync(file)).digest('hex');
const root = mkdtempSync(join(tmpdir(), 'morphir-local-extension-lifecycle-'));
const home = join(root, 'home');
mkdirSync(join(root, 'temporary'));
const controls = ['--services-pin', 'services.json', '--services-helper', helper, '--home', home, '--json'];
const invoke = (args: string[], status = 0) => {
  const child = spawnSync(binary, [...args, ...controls], { cwd: root, env: { ...process.env, TMPDIR: join(root, 'temporary') }, encoding: 'utf8', timeout: 45000 });
  assert.equal(child.status, status, `${JSON.stringify(args)}\n${child.stdout}\n${child.stderr}`);
  const report = JSON.parse(child.stdout);
  assert.equal(report.profile, 'morphir/command-result');
  assert.equal(report.exitCode, status);
  assert.equal(report.state, status === 0 ? 'succeeded' : 'failed');
  assert.deepEqual(readdirSync(join(root, 'temporary')), [], 'owned temporary storage is released');
  return report;
};
try {
  writeFileSync(join(root, 'services.json'), JSON.stringify({ executable: adapter, sha256: sha256(adapter), sourceRevision: 'ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409' }));
  assert.deepEqual(invoke(['extension', 'list']).result, []);
  invoke(['extension', 'repository', 'init', 'repository']);
  invoke(['extension', 'repository', 'add', 'local', '--directory', 'repository']);
  const platform = process.platform === 'darwin' ? `${process.arch === 'arm64' ? 'aarch64' : 'x86_64'}-apple-darwin` : `${process.arch === 'arm64' ? 'aarch64' : 'x86_64'}-unknown-linux-gnu`;
  const bundle = invoke(['extension', 'bundle', '--executable', guest, '--sha256', sha256(guest), '--extension-id', 'morphir-moonbit', '--short-id', 'moonbit', '--version', '0.1.0', '--platform', platform, '--output', 'bundle']);
  assert.equal(bundle.result.bundle.descriptor.artifacts[0].sha256, sha256(guest));
  assert.deepEqual(readFileSync(join(root, 'bundle', guest.split('/').at(-1)!)), readFileSync(guest));
  invoke(['extension', 'repository', 'publish', 'bundle', '--repository', 'local']);
  assert.equal(invoke(['extension', 'search', 'moonbit']).result.length, 1);
  const installed = invoke(['extension', 'install', 'morphir-moonbit', '--repository', 'local', '--version', '0.1.0']);
  assert.equal(installed.result.installed.version, '0.1.0');
  assert.equal(installed.result.installed.claimCheck, 'probed');
  const inventory = invoke(['extension', 'list']).result;
  assert.equal(inventory.length, 1);
  assert.equal(inventory[0].verified, true);
  assert.ok(JSON.stringify(inventory[0]).includes(sha256(guest)));
  const configured = invoke(['extension', 'repository', 'inspect', 'local']).result;
  assert.equal(configured.name, 'local');
  cpSync(join(root, 'bundle'), join(root, 'corrupt-bundle'), { recursive: true });
  writeFileSync(join(root, 'corrupt-bundle', guest.split('/').at(-1)!), 'corrupt executable');
  invoke(['extension', 'repository', 'publish', 'corrupt-bundle', '--repository', 'local'], 1);
  assert.deepEqual(invoke(['extension', 'list']).result, inventory);
  invoke(['extension', 'repository', 'disable', 'local']);
  assert.deepEqual(invoke(['extension', 'search', 'moonbit']).result, []);
  invoke(['extension', 'update', 'morphir-moonbit', '--repository', 'local', '--version', '0.1.0'], 1);
  assert.deepEqual(invoke(['extension', 'list']).result, inventory);
  invoke(['extension', 'repository', 'enable', 'local']);
  invoke(['extension', 'bundle', '--executable', nextGuest, '--sha256', sha256(nextGuest), '--extension-id', 'morphir-moonbit', '--short-id', 'moonbit', '--version', '0.1.1', '--platform', platform, '--output', 'bundle-v2']);
  const published = invoke(['extension', 'repository', 'publish', 'bundle-v2', '--repository', 'local']).result;
  const stored = published.artifactPath;
  const historyPath = join(root, 'repository/extensions/morphir-moonbit.jsonl');
  const history = readFileSync(historyPath, 'utf8');
  const records = history.trimEnd().split('\n').map(line => JSON.parse(line));
  const candidate = records.find(record => record.version === '0.1.1');
  assert.ok(candidate, 'canonical repository retains the new release');
  candidate.artifacts[0].args = ['crash'];
  writeFileSync(historyPath, records.map(record => JSON.stringify(record)).join('\n') + '\n');
  invoke(['extension', 'update', 'morphir-moonbit', '--repository', 'local', '--version', '0.1.1'], 1);
  assert.deepEqual(invoke(['extension', 'list']).result, inventory, 'failed activation probe preserves old state');
  writeFileSync(historyPath, history);
  const frozen = readFileSync(stored);
  writeFileSync(stored, 'corrupt newly selected artifact');
  invoke(['extension', 'update', 'morphir-moonbit', '--repository', 'local', '--version', '0.1.1'], 1);
  assert.deepEqual(invoke(['extension', 'list']).result, inventory);
  writeFileSync(stored, frozen);
  const updated = invoke(['extension', 'update', 'morphir-moonbit', '--repository', 'local', '--version', '0.1.1']).result;
  assert.equal(updated.installed.version, '0.1.1');
  assert.ok(JSON.stringify(updated).includes(sha256(nextGuest)));
  assert.equal(invoke(['extension', 'list']).result[0].installed.version, '0.1.1');
  invoke(['extension', 'repository', 'verify', 'local']);
  // Offline inventory/activation does not reopen the repository.
  rmSync(join(root, 'repository'), { recursive: true });
  assert.equal(invoke(['extension', 'list']).result[0].verified, true);
  invoke(['extension', 'uninstall', 'morphir-moonbit']);
  assert.deepEqual(invoke(['extension', 'list']).result, []);
  invoke(['extension', 'repository', 'remove', 'local']);
  assert.deepEqual(invoke(['extension', 'repository', 'list']).result, []);
  const evidence = join(repository, '.dev/native-services');
  mkdirSync(evidence, { recursive: true });
  writeFileSync(join(evidence, 'local-lifecycle-evidence.json'), JSON.stringify({
    profile: 'morphir/cli/local-repository-acceptance', contractVersion: '0.1.0',
    platform, initialArtifactSha256: sha256(guest), updatedArtifactSha256: sha256(nextGuest),
    initialDescriptor: bundle.result.bundle.descriptor, initialInventory: inventory,
    updatedInstallation: updated, tested: ['fresh-home', 'canonical-bundle', 'publish-search-install', 'exact-inventory',
      'corrupt-bundle', 'disabled-repository', 'failed-activation-probe-preserves-old', 'corrupt-update-preserves-old',
      'version-update', 'offline-replay', 'uninstall-remove', 'temporary-cleanup'], installedQualification: 'not-run',
  }, null, 2) + '\n');
  console.log('local native repository lifecycle acceptance passed: exact pinned artifacts, canonical descriptors/probes, real version update, corruption/disabled/update preservation, offline replay and cleanup');
} finally { rmSync(root, { recursive: true, force: true }); }
