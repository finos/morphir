import type { Adapter, NativeOperations, Project, WorkResult } from './contracts.ts';
import type { NativeSession } from './native-session.ts';
// Page-bound native workspace transport. Business model bytes stay opaque until
// the compiled codec inspects them; JavaScript never parses their JSON numbers.
const keys = (value: unknown) => value && typeof value === 'object' && !Array.isArray(value) ? Object.keys(value).sort().join(',') : '';
const token = (value: unknown): value is string => typeof value === 'string' && /^[a-zA-Z0-9_.-]{1,128}$/.test(value);
const maxModel = 16 * 1024 * 1024;

function rejected(code: string, message?: string) {
  const messages: Record<string, string> = {
    'workbench.workspace_configuration': 'Workspace configuration is invalid. Check morphir.toml or morphir.json.',
    'workbench.workspace_link_or_type': 'The workspace contains unsupported links or file types.',
    'workbench.workspace_changed': 'The workspace changed during reading. Reopen the workspace.',
    'workbench.workspace_stale_root': 'The workspace folder was moved or replaced. Reopen the workspace.',
    'workbench.workspace_quota': 'The workspace exceeds a native discovery or read limit. Select a smaller project folder.',
    'workbench.workspace_revoked': 'The workspace grant has been revoked. Reopen the workspace.',
  };
  message ||= messages[code];
  return Object.assign(new Error(message || `The native workspace request was rejected (${code}).`), {
    diagnostics: [{ severity: 'error', code, message: message || code }],
  });
}

