import type { Core, NativeBridge, WorkRequest, Artifact } from '../apps/morphir-workbench/browser/contracts.ts';

declare global {
  var morphirWorkbenchJobs: Core;
  var morphirWorkbenchDecode: Core;
  var morphirWorkbenchJobHost: (offer: string) => Core;
  var __MoonBit__: NativeBridge | undefined;
  var morphirWorkbench: {
    connected: boolean;
    readonly runtimeLabel: string;
    request(request: WorkRequest, receive: (source: string) => void): void | Promise<void>;
    cancel(): void;
    importModel(receive: (source: string) => void): void;
    download(text: string): void;
    downloadArtifacts(artifacts: unknown, project: boolean): string;
  };
}
