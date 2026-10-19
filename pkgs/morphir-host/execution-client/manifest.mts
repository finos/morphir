import { isRecord } from '../../../types/data.ts';
export interface Manifest { protocolVersion: number; webSocketPath: string; sessionId: string; providers: {id: string; status: string; capabilities: {name: string; version: string}[]}[]; initialSources: {providerId: string; locator: string; displayName: string}[]; }

export function validateManifest(manifest: unknown): Manifest {
  if (!isRecord(manifest)) throw new Error('Invalid session manifest.');
  if (manifest?.protocolVersion !== 1 || manifest.webSocketPath !== '/rpc' || typeof manifest.sessionId !== 'string' || !manifest.sessionId) {
    throw new Error('This client requires connected Morphir protocol v1 and /rpc.');
  }
  if (!Array.isArray(manifest.providers) || !Array.isArray(manifest.initialSources)) throw new Error('Invalid session manifest.');
  const ids = new Set();
  for (const provider of manifest.providers) {
    if (typeof provider.id !== 'string' || ids.has(provider.id) || !Array.isArray(provider.capabilities)) throw new Error('Invalid session provider.');
    ids.add(provider.id);
  }
  if (manifest.initialSources.some(source => !ids.has(source.providerId) || typeof source.locator !== 'string' || typeof source.displayName !== 'string')) {
    throw new Error('An initial source references an unknown provider.');
  }
  return manifest as unknown as Manifest;
}
