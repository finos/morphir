import type { Core, CoreReply, Invoke, Json, NativeReply, WorkRequest, WorkspaceFileAuthority } from './contracts.ts';

export const workspaceFilesProfile = 'morphir/workbench/workspace-files';
export const workspaceFilesVersion = '0.1.0-draft.1';
const frameLimit = 1048576, chunkLimit = 196608, transferLimit = 25165824;
type Inventory = NonNullable<WorkRequest['workspace']>;
export type FileAuthority = WorkspaceFileAuthority;
interface Grant { revision: number; sequence: number; blocked: boolean; tail: Promise<unknown> }
interface Failure extends Error { effect?: 'none' | 'unknown'; code?: string }
const encoder = new TextEncoder();
const unknown = (message: string): Failure => Object.assign(new Error(message), { effect: 'unknown' as const });
const base64 = (bytes: Uint8Array) => { let text = ''; for (let i = 0; i < bytes.length; i += 8192) text += String.fromCharCode(...bytes.subarray(i, i + 8192)); return btoa(text); };

/** Separate page-bound file channel; it does not change native execution contracts. */
export class WorkspaceFilesClient {
  private id: string | null = null;
  private disposed = false;
  private choosing = false;
  private pickerEpoch = 0;
  private grants = new Map<string, Grant>();
  private exchangeFrame: (source: string) => unknown | Promise<unknown>;
  private kind: FileAuthority['kind'];
  private core: Core;
  private timeout: number;
  constructor(exchangeFrame: (source: string) => unknown | Promise<unknown>, core: Core = globalThis.morphirWorkbenchExecutions, timeout = 10000, kind: FileAuthority['kind'] = 'native-write') {
    this.exchangeFrame = exchangeFrame; this.core = core; this.timeout = timeout; this.kind = kind;
  }
  private async exchange<T>(operation: string, payload?: Json, interactive = false): Promise<T> {
    if (this.disposed) throw unknown('The workspace file session is closed.');
    const request = JSON.stringify({ profile: workspaceFilesProfile, contractVersion: workspaceFilesVersion, operation,
      ...(operation === 'session.open' ? {} : { sessionId: this.id }), ...(payload === undefined ? {} : { payload }) });
    if (encoder.encode(request).length > frameLimit) throw new Error('The workspace request exceeds the frame limit.');
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const invocation = Promise.resolve().then(() => this.exchangeFrame(request));
      const raw = await (interactive ? invocation : Promise.race([invocation, new Promise((_, reject) => {
        timer = setTimeout(() => reject(unknown('The workspace request timed out. Its effect is unknown.')), this.timeout);
      })]));
      if (this.disposed || typeof raw !== 'string' || encoder.encode(raw).length > frameLimit) throw unknown('Invalid or obsolete workspace file reply.');
      const decoded: CoreReply<NativeReply<T>> = JSON.parse(this.core(JSON.stringify({ op: 'workspace-files-response', request, source: raw })));
      if (!decoded.ok) throw unknown('The workspace file reply is incompatible.');
      const reply = decoded.value;
      if (!reply.ok) throw Object.assign(new Error(reply.error.message), reply.error);
      if (operation === 'session.open') this.id = (JSON.parse(raw) as { sessionId: string }).sessionId;
      return reply.value;
    } finally { clearTimeout(timer); }
  }
  async open() { await this.exchange('session.open'); }
  async choose(interactive = true): Promise<{ authority: FileAuthority; workspace: Inventory } | null> {
    if (this.choosing) throw new Error('A workspace folder picker is already open.');
    this.choosing = true;
    const epoch = ++this.pickerEpoch;
    try {
      await this.exchange('session.check');
      if (epoch !== this.pickerEpoch) throw new Error('The folder selection was cancelled.');
      const choice = await this.exchange<{ cancelled: true } | { cancelled: false; grantId: string; revision: number; name: string }>('workspace.choose-write', undefined, interactive);
      if (choice.cancelled) return null;
      this.grants.set(choice.grantId, { revision: choice.revision, sequence: 0, blocked: false, tail: Promise.resolve() });
      try {
        if (epoch !== this.pickerEpoch) throw new Error('The folder selection was cancelled.');
        const workspace = await this.snapshot(choice.grantId);
        if (epoch !== this.pickerEpoch) throw new Error('The folder selection was cancelled.');
        return { workspace, authority: { kind: this.kind, grantId: choice.grantId, revision: this.grants.get(choice.grantId)!.revision, name: choice.name } };
      } catch (error) { await this.revoke(choice.grantId).catch(() => {}); throw error; }
    } finally { this.choosing = false; }
  }
  private grant(id: string) {
    const grant = this.grants.get(id);
    if (!grant || this.disposed) throw unknown('The workspace folder grant is no longer available. Reopen the folder.');
    return grant;
  }
  private sequence(grant: Grant) {
    if (grant.sequence === 2147483647) throw new Error('Reopen the application before another workspace transfer.');
    return ++grant.sequence;
  }
  private async snapshot(id: string): Promise<Inventory> {
    const grant = this.grant(id), sequence = this.sequence(grant), payload = { grantId: id, sequence };
    try {
      const opened = await this.exchange<{ size: number; revision: number }>('workspace.snapshot', payload);
      const bytes = new Uint8Array(opened.size);
      let offset = 0;
      while (offset < opened.size) {
        const chunk = await this.exchange<{ content: string; done: boolean }>('workspace.read', { ...payload, offset });
        const raw = atob(chunk.content);
        if (raw.length !== Math.min(chunkLimit, opened.size - offset) || chunk.done !== (offset + raw.length === opened.size)) throw unknown('Invalid workspace download length.');
        for (let i = 0; i < raw.length; i++) bytes[offset + i] = raw.charCodeAt(i);
        offset += raw.length;
      }
      const source = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
      if (!this.core.workspaceFiles) throw unknown('The workspace inventory validator is unavailable.');
      const validation: CoreReply<boolean> = JSON.parse(this.core.workspaceFiles(source));
      if (!validation.ok || validation.value !== true) throw unknown('The workspace inventory is incompatible.');
      // The shared bounded parser has already rejected duplicate keys, deep
      // structures, unsafe paths, malformed byte records and content overflow.
      const inventory = JSON.parse(source);
      grant.revision = opened.revision;
      return { ...inventory, openFile: null };
    } finally { await this.exchange('workspace.release', payload); }
  }
  save(id: string, workspace: Inventory): Promise<number> {
    // Capture before waiting for a previous save; callers may keep editing.
    const bytes = encoder.encode(JSON.stringify({ version: 1, files: workspace.files }));
    if (bytes.length > transferLimit) return Promise.reject(new Error('The workspace exceeds the transfer limit.'));
    const grant = this.grant(id);
    const save = grant.tail.then(async () => {
      if (grant.blocked) throw unknown('The previous save needs reconciliation. Keep the local draft and reopen the folder.');
      const sequence = this.sequence(grant), payload = { grantId: id, sequence };
      try {
        await this.exchange('session.check');
        await this.exchange('workspace.begin-edit', { ...payload, baseRevision: grant.revision, size: bytes.length });
        for (let offset = 0; offset < bytes.length; offset += chunkLimit) {
          await this.exchange('workspace.write', { ...payload, offset, content: base64(bytes.subarray(offset, offset + chunkLimit)) });
        }
        let revision: number;
        try {
          revision = (await this.exchange<{ revision: number }>('workspace.commit', payload)).revision;
        } catch (error) {
          // Query this exact sequence. Never submit a second commit or upload
          // after a missing acknowledgement, even if the status query fails.
          const status = await this.exchange<{ state: string; revision?: number; error?: { code: string; message: string; effect: string } }>('workspace.status', payload);
          if (status.state !== 'committed' || status.revision === undefined) {
            if (status.state === 'failed' && status.error) throw Object.assign(new Error(status.error.message), status.error);
            throw error;
          }
          revision = status.revision;
        }
        if (revision !== grant.revision + 1) throw unknown('The saved workspace revision is incompatible.');
        grant.revision = revision;
        // Cleanup cannot undo a confirmed commit. A newer sequence safely
        // supersedes this terminal transfer even if its release reply is lost.
        await this.exchange('workspace.release', payload).catch(() => {});
        return revision;
      } catch (error) {
        grant.blocked = true;
        throw error;
      }
    });
    grant.tail = save.catch(() => {});
    return save;
  }
  async cancelPicker() { ++this.pickerEpoch; await this.exchange('workspace.cancel-picker'); }
  async revoke(id: string) {
    const grant = this.grants.get(id);
    if (grant) { grant.blocked = true; await grant.tail; await this.exchange('workspace.revoke', { grantId: id }); this.grants.delete(id); }
  }
  dispose() {
    if (this.disposed) return;
    if (this.id) {
      const source = JSON.stringify({ profile: workspaceFilesProfile, contractVersion: workspaceFilesVersion, operation: 'session.close', sessionId: this.id });
      Promise.resolve().then(() => this.exchangeFrame(source)).catch(() => {});
    }
    this.disposed = true;
    this.grants.clear();
  }
}

/** Native binding keeps renderer frames independent of OS path authority. */
export class NativeFilesClient extends WorkspaceFilesClient {
  constructor(invoke: Invoke, core?: Core, timeout?: number) {
    super(source => invoke('app:workbench_native', source), core, timeout, 'native-write');
  }
}
