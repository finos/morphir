import assert from 'node:assert/strict';
import { lstat, mkdtemp, readdir, rm } from 'node:fs/promises';
import { join } from 'node:path';

export class NormalPackageExit {
  private constructor() {}
  static checked(exit: { code: number | null; signal: string | null }, quiescent: boolean): NormalPackageExit {
    assert.deepEqual({ code: exit.code, signal: exit.signal }, { code: 0, signal: null }, 'Profile cleanup requires normal package exit');
    assert.equal(quiescent, true, 'Profile cleanup requires confirmed owned-process quiescence');
    return new NormalPackageExit();
  }
}
export type TemporaryRetention = { kind: 'empty' }
  | { kind: 'preserved'; root: string; entries: [string, ...string[]] };
function temporaryRetention(root: string, names: string[]): TemporaryRetention {
  const [first, ...rest] = names;
  return first === undefined ? { kind: 'empty' } : { kind: 'preserved', root, entries: [first, ...rest] };
}
export type ProfileCleanup = {
  after: 'normal-entry-exit-and-owned-process-quiescence';
  profileRemoved: true;
  maxAttempts: 4;
  retryDelayMs: 100;
  temporaryRetention: TemporaryRetention;
} & ({ appSelfRemoved: true; cleanupActor: 'none'; beforeCleanup: [] }
  | { appSelfRemoved: false; cleanupActor: 'harness'; beforeCleanup: [string] });

class DirectoryIdentity {
  private device: bigint;
  private inode: bigint;
  private constructor(device: bigint, inode: bigint) { this.device = device; this.inode = inode; }
  static async read(path: string, refusal: string): Promise<DirectoryIdentity> {
    const stat = await lstat(path, { bigint: true });
    assert.ok(stat.isDirectory() && !stat.isSymbolicLink(), refusal);
    assert.ok(stat.ino > 0n, 'The actual filesystem must supply a directory identity');
    return new DirectoryIdentity(stat.dev, stat.ino);
  }
  same(other: DirectoryIdentity): boolean { return this.device === other.device && this.inode === other.inode; }
}

/** Owns only the fresh temporary root created for one actual package launch. */
export class TemporaryProfileOwner {
  private observed: { name: string; identity: DirectoryIdentity } | undefined;
  private identity: DirectoryIdentity;
  readonly path: string;
  private constructor(path: string, identity: DirectoryIdentity) { this.path = path; this.identity = identity; }
  static async create(parent: string): Promise<TemporaryProfileOwner> {
    const path = await mkdtemp(join(parent, 'cef-temporary-'));
    return new TemporaryProfileOwner(path, await DirectoryIdentity.read(path, 'Expected a fresh temporary directory'));
  }
  private async checkRoot(): Promise<void> {
    const current = await DirectoryIdentity.read(this.path, 'Never follow a replaced temporary root');
    assert.ok(this.identity.same(current), 'Never follow a replaced temporary root');
  }
  async observe(): Promise<[string]> {
    assert.equal(this.observed, undefined, 'Observe this launch once');
    await this.checkRoot();
    // Live CEF helpers may share this temporary root. Observe only the profile;
    // cleanup refuses unknown profiles and preserves other temporary entries.
    const entries = (await readdir(this.path)).filter(name => name.startsWith('proton-cef-'));
    assert.equal(entries.length, 1, 'This launch creates one fresh CEF profile');
    const name = entries[0]!;
    assert.ok(name.startsWith('proton-cef-'));
    const identity = await DirectoryIdentity.read(join(this.path, name), 'The profile is an owned directory');
    await this.checkRoot();
    this.observed = { name, identity };
    return [name];
  }
  async cleanupAfterExit(_exit: NormalPackageExit): Promise<ProfileCleanup> {
    assert.ok(_exit instanceof NormalPackageExit, 'A checked exit boundary is required');
    assert.ok(this.observed, 'Observe the actual launch profile before cleanup');
    await this.checkRoot();
    const before = (await readdir(this.path)).sort();
    assert.ok(before.filter(name => name.startsWith('proton-cef-')).every(name => name === this.observed!.name),
      'Never remove an unobserved profile');
    const siblings = before.filter(name => name !== this.observed!.name);
    const common = { after: 'normal-entry-exit-and-owned-process-quiescence', profileRemoved: true,
      maxAttempts: 4, retryDelayMs: 100, temporaryRetention: temporaryRetention(this.path, siblings) } as const;
    if (!before.includes(this.observed.name)) return { ...common, appSelfRemoved: true, cleanupActor: 'none', beforeCleanup: [] };
    const profile = join(this.path, this.observed.name);
    const current = await DirectoryIdentity.read(profile, 'Never follow a replaced profile');
    assert.ok(this.observed.identity.same(current), 'Never follow a replaced profile');
    await this.checkRoot();
    await rm(profile, { recursive: true, force: false, maxRetries: 3, retryDelay: 100 });
    assert.deepEqual((await readdir(this.path)).sort(), siblings, 'Remove only the owned profile and preserve all other entries');
    return { ...common, appSelfRemoved: false, cleanupActor: 'harness', beforeCleanup: [this.observed.name] };
  }
}
