/**
 * Source for the standalone validation worker. Bundled with esbuild so Ajv
 * is included (no CDN, no importScripts). Same message contract as validation.worker.ts.
 * Build: npm run build:worker
 */
import Ajv from "ajv";

function extractLineNumber(jsonString, message) {
  const m = message && message.match(/position (\d+)/);
  if (!m) return null;
  return jsonString.substring(0, parseInt(m[1], 10)).split("\n").length;
}

self.onmessage = function (e) {
  const d = e.data || {};
  if (d.type !== "validate" || d.runId == null) return;
  try {
    let parsedJson;
    try {
      parsedJson = JSON.parse(d.jsonString);
    } catch (err) {
      self.postMessage({
        type: "result",
        runId: d.runId,
        valid: false,
        errors: [
          {
            type: "parse",
            message: err.message || String(err),
            line: extractLineNumber(d.jsonString, err.message),
          },
        ],
        parsedJson: null,
        schemaVersion: d.schemaVersion || null,
      });
      return;
    }

    function doValidate(schema) {
      if (schema == null || typeof schema !== "object") {
        self.postMessage({
          type: "result",
          runId: d.runId,
          valid: false,
          errors: [
            {
              type: "system",
              message:
                "Schema for " + (d.schemaVersion || "unknown") + " not loaded yet",
            },
          ],
          parsedJson,
          schemaVersion: d.schemaVersion || null,
        });
        return;
      }
      // 'fast' mode stops at first error, 'thorough' finds all errors (slower for large files)
      const allErrors = d.validationMode === 'thorough';
      const ajv = new Ajv({ allErrors, verbose: false, strict: false });
      const validate = ajv.compile(schema);
      try {
        const valid = validate(parsedJson);
        const errors = (validate.errors || []).map((err) => ({
          type: "schema",
          path: err.instancePath || "/",
          message: err.message || "Validation failed",
          keyword: err.keyword,
          params: err.params,
        }));
        self.postMessage({
          type: "result",
          runId: d.runId,
          valid: !!valid,
          errors,
          parsedJson,
          schemaVersion: d.schemaVersion || null,
        });
      } catch (err) {
        const msg = err && (err.message || err);
        self.postMessage({
          type: "result",
          runId: d.runId,
          valid: false,
          errors: [{ type: "system", message: "Validation Error: " + msg }],
          parsedJson,
          schemaVersion: d.schemaVersion || null,
        });
      }
    }

    if (d.schemaUrl) {
      fetch(d.schemaUrl)
        .then((r) => r.json())
        .then((schema) => doValidate(schema))
        .catch((err) => {
          self.postMessage({
            type: "error",
            runId: d.runId,
            message: "Failed to load schema: " + (err.message || String(err)),
          });
        });
      return;
    }
    if (d.schema != null && typeof d.schema === "object") {
      doValidate(d.schema);
      return;
    }
    self.postMessage({
      type: "result",
      runId: d.runId,
      valid: false,
      errors: [
        {
          type: "system",
          message:
            "Schema for " + (d.schemaVersion || "unknown") + " not loaded yet",
        },
      ],
      parsedJson,
      schemaVersion: d.schemaVersion || null,
    });
  } catch (err) {
    const message = err && (err.message || err);
    self.postMessage({
      type: "error",
      runId: d.runId,
      message: message || String(err),
    });
  }
};
