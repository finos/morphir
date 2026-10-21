import type { Core, CoreReply, Rpc, RpcSocket } from './contracts.ts';
const limit = 2162688;
const byteLength = (source: string) => new TextEncoder().encode(source).length;
type Pending = { kind: 'pending'; id: number; resolve(value: unknown): void; reject(error: Error): void; timer: ReturnType<typeof setTimeout> };
type State = { kind: 'idle' } | Pending | { kind: 'closed' };

/** The file grant owns this bounded connection independently of legacy RPC. */
export class WorkspaceFilesRpc implements Rpc {
  private socket: RpcSocket;
  private core: Core;
  private state: State = { kind: 'idle' };
  private next = 0;
  private timeout: number;
  constructor(socket: RpcSocket, core: Core = command => globalThis.morphirWorkbenchExecutions(command), timeout = 10000) {
    if (socket.readyState !== 1) throw new Error('The workspace file socket is not connected.');
    this.socket = socket; this.core = core; this.timeout = timeout;
    socket.addEventListener('message', this.receive);
    socket.addEventListener('close', this.disconnected);
    socket.addEventListener('error', this.disconnected);
  }
  private receive = (event: Event) => {
    const pending = this.state;
    if (pending.kind !== 'pending') { this.dispose(); return; }
    const source: unknown = (event as MessageEvent<unknown>).data;
    if (typeof source !== 'string' || source.length > limit || byteLength(source) > limit) {
      this.close(new Error('The workspace RPC reply exceeds its complete frame bound.')); return;
    }
    try {
      const decoded: CoreReply<{ ok: true; value: unknown } | { ok: false; message: string }> = JSON.parse(this.core(JSON.stringify({ op: 'workspace-files-rpc-response', id: pending.id, source })));
      if (!decoded.ok) { this.close(new Error('The workspace RPC reply is incompatible.')); return; }
      clearTimeout(pending.timer); this.state = { kind: 'idle' };
      if (decoded.value.ok) pending.resolve(decoded.value.value);
      else pending.reject(new Error(decoded.value.message));
    } catch { this.close(new Error('The workspace RPC reply is invalid.')); }
  };
  private disconnected = () => this.close(new Error('The workspace file connection closed. A pending save may be unconfirmed.'));
  call(method: string, params: Record<string, unknown>): Promise<unknown> {
    if (this.state.kind !== 'idle' || this.next === 2147483647 || !['morphir.session.initialize', 'morphir.workspace-files.exchange'].includes(method)) {
      return Promise.reject(new Error('The workspace file connection is unavailable or already has a request.'));
    }
    const id = ++this.next, source = JSON.stringify({ jsonrpc: '2.0', id, method, params });
    if (source.length > limit || byteLength(source) > limit) return Promise.reject(new Error('The workspace RPC request exceeds its complete frame bound.'));
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => this.close(new Error('The workspace RPC timed out; the save effect may be unknown.')), this.timeout);
      this.state = { kind: 'pending', id, resolve, reject, timer };
      try { this.socket.send(source); }
      catch { this.close(new Error('The workspace file request could not be sent.')); }
    });
  }
  private close(error: Error) {
    const pending = this.state;
    if (pending.kind === 'closed') return;
    this.state = { kind: 'closed' };
    this.socket.removeEventListener('message', this.receive);
    this.socket.removeEventListener('close', this.disconnected);
    this.socket.removeEventListener('error', this.disconnected);
    if (pending.kind === 'pending') { clearTimeout(pending.timer); pending.reject(error); }
    try { this.socket.close(); } catch { /* The owning channel remains retired. */ }
  }
  dispose() { this.close(new Error('The workspace file connection is closed.')); }
}

export function openWorkspaceFilesRpc(createSocket: () => RpcSocket, signal: AbortSignal): Promise<Rpc> {
  if (signal.aborted) return Promise.reject(new Error('The workspace connection was cancelled.'));
  return new Promise((resolve, reject) => {
    const socket = createSocket();
    const clean = () => { clearTimeout(timer); socket.removeEventListener('open', opened); socket.removeEventListener('error', failed); socket.removeEventListener('close', failed); signal.removeEventListener('abort', cancelled); };
    const refuse = (message: string) => { clean(); socket.close(); reject(new Error(message)); };
    const opened = () => { clean(); resolve(new WorkspaceFilesRpc(socket)); };
    const failed = () => refuse('The workspace file connection failed.');
    const cancelled = () => refuse('The workspace file connection was cancelled.');
    const timer = setTimeout(() => refuse('The workspace file connection timed out.'), 10000);
    socket.addEventListener('open', opened); socket.addEventListener('error', failed); socket.addEventListener('close', failed); signal.addEventListener('abort', cancelled, { once: true });
    if (signal.aborted) cancelled(); else if (socket.readyState === 1) opened(); else if (socket.readyState !== 0) failed();
  });
}
