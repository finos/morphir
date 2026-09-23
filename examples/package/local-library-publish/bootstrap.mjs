// Tutorial-only public TUF root and trust-policy documents. Never reads seed files.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

function keyInfo(path) {
  const info = JSON.parse(readFileSync(path, 'utf8'));
  if (!/^[a-f0-9]{64}$/.test(info.keyId) || !/^[a-f0-9]{64}$/.test(info.publicKey)) {
    throw new Error(`invalid public key information in ${path}`);
  }
  return info;
}

const [mode, ...args] = process.argv.slice(2);
if (mode === 'expiry' && args.length === 0) {
  const yearFromNow = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
  process.stdout.write(`${yearFromNow.toISOString().replace(/\.\d{3}Z$/, 'Z')}\n`);
} else if (mode === 'root' && args.length === 5) {
  const [expires, ...paths] = args;
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(expires)) {
    throw new Error('root expiry must be an RFC 3339 UTC timestamp');
  }
  const [root, targets, snapshot, timestamp] = paths.map(keyInfo);
  const role = (key) => ({ keyids: [key.keyId], threshold: 1 });
  const keys = Object.fromEntries([root, targets, snapshot, timestamp].map((key) => [key.keyId, key.tufKey]));
  process.stdout.write(`${JSON.stringify({
    _type: 'root',
    spec_version: '1.0.36',
    version: 1,
    expires,
    consistent_snapshot: true,
    keys,
    roles: { root: role(root), targets: role(targets), snapshot: role(snapshot), timestamp: role(timestamp) },
  }, null, 2)}\n`);
} else if (mode === 'policy' && args.length === 2) {
  const [rootPath, publisherInfoPath] = args;
  const digest = `sha256:${createHash('sha256').update(readFileSync(rootPath)).digest('hex')}`;
  const publisher = keyInfo(publisherInfoPath);
  process.stdout.write(`${JSON.stringify({
    formatVersion: '0.1.0-draft.3',
    kind: 'LibraryTrustPolicy',
    repositories: [{ identity: digest, bootstrapRoot: { version: 1, digest }, namespaces: ['example.com'] }],
    publisherRules: [{ namespace: 'example.com', publicKeys: [publisher.publicKey], threshold: 1 }],
    continuedUse: 'fresh-metadata',
  }, null, 2)}\n`);
} else {
  process.stderr.write('usage: node bootstrap.mjs expiry\n');
  process.stderr.write('   or: node bootstrap.mjs root EXPIRY ROOT_INFO TARGETS_INFO SNAPSHOT_INFO TIMESTAMP_INFO\n');
  process.stderr.write('   or: node bootstrap.mjs policy SIGNED_ROOT PUBLISHER_INFO\n');
  process.exitCode = 2;
}
