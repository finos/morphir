export interface Session {
  read(): string;
  [Symbol.dispose](): void;
}

export interface Sessions {
  Session: new (label: string) => Session;
  readBorrowed(value: Session): string;
  take(value: Session): string;
  live(): number;
  dropped(): number;
}

export interface Callbacks {
  notify(label: string, payload: Uint8Array): number;
}

export type CoreModuleLoader = (path: string) => Promise<WebAssembly.Module>;
export interface ComponentFactory<T> {
  instantiate(load: CoreModuleLoader, imports: Record<string, unknown>): T | Promise<T>;
}

function check(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function invalidResource(action: () => unknown): void {
  try { action(); }
  catch (error) {
    check(error instanceof TypeError && /resource/i.test(error.message), 'Expected an invalid-resource error');
    return;
  }
  throw new Error('Invalid resource was accepted');
}

export async function qualifyResources(fresh: () => Promise<Sessions>) {
  const api = await fresh();
  const label = 'Session 😀 𝄞 雪\u0000';
  check(api.live() === 0 && api.dropped() === 0, 'Resource instance was not fresh');
  const first = new api.Session(label);
  check(api.live() === 1 && first.read() === label, 'Resource constructor/method changed its value');
  for (let i = 0; i < 100; ++i) {
    check(api.readBorrowed(first) === label && first.read() === label, 'Borrow changed the resource');
  }
  check(api.live() === 1 && api.dropped() === 0, 'Borrow consumed or destroyed the resource');
  check(api.take(first) === label, 'Owned transfer changed the resource');
  check(api.live() === 0 && api.dropped() === 1, 'Owned transfer did not destroy exactly once');
  invalidResource(() => first.read());
  invalidResource(() => api.readBorrowed(first));
  invalidResource(() => api.take(first));
  first[Symbol.dispose]();
  check(api.dropped() === 1, 'Disposing a transferred wrapper destroyed twice');

  const disposable = new api.Session('explicit disposal');
  disposable[Symbol.dispose]();
  disposable[Symbol.dispose]();
  check(api.live() === 0 && api.dropped() === 2, 'Explicit disposal was not idempotent');
  invalidResource(() => disposable.read());
  invalidResource(() => api.readBorrowed(disposable));

  const other = await fresh();
  const local = new api.Session('local');
  const foreign = new other.Session('foreign');
  invalidResource(() => api.readBorrowed(foreign));
  invalidResource(() => api.take(foreign));
  check(foreign.read() === 'foreign' && local.read() === 'local', 'Cross-instance refusal changed either owner');
  local[Symbol.dispose]();
  foreign[Symbol.dispose]();
  check(api.live() === 0 && other.live() === 0 && api.dropped() === 3 && other.dropped() === 1,
    'Explicit resources leaked or destroyed the wrong instance');
  return {status: 'qualified' as const, borrowedCalls: 100, ownedTransfer: true, consumedHandleRefused: true,
    explicitDisposal: true, destructorExactlyOnce: true, crossInstanceRefusal: true};
}

class HostRefusal extends Error {
  readonly payload: string;
  constructor(payload: string) { super(payload); this.payload = payload; }
}

export async function qualifyCallbacks(factory: ComponentFactory<Callbacks>, load: CoreModuleLoader) {
  const calls: {label: string; payload: Uint8Array}[] = [];
  const observe = (label: string, payload: Uint8Array): number => {
    calls.push({label, payload});
    if (label === 'refuse') throw new HostRefusal('Host refused 😀');
    return payload.length * 7;
  };
  const imports = {'morphir:lifetime-probe/host': {observe}};
  const api = await factory.instantiate(load, imports);
  const label = 'Callback 😀 𝄞 e\u0301 雪\u0000';
  const ion = new Uint8Array([224, 1, 0, 234, 33, 42]);
  check(api.notify(label, ion) === 42, 'Host result did not return through the guest');
  check(calls.length === 1 && calls[0]?.label === label && calls[0].payload.join(',') === [...ion].join(','),
    'Host callback did not receive exact Unicode and Ion bytes');
  check(api.notify('', new Uint8Array()) === 0, 'Empty callback values changed');
  let typedFailure = false;
  try { api.notify('refuse', ion); }
  catch (error) {
    typedFailure = typeof error === 'object' && error !== null && 'payload' in error && error.payload === 'Host refused 😀';
  }
  check(typedFailure, 'Host typed error did not round trip through result');
  check(api.notify('after refusal', ion) === 42 && calls.length === 4, 'Callback instance did not recover');
  check(calls[0]?.label === label && calls[0].payload.join(',') === [...ion].join(','), 'Later callbacks changed retained host data');

  let missingImport = false;
  try { await factory.instantiate(load, {}); }
  catch (error) { missingImport = error instanceof TypeError && /observe/.test(error.message); }
  check(missingImport, 'Missing host capability was not refused at instantiation');
  return {status: 'qualified' as const, calls: 4, unicode: true, ionBytes: true, emptyValues: true, hostResult: true,
    typedFailure: true, recovery: true, missingImportRefused: true};
}