export class NativeWorkspaceClient {
  session: NativeSession;
  local: Pick<Adapter, 'execute' | 'cancel'>;
  epoch: number;
  projects: (Project & { available: boolean; message: string })[];
  grant: string | null;
  pendingRelease: { grantId: string; sequence: number } | null;
  choosing: boolean;
  opening: boolean;
  sequence: number;
  disposed: boolean;
  constructor(session: NativeSession, local: Pick<Adapter, 'execute' | 'cancel'>) {
    this.session = session; this.local = local; this.epoch = 0;
    this.projects = []; this.grant = null; this.pendingRelease = null;
    this.choosing = false; this.opening = false; this.sequence = 0; this.disposed = false;
  }
  current(epoch: number) {
    if (this.disposed || epoch !== this.epoch) throw rejected('workbench.workspace_discarded', 'The workspace request is no longer current.');
  }
  async release() {
    const pending = this.pendingRelease;
    if (!pending) return;
    const reply = await this.session.request('workspace.release', pending);
    if (keys(reply) !== '') throw rejected('workbench.workspace_cleanup', 'Model transfer cleanup could not be confirmed.');
    if (this.pendingRelease === pending) this.pendingRelease = null;
  }
  async choose() {
    if (this.choosing || this.opening) throw rejected('workbench.workspace_busy', 'A workspace request is still active.');
    const epoch = ++this.epoch;
    await this.release();
    await this.session.check(); this.current(epoch);
    this.choosing = true;
    try {
      // An interactive system picker has no worker deadline. Its native Cancel
      // action, page revocation and explicit client cancellation fence its result.
      const reply = await this.session.request('workspace.choose', undefined, true);
      await this.session.check();
      if (this.disposed || epoch !== this.epoch) {
        if ('grantId' in reply && token(reply.grantId)) await this.session.request('workspace.revoke', { grantId: reply.grantId });
        this.current(epoch);
      }
      if (keys(reply) === 'cancelled' && reply.cancelled === true) return this.result(true);
      if (keys(reply) !== 'cancelled,grantId,projects,warnings' || reply.cancelled !== false || !token(reply.grantId) ||
          !Array.isArray(reply.projects) || reply.projects.length > 128 || !Array.isArray(reply.warnings) ||
          reply.warnings.some(w => typeof w !== 'string') || reply.projects.some(p =>
            keys(p) !== 'available,id,message,name' || !token(p.id) || typeof p.name !== 'string' || !p.name ||
            typeof p.available !== 'boolean' || typeof p.message !== 'string') ||
          new Set(reply.projects.map(p => p.id)).size !== reply.projects.length) {
        throw rejected('workbench.workspace_reply', 'The native workspace offer is incompatible.');
      }
      this.grant = reply.grantId; this.projects = reply.projects;
      return { ...this.result(false), diagnostics: [
        ...reply.warnings.map(message => ({ severity: 'warning', code: 'workbench.workspace_notice', message })),
        ...reply.projects.filter(p => !p.available).map(p => ({ severity: 'error', code: 'workbench.workspace_project', message: `${p.name}: ${p.message}` })),
      ] };
    } finally { this.choosing = false; }
  }
  result(cancelled: boolean) {
    return { success: true, operation: 'workspace', cancelled, projects: this.projects,
      message: cancelled ? 'Workspace selection cancelled' : `Workspace opened · ${this.projects.length} project models` };
  }
  async openProject(id: string) {
    if (this.opening || this.choosing) throw rejected('workbench.workspace_busy', 'A workspace request is still active.');
    this.opening = true;
    try { return await this.openModel(id); } finally { this.opening = false; }
  }
  async openModel(id: string): Promise<WorkResult> {
    const epoch = ++this.epoch;
    const project = this.projects.find(p => p.id === id);
    if (!this.grant || !project) throw rejected('workbench.workspace_project', 'Unknown workspace project. Reopen the workspace.');
    if (!project.available) throw rejected('workbench.workspace_model_missing', project.message);
    await this.release(); this.current(epoch);
    const grantId = this.grant;
    if (this.sequence >= 2147483647) throw rejected('workbench.workspace_quota', 'Reopen the application page before another transfer.');
    const sequence = ++this.sequence;
    this.pendingRelease = { grantId, sequence }; // Also fences a lost/late open.
    let opened: NativeOperations['workspace.open'], content: string;
    try {
      opened = await this.session.request('workspace.open', { grantId, projectId: id, sequence }); this.current(epoch);
      if (keys(opened) !== 'filename,format,sequence,size' || opened.sequence !== sequence || !Number.isInteger(opened.size) || opened.size < 0 || opened.size > maxModel ||
          !['morphir-json', 'ion-text', 'ion-binary'].includes(opened.format) || typeof opened.filename !== 'string' ||
          [...opened.filename].length < 1 || [...opened.filename].length > 256 || /[/\\]/.test(opened.filename)) throw rejected('workbench.workspace_reply', 'Invalid native model descriptor.');
      let offset = 0; const chunks = [];
      while (offset < opened.size) {
        const reply = await this.session.request('workspace.read', { grantId, sequence, offset }); this.current(epoch);
        if (keys(reply) !== 'content,done,offset,sequence' || reply.sequence !== sequence || reply.offset !== offset || typeof reply.content !== 'string' ||
            reply.content.length > 256 * 1024 || reply.content.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(reply.content)) {
          throw rejected('workbench.workspace_sequence', 'Invalid native model chunk.');
        }
        const size = atob(reply.content).length;
        if (size !== Math.min(192 * 1024, opened.size - offset) || reply.done !== (offset + size === opened.size)) {
          throw rejected('workbench.workspace_sequence', 'Invalid native model chunk length.');
        }
        chunks.push(reply.content); offset += size;
      }
      content = chunks.join('');
    } finally { await this.release(); }
    this.current(epoch);
    const result = await this.local.execute({ operation: 'inspect', source: '', sourceCodec: opened.format, sourceBase64: content });
    this.current(epoch); await this.session.check(); this.current(epoch);
    if (!result.success) return result;
    if (typeof result.sourceFormatVersion !== 'string') throw rejected('workbench.workspace_reply', 'The model inspector did not report its input format version.');
    return { ...result, operation: 'project', modelSource: { kind: 'original-file', filename: opened.filename,
      codec: opened.format as 'morphir-json' | 'ion-text' | 'ion-binary', formatVersion: result.sourceFormatVersion, contentBase64: content } };
  }
  async cancel() {
    ++this.epoch;
    this.local.cancel();
    if (this.choosing) await this.session.request('workspace.cancel-picker');
    // The active open owns cleanup until its request settles. Releasing here
    // could run before a delayed validation; its finally retires the sequence.
    if (!this.opening) await this.release();
  }
  dispose() { this.disposed = true; ++this.epoch; }
}
