import type { Fetch } from './contracts.ts';
export const jobFrameLimit = 1024 * 1024;

// Transports carry bounded text. JobClient owns decoding and receipt validation.
export class HttpJobTransport {
  fetchFn: Fetch;
  timeout: number;
  constructor({ fetchFn = fetch, timeout = 10000 }: { fetchFn?: Fetch; timeout?: number } = {}) {
    this.fetchFn = fetchFn.bind(globalThis);
    this.timeout = timeout;
  }
  async request(path: string, source?: string, optional = false) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(new Error('The host job request timed out.')), this.timeout);
    try {
      const response = await this.fetchFn(`/api/workbench/${path}`, {
        method: source === undefined ? 'GET' : 'POST', credentials: 'same-origin', cache: 'no-store',
        signal: controller.signal, ...(source === undefined ? {} : {
          headers: { 'Content-Type': 'application/json' }, body: source,
        }),
      });
      if (optional && response.status === 404) return { ok: false, status: 404, source: '' };
      let text;
      if (response.body?.getReader) {
        const reader = response.body.getReader();
        const chunks = []; let size = 0;
        try {
          for (;;) {
            const chunk = await reader.read();
            if (chunk.done) break;
            size += chunk.value.byteLength;
            if (size > jobFrameLimit) { await reader.cancel(); throw new Error('Host job response exceeds the 1-MiB limit.'); }
            chunks.push(chunk.value);
          }
        } finally { reader.releaseLock(); }
        const all = new Uint8Array(size); let offset = 0;
        for (const chunk of chunks) { all.set(chunk, offset); offset += chunk.byteLength; }
        text = new TextDecoder('utf-8', { fatal: true }).decode(all);
      } else text = await response.text();
      return { ok: response.ok, status: response.status, source: text };
    } finally { clearTimeout(timer); }
  }
}
