import './code-editor.js';
import type { Adapter } from './contracts.ts';
import { workbenchError } from '../../../types/data.ts';
import { LocalAdapter, connect } from './transport.ts';
import { selectLocalAdapter } from './native-session.ts';
import { downloadArtifacts } from './artifact-download.ts';
import { fetchText, pickFolder, storage, watchDrop } from './project-io.ts';
import { ModelImporter, captureOriginalRequest } from './model-import.ts';

const local = new LocalAdapter();
const requestedMode = new URLSearchParams(location.search).get('mode');
const connected = requestedMode === 'connected' || (!requestedMode && document.querySelector<HTMLMetaElement>('meta[name="morphir-host-mode"]')?.content === 'connected');
let adapter: Adapter = local;
let generation = 0;
let activeRequest: { operation: string; modelOpenAttempt?: string } | null = null;
const importer = new ModelImporter();

globalThis.morphirWorkbench = {
  connected,
  projectIo: { fetchText, pickFolder, storage, watchDrop },
  get runtimeLabel() { return adapter.runtimeLabel || 'Browser local'; },
  async request(request, receive) {
    const current = ++generation;
    activeRequest = { operation: request.operation, modelOpenAttempt: request.modelOpenAttempt };
    try {
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
  importModel(attempt, receive) { importer.start(attempt, receive); },
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
};
window.addEventListener('pagehide', () => { ++generation; importer.dispose(); adapter.dispose?.(); local.cancel(); });
await import(new URL('./browser.js', import.meta.url).href);
