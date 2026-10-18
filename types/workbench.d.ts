import type { Core, NativeBridge, WorkRequest, Artifact } from '../apps/morphir-workbench/browser/contracts.ts';

declare global {
  var morphirWorkbenchExecutions: Core;
  var morphirWorkbenchWorksheet: Core;
  var morphirWorkbenchDecode: Core;
  var morphirWorkbenchExecutionHost: (offer: string) => Core;
  var __MoonBit__: NativeBridge | undefined;
  var morphirWorkbench: {
    connected: boolean;
    /** File, network and storage access of the project editor, for the MoonBit page. */
    projectIo: {
      fetchText(path: string, receive: (reply: string) => void): Promise<void>;
      pickFolder(receive: (reply: string) => void): void;
      watchDrop(selector: string, receive: (reply: string) => void): void;
      storage: { load(key: string): string | null; save(key: string, text: string): boolean; remove(key: string): boolean };
    };
    readonly runtimeLabel: string;
    request(request: WorkRequest, receive: (source: string) => void): void | Promise<void>;
    cancel(): void;
    importModel(receive: (source: string) => void): void;
    download(text: string): void;
    downloadArtifacts(artifacts: unknown, project: boolean): string;
  };
}
