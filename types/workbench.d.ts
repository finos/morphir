import type { Core, NativeBridge, WorkRequest, Artifact } from '../apps/morphir-workbench/browser/contracts.ts';

declare global {
  var morphirWorkbenchExecutions: Core;
  var morphirWorkbenchWorksheet: Core;
  var morphirWorkbenchDecode: Core;
  var morphirWorkbenchExecutionHost: (offer: string) => Core;
  var __MoonBit__: NativeBridge | undefined;
  var morphirWorkbench: {
    readonly mode: import('../apps/morphir-workbench/browser/session-mode.ts').WorkbenchMode;
    connected: boolean;
    /** File, network and storage access of the project editor, for the MoonBit page. */
    projectIo: {
      fetchText(path: string, receive: (reply: string) => void): Promise<void>;
      pickFolder(receive: (reply: string) => void): void;
      watchDrop(selector: string, receive: (reply: string) => void): void;
      storage: { load(key: string): string | null; save(key: string, text: string): boolean; remove(key: string): boolean };
    };
    readonly runtimeLabel: string;
    invalidateArtifacts(): void;
    request(request: WorkRequest, receive: (source: string) => void): void | Promise<void>;
    cancel(): void;
    importModelTree(attempt: string, receive: (source: string) => void): void;
    importModel(attempt: string, format: import('../apps/morphir-workbench/browser/contracts.ts').ModelCodec | '', receive: (source: string) => void): void;
    openOriginals(makeHash: () => import('../pkgs/morphir-host/model-originals-client/originals.ts').Hasher,
      receive: (event: import('../apps/morphir-workbench/browser/connected-originals.ts').ConnectedOriginalsEvent) => void): import('../apps/morphir-workbench/browser/connected-originals.ts').ConnectedOriginalsOpening;
    disposeOriginals(opening: import('../apps/morphir-workbench/browser/connected-originals.ts').ConnectedOriginalsOpening): void;
    originalHeaderParts(payload: import('../apps/morphir-workbench/browser/connected-originals.ts').OriginalPayload): number[];
    releaseModel(): void;
    cancelModelOpen(attempt: string): Promise<void>;
    download(text: string): void;
    downloadArtifacts(artifacts: unknown, project: boolean): string;
  };
}
