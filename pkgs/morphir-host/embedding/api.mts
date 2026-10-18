/** Public host API. The compiler and all standard-library bytes are host supplied. */
export type Target = 'wasm' | 'wasm-gc';
export type Interface = [name: string, bytes: Uint8Array<ArrayBuffer>];
export interface Artifact { target: Target; bytes: Uint8Array<ArrayBuffer>; }
export interface BuildRequest {
  operation: 'build';
  files: [path: string, source: string][];
  package?: string;
  target?: Target;
  exports?: string[];
  interfaces?: Interface[];
  indirectInterfaces?: Interface[];
  standardInterfaces?: Interface[];
  cores?: Uint8Array<ArrayBuffer>[];
  isMain?: boolean;
  optimization?: 'optimized' | 'unoptimized';
}
export interface CompileRequest extends Omit<BuildRequest, 'operation'> { operation: 'compile'; }
export interface LinkRequest {
  operation: 'link';
  package: string;
  target: Target;
  cores: Uint8Array<ArrayBuffer>[];
  exports: string[];
  optimization?: 'optimized' | 'unoptimized';
}
export interface RunRequest {
  operation: 'run';
  artifact: Artifact;
  imports?: WebAssembly.Imports;
  export?: string;
  args?: (number | bigint)[];
}
export interface InfoRequest { operation: 'info'; }
export type Request = CompileRequest | BuildRequest | LinkRequest | RunRequest | InfoRequest;
export interface BuildResult {
  successful: boolean;
  diagnostics: unknown[];
  interface?: Uint8Array<ArrayBuffer>;
  core?: Uint8Array<ArrayBuffer>;
}
export interface LinkResult { artifact: Artifact; }
export interface CompileResult {
  successful: boolean;
  diagnostics: unknown[];
  artifact: Artifact | null;
  interface?: Uint8Array<ArrayBuffer>;
  core?: Uint8Array<ArrayBuffer>;
}
export interface RunResult { successful: boolean; value: unknown; }
export interface InfoResult {
  protocolVersion: number;
  mode: string;
  operations: readonly string[];
  targets: readonly string[];
  compilerVersion: string;
  supported: boolean;
  available: boolean;
}
export type Result = CompileResult | BuildResult | LinkResult | RunResult | InfoResult;
export type ResultFor<R extends Request> = R extends CompileRequest ? CompileResult : R extends BuildRequest ? BuildResult : R extends LinkRequest ? LinkResult : R extends RunRequest ? RunResult : InfoResult;
export interface Options { imports?: WebAssembly.Imports; }
export interface RequestOptions { signal?: AbortSignal; }
export interface Toolchain {
  capabilities: { protocolVersion: number; mode: string; operations: readonly string[]; targets: readonly string[] };
  request<R extends Request>(request: R, options?: RequestOptions): Promise<ResultFor<R>>;
  dispose(): void;
}
export interface Compiler {
  buildPackage(request: {
    mbtFiles: CompileRequest['files']; miFiles: Interface[]; indirectImportMiFiles: Interface[];
    stdMiFiles: Interface[]; target: Target; pkg: string; pkgSources: never[]; isMain: boolean;
    errorFormat: 'json'; enableValueTracing: false; noOpt: boolean;
  }): Promise<{ diagnostics?: string[]; core?: Uint8Array<ArrayBuffer>; mi?: Uint8Array<ArrayBuffer> }>;
  linkCore(request: {
    coreFiles: Uint8Array<ArrayBuffer>[]; main: string; pkgSources: never[]; target: Target;
    exportedFunctions: string[]; outputFormat: 'wasm'; testMode: false; debug: false;
    noOpt: boolean; sourceMap: false; sources: Record<string, string>; stopOnMain: true;
  }): Promise<{ result: Uint8Array<ArrayBuffer> }>;
}
export type CompilerFactory = () => Compiler | Promise<Compiler>;
export interface WorkerRequest { id: number; request: Request; }
export interface WorkerReply { id: number; result?: Result; error?: { name: string; message: string }; }
export interface BrowserWorkerPort {
  postMessage(message: WorkerRequest): void;
  terminate(): void;
  addEventListener(type: 'message', listener: (event: { data: WorkerReply }) => void): void;
  addEventListener(type: 'error', listener: (event: { message: string }) => void): void;
  addEventListener(type: 'messageerror', listener: () => void): void;
}
export interface NodeWorkerPort {
  postMessage(message: WorkerRequest): void;
  terminate(): Promise<number>;
  on(type: 'message', listener: (reply: WorkerReply) => void): unknown;
  on(type: 'error', listener: (error: Error) => void): unknown;
  on(type: 'exit', listener: (code: number) => void): unknown;
}
