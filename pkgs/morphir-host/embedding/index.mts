import type { BrowserWorkerPort, CompilerFactory, Interface, NodeWorkerPort, Options, Request, RequestOptions, Result, ResultFor, Toolchain, WorkerReply, WorkerRequest } from './api.mjs';
export type * from './api.mjs';
export * from './assembly.mjs';
export const compilerVersion = "0.10.15+943464bfa";
export const capabilities = Object.freeze({protocolVersion: 1, mode: "embedded",
  operations: Object.freeze(["info", "compile", "build", "link", "run"]), targets: Object.freeze(["wasm", "wasm-gc"])});

const aborted = () => new DOMException("Cancelled", "AbortError");
const check = (signal?: AbortSignal) => { if (signal?.aborted) throw aborted(); };
const bytes = (value: unknown): Uint8Array<ArrayBuffer> => {
  if (!(value instanceof Uint8Array)) throw new TypeError("Compiler assets must be Uint8Array values");
  return value as Uint8Array<ArrayBuffer>;
};

// The compiler is injected. This module imports no filesystem, process or compiler assets.
export function createEmbeddedToolchain(createCompiler: CompilerFactory, {imports = {}}: Options = {}): Toolchain {
  if (typeof createCompiler !== "function") throw new TypeError("An isolated compiler factory is required");
  let disposed = false;
  let queue = Promise.resolve();
  const active = (signal?: AbortSignal) => { check(signal); if (disposed) throw new Error("Toolchain disposed"); };
  async function execute(request: Request, signal?: AbortSignal): Promise<Result> {
    active(signal);
    switch (request.operation) {
      case "info": return {...capabilities, compilerVersion, supported: true, available: true};
      case "build":
      case "compile": {
        const compiler = await createCompiler();
        active(signal);
        const {files, package: pkg = "morphir/embedded", target = "wasm", exports = [],
          interfaces = [], indirectInterfaces = [], standardInterfaces = [], cores = [], isMain = false,
          optimization = "optimized"} = request;
        if (optimization !== "optimized" && optimization !== "unoptimized") throw new TypeError("Invalid optimization");
        if (!capabilities.targets.includes(target)) throw new Error(`Unsupported embedded target: ${target}`);
        if (!Array.isArray(files) || files.length === 0 || files.some(f => !Array.isArray(f) || f.length !== 2 || f.some(v => typeof v !== "string")))
          throw new TypeError("files must be nonempty [path, source] pairs");
        if (typeof pkg !== "string" || !pkg || !Array.isArray(exports) || exports.some(e => typeof e !== "string"))
          throw new TypeError("Invalid package or exports");
        const mi = (entries: Interface[]): Interface[] => entries.map(([name, data]) => [name, bytes(data)]);
        const built = await compiler.buildPackage({mbtFiles: files, miFiles: mi(interfaces),
          indirectImportMiFiles: mi(indirectInterfaces), stdMiFiles: mi(standardInterfaces),
          target, pkg, pkgSources: [], isMain, errorFormat: "json", enableValueTracing: false, noOpt: optimization === "unoptimized"});
        active(signal);
        const diagnostics = (built.diagnostics ?? []).map(text => {
          try { return JSON.parse(text); } catch { return {message: text}; }
        });
        // Some compiler releases can return partial outputs alongside errors.
        const errors = diagnostics.some(d => d && typeof d === "object" && 'level' in d && d.level === "error");
        if (!built.core || errors) return request.operation === "build"
          ? {successful: false, diagnostics} : {successful: false, diagnostics, artifact: null};
        if (request.operation === "build") return {successful: true, diagnostics, interface: built.mi, core: built.core};
        const linked = await compiler.linkCore({coreFiles: [...cores.map(core => bytes(core)), built.core], main: pkg,
          pkgSources: [], target, exportedFunctions: exports, outputFormat: "wasm", testMode: false,
          debug: false, noOpt: optimization === "unoptimized", sourceMap: false, sources: Object.fromEntries(files), stopOnMain: true});
        active(signal);
        return {successful: true, diagnostics, interface: built.mi, core: built.core, artifact: {target, bytes: linked.result}};
      }
      case "link": {
        const {package: pkg, target, cores, exports, optimization = "optimized"} = request;
        if (!capabilities.targets.includes(target) || typeof pkg !== "string" || !pkg ||
          !Array.isArray(cores) || !cores.length || !Array.isArray(exports) || exports.some(e => typeof e !== "string") ||
          (optimization !== "optimized" && optimization !== "unoptimized")) throw new TypeError("Invalid link request");
        const compiler = await createCompiler();
        active(signal);
        const linked = await compiler.linkCore({coreFiles: cores.map(bytes), main: pkg, target,
          pkgSources: [], exportedFunctions: exports, outputFormat: "wasm", testMode: false,
          debug: false, noOpt: optimization === "unoptimized", sourceMap: false, sources: {}, stopOnMain: true});
        active(signal);
        return {artifact: {target, bytes: linked.result}};
      }
      case "run": {
        const artifact = request.artifact;
        if (!artifact || !capabilities.targets.includes(artifact.target)) throw new TypeError("Expected an embedded Wasm artifact");
        const result = await WebAssembly.instantiate(bytes(artifact.bytes), request.imports ?? imports);
        active(signal);
        const fn = result.instance.exports[request.export ?? "_start"];
        if (typeof fn !== "function") throw new Error(`Missing runtime export: ${request.export ?? "_start"}`);
        const value = fn(...(request.args ?? []));
        active(signal);
        return {successful: true, value};
      }
      default: throw new Error(`Unknown embedded operation`);
    }
  }
  return {
    capabilities,
    request<R extends Request>(request: R, {signal}: RequestOptions = {}): Promise<ResultFor<R>> {
      // Upstream compiler state is mutable; serialize requests and recover after failures.
      const pending = queue.then(() => execute(request, signal));
      queue = pending.then(() => {}, () => {});
      return pending as Promise<ResultFor<R>>;
    },
    dispose() { disposed = true; },
  };
}

