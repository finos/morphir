export interface ToolchainPin {
  profile: string; platform: string; arch: string; compilerVersion: string;
  compilerIdentity: string; coreIdentity: string; targets: string[];
  acquisition?: Record<string, string>;
}
export interface CapabilityRequest { timeout: number; compilerHome: string; toolchainPin?: ToolchainPin; }
export interface FileIdentity { path: string; identity: string; }
export interface Runtime {
  kind: string; identity: string; version: string; path?: string; runner?: string; runnerIdentity?: string;
  system?: { platform: string; arch: string; release: string; version: string };
  dependencies?: FileIdentity[]; inputs?: FileIdentity[];
}
export interface NativeToolchain {
  cc: string; driverIdentity: string; compilerProgram: string; compilerIdentity: string;
  compilerVersion: string; linker: string; linkerIdentity: string; linkerVersion: string;
}
export interface Capability {
  target: string; backend: string; compile: boolean; run: boolean; protocol: string;
  platform: string; arch: string; requiredImports: string[]; runtime: Runtime; toolchain: NativeToolchain | null;
}
export interface Dependency { moduleName: string; version: string; apiProfile: string; semanticPin: string; }
export interface BuildRequest extends CapabilityRequest {
  contract: string; target: string; cancelFile?: string; snapshot: string; sourceIdentity: string;
  projectId: string; leaseId: string; dependencies: Dependency[]; suppliedDependencies: Record<string, string>;
  buildMode?: string;
}
export type SourceMember = [path: string, content: ['text', string] | ['binary', number[]]];
export interface LinkedRuntime { path: string; kind: string; identity?: string; systemVersion?: string; }
export interface BuildEvidence {
  successful: boolean; frozen: boolean; leaseId: string; projectId: string; contract: string; sourceIdentity: string;
  target: string; compilerVersion: string; compilerIdentity: string; coreIdentity: string; buildIdentity: string;
  dependencies: (Dependency & { sourceIdentity: string })[];
  executable?: string; executableIdentity?: string; buildMode?: string; capability?: Capability;
  configuredDriverIdentity?: string | null; driverIdentity?: string; manifestIdentity?: string;
  runtimeIdentity?: string; runtimeVersion?: string; linkedRuntime?: LinkedRuntime[]; toolchainPin?: ToolchainPin;
  executionSources?: [string, string][];
}
export interface TreeOptions { core?: boolean; includeBuild?: boolean; check?: () => void; }
export interface SuperviseOptions {
  cwd?: string; env?: NodeJS.ProcessEnv; timeout: number; cancelFile?: string; cancelled?: () => boolean; interruptGraceMs?: number; limit?: number; input?: Buffer;
}
export interface SupervisedResult<T = string> { code: number | null; signal: NodeJS.Signals | null; stdout: T; stderr: string; }
