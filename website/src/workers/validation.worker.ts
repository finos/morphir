/**
 * Web Worker for Morphir IR JSON validation.
 * Runs parse + Ajv schema validation off the main thread to keep the UI responsive.
 *
 * Message in:  { type: 'validate', runId, jsonString, schema?, schemaUrl?, schemaVersion }
 * When schemaUrl is set, worker fetches the schema (avoids main-thread clone of huge schema).
 * Message out: { type: 'result', runId, valid, errors, parsedJson, schemaVersion }
 *              { type: 'error', runId, message }
 */

import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import type { ValidationError, WorkerValidateMessage } from '../components/ir-checker/types';

function extractLineNumber(jsonString: string, message: string): number | null {
  const match = message.match(/position (\d+)/);
  if (match) {
    const pos = parseInt(match[1], 10);
    const lines = jsonString.substring(0, pos).split('\n');
    return lines.length;
  }
  return null;
}

self.onmessage = function handleValidate(e: MessageEvent<WorkerValidateMessage>): void {
  const { type, runId, jsonString, schema, schemaUrl, schemaVersion } = e.data ?? ({} as Partial<WorkerValidateMessage>);
  if (type !== 'validate' || runId == null) return;

  try {
    let parsedJson: unknown;
    try {
      parsedJson = JSON.parse(jsonString);
    } catch (parseErr) {
      const err = parseErr as Error;
      self.postMessage({
        type: 'result',
        runId,
        valid: false,
        errors: [{
          type: 'parse' as const,
          message: err.message,
          line: extractLineNumber(jsonString, err.message),
        }],
        parsedJson: null,
        schemaVersion: schemaVersion ?? null,
      });
      return;
    }

    function doValidate(schemaObj: object): void {
      const ajv = new Ajv({ allErrors: true, verbose: true, strict: false });
      addFormats(ajv);
      const validate = ajv.compile(schemaObj);

      try {
        const valid = validate(parsedJson);
        const errors: ValidationError[] = (validate.errors ?? []).map((err) => ({
          type: 'schema' as const,
          path: err.instancePath ?? '/',
          message: err.message ?? 'Validation failed',
          keyword: err.keyword,
          params: err.params as Record<string, unknown> | undefined,
        }));
        self.postMessage({
          type: 'result',
          runId,
          valid: valid as boolean,
          errors,
          parsedJson,
          schemaVersion: schemaVersion ?? null,
        });
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        self.postMessage({
          type: 'result',
          runId,
          valid: false,
          errors: [{ type: 'system', message: `Validation Error: ${message}` }],
          parsedJson,
          schemaVersion: schemaVersion ?? null,
        });
      }
    }

    if (schemaUrl) {
      fetch(schemaUrl)
        .then((r) => r.json() as Promise<object>)
        .then(doValidate)
        .catch((err) => {
          self.postMessage({
            type: 'error',
            runId,
            message: 'Failed to load schema: ' + (err instanceof Error ? err.message : String(err)),
          });
        });
      return;
    }

    if (schema != null && typeof schema === 'object') {
      doValidate(schema);
      return;
    }

    self.postMessage({
      type: 'result',
      runId,
      valid: false,
      errors: [{ type: 'system', message: `Schema for ${schemaVersion ?? 'unknown'} not loaded yet` }],
      parsedJson,
      schemaVersion: schemaVersion ?? null,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    self.postMessage({
      type: 'error',
      runId,
      message,
    });
  }
};
