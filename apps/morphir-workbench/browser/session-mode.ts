/** Page experience selection. This does not confer a host or source grant. */
export type WorkbenchMode = 'local' | 'connected' | 'connected-originals';

export function selectWorkbenchMode(search: string, hostMode: string | undefined): WorkbenchMode {
  const requested = new URLSearchParams(search).get('mode');
  if (requested === 'connected-originals') return 'connected-originals';
  if (requested === 'connected' || (!requested && hostMode === 'connected')) return 'connected';
  return 'local';
}
