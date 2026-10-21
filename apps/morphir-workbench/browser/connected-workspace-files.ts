import type { Core, Manifest, Rpc, WorkRequest, WorkResult } from './contracts.ts';
import { WorkspaceFilesClient, workspaceFilesProfile, workspaceFilesVersion } from './workspace-files.ts';

export type FileSourceSelection =
  | { kind: 'read-only'; message: string }
  | { kind: 'selected'; sessionId: string; source: Manifest['initialSources'][number] };

/** Bind one advertised root and provider before any asynchronous RPC work. */
export function selectFileSource(manifest: Manifest): FileSourceSelection {
  const sources = manifest.initialSources.filter(source => manifest.providers.some(provider =>
    provider.id === source.providerId && provider.status === 'available' && provider.capabilities.some(cap =>
      cap?.name === workspaceFilesProfile && cap.version === workspaceFilesVersion)));
  if (sources.length === 0) return { kind: 'read-only', message: 'The host does not advertise workspace file editing.' };
  if (sources.length !== 1) return { kind: 'read-only', message: 'Open one workspace root in the host to enable editing.' };
  const source = sources[0]!;
  const provider = manifest.providers.find(provider => provider.id === source.providerId)!;
  const offers = provider.capabilities.filter(cap => cap?.name === workspaceFilesProfile);
  if (offers.length !== 1 || offers[0]!.version !== workspaceFilesVersion ||
    !/^[A-Za-z0-9_.-]{1,128}$/.test(manifest.sessionId) ||
    !/^[A-Za-z0-9_.-]{1,128}$/.test(source.providerId) || typeof source.locator !== 'string' || !source.locator || source.locator.length > 4096 ||
    typeof source.displayName !== 'string' || !source.displayName || source.displayName.length > 1024 || /[\x00-\x1f\x7f]/.test(source.displayName)) {
    return { kind: 'read-only', message: 'The workspace file offer is ambiguous or incompatible.' };
  }
  return { kind: 'selected', sessionId: manifest.sessionId,
    source: { providerId: source.providerId, locator: source.locator, displayName: source.displayName } };
}

/** Proposed connected binding of the same bounded file profile. Host support is
 * tracked separately; capability advertisement and an accepted grant are both required. */
export class ConnectedWorkspaceFiles {
  private client: WorkspaceFilesClient;
  private binding: Extract<FileSourceSelection, { kind: 'selected' }>;
  private grant: string | null = null;
  private state: 'new' | 'opening' | 'open' | 'closed' = 'new';
  private closeTransport: () => void;
  constructor(rpc: Rpc, selection: Extract<FileSourceSelection, { kind: 'selected' }>, core?: Core, ownsConnection = false) {
    this.binding = structuredClone(selection);
    const binding = structuredClone(this.binding);
    this.closeTransport = ownsConnection ? () => rpc.dispose?.() : () => {};
    this.client = new WorkspaceFilesClient(source => rpc.call('morphir.workspace-files.exchange', {
      protocolVersion: 1, sessionId: binding.sessionId, source: structuredClone(binding.source), frame: source,
    }), core, undefined, 'connected-write');
  }
  async open(): Promise<Pick<WorkResult, 'workspaceFiles' | 'fileAuthority'>> {
    if (this.state !== 'new') throw new Error('The connected file opening is no longer current.');
    this.state = 'opening';
    try {
      await this.client.open();
      const opened = await this.client.choose(false);
      if (!opened) throw new Error('The host refused workspace file editing.');
      this.grant = opened.authority.grantId; this.state = 'open';
      return { workspaceFiles: opened.workspace, fileAuthority: { ...opened.authority, name: this.binding.source.displayName } };
    } catch (error) { this.dispose(); throw error; }
  }
  save(grantId: string, workspace: NonNullable<WorkRequest['workspace']>) {
    if (this.state !== 'open' || grantId !== this.grant) throw new Error('The connected folder grant is no longer current.');
    return this.client.save(grantId, workspace);
  }
  async revoke(grantId: string) { if (grantId === this.grant) { await this.client.revoke(grantId); this.grant = null; } }
  dispose() { if (this.state === 'closed') return; this.state = 'closed'; this.grant = null; this.client.dispose(); this.closeTransport(); }
}
