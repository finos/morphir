import type { Core, WorkRequest, WorkResult } from './contracts.ts';

/** A capture validated by the production worksheet codec before dispatch. */
export class WorksheetCapture {
  readonly request: string;
  private readonly core: Core;
  private constructor(request: string, core: Core) {
    this.request = request;
    this.core = core;
  }

  static from(request: WorkRequest, core: Core = command => globalThis.morphirWorkbenchWorksheet(command)): WorksheetCapture {
    if (typeof request.worksheetRequest !== 'string') throw new Error('A worksheet requires a captured source.');
    const canonical = call(core, { action: 'capture', request: request.worksheetRequest });
    if (JSON.parse(canonical).source.text !== request.source) throw new Error('worksheet.source_mismatch');
    return new WorksheetCapture(canonical, core);
  }

  validate(result: WorkResult): WorkResult {
    if (typeof result.worksheetReport !== 'string') throw new Error('worksheet.invalid_report');
    return { success: true, worksheetReport: call(this.core, { action: 'validate', request: this.request, report: result.worksheetReport }) };
  }

  terminated(reason: 'cancelled' | 'timeout' | 'worker-failed'): WorkResult {
    return { success: true, worksheetReport: call(this.core, { action: 'terminate', request: this.request, reason }) };
  }
}

function call(core: Core, command: Record<string, string>): string {
  const reply: unknown = JSON.parse(core(JSON.stringify(command)));
  if (typeof reply !== 'object' || reply === null || !('ok' in reply) || reply.ok !== true ||
      !('value' in reply) || typeof reply.value !== 'string') {
    const code = typeof reply === 'object' && reply !== null && 'code' in reply && typeof reply.code === 'string'
      ? reply.code : 'worksheet.invalid_report';
    throw new Error(code);
  }
  return reply.value;
}