// Workers isolate compiler state and let hosts cancel compilation or evaluation.
export function createWorkerToolchain(worker: BrowserWorkerPort | NodeWorkerPort): Toolchain {
  const pending = new Map<number, { cleanup(): void; reject(error: unknown): void; resolve(result: Result): void }>();
  let next = 0, disposed = false;
  function stop(error: Error) {
    if (disposed) return;
    disposed = true;
    for (const p of pending.values()) { p.cleanup(); p.reject(error); }
    pending.clear();
    void worker.terminate();
  }
  function message(data: WorkerReply) {
    const p = pending.get(data.id);
    if (!p) return;
    pending.delete(data.id); p.cleanup();
    if (data.error) {
      const error = new Error(data.error.message); error.name = data.error.name;
      p.reject(error);
    } else p.resolve(data.result!);
  }
  if ('addEventListener' in worker) {
    worker.addEventListener("message", e => message(e.data));
    worker.addEventListener("error", e => stop(new Error(e.message)));
    worker.addEventListener("messageerror", () => stop(new Error("Worker message could not be decoded")));
  } else {
    worker.on("message", message);
    worker.on("error", stop);
    worker.on("exit", code => stop(new Error(`Toolchain worker exited: ${code}`)));
  }
  return {
    capabilities,
    request<R extends Request>(request: R, {signal}: RequestOptions = {}): Promise<ResultFor<R>> {
      if (disposed) return Promise.reject(new Error("Toolchain disposed"));
      if (signal?.aborted) return Promise.reject(aborted());
      return new Promise<ResultFor<R>>((resolve, reject) => {
        const id = ++next;
        const abort = () => stop(aborted());
        const cleanup = () => signal?.removeEventListener("abort", abort);
        pending.set(id, {resolve: result => resolve(result as ResultFor<R>), reject, cleanup});
        signal?.addEventListener("abort", abort, {once: true});
        try { worker.postMessage({id, request}); }
        catch (error) { pending.delete(id); cleanup(); reject(error); }
      });
    },
    dispose() { stop(new Error("Toolchain disposed")); },
  };
}

export function serveToolchain(toolchain: Toolchain, receive: (listener: (message: WorkerRequest) => Promise<void>) => void, send: (reply: WorkerReply) => void) {
  receive(async ({id, request}) => {
    try { send({id, result: await toolchain.request(request)}); }
    catch (cause) { const error = cause instanceof Error ? cause : new Error(String(cause)); send({id, error: {name: error.name, message: error.message}}); }
  });
}
