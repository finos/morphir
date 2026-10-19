import { ExecutionClient as SharedClient } from '../../../pkgs/morphir-host/execution-client/client.mts';
import type { ExecutionOptions } from './contracts.ts';

/** Workbench supplies its compiled pure validation core; orchestration is shared. */
export class ExecutionClient extends SharedClient {
  constructor(sessionId: string, options: ExecutionOptions = {}) {
    super(sessionId, { core: command => globalThis.morphirWorkbenchExecutions(command), ...options });
  }
}
