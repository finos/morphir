import './code-editor.js';
import type { Adapter } from './contracts.ts';
import { workbenchError } from '../../../types/data.ts';
import { LocalAdapter, connect } from './transport.ts';
import { selectLocalAdapter } from './native-session.ts';
import { downloadArtifacts } from './artifact-download.ts';
import {createOriginalsArchive, prepareOriginalsArchive} from './originals-archive.ts';
import { fetchText, pickFolder, storage, watchDrop } from './project-io.ts';
import { ModelImporter, captureOriginalRequest } from './model-import.ts';
import { selectWorkbenchMode } from './session-mode.ts';
import {openConnectedOriginals, type ConnectedOriginalsOpening} from './connected-originals.ts';
import {ModelOriginalsConnectionLimits} from './model-originals-session.ts';
import {parse as parseRelease} from '@std/semver';
import {productObservation} from './product-observer.ts';

const local = new LocalAdapter();
const mode = selectWorkbenchMode(location.search, document.querySelector<HTMLMetaElement>('meta[name="morphir-host-mode"]')?.content);
const connected = mode !== 'local';
let adapter: Adapter = local;
let generation = 0;
let activeRequest: { operation: string; modelOpenAttempt?: string } | null = null;
const importer = new ModelImporter();
let originalsOpening: ConnectedOriginalsOpening | undefined;

globalThis.morphirWorkbench = {
  mode,
  connected,
  projectIo: { fetchText, pickFolder, storage, watchDrop },
  get runtimeLabel() { return mode === 'connected-originals' ? 'Connected originals' : adapter.runtimeLabel || 'Browser local'; },
  invalidateArtifacts() { adapter.invalidateArtifacts?.(); },
  async revokeWorkspace(grantId) { await adapter.revokeWorkspace?.(grantId); },
  async saveWorkspace(grantId, workspace, receive) {
    try {
      if (!adapter.saveWorkspace) throw new Error('This host does not offer workspace writes.');
      const revision = await adapter.saveWorkspace(grantId, workspace);
      receive(JSON.stringify({ success: true, revision }));
    } catch (cause) {
      receive(JSON.stringify({ success: false, message: workbenchError(cause).message || 'Workspace save could not be confirmed.' }));
    }
  },
  async request(request, receive) {
    const current = ++generation;
    activeRequest = { operation: request.operation, modelOpenAttempt: request.modelOpenAttempt };
    try {
      if (mode === 'connected-originals') throw new Error('Use model sources on this page; switch modes to compile or inspect a model.');
      const original = captureOriginalRequest(request);
      let result;
      if (request.operation === 'initialize') {
        if (connected) {
          await import(new URL('./execution-core.js', import.meta.url).href);
          adapter = await connect(location, local);
          result = await adapter.initialize();
        } else {
          await import(new URL('./execution-core.js', import.meta.url).href);
          adapter = selectLocalAdapter(location, local);
          result = await adapter.initialize();
        }
      } else result = await adapter.execute(request, execution => {
        if (current === generation) receive(JSON.stringify({ success: true, operation: 'execution-progress', execution }));
      });
      if (current === generation) receive(JSON.stringify(original ? original(result) : result));
    } catch (cause) {
      const error = workbenchError(cause);
      if (request.operation === 'initialize') adapter.dispose?.();
      if (current === generation) receive(JSON.stringify({ success: false, message: error.message || 'Host request failed',
        ...(error.execution ? { execution: error.execution } : {}),
        ...(error.executionTransport ? { executionTransport: true } : {}),
        ...(error.submissionUnknown ? { submissionUnknown: true } : {}),
        ...(Array.isArray(error.diagnostics) && error.diagnostics.length ? { diagnostics: error.diagnostics } : {}) }));
    } finally { if (current === generation) activeRequest = null; }
  },
  cancel() {
    const hostExecution = adapter.executions?.active || (adapter.executions?.execution && adapter.executions.execution.state !== 'terminal');
    if (!hostExecution && activeRequest?.operation !== 'worksheet') ++generation;
    Promise.resolve(adapter.cancel()).catch(() => { /* The active observer reports retained disconnection evidence. */ });
  },
  importModelTree(attempt, receive) { importer.startTree(attempt, receive); },
  importModel(attempt, format, receive) { importer.start(attempt, receive, format || undefined); },
  openOriginals(makeHash, receive) {
    if (mode !== 'connected-originals') throw new Error('Open the model sources experience first.');
    originalsOpening?.dispose();
    const opening = openConnectedOriginals({base: new URL(location.href),
      limits: ModelOriginalsConnectionLimits.create({manifestBytes: 128 * 1024}),
      makeHash, receive, current: () => originalsOpening === opening});
    originalsOpening = opening;
    return opening;
  },
  disposeOriginals(opening) {
    if (originalsOpening === opening) originalsOpening = undefined;
    opening.dispose();
  },
  originalHeaderParts(payload) {
    if (payload.sourceFormatVersion.status === 'not-reported') return [];
    const release = parseRelease(payload.sourceFormatVersion.release);
    return [release.major, release.minor, release.patch];
  },
  releaseModel() { adapter.invalidateArtifacts?.(); },
  async cancelModelOpen(attempt) {
    importer.cancel(attempt);
    if (activeRequest?.modelOpenAttempt !== attempt || !['inspect', 'project'].includes(activeRequest.operation)) return;
    ++generation; activeRequest = null;
    try { await adapter.cancelModelOpen?.(); }
    catch (cause) {
      // The native capture owner keeps pending release and refuses another open
      // until that same cleanup is confirmed. Closing the view grants no bypass.
      console.warn('Model-opening cleanup is pending.', workbenchError(cause).message);
    }
  },
  download(text) {
    const url = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
    const link = document.createElement('a');
    link.href = url; link.download = 'morphir-ir.json'; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  },
  downloadArtifacts,
  createOriginalsArchive,
  prepareOriginalsArchive,
};
window.addEventListener('pagehide', () => { ++generation; originalsOpening?.dispose(); originalsOpening = undefined; importer.dispose(); adapter.dispose?.(); local.cancel(); });
productObservation.start(document);
await import(new URL('./browser.js', import.meta.url).href);
