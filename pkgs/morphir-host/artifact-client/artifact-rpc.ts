import type { RpcSocket } from './contracts.ts';
import { workbenchError } from '../../../types/data.ts';

type Exchange = {
  kind: 'pending';
  resolve(source: string): void;
  reject(cause: Error): void;
  timer: ReturnType<typeof setTimeout>;
};
type ChannelState = { kind: 'idle' } | Exchange | { kind: 'closed' };

const requestLimit = 1048576;
const replyLimit = 131072;
const byteLength = (source: string) => new TextEncoder().encode(source).byteLength;

/** Open only the supplied attempt-owned socket, with bounded abortable setup. */
export function openArtifactChannel(
  createSocket: () => RpcSocket, signal: AbortSignal, timeout = 10000, exchangeTimeout = 60000,
): Promise<ArtifactRpcChannel> {
  if (!Number.isSafeInteger(timeout) || timeout < 1) return Promise.reject(new Error('Invalid artifact connection timeout.'));
  if (signal.aborted) return Promise.reject(new Error('The artifact connection was cancelled.'));
  return new Promise((resolve, reject) => {
    let socket: RpcSocket;
    try { socket = createSocket(); } catch (cause) { reject(workbenchError(cause)); return; }
    const clean = () => {
      clearTimeout(timer);
      socket.removeEventListener('open', opened);
      socket.removeEventListener('error', failed);
      socket.removeEventListener('close', disconnected);
      signal.removeEventListener('abort', cancelled);
    };
    const refuse = (message: string) => {
      clean();
      try { socket.close(); } catch { /* Already disconnected. */ }
      reject(new Error(message));
    };
    const opened = () => {
      clean();
      try { resolve(new ArtifactRpcChannel(socket, exchangeTimeout)); }
      catch (cause) { try { socket.close(); } catch { /* Already disconnected. */ } reject(workbenchError(cause)); }
    };
    const failed = () => refuse('The artifact connection failed.');
    const disconnected = () => refuse('The artifact connection closed before initialization.');
    const cancelled = () => refuse('The artifact connection was cancelled.');
    const timer = setTimeout(() => refuse('The artifact connection timed out.'), timeout);
    socket.addEventListener('open', opened);
    socket.addEventListener('error', failed);
    socket.addEventListener('close', disconnected);
    signal.addEventListener('abort', cancelled, { once: true });
    if (signal.aborted) cancelled();
    else if (socket.readyState === 1) opened();
    else if (socket.readyState !== 0) disconnected();
  });
}

/**
 * One generation attempt owns this socket. Replies stay raw until the selected
 * artifact decoder validates them against the captured request. IDs and JSON
 * syntax deliberately belong to that decoder, never a lossy routing pre-pass.
 * The caller initializes the existing v1 session before sending artifact calls.
 */
export class ArtifactRpcChannel {
  private readonly socket: RpcSocket;
  private readonly timeout: number;
  private state: ChannelState = { kind: 'idle' };

  constructor(socket: RpcSocket, timeout = 60000) {
    if (socket.readyState !== 1) throw new Error('The artifact socket is not connected.');
    if (!Number.isSafeInteger(timeout) || timeout < 1) throw new Error('Invalid artifact exchange timeout.');
    this.socket = socket;
    this.timeout = timeout;
    socket.addEventListener('message', this.receive);
    socket.addEventListener('close', this.disconnected);
    socket.addEventListener('error', this.failed);
  }

  get closed() { return this.state.kind === 'closed'; }

  private receive = (event: Event) => {
    const pending = this.state;
    if (pending.kind !== 'pending') {
      this.close(new Error('An unexpected artifact reply closed this attempt.'));
      return;
    }
    const source: unknown = (event as MessageEvent<unknown>).data;
    if (typeof source !== 'string') {
      this.close(new Error('The artifact reply must be a text frame.'));
      return;
    }
    if (source.length > replyLimit || byteLength(source) > replyLimit) {
      this.close(new Error('The artifact reply exceeds the complete 128 KiB frame limit.'));
      return;
    }
    clearTimeout(pending.timer);
    this.state = { kind: 'idle' };
    pending.resolve(source);
  };

  private disconnected = () => this.close(new Error('The artifact socket disconnected. Retention status may be unknown.'));
  private failed = () => this.close(new Error('The artifact socket failed. Retention status may be unknown.'));

  exchange(source: string): Promise<string> {
    if (this.state.kind === 'closed') return Promise.reject(new Error('The artifact attempt is closed.'));
    if (this.state.kind === 'pending') return Promise.reject(new Error('An artifact exchange is already pending.'));
    if (source.length > requestLimit || byteLength(source) > requestLimit) {
      return Promise.reject(new Error('The artifact request exceeds the complete 1 MiB frame limit.'));
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.close(new Error('The artifact exchange timed out. Closing its socket releases uncertain retention.'));
      }, this.timeout);
      this.state = { kind: 'pending', resolve, reject, timer };
      try { this.socket.send(source); }
      catch (cause) { this.close(workbenchError(cause)); }
    });
  }

  /** Closing the owning connection also covers a generation ID never received. */
  close(cause = new Error('The artifact attempt is closed.')) {
    const previous = this.state;
    if (previous.kind === 'closed') return;
    this.state = { kind: 'closed' };
    this.socket.removeEventListener('message', this.receive);
    this.socket.removeEventListener('close', this.disconnected);
    this.socket.removeEventListener('error', this.failed);
    if (previous.kind === 'pending') {
      clearTimeout(previous.timer);
      previous.reject(cause);
    }
    try { this.socket.close(); } catch { /* Already disconnected. */ }
  }
}
