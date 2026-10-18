import './code-editor.js';
import type { Adapter } from './contracts.ts';
import { workbenchError } from '../../../types/data.ts';
import { LocalAdapter, connect } from './transport.ts';
import { selectLocalAdapter } from './native-session.ts';
import { downloadArtifacts } from './artifact-download.ts';
import { fetchText, pickFolder, storage, watchDrop } from './project-io.ts';

const local = new LocalAdapter();
const requestedMode = new URLSearchParams(location.search).get('mode');
const connected = requestedMode === 'connected' || (!requestedMode && document.querySelector<HTMLMetaElement>('meta[name="morphir-host-mode"]')?.content === 'connected');
let adapter: Adapter = local;
let generation = 0;

globalThis.morphirWorkbench = {
  connected,
  projectIo: { fetchText, pickFolder, storage, watchDrop },
  get runtimeLabel() { return adapter.runtimeLabel || 'Browser local'; },
  async request(request, receive) {
    const current = ++generation;
    try {
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
      if (current === generation) receive(JSON.stringify(result));
    } catch (cause) {
      const error = workbenchError(cause);
      if (request.operation === 'initialize') adapter.dispose?.();
      if (current === generation) receive(JSON.stringify({ success: false, message: error.message || 'Host request failed',
        ...(error.execution ? { execution: error.execution } : {}),
        ...(error.executionTransport ? { executionTransport: true } : {}),
        ...(error.submissionUnknown ? { submissionUnknown: true } : {}),
        ...(Array.isArray(error.diagnostics) && error.diagnostics.length ? { diagnostics: error.diagnostics } : {}) }));
    }
  },
  cancel() {
    const hostExecution = adapter.executions?.active || (adapter.executions?.execution && adapter.executions.execution.state !== 'terminal');
    if (!hostExecution) ++generation;
    Promise.resolve(adapter.cancel()).catch(() => { /* The active observer reports retained disconnection evidence. */ });
  },
  importModel(receive) {
    const input = document.createElement('input');
    input.type = 'file'; input.accept = '.json,application/json';
    input.addEventListener('change', async () => {
      const file = input.files?.[0];
      if (!file) return;
      // The worker also enforces its input bound, so this guard is only an early hint.
      if (file.size > 16 * 1024 * 1024) { receive('{"oversizedImport":true}'); return; }
      try { receive(await file.text()); } catch { receive('{"unreadableImport":true}'); }
    });
    input.click();
  },
  download(text) {
    const url = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
    const link = document.createElement('a');
    link.href = url; link.download = 'morphir-ir.json'; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  },
  downloadArtifacts,
};
window.addEventListener('pagehide', () => { ++generation; adapter.dispose?.(); local.cancel(); });
await import(new URL('./browser.js', import.meta.url).href);
